import AppKit
import QuillandCore

/// The card of a relationship in the Characters view: its kind ("sisters"), who takes part, notes, and the scenes where the characters meet, each with what
/// the relationship does there.
final class RelationshipCardController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    var store: RelationshipStore!
    var characters: CharacterStore!
    var scenes: () -> [(id: String, title: String)] = { [] }
    var mentions: (String) -> [String: Int] = { _ in [:] }
    var onChange: (() -> Void)?
    var onOpenScene: ((String) -> Void)?
    var onDeleted: (() -> Void)?

    private(set) var shownID: String?
    private(set) var members: [String] = []
    private(set) var sceneRows: [CharacterSceneRow] = []
    let kindField = NSTextField()
    private let membersTable = NSTableView()
    private let addPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    let notes = NSTextView()
    private let sceneTable = NSTableView()
    private let deleteButton = NSButton(title: L("Delete Relationship…"), target: nil, action: nil)
    private var notesDirty = false
    private var saveTimer: Timer?

    override func loadView() {
        let root = NSView()
        view = root
        let heading = NSTextField(labelWithString: L("Relationship"))
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        kindField.font = .systemFont(ofSize: 24, weight: .semibold)
        kindField.isBordered = false; kindField.drawsBackground = false; kindField.focusRingType = .none
        kindField.placeholderString = L("What they are to each other")
        kindField.delegate = self
        kindField.setAccessibilityLabel(L("Kind of relationship"))

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("member"))
        membersTable.addTableColumn(nameColumn)
        membersTable.headerView = nil
        membersTable.dataSource = self; membersTable.delegate = self
        membersTable.rowHeight = 24
        membersTable.setAccessibilityLabel(L("Characters of the relationship"))
        let membersScroll = scroll(membersTable, height: 100)
        addPopup.controlSize = .small
        let participants = NSStackView(views: [caption(L("Who takes part")), addPopup])
        participants.distribution = .equalSpacing

        notes.isRichText = false; notes.allowsUndo = true
        notes.font = .systemFont(ofSize: 14)
        notes.textContainerInset = NSSize(width: 6, height: 6)
        notes.isVerticallyResizable = true
        notes.autoresizingMask = [.width]
        notes.delegate = self
        notes.setAccessibilityLabel(L("Notes"))
        let notesScroll = NSScrollView()
        notesScroll.documentView = notes
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .bezelBorder
        notesScroll.translatesAutoresizingMaskIntoConstraints = false
        notesScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true

        for (id, title, width) in [("scene", L("Scene"), 220), ("together", L("Together"), 62), ("text", L("What the relationship does here"), 260)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width; c.minWidth = id == "text" ? 140 : 40
            sceneTable.addTableColumn(c)
        }
        sceneTable.dataSource = self; sceneTable.delegate = self
        sceneTable.rowHeight = 22
        sceneTable.target = self; sceneTable.doubleAction = #selector(openSceneRow)
        sceneTable.setAccessibilityLabel(L("Scenes of the relationship"))
        let sceneScroll = scroll(sceneTable, height: 200)
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self; deleteButton.action = #selector(deletePressed)

        let card = NSStackView(views: [heading, kindField, participants, membersScroll, caption(L("Notes (one per line)")), notesScroll,
                                       caption(L("Scenes where they meet (double-click opens the scene)")), sceneScroll, deleteButton])
        card.orientation = .vertical; card.alignment = .leading; card.spacing = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedBox()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(card)
        let outer = NSScrollView()
        outer.documentView = document
        outer.hasVerticalScroller = true
        outer.drawsBackground = false
        outer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(outer)
        let clip = outer.contentView
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: root.topAnchor), outer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            outer.leadingAnchor.constraint(equalTo: root.leadingAnchor), outer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor), document.leadingAnchor.constraint(equalTo: clip.leadingAnchor), document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            card.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), card.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24), card.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            kindField.widthAnchor.constraint(equalTo: card.widthAnchor), participants.widthAnchor.constraint(equalTo: card.widthAnchor),
            membersScroll.widthAnchor.constraint(equalTo: card.widthAnchor), notesScroll.widthAnchor.constraint(equalTo: card.widthAnchor), sceneScroll.widthAnchor.constraint(equalTo: card.widthAnchor),
        ])
    }

    private final class FlippedBox: NSView { override var isFlipped: Bool { true } }

    private func caption(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func scroll(_ table: NSTableView, height: CGFloat) -> NSScrollView {
        let s = NSScrollView()
        s.documentView = table
        s.hasVerticalScroller = true
        s.borderType = .bezelBorder
        s.translatesAutoresizingMaskIntoConstraints = false
        s.heightAnchor.constraint(equalToConstant: height).isActive = true
        return s
    }

    // MARK: Showing

    func show(_ id: String?) {
        _ = view
        commitEdits()
        shownID = id
        guard let id, let record = store.relationship(id) else { view.isHidden = true; return }
        view.isHidden = false
        kindField.stringValue = record.kind ?? ""
        members = record.characters
        let text = record.notes.joined(separator: "\n")
        if notes.string != text { notes.string = text }
        notes.undoManager?.removeAllActions()
        membersTable.reloadData()
        fillAddPopup()
        rebuildScenes(record)
    }

    private func fillAddPopup() {
        addPopup.removeAllItems()
        addPopup.addItem(withTitle: L("Add a character"))
        for c in characters.characters where !members.contains(c.id ?? "") {
            addPopup.addItem(withTitle: c.name ?? "")
            addPopup.lastItem?.representedObject = c.id
            addPopup.lastItem?.target = self
            addPopup.lastItem?.action = #selector(addMember(_:))
        }
    }

    /// The scenes where every character of the relationship is named, and the ones that already have a line about it.
    private func rebuildScenes(_ record: RelationshipRecord) {
        let named = record.characters.map(mentions)
        let links = record.links
        sceneRows = scenes().compactMap { s in
            let together = named.map { $0[s.id] ?? 0 }.min() ?? 0
            let line = links[s.id]
            guard together > 0 || line != nil else { return nil }
            return CharacterSceneRow(sceneID: s.id, title: s.title, mentions: together, pov: false, text: line ?? "")
        }
        sceneTable.reloadData()
    }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === membersTable ? members.count : sceneRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === membersTable {
            let name = characters.character(members[row])?.name ?? "?"
            let label = NSTextField(labelWithString: name)
            let remove = NSButton(title: "−", target: self, action: #selector(removeMember(_:)))
            remove.bezelStyle = .inline
            remove.setAccessibilityLabel(L("Remove from the relationship"))
            let stack = NSStackView(views: [label, remove])
            stack.distribution = .equalSpacing
            return stack
        }
        guard let id = tableColumn?.identifier.rawValue, sceneRows.indices.contains(row) else { return nil }
        let r = sceneRows[row]
        switch id {
        case "scene": return NSTextField(labelWithString: r.title)
        case "together":
            let l = NSTextField(labelWithString: r.mentions > 0 ? String(r.mentions) : "")
            l.alignment = .right; l.textColor = .secondaryLabelColor
            return l
        default:
            let f = NSTextField(string: r.text)
            f.isBezeled = true; f.bezelStyle = .squareBezel; f.isEditable = true
            f.drawsBackground = true; f.backgroundColor = .textBackgroundColor; f.textColor = .textColor
            f.delegate = self
            f.placeholderString = L("Type what happens between them here")
            return f
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { QuietRowView() }

    // MARK: Editing

    private func update(_ change: @escaping (inout RelationshipRecord) -> Void) {
        guard let id = shownID else { return }
        try? store.update(id, change)
        onChange?()
    }

    @objc private func addMember(_ sender: NSMenuItem) {
        guard let character = sender.representedObject as? String, !members.contains(character) else { return }
        update { $0.characters = $0.characters + [character] }
        show(shownID)
    }

    @objc private func removeMember(_ sender: NSButton) {
        let row = membersTable.row(for: sender)
        guard members.indices.contains(row) else { return }
        guard members.count > 2 else { NSSound.beep(); return }
        let character = members[row]
        update { $0.characters = $0.characters.filter { $0 != character } }
        show(shownID)
    }

    func controlTextDidBeginEditing(_ obj: Notification) { (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = .textColor }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === kindField {
            let kind = kindField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind.isEmpty { kindField.stringValue = store.relationship(shownID ?? "")?.kind ?? "" } else { update { $0.kind = kind } }
        } else {
            let row = sceneTable.row(for: field)
            if row >= 0 { setSceneLine(row: row, field.stringValue) }
        }
    }

    /// What the relationship does in the scene of this row (empty removes the line).
    func setSceneLine(row: Int, _ raw: String) {
        guard sceneRows.indices.contains(row) else { return }
        let scene = sceneRows[row].sceneID
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        update { r in
            var links = r.links
            if text.isEmpty { links.removeValue(forKey: scene) } else { links[scene] = text }
            r.links = links
        }
        sceneRows[row].text = text
    }

    func textDidChange(_ notification: Notification) {
        notesDirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.commitEdits() }
    }

    func textDidEndEditing(_ notification: Notification) { commitEdits() }

    func commitEdits() {
        saveTimer?.invalidate(); saveTimer = nil
        guard notesDirty, shownID != nil else { notesDirty = false; return }
        notesDirty = false
        let lines = notes.string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        update { $0.notes = lines }
    }

    @objc private func openSceneRow() {
        let row = sceneTable.clickedRow, column = sceneTable.clickedColumn
        if sceneTable.tableColumns.indices.contains(column), sceneTable.tableColumns[column].identifier.rawValue == "text" { return }
        guard sceneRows.indices.contains(row) else { return }
        onOpenScene?(sceneRows[row].sceneID)
    }

    @objc private func deletePressed() { deleteShown(confirm: true) }

    func deleteShown(confirm: Bool) {
        guard let id = shownID, let record = store.relationship(id) else { return }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Delete the relationship “{kind}”?", ["kind": record.kind ?? ""])
            alert.informativeText = L("It goes to the book's trash folder (.quilland/trash). The characters stay.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Delete"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        commitEdits()
        do { try store.delete(id) } catch { return }
        shownID = nil
        onDeleted?()
    }
}
