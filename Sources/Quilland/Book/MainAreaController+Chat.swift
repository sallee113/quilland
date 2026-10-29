import AppKit
import QuillandCore

extension MainAreaController {
    private var chatBook: ChatMentions.Book {
        let structure = session.structure
        return ChatMentions.Book(structure: structure, characters: characters, worlds: worlds, events: eventStore, relationships: relationships, plan: try? PlanStore(folder: folder),
                                 sceneText: { [weak self] id in self?.session.document(id)?.storage.string ?? "" })
    }

    /// The scene the chat is about: where the cursor is (or the one the right panel shows).
    private var chatScene: String? { rightPanel.shownScene ?? currentSceneID }

    /// What `@` offers: the current scene and chapter, what is found in the scene, the plan and the synopses, and any one character, place, event or scene.
    func chatMentionsMenu() -> NSMenu {
        let menu = NSMenu()
        let book = chatBook
        func attach(_ attachment: ChatAttachment?, _ what: String) {
            chatSession.mentionPicked = true
            if let attachment { chatSession.attach(attachment) } else { NSSound.beep(); onAIStatus?(L("Nothing found for {what}.", ["what": what])) }
        }
        let scene = chatScene
        let entries: [(String, () -> ChatAttachment?)] = [
            ("@" + L("scene"), { scene.flatMap { ChatMentions.scene($0, in: book) } }),
            ("@" + L("chapter"), { scene.flatMap { ChatMentions.chapter(of: $0, in: book) } }),
            ("@" + L("characters"), { scene.flatMap { ChatMentions.characters(of: $0, in: book) } }),
            ("@" + L("places"), { scene.flatMap { ChatMentions.places(of: $0, in: book) } }),
            ("@" + L("events"), { scene.flatMap { ChatMentions.events(of: $0, in: book) } }),
            ("@" + L("plan"), { ChatMentions.plan(in: book) }),
            ("@" + L("cards"), { ChatMentions.cards(in: book) }),
            ("@" + L("synopses"), { ChatMentions.synopses(in: book) }),
        ]
        for (title, make) in entries { menu.addItem(ClosureMenuItem(title: title) { attach(make(), title) }) }
        menu.addItem(.separator())
        func submenu(_ title: String, _ items: [(String, ChatMentions.Item)]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (name, item) in items.prefix(200) { sub.addItem(ClosureMenuItem(title: name) { attach(ChatMentions.item(item, in: book), name) }) }
            if items.isEmpty { let none = NSMenuItem(title: L("None yet"), action: nil, keyEquivalent: ""); none.isEnabled = false; sub.addItem(none) }
            parent.submenu = sub
            menu.addItem(parent)
        }
        submenu(L("A character…"), characters.characters.compactMap { c in c.id.map { (c.name ?? "", .character($0)) } })
        submenu(L("A place or thing…"), worlds.entries.compactMap { e in e.id.map { (e.name ?? "", .place($0)) } })
        submenu(L("An event…"), eventStore.events.compactMap { e in e.id.map { (e.title ?? "", .event($0)) } })
        submenu(L("A scene…"), session.structure.scenes.map { ($0.node.title, .scene($0.id)) })
        return menu
    }

    /// Asks where the last answer should be saved, then appends it there.
    func saveChatAnswer() {
        guard let answer = chatSession.lastAnswer else { return }
        let targets = chatSession.noteTargets()
        guard !targets.isEmpty else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = L("Save the answer as a note")
        alert.informativeText = L("It is added after what the note already says.")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26), pullsDown: false)
        popup.addChoices(targets.enumerated().map { (title: $1.title, value: $0) })   // (two targets can share a title: the entry knows its place in the list)
        alert.accessoryView = popup
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let at = popup.chosenValue as? Int, targets.indices.contains(at) else { return }
        let t = targets[at]
        if chatSession.saveAnswer(answer, kind: t.kind, id: t.id) { onAIStatus?(L("Saved.")) } else { NSSound.beep() }
    }

    /// Keeps the last question as an action of the AI menu, with the kinds of material that were attached to it.
    func saveChatAction() {
        guard let prompt = chatSession.turns.last(where: { $0.role == "user" })?.content else { return }
        let kinds = chatSession.attachments.compactMap(\.mention)
        let alert = NSAlert()
        alert.messageText = L("Save the prompt as an action")
        alert.informativeText = kinds.isEmpty ? L("It will appear in the AI menu under Actions. Nothing is attached when it runs.")
            : L("It will appear in the AI menu under Actions. When it runs, it attaches: {kinds}.", ["kinds": kinds.map { L($0) }.joined(separator: ", ")])
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.stringValue = String(prompt.prefix(40))
        field.placeholderString = L("A name")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        AppPreferences.shared.updateActions { $0.append(AIAction(name: name, prompt: prompt, attach: kinds)) }
        onAIStatus?(L("Saved in the AI menu."))
    }

    /// Runs a saved action: the Chat opens, the material it asks for is attached for the scene where the cursor is, and the prompt is sent.
    func runAIAction(_ action: AIAction) {
        guard AIService.shared.isReady else {
            let alert = NSAlert()
            alert.messageText = L("The AI is not available")
            alert.informativeText = AIService.shared.unavailableReason ?? ""
            alert.runModal()
            return
        }
        if !AppPreferences.shared.values.panelTabs.contains("chat") { AppPreferences.shared.update { $0.panelTabs.append("chat") } }
        if !showsRightPanel { setRightPanel(true) }
        rightPanel.showTab(.chat)
        let book = chatBook
        let scene = chatScene
        for key in action.attach { if let a = ChatMentions.attachment(for: key, scene: scene, in: book) { chatSession.attach(a) } }
        chatSession.send(action.prompt)
    }
}
