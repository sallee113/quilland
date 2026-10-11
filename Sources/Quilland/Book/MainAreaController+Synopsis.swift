import AppKit
import QuillandCore

extension MainAreaController {
    /// The field the synopsis goes in, and the section it is for: the Outline's, when it shows one section; else the current scene's, in the right panel.
    private func synopsisTarget() -> (field: SuggestTextView, section: BookStructure.Node)? {
        if mode == .outline {
            guard let detail = outlineDetail, detail.shown.count == 1, let id = detail.shown.first, let node = findNode(id) else { return nil }
            return (detail.synopsis, node)
        }
        guard let id = currentSceneID, let node = findNode(id) else { return nil }
        if !showsRightPanel { setRightPanel(true) }
        rightPanel.showTab(.section)
        rightPanel.show(id)
        return (rightPanel.synopsis, node)
    }

    /// What a chapter's or a part's synopsis is written from: its children and their synopses (a chapter without its own is described by its scenes').
    private func synopsisChildren(of node: BookStructure.Node) -> [(title: String, synopsis: String)] {
        let editor = BookEditor(structure: session.structure)
        func own(_ n: BookStructure.Node) -> String { editor.record(n.id)?.string("synopsis") ?? "" }
        return node.children.map { child in
            var text = own(child)
            if text.isEmpty { text = child.children.map(own).filter { !$0.isEmpty }.joined(separator: " ") }
            return (child.title, text)
        }
    }

    /// AI ▸ Write Synopsis (⌃⌘Y): the model writes the synopsis of the chosen section, shown faint in its field; Tab replaces the synopsis with it, Esc drops it.
    func writeSynopsis() {
        guard AIService.shared.isReady, let client = AIService.shared.client() else {
            let alert = NSAlert()
            alert.messageText = L("The AI is not available")
            alert.informativeText = AIService.shared.unavailableReason ?? ""
            alert.runModal()
            return
        }
        guard let target = synopsisTarget() else { NSSound.beep(); return }
        let node = target.section, field = target.field
        let language = bookLanguage
        let context = AIService.shared.context
        let kind = node.kind
        var userText = ""
        var sceneText = ""
        if kind == .scene {
            sceneText = session.document(node.id)?.storage.string ?? ""
            guard sceneText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 else { NSSound.beep(); onAIStatus?(L("This scene has too little text for a synopsis.")); return }
        } else {
            let children = synopsisChildren(of: node)
            guard children.contains(where: { !$0.synopsis.isEmpty }) else { onAIStatus?(L("Nothing to write from: its scenes have no synopses yet.")); return }
            userText = SynopsisPrompt.userForSection(kind: kind, title: node.title, children: children)
        }
        // Tab and Esc go to the field that holds the suggestion, so the field takes the keyboard (a click on the button left it elsewhere).
        field.window?.makeFirstResponder(field)
        let existing = field.string
        field.ghost.replacesAll = !existing.isEmpty
        var finished = false
        field.ghost.begin { [weak self] in finished = true; self?.continueTask?.cancel(); self?.onAIStatus?(nil) }
        if !existing.isEmpty { field.ghost.append("\n") }
        onAIStatus?(L("Writing the synopsis… Esc stops"))
        let me = self
        continueTask = Task {
            do {
                if kind == .scene {
                    // A scene longer than the model reads at once is summarised piece by piece first.
                    let budget = min(30000, max(1500, Int(Double(max(2048, context) - 2500) * 2.4)))
                    var text = sceneText
                    if text.count > budget {
                        let pieces = CollectChunker.chunks(text, maxCharacters: budget / 2)
                        var parts: [String] = []
                        for (i, p) in pieces.enumerated() {
                            await MainActor.run { me.onAIStatus?(L("Reading part {n} of {total}…", ["n": i + 1, "total": pieces.count])) }
                            let reply = try await client.chat([ChatMessage("system", SynopsisPrompt.pieceSystem), ChatMessage("user", SynopsisPrompt.pieceUser(title: node.title, index: i + 1, of: pieces.count, text: p.text))], think: false, temperature: 0.3, maxTokens: 300)
                            parts.append(reply.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        text = parts.joined(separator: "\n")
                    }
                    userText = SynopsisPrompt.userForScene(title: node.title, text: text)
                    await MainActor.run { me.onAIStatus?(L("Writing the synopsis… Esc stops")) }
                }
                var filter = ContinuationFilter(before: "")
                let messages = [ChatMessage("system", SynopsisPrompt.system(kind: kind, language: language)), ChatMessage("user", userText)]
                for try await event in client.chatStream(messages, think: false, temperature: AIPrompts.temperature("synopsis.scene", default: 0.4), maxTokens: 500) {
                    guard case .text(let piece) = event else { continue }
                    let cleaned = filter.feed(piece)
                    if !cleaned.isEmpty { await MainActor.run { if !finished { field.ghost.append(cleaned) } } }
                    if filter.isFinished { break }
                }
                await MainActor.run { me.onAIStatus?(field.ghost.isActive ? L("Tab accepts, Esc discards") : nil); me.continueTask = nil }
            } catch {
                await MainActor.run {
                    me.continueTask = nil
                    if !finished { field.ghost.discard(); if !(error is CancellationError) { me.onAIStatus?("\(error)") } }
                }
            }
        }
    }
}
