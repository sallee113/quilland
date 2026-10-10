import Foundation
import Testing
@testable import QuillandCore

@Suite("Collecting from the book", .serialized)
struct CollectTests {
    // MARK: Quotes

    @Test("a quote is looked for in the text ignoring case, ё, quotation marks and spacing, and the range is the text's own")
    func quotes() {
        let text = "Утром Анна вышла на платформу.  «Поезд ушёл», — сказал старик."
        let r1 = QuoteVerifier.find("анна ВЫШЛА на платформу", in: text)!
        #expect((text as NSString).substring(with: r1) == "Анна вышла на платформу")
        let r2 = QuoteVerifier.find("Поезд ушел сказал старик", in: text)
        #expect(r2 != nil, "ё and е, a dash and quotes do not matter")
        let r3 = QuoteVerifier.find("Анна вышла на платформу и закурила", in: text)!
        #expect((text as NSString).substring(with: r3) == "Анна вышла на платформу", "a quote that goes on past the text still finds its beginning")
        #expect(QuoteVerifier.find("Анна вернулась домой поздно", in: text) == nil)
        #expect(QuoteVerifier.find("Старик", in: text) != nil && QuoteVerifier.find("Старуха", in: text) == nil, "a short quote must be there whole")
        #expect(QuoteVerifier.find("", in: text) == nil)
    }

    // MARK: The answer

    static let passage = "Анна стояла на платформе. Старик в фуражке спросил, к кому она приехала. Она ответила: к тёте Вере. Они пошли к дому у озера."

    @Test("a JSON answer, even in a fence and with talk around it, becomes findings; those without a true quote are dropped")
    func parsing() {
        let reply = """
        Here you go:
        ```json
        {"characters": [
          {"name": "Анна", "aliases": ["Аня"], "description": "Приезжает к тёте.", "note": "стоит на платформе", "quote": "Анна стояла на платформе"},
          {"name": "Лев", "description": "Выдуманный", "note": "", "quote": "Лев вошёл в комнату"}],
         "places": [{"name": "Озеро", "type": "place", "parent": "", "description": "Рядом с домом.", "note": "", "quote": "к дому у озера"},
                    {"name": "Дом", "type": "weird", "description": "", "note": "", "quote": "Они пошли к дому"}],
         "events": [{"title": "Приезд Анны", "date": "", "places": ["Станция"], "note": "Её встречает старик", "quote": "Старик в фуражке спросил"}],
         "relationships": [{"characters": ["Анна", "Вера"], "kind": "племянница и тётя", "note": "", "quote": "к тёте Вере"}, {"characters": ["Анна"], "kind": "x", "note": "", "quote": "Анна стояла"}],
         "observations": [{"about": "Старик", "note": "носит фуражку", "quote": "Старик в фуражке"}]}
        ```
        Hope it helps.
        """
        let kinds = Set(CollectKind.allCases)
        let result = CollectParser.parse(reply, kinds: kinds, scene: "s1", chunk: Self.passage, chunkOffset: 1000)
        #expect(!result.malformed && result.dropped == 1 && result.items.count == 6, "\(result.dropped) \(result.items.map(\.title))")
        let anna = result.items.first { $0.name == "Анна" }!
        #expect(anna.aliases == ["Аня"] && anna.evidence[0].quote == "Анна стояла на платформе" && anna.evidence[0].range.location == 1000 && anna.evidence[0].note == "стоит на платформе")
        #expect(result.items.first { $0.name == "Дом" }?.type == "place", "an unknown type becomes a place")
        #expect(result.items.contains { $0.kind == .relationships && $0.members == ["Анна", "Вера"] } && !result.items.contains { $0.members == ["Анна"] }, "a relationship needs two different names")
        #expect(result.items.first { $0.kind == .observations }?.about == "Старик")
        let only = CollectParser.parse(reply, kinds: [.events], scene: "s1", chunk: Self.passage, chunkOffset: 0)
        #expect(only.items.count == 1 && only.items[0].kind == .events, "only the kinds asked for")
        #expect(CollectParser.parse("I could not do it.", kinds: kinds, scene: "s", chunk: "x", chunkOffset: 0).malformed)
        #expect(CollectParser.parse("{\"characters\": []}", kinds: kinds, scene: "s", chunk: "x", chunkOffset: 0).items.isEmpty)
    }

    // MARK: Merging

    @Test("the same thing found in several scenes is one item, with all the evidence; another name of it joins")
    func merging() {
        func character(_ name: String, aliases: [String] = [], scene: String, at: Int, detail: String = "") -> CollectedItem {
            var c = CollectedItem(kind: .characters, name: name)
            c.aliases = aliases; c.detail = detail
            c.evidence = [CollectedEvidence(scene: scene, quote: "q", range: NSRange(location: at, length: 1), note: "в \(scene)")]
            return c
        }
        var set = CollectedSet()
        set.merge([character("Анна", scene: "a", at: 1, detail: "Коротко.")])
        set.merge([character("анна", scene: "b", at: 5, detail: "Подробнее и длиннее."), character("Аня", aliases: ["Анна"], scene: "c", at: 9)])
        #expect(set.items.count == 1 && set.items[0].evidence.map(\.scene) == ["a", "b", "c"], "\(set.items.map(\.name))")
        #expect(set.items[0].detail == "Подробнее и длиннее." && set.items[0].aliases == ["Аня"])
        set.merge([character("Анна", scene: "a", at: 1)])
        #expect(set.items[0].evidence.count == 3, "the same place in the same scene is not counted twice")
        var r1 = CollectedItem(kind: .relationships, name: ""); r1.members = ["Анна", "Вера"]; r1.type = "тётя"
        var r2 = CollectedItem(kind: .relationships, name: ""); r2.members = ["вера", "анна"]; r2.type = "Тётя"
        set.merge([r1, r2])
        #expect(set.items.filter { $0.kind == .relationships }.count == 1, "a relationship is the same whichever way it is written")
    }

    @Test("a long scene is cut at paragraph ends, and the offsets add up")
    func chunking() {
        let paragraph = String(repeating: "слово ", count: 100) + "\n"
        let text = String(repeating: paragraph, count: 10)
        let chunks = CollectChunker.chunks(text, maxCharacters: 1500)
        #expect(chunks.count >= 3 && chunks.allSatisfy { $0.text.count <= 1500 + 600 })
        #expect(chunks.map(\.text).joined() == text, "nothing lost")
        var at = 0
        for c in chunks { #expect(c.offset == at); at += (c.text as NSString).length }
        #expect(CollectChunker.chunks("short", maxCharacters: 1500).count == 1 && CollectChunker.chunks("", maxCharacters: 1500).isEmpty)
        #expect(CollectJob.pieceSize(context: 40960) == 8000 && CollectJob.pieceSize(context: 4096) == 1500)
    }

    // MARK: The job

    final class Gathered: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [CollectedItem] = []
        private var _progress: [CollectProgress] = []
        func add(_ i: [CollectedItem]) { lock.withLock { _items += i } }
        func add(_ p: CollectProgress) { lock.withLock { _progress.append(p) } }
        var items: [CollectedItem] { lock.withLock { _items } }
        var progress: [CollectProgress] { lock.withLock { _progress } }
    }

    static func scene(_ id: String, _ text: String) -> CollectScene { CollectScene(id: id, title: "Сцена \(id)", text: text) }

    static func answeringServer(_ answer: @escaping @Sendable (String) -> String) throws -> FakeLMServer {
        let server = try FakeLMServer()
        server.handler = { request, responder in
            let messages = (request.json?["messages"] as? [[String: Any]]) ?? []
            let user = (messages.last?["content"] as? String) ?? ""
            responder.json(["choices": [["message": ["content": answer(user)]]]])
        }
        return server
    }

    @Test("the job reads scene after scene, reports, skips short and unchanged scenes, and keeps what it found")
    func job() async throws {
        let long = Self.passage + " " + String(repeating: "Они шли медленно и молчали. ", count: 12)
        let server = try Self.answeringServer { user in
            if user.contains("Сцена two") { return "not json at all" }
            return "{\"characters\": [{\"name\": \"Анна\", \"description\": \"d\", \"note\": \"n\", \"quote\": \"Анна стояла на платформе\"}]}"
        }
        let client = LLMTests.client(server)
        var request = CollectRequest(kinds: [.characters], scenes: [Self.scene("one", long), Self.scene("two", long), Self.scene("tiny", "Коротко."), Self.scene("three", long)])
        request.context = 8192
        let gathered = Gathered()
        let summary = await CollectJob.run(request, client: client, progress: { gathered.add($0) }, found: { gathered.add($0) })
        #expect(summary.scenesDone == 3 && summary.scenesTooShort == 1 && summary.failedPieces == 1 && !summary.stopped && summary.error == nil)
        #expect(gathered.items.count == 2 && gathered.progress.map(\.scene) == [1, 2, 4], "scene two's answer was not JSON")
        #expect(Set(summary.analysed.keys) == ["one", "three"], "a scene whose answer failed is not remembered as read")
        // Again with the memory: the scenes read before are skipped; Re-analyse reads them all.
        var again = request
        again.analysed = summary.analysed
        let second = await CollectJob.run(again, client: client, progress: { _ in }, found: { _ in })
        #expect(second.scenesSkipped == 2 && second.scenesDone == 1)
        again.reanalyse = true
        let third = await CollectJob.run(again, client: client, progress: { _ in }, found: { _ in })
        #expect(third.scenesSkipped == 0 && third.scenesDone == 3)
        // A different ask is a different fingerprint.
        #expect(CollectJob.fingerprint(long, kinds: [.characters]) != CollectJob.fingerprint(long, kinds: [.characters, .places]))
        // The request carries the instructions, the known names and the passage.
        let body = String(decoding: server.requests.last!.body, as: UTF8.self)
        #expect(body.contains("EXACTLY") && body.contains("Анна стояла") && body.contains("no_think"))
    }

    @Test("Stop keeps what was found; a server that does not answer ends the run with the reason")
    func stopping() async throws {
        let long = Self.passage + " " + String(repeating: "Они шли медленно и молчали. ", count: 12)
        let server = try Self.answeringServer { _ in "{\"characters\": [{\"name\": \"Анна\", \"description\": \"\", \"note\": \"\", \"quote\": \"Анна стояла на платформе\"}]}" }
        let client = LLMTests.client(server)
        let request = CollectRequest(kinds: [.characters], scenes: (1...20).map { Self.scene("s\($0)", long) })
        let gathered = Gathered()
        let task = Task { await CollectJob.run(request, client: client, progress: { gathered.add($0) }, found: { gathered.add($0) }) }
        while gathered.items.count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        task.cancel()
        let summary = await task.value
        #expect(summary.stopped && summary.scenesDone < 20 && gathered.items.count >= 2)
        var closed: FakeLMServer? = try FakeLMServer()
        let dead = LLMTests.client(closed!)
        closed = nil
        let failed = await CollectJob.run(request, client: dead, progress: { _ in }, found: { _ in })
        #expect(failed.error?.contains("LM Studio") == true && failed.scenesDone == 0)
    }
}
