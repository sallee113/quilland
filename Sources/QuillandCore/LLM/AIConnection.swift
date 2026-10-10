import Foundation

/// What the AI actions need to know about the local model server: whether it answers, which model they would use, and how much it can read at once.
/// Worked out from the author's settings and what the server says (quilland-ui.md, "AI"; the server is LM Studio on this computer, never anything else).
public struct AIStatus: Equatable, Sendable {
    public var reachable: Bool
    /// The chat models the server has (embedding models left out).
    public var models: [ModelInfo]
    /// The one the actions would use: the author's choice if the server has it, else the first loaded model, else the first.
    public var model: String?
    /// What the server says about that model (its name, size, quantization).
    public var info: ModelInfo?
    /// How many tokens the model reads at once (the author's setting, or what the server says, or a default).
    public var context: Int
    public var loaded: Bool
    /// One sentence for the Settings window.
    public var message: String
}

public enum AIConnection {
    public static let defaultAddress = "http://localhost:1234"

    /// The client's configuration for these settings. The address may end in `/v1` or not.
    public static func config(address: String, model: String) -> LLMConfig? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = defaultAddress }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if !text.hasSuffix("/v1") { text += "/v1" }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return LLMConfig(baseURL: url, chatModel: model)
    }

    /// Asks the server. Never throws: a server that does not answer is a status, not an error.
    public static func check(address: String, model wanted: String, contextSetting: Int) async -> AIStatus {
        guard let config = config(address: address, model: wanted) else {
            return AIStatus(reachable: false, models: [], model: nil, info: nil, context: LMStudioClient.defaultContext, loaded: false, message: L("The address is not valid."))
        }
        let client = LMStudioClient(config: config)
        do {
            let all = try await client.listModels(timeout: 4)
            let chat = all.filter { !$0.isEmbedding }
            guard !chat.isEmpty else {
                return AIStatus(reachable: true, models: [], model: nil, info: nil, context: LMStudioClient.defaultContext, loaded: false, message: L("LM Studio answers, but has no chat model. Download one in LM Studio."))
            }
            let chosen = chat.first { $0.id == wanted } ?? chat.first { $0.loaded == true } ?? chat[0]
            let context = contextSetting > 0 ? contextSetting : (chosen.loadedContext ?? chosen.maxContext ?? LMStudioClient.defaultContext)
            let isLoaded = chosen.loaded != false
            var message = L("Connected. The model is “{model}”, {context} tokens at a time.", ["model": chosen.id, "context": context])
            if !wanted.isEmpty && chosen.id != wanted { message = L("“{wanted}” is not on the server; “{model}” will be used instead.", ["wanted": wanted, "model": chosen.id]) }
            else if !isLoaded { message += " " + L("It is not loaded yet; LM Studio loads it when the first request comes.") }
            return AIStatus(reachable: true, models: chat, model: chosen.id, info: chosen, context: context, loaded: isLoaded, message: message)
        } catch {
            return AIStatus(reachable: false, models: [], model: nil, info: nil, context: LMStudioClient.defaultContext, loaded: false, message: "\(error)")
        }
    }
}
