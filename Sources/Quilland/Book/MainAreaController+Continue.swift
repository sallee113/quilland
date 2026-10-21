import AppKit
import QuillandCore

extension MainAreaController {
    /// The text view where the cursor is, and its scene.
    private var writingTarget: (view: EditorTextView, scene: String, document: SceneDocument)? {
        guard let c = controllers.first(where: { $0.currentSceneID != nil }) ?? controllers.first, let id = c.currentSceneID,
              let sheet = c.currentSheet, let doc = session.document(id) else { return nil }
        return (sheet.textView, id, doc)
    }

    /// AI ▸ Continue Writing (⌃⌘G): the model writes one paragraph after the cursor, shown faint; Tab accepts it, Esc discards it. Asked again while one is
    /// shown, it writes another. With `askDirection`, a line says where the story should go.
    func continueWriting(askDirection: Bool) {
        guard let target = writingTarget, mode == .book || mode == .panels else { return }
        guard AIService.shared.isReady, let client = AIService.shared.client() else {
            let alert = NSAlert()
            alert.messageText = L("The AI is not available")
            alert.informativeText = AIService.shared.unavailableReason ?? ""
            alert.runModal()
            return
        }
        var direction: String?
        if askDirection {
            guard let asked = askContinueDirection() else { return }
            direction = asked
        }
        let view = target.view
        view.discardGhost()
        continueTask?.cancel()

        let text = target.document.storage.string as NSString
        let caret = min(text.length, NSMaxRange(view.selectedRange()))
        let before = text.substring(to: caret), after = text.substring(from: caret)
        let structure = session.structure
        let record = BookEditor(structure: structure).record(target.scene)
        let sources = ConsistencySources.gather(sceneID: target.scene, passage: before.suffix(6000).description, characters: characters, worlds: worlds, events: eventStore, relationships: relationships,
                                                structure: structure, budget: 6000)
        let linked = Set(eventStore.events.filter { $0.links.keys.contains(target.scene) }.compactMap(\.id))
        let planCards: [(title: String, text: String)] = ((try? PlanStore(folder: folder))?.cards.values.filter { card in !linked.isDisjoint(with: Set(card.links.keys)) }
            .compactMap { c in c.title.map { ($0, c.text ?? "") } }) ?? []
        let (messages, summary) = ContinuePrompt.messages(before: before, after: after, language: bookLanguage, synopsis: record?.string("synopsis") ?? "", note: record?.string("note") ?? "",
                                                           sources: sources, planCards: planCards, direction: direction, context: AIService.shared.context)
        onAIStatus?(Self.continueStatus(summary))
        var filter = ContinuationFilter(before: before)
        var finished = false
        view.beginGhost { [weak self] in
            finished = true
            self?.continueTask?.cancel()
            self?.onAIStatus?(nil)
        }
        let me = self
        continueTask = Task {
            do {
                for try await event in client.chatStream(messages, think: false, temperature: AIPrompts.temperature("continue", default: 0.8), maxTokens: 700) {
                    guard case .text(let piece) = event else { continue }
                    let cleaned = filter.feed(piece)
                    if !cleaned.isEmpty { await MainActor.run { if !finished { view.appendGhost(cleaned) } } }
                    if filter.isFinished { break }
                }
                await MainActor.run { me.onAIStatus?(view.hasGhost ? L("Tab accepts, Esc discards") : nil); me.continueTask = nil }
            } catch {
                await MainActor.run {
                    me.continueTask = nil
                    if !finished {
                        view.discardGhost()
                        if !(error is CancellationError) { me.onAIStatus?("\(error)") }
                    }
                }
            }
        }
    }

    static func continueStatus(_ s: ContinueSummary) -> String {
        var parts = [Lp("{n} character of the text", "{n} characters of the text", s.textCharacters)]
        if s.cards > 0 { parts.append(Lp("{n} card", "{n} cards", s.cards)) }
        if s.hasPlan { parts.append(L("the plan")) }
        if s.hasDirection { parts.append(L("your direction")) }
        let number = { (n: Int) in NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
        return L("Writing… {parts}: {tokens} of {context} tokens · Esc stops", ["parts": parts.joined(separator: ", "), "tokens": number(s.tokens), "context": number(s.context)])
    }

    /// For the checks: waits until the suggestion is complete.
    func waitForContinuation(timeout: TimeInterval = 120) {
        let end = Date().addingTimeInterval(timeout)
        while continueTask != nil, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    private func askContinueDirection() -> String? {
        let alert = NSAlert()
        alert.messageText = L("Continue Writing")
        alert.informativeText = L("Where should the story go? One line is enough, for example “they quarrel”. It can stay empty.")
        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        let recent = UserDefaults.standard.stringArray(forKey: "continueDirections") ?? []
        field.addItems(withObjectValues: recent)
        field.placeholderString = L("A direction")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Continue"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { UserDefaults.standard.set(Array(([text] + recent.filter { $0 != text }).prefix(5)), forKey: "continueDirections") }
        return text
    }
}
