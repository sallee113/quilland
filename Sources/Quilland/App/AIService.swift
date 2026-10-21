import AppKit
import QuillandCore

/// The application's one connection to the local model: what the server said last time, and a client for the AI actions.
/// The AI is always optional: with it off, or with nothing answering, the actions are unavailable and say why.
final class AIService {
    static let shared = AIService()

    private(set) var status: AIStatus?
    private(set) var checking = false
    private var generation = 0

    var settings: Preferences { AppPreferences.shared.values }
    var isEnabled: Bool { settings.aiEnabled }
    /// The model is there and the actions can start.
    var isReady: Bool { isEnabled && status?.reachable == true && status?.model != nil }

    /// Why the actions are unavailable, in a sentence; nil when they are available.
    var unavailableReason: String? {
        if !isEnabled { return L("The AI is switched off (Settings ▸ AI).") }
        guard let status else { return L("The connection to LM Studio has not been checked yet (Settings ▸ AI).") }
        if !status.reachable || status.model == nil { return status.message }
        return nil
    }

    /// The model's context in tokens, as far as it is known.
    var context: Int { status?.context ?? (settings.aiContext > 0 ? settings.aiContext : LMStudioClient.defaultContext) }

    func client() -> LMStudioClient? {
        guard isReady, let model = status?.model, let config = AIConnection.config(address: settings.aiAddress, model: model) else { return nil }
        return LMStudioClient(config: config)
    }

    /// Takes a new status (what the server said, or nothing) and tells whoever listens.
    func apply(_ new: AIStatus?) {
        status = new
        changed()
    }

    /// Tells the places that depend on the AI (`.aiStatusChanged`) that something about the connection is different.
    private func changed() { NotificationCenter.default.post(name: .aiStatusChanged, object: nil) }

    /// Asks the server again (the address, the model or the context may have changed). `completion` gets the new status on the main thread.
    func refresh(completion: ((AIStatus) -> Void)? = nil) {
        guard isEnabled else {
            apply(nil)
            return
        }
        generation += 1
        let mine = generation
        checking = true
        changed()
        let s = settings
        Task {
            let result = await AIConnection.check(address: s.aiAddress, model: s.aiModel, contextSetting: s.aiContext)
            await MainActor.run {
                let me = AIService.shared
                guard mine == me.generation else { return }
                me.checking = false
                me.apply(result)
                completion?(result)
            }
        }
    }
}
