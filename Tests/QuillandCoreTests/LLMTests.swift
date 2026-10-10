import Foundation
import Network
import Testing
@testable import QuillandCore

// MARK: A fake LM Studio, on a real socket

/// An HTTP server on localhost that answers as a script says: slowly, in pieces cut anywhere, or never.
final class FakeLMServer: @unchecked Sendable {
    struct Request: @unchecked Sendable {
        var method: String
        var path: String
        var body: Data
        var json: [String: Any]? { try? JSONSerialization.jsonObject(with: body) as? [String: Any] }
    }

    final class Responder: @unchecked Sendable {
        fileprivate let connection: NWConnection
        private let lock = NSLock()
        private var _closedByClientAt: Date?
        init(_ connection: NWConnection) { self.connection = connection }
        var closedByClientAt: Date? { lock.withLock { _closedByClientAt } }
        var isClosed: Bool { closedByClientAt != nil }
        fileprivate func markClosed() { lock.withLock { if _closedByClientAt == nil { _closedByClientAt = Date() } } }

        func write(_ text: String) { write(Data(text.utf8)) }
        func write(_ data: Data) {
            let done = DispatchSemaphore(value: 0)
            connection.send(content: data, completion: .contentProcessed { _ in done.signal() })
            _ = done.wait(timeout: .now() + 2)
        }
        func head(_ status: Int = 200, contentType: String = "text/event-stream", contentLength: Int? = nil) {
            var h = "HTTP/1.1 \(status) X\r\nContent-Type: \(contentType)\r\nConnection: close\r\n"
            if let contentLength { h += "Content-Length: \(contentLength)\r\n" }
            write(h + "\r\n")
        }
        func json(_ object: Any) { json(200, object) }
        func json(_ status: Int, _ object: Any) {
            let data = try! JSONSerialization.data(withJSONObject: object)
            head(status, contentType: "application/json", contentLength: data.count)
            write(data)
            close()
        }
        func event(_ object: [String: Any]) { write("data: " + String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n") }
        func delta(_ text: String) { event(["choices": [["delta": ["content": text]]]]) }
        func close() { connection.cancel() }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-lm")
    private let lock = NSLock()
    private var _requests: [Request] = []
    private var _responders: [Responder] = []
    var handler: @Sendable (Request, Responder) -> Void = { _, r in r.json(404, ["error": "nothing"]) }
    private(set) var port: UInt16 = 0

    var requests: [Request] { lock.withLock { _requests } }
    var responders: [Responder] { lock.withLock { _responders } }
    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)/v1")! }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [unowned self] connection in accept(connection) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        port = listener.port!.rawValue
    }

    deinit { listener.cancel() }

    private func accept(_ connection: NWConnection) {
        let responder = Responder(connection)
        lock.withLock { _responders.append(responder) }
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: responder.markClosed()
            default: break
            }
        }
        connection.start(queue: queue)
        var buffer = Data()
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, complete, error in
                if let data { buffer.append(data) }
                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
                    let length = head.split(separator: "\r\n").compactMap { line -> Int? in
                        line.lowercased().hasPrefix("content-length:") ? Int(line.dropFirst(15).trimmingCharacters(in: .whitespaces)) : nil
                    }.first ?? 0
                    let body = buffer[range.upperBound...]
                    if body.count >= length {
                        let first = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
                        let request = Request(method: String(first.first ?? ""), path: String(first.count > 1 ? first[1] : ""), body: Data(body.prefix(length)))
                        lock.withLock { _requests.append(request) }
                        // From now on only the client closing the connection matters.
                        func watch() {
                            connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, complete, error in
                                if complete || error != nil { responder.markClosed() } else { watch() }
                            }
                        }
                        watch()
                        let handler = self.handler
                        DispatchQueue.global().async { handler(request, responder) }
                        return
                    }
                }
                if complete || error != nil { responder.markClosed(); return }
                readMore()
            }
        }
        readMore()
    }

    func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if condition() { return true }; Thread.sleep(forTimeInterval: 0.005) }
        return condition()
    }
}

// MARK: Tests

@Suite("LM Studio client", .serialized)
struct LLMTests {
    static func client(_ server: FakeLMServer, model: String = "qwen/qwen3-14b") -> LMStudioClient {
        LMStudioClient(config: LLMConfig(baseURL: server.baseURL, chatModel: model, embeddingModel: "embed"))
    }

    static func collect(_ stream: AsyncThrowingStream<LLMEvent, Error>) async throws -> (text: String, events: [LLMEvent]) {
        var text = ""
        var events: [LLMEvent] = []
        for try await e in stream { events.append(e); if case .text(let t) = e { text += t } }
        return (text, events)
    }

    // MARK: The reasoning filter (the old app's test cases)

    static let reasoningCases: [(String, String)] = [
        ("\n\nHello world", "Hello world"),
        ("<think>\nhmm a < b\n</think>\n\nAnswer <b>bold</b> here", "Answer <b>bold</b> here"),
        ("[THINK]x[/THINK]Ответ", "Ответ"),
        ("a <thin", "a <thin"),
        ("<think>never closed", ""),
        ("x < y and [T is fine", "x < y and [T is fine"),
        ("<think>a</think>b<think>c</think>d", "bd"),
        ("<think>é\u{301}</think>ё", "ё"),
        ("Ответ без размышлений.", "Ответ без размышлений."),
    ]

    @Test("reasoning is stripped, however the reply is cut into pieces (200 random cuts of every case)")
    func reasoningFilter() {
        for (raw, expected) in Self.reasoningCases {
            #expect(Reasoning.strip(raw) == expected, "\(raw.debugDescription)")
            var rng = SplitMix64(seed: 1)
            for _ in 0..<200 {
                var filter = ReasoningFilter()
                var out = ""
                let scalars = Array(raw.unicodeScalars)
                var i = 0
                while i < scalars.count {
                    let n = Int.random(in: 1...4, using: &rng)
                    var piece = String.UnicodeScalarView()
                    piece.append(contentsOf: scalars[i..<min(i + n, scalars.count)])
                    out += filter.feed(String(piece))
                    i += n
                }
                out += filter.finish()
                if out != expected { Issue.record("\(raw.debugDescription) cut at random gave \(out.debugDescription), expected \(expected.debugDescription)"); break }
            }
        }
    }

    // MARK: Streaming

    @Test("text is yielded as it arrives, pieces cut anywhere (also inside a Cyrillic letter), with the reasoning left out")
    func streaming() async throws {
        let server = try FakeLMServer()
        let answer = "<think>Подумаем, как лучше.</think>\n\nПривет, мир! Это ответ на русском языке, ёлка, 😀."
        server.handler = { _, r in
            r.head()
            var all = Data()
            for scalar in answer.unicodeScalars {
                var piece = String.UnicodeScalarView()
                piece.append(scalar)
                all += Data("data: ".utf8)
                all += (try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": String(piece)]]]]))
                all += Data("\n\n".utf8)
            }
            all += Data("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":12,\"completion_tokens\":34}}\n\ndata: [DONE]\n\n".utf8)
            // Written in cuts of 1 to 7 bytes, so the cuts fall inside multi-byte letters and inside lines.
            var rng = SplitMix64(seed: 5)
            var i = 0
            while i < all.count {
                let n = Int.random(in: 1...7, using: &rng)
                r.write(all.subdata(in: i..<min(i + n, all.count)))
                i += n
            }
            r.close()
        }
        let (text, events) = try await Self.collect(Self.client(server).chatStream([ChatMessage("user", "Привет")]))
        #expect(text == "Привет, мир! Это ответ на русском языке, ёлка, 😀.")
        #expect(events.last == .finished(reason: "stop", promptTokens: 12, completionTokens: 34))
        #expect(events.contains { if case .reasoning = $0 { return true } else { return false } })
    }

    @Test("a reply that arrives slowly is shown slowly: the first piece comes long before the last")
    func arrivesAsItComes() async throws {
        let server = try FakeLMServer()
        server.handler = { _, r in
            r.head()
            for i in 0..<10 { r.delta("слово\(i) "); Thread.sleep(forTimeInterval: 0.1) }
            r.write("data: [DONE]\n\n")
            r.close()
        }
        let start = Date()
        var arrivals: [TimeInterval] = []
        for try await e in Self.client(server).chatStream([ChatMessage("user", "x")]) {
            if case .text = e { arrivals.append(Date().timeIntervalSince(start)) }
        }
        #expect(arrivals.count == 10)
        #expect(arrivals[0] < 0.25, "the first piece after \(arrivals[0]) s")
        #expect(arrivals[9] > 0.8)
        let gaps = zip(arrivals.dropFirst(), arrivals).map { $0 - $1 }
        #expect(gaps.allSatisfy { $0 > 0.05 && $0 < 0.25 }, "each piece shown when it arrives, not in a lump: \(gaps)")
        print("LLM STREAM: first piece \(Int(arrivals[0] * 1000)) ms after sending; gaps \(gaps.map { Int($0 * 1000) }) ms")
    }

    @Test("Stop while the model is still reading the prompt (nothing has come back) ends at once and closes the connection")
    func stopBeforeFirstByte() async throws {
        let server = try FakeLMServer()
        server.handler = { _, r in Thread.sleep(forTimeInterval: 30); r.close() }   // reads the prompt "for 30 seconds"
        let client = Self.client(server)
        let consumer = Task { () -> Bool in
            do { for try await _ in client.chatStream([ChatMessage("user", "the whole book")]) {}; return true } catch { return false }
        }
        #expect(server.waitUntil { server.requests.count == 1 })
        let stopped = Date()
        consumer.cancel()
        let ended = await consumer.value
        let latency = Date().timeIntervalSince(stopped)
        #expect(ended, "cancelling is not an error")
        #expect(latency < 0.3, "the stream ended after \(latency) s")
        #expect(server.waitUntil(timeout: 1) { server.responders.first?.isClosed == true }, "the server must see the connection closed")
        print("LLM STOP (before the first byte): stream ended \(Int(latency * 1000)) ms after Stop; server saw the connection close \(Int((server.responders.first!.closedByClientAt!.timeIntervalSince(stopped)) * 1000)) ms after")
    }

    @Test("Stop in the middle of an answer: no more text is delivered, the connection closes, the server stops writing")
    func stopInTheMiddle() async throws {
        let server = try FakeLMServer()
        let written = LockedCounter()
        server.handler = { _, r in
            r.head()
            for i in 0..<1000 {
                if r.isClosed { break }
                r.delta("кусок\(i) ")
                written.add()
                Thread.sleep(forTimeInterval: 0.01)
            }
            r.close()
        }
        let client = Self.client(server)
        var received = 0
        var stoppedAt: Date?
        let consumer = Task { () -> (Int, Date?) in
            var n = 0
            var after: Date?
            for try await e in client.chatStream([ChatMessage("user", "x")]) {
                if case .text = e { n += 1 }
                if n == 10, after == nil { after = Date(); withUnsafeCurrentTask { $0?.cancel() } }
            }
            return (n, after)
        }
        (received, stoppedAt) = try await consumer.value
        let latency = Date().timeIntervalSince(stoppedAt!)
        #expect(received <= 12, "got \(received) pieces")
        #expect(latency < 0.3)
        #expect(server.waitUntil(timeout: 1) { server.responders.first?.isClosed == true })
        let writtenAtStop = written.value
        try await Task.sleep(for: .seconds(0.3))
        #expect(written.value - writtenAtStop <= 30, "the server must stop writing soon after the client left")
    }

    @Test("leaving the loop early (break) is a stop too")
    func breakIsStop() async throws {
        let server = try FakeLMServer()
        server.handler = { _, r in
            r.head()
            for i in 0..<1000 { if r.isClosed { break }; r.delta("a\(i) "); Thread.sleep(forTimeInterval: 0.01) }
            r.close()
        }
        var n = 0
        for try await e in Self.client(server).chatStream([ChatMessage("user", "x")]) {
            if case .text = e { n += 1 }
            if n == 5 { break }
        }
        #expect(server.waitUntil(timeout: 1) { server.responders.first?.isClosed == true })
    }

    // MARK: What is sent

    @Test("the request: the /no_think directive, the model, the temperature only when set, streaming on")
    func requestBody() async throws {
        let server = try FakeLMServer()
        server.handler = { _, r in r.head(); r.delta("ok"); r.write("data: [DONE]\n\n"); r.close() }
        let client = Self.client(server, model: "qwen/qwen3-14b")
        _ = try await Self.collect(client.chatStream([ChatMessage("system", "Be brief."), ChatMessage("user", "Привет")]))
        _ = try await Self.collect(client.chatStream([ChatMessage("user", "Think hard")], think: true, temperature: 0.3, maxTokens: 50))
        let bodies = server.requests.map { $0.json! }
        #expect(server.requests.allSatisfy { $0.path == "/v1/chat/completions" && $0.method == "POST" })
        #expect(bodies[0]["model"] as? String == "qwen/qwen3-14b")
        #expect(bodies[0]["stream"] as? Bool == true)
        #expect(bodies[0]["temperature"] == nil && bodies[0]["max_tokens"] == nil)
        let m0 = bodies[0]["messages"] as! [[String: String]]
        #expect(m0[0]["content"] == "Be brief." && m0[1]["content"] == "Привет /no_think", "only the last message gets the directive")
        let m1 = bodies[1]["messages"] as! [[String: String]]
        #expect(m1[0]["content"] == "Think hard")
        #expect(bodies[1]["temperature"] as? Double == 0.3 && bodies[1]["max_tokens"] as? Int == 50)
    }

    @Test("non-streaming chat strips the reasoning; embeddings come back as numbers")
    func chatAndEmbed() async throws {
        let server = try FakeLMServer()
        server.handler = { req, r in
            if req.path.hasSuffix("/embeddings") { r.json(["data": [["embedding": [0.5, -1.25, 3]]]]) }
            else { r.json(["choices": [["message": ["content": "<think>plan</think>\n\nПривет!"]]]]) }
        }
        let client = Self.client(server)
        #expect(try await client.chat([ChatMessage("user", "x")]) == "Привет!")
        #expect(try await client.embed("text") == [0.5, -1.25, 3])
        #expect((server.requests[1].json!["model"] as? String) == "embed")
    }

    // MARK: Failures

    @Test("nothing listening: unreachable at once, and the app is told (to switch the AI actions off)")
    func unreachable() async throws {
        let listener = try FakeLMServer()
        let url = listener.baseURL
        let port = listener.port
        _ = port
        // A port that is closed: take a free one by opening and dropping a listener.
        var closed: FakeLMServer? = try FakeLMServer()
        let closedURL = closed!.baseURL
        closed = nil
        _ = url
        let told = LockedCounter()
        let client = LMStudioClient(config: LLMConfig(baseURL: closedURL, chatModel: "m"))
        client.onUnreachable = { told.add() }
        let start = Date()
        do { for try await _ in client.chatStream([ChatMessage("user", "x")]) {}; Issue.record("no error") } catch {
            #expect((error as? LLMError) == .unreachable, "\(error)")
        }
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(told.value == 1)
        do { _ = try await client.listModels(); Issue.record("no error") } catch { #expect((error as? LLMError) == .unreachable) }
        #expect((LLMError.unreachable.description).contains("LM Studio doesn't answer"))
    }

    @Test("server errors carry the server's own message; the memory and missing-model errors are put in plain words")
    func serverErrors() async throws {
        let server = try FakeLMServer()
        server.handler = { req, r in
            let body = req.json!
            switch body["model"] as? String {
            case "gone": r.json(404, ["error": ["message": "Model \"gone\" not found in downloaded models"]])
            case "big": r.json(400, ["error": ["message": "Failed to load model: insufficient system resources"]])
            case "mid": r.head(); r.write("data: {\"error\":{\"message\":\"model crashed\"}}\n\n"); r.close()
            default: r.json(500, ["error": "plain text error"])
            }
        }
        func error(for model: String) async -> LLMError? {
            do { for try await _ in Self.client(server, model: model).chatStream([ChatMessage("user", "x")]) {}; return nil } catch { return error as? LLMError }
        }
        let gone = await error(for: "gone")
        #expect(gone == .server(status: 404, message: "Model \"gone\" not found in downloaded models"))
        #expect(gone?.description.hasPrefix("This model isn't downloaded in LM Studio") == true)
        #expect((await error(for: "big"))?.description.contains("Not enough memory") == true)
        #expect(await error(for: "mid") == .server(status: 200, message: "model crashed"))
        #expect(await error(for: "other") == .server(status: 500, message: "plain text error"))
    }

    @Test("the stream tolerates keep-alive comments and blank lines, and refuses garbage")
    func oddStreams() async throws {
        let server = try FakeLMServer()
        server.handler = { req, r in
            r.head()
            r.write(": keep-alive\n\n\n")
            if (req.json!["model"] as? String) == "garbage" { r.write("data: {not json\n\n"); r.close(); return }
            r.delta("a"); r.write(": ping\n\n"); r.delta("b"); r.write("data: [DONE]\n\n"); r.close()
        }
        #expect(try await Self.collect(Self.client(server).chatStream([ChatMessage("user", "x")])).text == "ab")
        do { _ = try await Self.collect(Self.client(server, model: "garbage").chatStream([ChatMessage("user", "x")])); Issue.record("accepted garbage") } catch {
            #expect((error as? LLMError).map { if case .badResponse = $0 { true } else { false } } == true)
        }
    }

    // MARK: Models

    @Test("the model list: LM Studio 0.4 API, then the older API, then the standard one")
    func modelLists() async throws {
        let server = try FakeLMServer()
        let level = LockedCounter()
        server.handler = { req, r in
            switch req.path {
            case "/api/v1/models" where level.value == 0:
                r.json(["models": [
                    ["key": "qwen/qwen3-14b", "type": "llm", "format": "mlx", "architecture": "qwen3", "quantization": ["name": "4bit"], "max_context_length": 40960, "size_bytes": 8_300_000_000,
                     "loaded_instances": [["id": "qwen/qwen3-14b", "config": ["context_length": 16384]]]],
                    ["key": "qwen/qwen3.8-27b", "type": "llm", "max_context_length": 262144, "loaded_instances": []],
                    ["key": "text-embedding-nomic", "type": "embedding", "max_context_length": 2048, "loaded_instances": []],
                ]])
            case "/api/v0/models" where level.value == 1:
                r.json(["data": [["id": "old-model", "type": "llm", "state": "loaded", "arch": "llama", "max_context_length": 8192, "loaded_context_length": 4096]]])
            case "/v1/models":
                r.json(["data": [["id": "plain-model"], ["id": "some-embed-model"]]])
            default: r.json(404, ["error": "no"])
            }
        }
        let client = Self.client(server)
        let a = try await client.listModels()
        #expect(a.map(\.id) == ["qwen/qwen3-14b", "qwen/qwen3.8-27b", "text-embedding-nomic"])
        #expect(a[0].loaded == true && a[0].loadedContext == 16384 && a[0].maxContext == 40960 && a[0].quantization == "4bit" && a[0].sizeBytes == 8_300_000_000)
        #expect(a[1].loaded == false && a[2].isEmbedding)
        level.add()
        let b = try await client.listModels()
        #expect(b.map(\.id) == ["old-model"] && b[0].loaded == true && b[0].loadedContext == 4096)
        level.add()
        let c = try await client.listModels()
        #expect(c.map(\.id) == ["plain-model", "some-embed-model"] && c[0].loaded == nil && c[1].isEmbedding)
    }

    @Test("the context length is the loaded size, remembered for a minute; a default when nothing says")
    func contextLength() async throws {
        let server = try FakeLMServer()
        server.handler = { req, r in
            r.json(["models": [["key": "qwen/qwen3-14b", "type": "llm", "max_context_length": 40960, "loaded_instances": [["config": ["context_length": 16384]]]]]])
        }
        let client = Self.client(server)
        #expect(await client.contextLength() == 16384)
        #expect(await client.contextLength() == 16384)
        #expect(server.requests.count == 1, "asked once, then remembered")
        let none = LMStudioClient(config: LLMConfig(baseURL: URL(string: "http://127.0.0.1:9/v1")!, chatModel: "x"))
        #expect(await none.contextLength() == LMStudioClient.defaultContext)
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func add() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

@Suite("The AI connection", .serialized)
struct AIConnectionTests {
    @Test("the address may be written in several ways")
    func addresses() {
        #expect(AIConnection.config(address: "http://localhost:1234", model: "m")?.baseURL.absoluteString == "http://localhost:1234/v1")
        #expect(AIConnection.config(address: "localhost:1234/", model: "m")?.baseURL.absoluteString == "http://localhost:1234/v1")
        #expect(AIConnection.config(address: "http://127.0.0.1:1234/v1", model: "m")?.baseURL.absoluteString == "http://127.0.0.1:1234/v1")
        #expect(AIConnection.config(address: "  ", model: "m")?.baseURL.absoluteString == "http://localhost:1234/v1", "empty: the usual address")
        #expect(AIConnection.config(address: "http://", model: "m") == nil)
    }

    @Test("the model is the author's choice, else the loaded one; embeddings are never chosen; the context comes from the server unless set")
    func choosing() async throws {
        let server = try FakeLMServer()
        server.handler = { request, responder in
            if request.path.hasSuffix("/api/v1/models") {
                responder.json(["models": [
                    ["key": "text-embedding-nomic", "type": "embedding"],
                    ["key": "qwen/qwen3-14b", "type": "llm", "loaded_instances": [["config": ["context_length": 16384]]], "max_context_length": 40960],
                    ["key": "other/model", "type": "llm", "loaded_instances": [], "max_context_length": 8192],
                ]])
            } else { responder.json(404, ["error": "no"]) }
        }
        let base = server.baseURL.absoluteString.replacingOccurrences(of: "/v1", with: "")
        let auto = await AIConnection.check(address: base, model: "", contextSetting: 0)
        #expect(auto.reachable && auto.model == "qwen/qwen3-14b" && auto.context == 16384 && auto.loaded && auto.models.count == 2, "\\(auto)")
        let chosen = await AIConnection.check(address: base, model: "other/model", contextSetting: 0)
        #expect(chosen.model == "other/model" && chosen.context == 8192 && !chosen.loaded && chosen.message.contains("not loaded"))
        let forced = await AIConnection.check(address: base, model: "", contextSetting: 6000)
        #expect(forced.context == 6000)
        let missing = await AIConnection.check(address: base, model: "gone/model", contextSetting: 0)
        #expect(missing.model == "qwen/qwen3-14b" && missing.message.contains("gone/model"))
    }

    @Test("a server that does not answer is a status, not a crash")
    func unreachable() async throws {
        var closed: FakeLMServer? = try FakeLMServer()
        let base = closed!.baseURL.absoluteString.replacingOccurrences(of: "/v1", with: "")
        closed = nil
        let status = await AIConnection.check(address: base, model: "", contextSetting: 0)
        #expect(!status.reachable && status.model == nil && status.message.contains("LM Studio"))
    }

    @Test("the settings are kept, and a bad value is brought back")
    func settings() {
        var p = Preferences()
        p.aiAddress = "  "; p.aiContext = 5
        #expect(p.clamped().aiAddress == AIConnection.defaultAddress && p.clamped().aiContext == 1024)
        p.aiModel = "qwen/qwen3-14b"; p.aiAddress = "localhost:5555"; p.aiContext = 12000; p.aiEnabled = false
        var o: JSONObject = [:]
        p.clamped().write(into: &o)
        let back = Preferences(object: o)
        #expect(back.aiModel == "qwen/qwen3-14b" && back.aiAddress == "localhost:5555" && back.aiContext == 12000 && !back.aiEnabled)
    }
}
