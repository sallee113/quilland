import Foundation

// Experiment 5: talking to LM Studio (or any OpenAI-compatible local server) from Swift.
// A port of the old app's `llm/client.py`, with streaming that ends the moment the consumer stops.

public struct LLMConfig: Sendable, Equatable {
    /// For example `http://localhost:1234/v1`.
    public var baseURL: URL
    public var chatModel: String
    public var embeddingModel: String
    public init(baseURL: URL, chatModel: String, embeddingModel: String = "") {
        self.baseURL = baseURL
        self.chatModel = chatModel
        self.embeddingModel = embeddingModel
    }
}

public struct ChatMessage: Sendable, Equatable {
    public var role: String
    public var content: String
    public init(_ role: String, _ content: String) {
        self.role = role
        self.content = content
    }
}

public enum LLMEvent: Sendable, Equatable {
    /// A piece of the answer, reasoning left out.
    case text(String)
    /// The model is reasoning (its text is not given); sent once each time reasoning grows by a piece. For a "thinking…" indicator.
    case reasoning(characters: Int)
    /// The reply is complete.
    case finished(reason: String?, promptTokens: Int?, completionTokens: Int?)
}

public enum LLMError: Error, Equatable, CustomStringConvertible {
    /// Nothing answers at the address: LM Studio is not running, or its server is not started.
    case unreachable
    /// The server is there but slow: not a reason to switch the AI off.
    case timedOut
    case server(status: Int, message: String)
    case badResponse(String)

    public var description: String {
        switch self {
        case .unreachable: return "LM Studio doesn't answer. Is it running, with its server started (Developer › Status: Running)?"
        case .timedOut: return "The model didn't answer in time."
        case .server(let status, let message): return Self.humanize(status: status, message: message)
        case .badResponse(let text): return "The server sent something unexpected: \(text)"
        }
    }

    static func humanize(status: Int, message: String) -> String {
        if message.contains("insufficient system resources") || message.contains("resource guardrails") {
            return "Not enough memory to load the model next to the one already loaded. Pick a smaller model or context size."
        }
        if message.contains("not found in downloaded models") || message.contains("model_not_found") {
            return "This model isn't downloaded in LM Studio: \(message)"
        }
        return message.isEmpty ? "The server answered with status \(status)." : message
    }
}

public struct ModelInfo: Equatable, Sendable {
    public var id: String
    /// "llm", "vlm", "embeddings", or "" when the server doesn't say.
    public var kind: String
    /// nil: the server doesn't say.
    public var loaded: Bool?
    public var architecture = ""
    public var quantization = ""
    public var format = ""
    public var maxContext: Int?
    public var loadedContext: Int?
    public var sizeBytes: Int?
    /// A name for people ("Qwen3 14B") and the size in parameters ("14B"), when the server says them.
    public var displayName = ""
    public var params = ""
    public var isEmbedding: Bool { kind == "embeddings" || kind == "embedding" || (kind.isEmpty && id.lowercased().contains("embed")) }
}

public final class LMStudioClient: @unchecked Sendable {
    public static let answerTimeout: TimeInterval = 30 * 60
    public static let defaultContext = 8192
    public static let contextRecheck: TimeInterval = 60

    public let config: LLMConfig
    /// Called when the server cannot be reached at all (the app then switches the AI actions off).
    public var onUnreachable: (@Sendable () -> Void)?

    private let session: URLSession
    private let lock = NSLock()
    private var cachedContext: Int?
    private var contextChecked = Date.distantPast

    public init(config: LLMConfig) {
        self.config = config
        let c = URLSessionConfiguration.ephemeral
        // How long the server may stay silent: it reads the whole prompt first, sending nothing meanwhile.
        c.timeoutIntervalForRequest = Self.answerTimeout
        c.timeoutIntervalForResource = 4 * 3600
        c.waitsForConnectivity = false
        c.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: c)
    }

    deinit { session.invalidateAndCancel() }

    // MARK: Requests

    /// Qwen3 models reason by default, which costs several times the tokens of the answer; `/no_think` on the last message stops it.
    static func withThinkDirective(_ messages: [ChatMessage], think: Bool) -> [ChatMessage] {
        guard !think, var last = messages.last else { return messages }
        last.content += " /no_think"
        return Array(messages.dropLast()) + [last]
    }

    func chatRequest(_ messages: [ChatMessage], think: Bool, temperature: Double?, maxTokens: Int?, stream: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": config.chatModel,
            "messages": Self.withThinkDirective(messages, think: think).map { ["role": $0.role, "content": $0.content] },
            "stream": stream,
        ]
        if stream { body["stream_options"] = ["include_usage": true] }
        if let temperature { body["temperature"] = temperature }
        if let maxTokens { body["max_tokens"] = maxTokens }
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer not-needed", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func translate(_ error: Error) -> Error {
        if let e = error as? LLMError { return e }
        if let e = error as? URLError {
            switch e.code {
            case .timedOut: return LLMError.timedOut
            case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .notConnectedToInternet, .dnsLookupFailed:
                onUnreachable?()
                return LLMError.unreachable
            default: return e
            }
        }
        return error
    }

    private static func serverMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let message = object["error"] as? String { return message }
            if let message = object["message"] as? String { return message }
        }
        return String(decoding: data.prefix(500), as: UTF8.self)
    }

    /// Streams the answer. **Stopping is cancelling:** when the consuming task is cancelled, or the loop ends early,
    /// the connection is closed at once, even while the server is still reading the prompt and has sent nothing.
    public func chatStream(_ messages: [ChatMessage], think: Bool = false, temperature: Double? = nil, maxTokens: Int? = nil) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try chatRequest(messages, think: think, temperature: temperature, maxTokens: maxTokens, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse("no HTTP response") }
                    if http.statusCode != 200 {
                        var body = Data()
                        for try await byte in bytes { body.append(byte); if body.count > 4000 { break } }
                        throw LLMError.server(status: http.statusCode, message: Self.serverMessage(from: body))
                    }
                    var filter = ReasoningFilter()
                    var finishReason: String?
                    var usage: (Int?, Int?) = (nil, nil)
                    var reasoningSeen = 0
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }   // comments (": keep-alive") and blank lines
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            throw LLMError.badResponse(String(payload.prefix(200)))
                        }
                        if let error = object["error"] as? [String: Any] { throw LLMError.server(status: 200, message: error["message"] as? String ?? "") }
                        if let u = object["usage"] as? [String: Any] { usage = (u["prompt_tokens"] as? Int, u["completion_tokens"] as? Int) }
                        guard let choice = (object["choices"] as? [[String: Any]])?.first else { continue }
                        if let reason = choice["finish_reason"] as? String { finishReason = reason }
                        let delta = choice["delta"] as? [String: Any]
                        // Some servers send reasoning in its own field.
                        if let r = (delta?["reasoning_content"] as? String) ?? (delta?["reasoning"] as? String), !r.isEmpty {
                            reasoningSeen += r.count
                            continuation.yield(.reasoning(characters: reasoningSeen))
                        }
                        if let piece = delta?["content"] as? String, !piece.isEmpty {
                            let before = filter.reasoningScalars
                            let text = filter.feed(piece)
                            if filter.reasoningScalars > before || filter.isThinking { continuation.yield(.reasoning(characters: reasoningSeen + filter.reasoningScalars)) }
                            if !text.isEmpty { continuation.yield(.text(text)) }
                        }
                    }
                    let rest = filter.finish()
                    if !rest.isEmpty { continuation.yield(.text(rest)) }
                    continuation.yield(.finished(reason: finishReason, promptTokens: usage.0, completionTokens: usage.1))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: translate(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole answer at once (reasoning removed).
    public func chat(_ messages: [ChatMessage], think: Bool = false, temperature: Double? = nil, maxTokens: Int? = nil) async throws -> String {
        do {
            let request = try chatRequest(messages, think: think, temperature: temperature, maxTokens: maxTokens, stream: false)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse("no HTTP response") }
            guard http.statusCode == 200 else { throw LLMError.server(status: http.statusCode, message: Self.serverMessage(from: data)) }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else { throw LLMError.badResponse("no message") }
            return Reasoning.strip(message["content"] as? String ?? "")
        } catch {
            throw translate(error)
        }
    }

    public func embed(_ text: String) async throws -> [Double] {
        do {
            var request = URLRequest(url: config.baseURL.appendingPathComponent("embeddings"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": config.embeddingModel, "input": text])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse("no HTTP response") }
            guard http.statusCode == 200 else { throw LLMError.server(status: http.statusCode, message: Self.serverMessage(from: data)) }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let vector = (object["data"] as? [[String: Any]])?.first?["embedding"] as? [Double] else { throw LLMError.badResponse("no embedding") }
            return vector
        } catch {
            throw translate(error)
        }
    }

    // MARK: Models

    private var serverRoot: URL {
        var s = config.baseURL.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/v1") { s.removeLast(3) }
        return URL(string: s)!
    }

    private func getJSON(_ url: URL, timeout: TimeInterval) async throws -> (Int, Any?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, try? JSONSerialization.jsonObject(with: data))
    }

    /// The models the server can use. LM Studio's own API (0.4+, then the older one) also says which are loaded and how big
    /// their context is; any other OpenAI-compatible server only gives the names.
    public func listModels(timeout: TimeInterval = 3) async throws -> [ModelInfo] {
        do {
            let (s1, j1) = try await getJSON(serverRoot.appendingPathComponent("api/v1/models"), timeout: timeout)
            if s1 == 200, let models = (j1 as? [String: Any])?["models"] as? [[String: Any]] {
                return models.compactMap { m in
                    guard let key = m["key"] as? String else { return nil }
                    let instances = m["loaded_instances"] as? [[String: Any]] ?? []
                    var quantization = ""
                    if let q = m["quantization"] as? [String: Any] { quantization = q["name"] as? String ?? "" } else if let q = m["quantization"] as? String { quantization = q }
                    return ModelInfo(id: key, kind: m["type"] as? String ?? "", loaded: !instances.isEmpty, architecture: m["architecture"] as? String ?? "",
                                     quantization: quantization, format: m["format"] as? String ?? "", maxContext: m["max_context_length"] as? Int,
                                     loadedContext: (instances.first?["config"] as? [String: Any])?["context_length"] as? Int, sizeBytes: m["size_bytes"] as? Int,
                                     displayName: m["display_name"] as? String ?? "", params: m["params_string"] as? String ?? "")
                }
            }
            let (s0, j0) = try await getJSON(serverRoot.appendingPathComponent("api/v0/models"), timeout: timeout)
            if s0 == 200, let data = (j0 as? [String: Any])?["data"] as? [[String: Any]] {
                return data.compactMap { m in
                    guard let id = m["id"] as? String else { return nil }
                    return ModelInfo(id: id, kind: m["type"] as? String ?? "", loaded: (m["state"] as? String) == "loaded", architecture: m["arch"] as? String ?? "",
                                     quantization: m["quantization"] as? String ?? "", format: m["compatibility_type"] as? String ?? "",
                                     maxContext: m["max_context_length"] as? Int, loadedContext: m["loaded_context_length"] as? Int)
                }
            }
            let (s, j) = try await getJSON(config.baseURL.appendingPathComponent("models"), timeout: timeout)
            guard s == 200, let data = (j as? [String: Any])?["data"] as? [[String: Any]] else { throw LLMError.badResponse("model list, status \(s)") }
            return data.compactMap { ($0["id"] as? String).map { ModelInfo(id: $0, kind: "") } }
        } catch {
            throw translate(error)
        }
    }

    /// The chat model's loaded context size in tokens (the maximum when it is not loaded; a default when the server cannot say).
    /// Asked again at most once a minute: the author may reload the model with another size.
    public func contextLength() async -> Int {
        let (fresh, current) = lock.withLock { (cachedContext != nil && Date().timeIntervalSince(contextChecked) < Self.contextRecheck, cachedContext) }
        if fresh, let current { return current }
        var length = current ?? Self.defaultContext
        if let models = try? await listModels(timeout: 2), let model = models.first(where: { $0.id == config.chatModel }),
           let n = model.loadedContext ?? model.maxContext, n > 0 { length = n }
        lock.withLock { cachedContext = length; contextChecked = Date() }
        return length
    }
}
