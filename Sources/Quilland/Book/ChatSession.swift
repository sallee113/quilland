import AppKit
import QuillandCore

/// One conversation with the model about the book: it lasts while the book is open and is not kept. The chat only answers; it changes nothing in the book.
final class ChatSession {
    weak var main: MainAreaController?
    private(set) var turns: [ChatTurn] = []
    private(set) var attachments: [ChatAttachment] = []
    /// The answer as far as it has come (nil when none is being written).
    private(set) var streaming: String?
    private(set) var error: String?
    var onChange: (() -> Void)?
    private var task: Task<Void, Never>?
    /// The prompts of this book, for the up arrow (newest last), and where the arrow is now.
    /// Set when something was attached from the list that a typed `@` opened (the @ is then taken out of the text).
    var mentionPicked = false
    private(set) var recent: [String] = []
    private var recallIndex: Int?

    init() {}

    var running: Bool { streaming != nil }
    var lastAnswer: String? { turns.last(where: { $0.role == "assistant" })?.content }

    func loadRecent() { if let main { recent = ChatPrompts.load(book: main.folder) } }

    // MARK: Attachments

    func attach(_ a: ChatAttachment) {
        guard !attachments.contains(where: { $0.label == a.label }) else { return }
        attachments.append(a)
        onChange?()
    }

    func remove(_ id: UUID) { attachments.removeAll { $0.id == id }; onChange?() }

    var usage: ChatUsage {
        ChatPrompt.usage(history: turns, attachments: attachments, language: main?.bookLanguage ?? "", context: AIService.shared.context)
    }

    // MARK: Prompts

    /// ↑ and ↓ in an empty field: the earlier prompts, newest first.
    func recall(older: Bool) -> String? {
        guard !recent.isEmpty else { return nil }
        if older { recallIndex = recallIndex.map { max(0, $0 - 1) } ?? recent.count - 1 }
        else if let i = recallIndex { recallIndex = i + 1 < recent.count ? i + 1 : nil } else { return nil }
        return recallIndex.map { recent[$0] } ?? ""
    }

    // MARK: Sending

    func send(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running, let main else { return }
        guard let client = AIService.shared.client() else {
            error = AIService.shared.unavailableReason ?? L("The AI is not available")
            onChange?()
            return
        }
        error = nil
        recallIndex = nil
        ChatPrompts.remember(text, book: main.folder)
        loadRecent()
        let (messages, _) = ChatPrompt.build(history: turns, question: text, attachments: attachments, language: main.bookLanguage, context: AIService.shared.context)
        turns.append(ChatTurn("user", text))
        streaming = ""
        onChange?()
        let me = self
        task = Task {
            var answer = ""
            do {
                for try await event in client.chatStream(messages, think: false, temperature: AIPrompts.temperature("chat", default: 0.7), maxTokens: 1800) {
                    guard case .text(let piece) = event else { continue }
                    answer += piece
                    let snapshot = answer
                    await MainActor.run { me.streaming = snapshot; me.onChange?() }
                }
                let finished = answer
                await MainActor.run {
                    let final = finished.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !final.isEmpty { me.turns.append(ChatTurn("assistant", final)) }
                    me.streaming = nil; me.task = nil; me.onChange?()
                }
            } catch {
                let partialText = answer
                await MainActor.run {
                    let partial = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !partial.isEmpty { me.turns.append(ChatTurn("assistant", partial)) }
                    if !(error is CancellationError) { me.error = "\(error)" }
                    me.streaming = nil; me.task = nil; me.onChange?()
                }
            }
        }
    }

    /// Stop keeps what has been written.
    func stop() { task?.cancel() }

    /// For the checks: puts turns in the conversation.
    func inject(_ new: [ChatTurn]) { turns += new; onChange?() }

    func newConversation() { task?.cancel(); turns = []; streaming = nil; error = nil; onChange?() }

    /// For the checks: waits until the answer is complete.
    func waitUntilDone(timeout: TimeInterval = 120) {
        let end = Date().addingTimeInterval(timeout)
        while running, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    // MARK: Saving an answer

    /// What an answer may be saved on: the note of the current scene, or the notes of a character or a place.
    func noteTargets() -> [(title: String, kind: String, id: String)] {
        guard let main else { return [] }
        var out: [(String, String, String)] = []
        if let scene = main.rightPanel.shownScene ?? main.currentSceneID, let node = main.findNode(scene) { out.append((L("Note of the scene “{title}”", ["title": node.title]), "scene", scene)) }
        out += main.characters.characters.compactMap { c in c.id.map { (L("Notes of the character “{name}”", ["name": c.name ?? ""]), "character", $0) } }
        out += main.worlds.entries.compactMap { e in e.id.map { (L("Notes of the place “{name}”", ["name": e.name ?? ""]), "place", $0) } }
        return out
    }

    /// Appends the answer to a note, after what is there. Returns whether it was saved.
    @discardableResult
    func saveAnswer(_ text: String, kind: String, id: String) -> Bool {
        guard let main else { return false }
        switch kind {
        case "scene":
            let editor = BookEditor(structure: main.session.structure)
            let old = editor.record(id)?.string("note") ?? ""
            do { try editor.setText(id, key: "note", to: old.isEmpty ? text : old + "\n\n" + text) } catch { return false }
            main.didChangeSectionTexts()
        case "character":
            try? main.characters.update(id) { $0.notes = $0.notes + text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
        case "place":
            try? main.worlds.updateEntry(id) { $0.notes = $0.notes + text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
        default: return false
        }
        main.collectedCardsChanged()
        return true
    }
}
