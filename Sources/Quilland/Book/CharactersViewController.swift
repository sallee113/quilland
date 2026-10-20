import AppKit
import QuillandCore

/// A scene in a character's card: how often the name is in it, whether it is the character's point of view, and what the character does.
struct CharacterSceneRow {
    var sceneID: String
    var title: String
    var mentions: Int
    var pov: Bool
    var text: String
}

/// The Characters view: the list of characters on the left, the card of the chosen one on the right (the two-part layout).
final class CharactersViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate, NSMenuDelegate {
    var store: CharacterStore!
    var relationships: RelationshipStore!
    let relCard = RelationshipCardController()
    private(set) var selectedRelationship: String?
    private var shownRelationships: [RelationshipRecord] = []
    private let relList = Hover.rows(NSTableView())
    private let addRelationshipButton = NSButton(title: L("New Relationship…"), target: nil, action: nil)
    private let relationshipsLabel = NSTextField(wrappingLabelWithString: "")
    /// The scenes of the book in order, with their titles and where they sit.
    var scenes: () -> [(id: String, title: String)] = { [] }
    /// How many times the character's name is in each scene (only scenes where it is).
    var mentions: (String) -> [String: Int] = { _ in [:] }
    var onOpenScene: ((String) -> Void)?
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?
    /// Merge Into…: the character to take out of the book and the one that keeps what is known of both. The owner of the book does it (and can undo it).
    var onMerge: ((String, String) -> Void)?
    private let addSceneButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeSceneButton = NSButton(title: L("Remove Link"), target: nil, action: nil)
    private let mergeButton = NSButton(title: L("Merge Into…"), target: nil, action: nil)

    private(set) var selected: String?
    private var shown: [CharacterRecord] = []
    private(set) var rows: [CharacterSceneRow] = []

    // List
    let filterField = NSSearchField()
    /// "Filter by…": the characters of a section, an event or a place.
    let relationFilter = RelationFilter(kind: .character)
    let addField = NSTextField()
    private let list = Hover.rows(NSTableView())
    private let emptyLabel = NSTextField(labelWithString: L("Add your first character"))

    // Card
    private let cardScroll = NSScrollView()
    private let card = NSStackView()
    let nameField = NSTextField()
    let aliasField = NSTextField()
    let mainBox = NSButton(checkboxWithTitle: L("Main character"), target: nil, action: nil)
    let profile = NSTextView()
    let notes = NSTextView()
    private let sceneTable = Hover.rows(NSTableView())
    private let deleteButton = NSButton(title: L("Delete Character…"), target: nil, action: nil)
    private let nothing = NSTextField(labelWithString: "")
    private var dirty: Set<String> = []
    private var saveTimer: Timer?

    // MARK: View

    override func loadView() {
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "QuillandCharacters"
        let left = NSViewController()
        left.view = buildList()
        let right = NSViewController()
        right.view = buildCard()
        let a = NSSplitViewItem(viewController: left)
        a.minimumThickness = 220; a.maximumThickness = 480
        a.holdingPriority = NSLayoutConstraint.Priority(260)
        let b = NSSplitViewItem(viewController: right)
        b.minimumThickness = 420
        split.addSplitViewItem(a)
        split.addSplitViewItem(b)
        addChild(split)
        view = split.view
        relCard.store = relationships
        relCard.characters = store
        relCard.scenes = { [weak self] in self?.scenes() ?? [] }
        relCard.mentions = { [weak self] in self?.mentions($0) ?? [:] }
        relCard.onChange = { [weak self] in self?.reloadRelationships(); self?.onChange?() }
        relCard.onOpenScene = { [weak self] in self?.onOpenScene?($0) }
        relCard.onDeleted = { [weak self] in
            self?.selectedRelationship = nil
            self?.relCard.show(nil)
            self?.reloadRelationships()
            self?.showCard()
            self?.onChange?()
        }
        reload()
    }

    private func buildList() -> NSView {
        let root = NSView()
        filterField.placeholderString = L("Filter")
        filterField.delegate = self
        addField.placeholderString = L("Add a character — type a name, press Return")
        addField.delegate = self
        addField.setAccessibilityLabel(L("Add a character"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        list.addTableColumn(column)
        list.headerView = nil
        list.dataSource = self
        list.delegate = self
        list.rowHeight = 24
        list.style = .sourceList
        list.setAccessibilityLabel(L("Characters"))
        let listMenu = NSMenu()
        listMenu.delegate = self
        list.menu = listMenu
        let scroll = NSScrollView()
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        // Below the characters: the relationships, a second list.
        let relColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("relationship"))
        relList.addTableColumn(relColumn)
        relList.headerView = nil
        relList.dataSource = self; relList.delegate = self
        relList.rowHeight = 24
        relList.style = .sourceList
        relList.setAccessibilityLabel(L("Relationships"))
        let relScroll = NSScrollView()
        relScroll.documentView = relList
        relScroll.hasVerticalScroller = true
        relScroll.drawsBackground = false
        relScroll.translatesAutoresizingMaskIntoConstraints = false
        relScroll.heightAnchor.constraint(equalToConstant: 130).isActive = true
        let relCaption = caption(L("Relationships"))
        addRelationshipButton.bezelStyle = .rounded; addRelationshipButton.controlSize = .small
        addRelationshipButton.target = self; addRelationshipButton.action = #selector(addRelationshipPressed)
        relationFilter.onChange = { [weak self] in self?.reload(keepingRelations: true) }
        for v in [filterField, relationFilter.view, scroll, addField, emptyLabel, relCaption, relScroll, addRelationshipButton] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            filterField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            relationFilter.view.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 6), relationFilter.view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            relationFilter.view.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: relationFilter.view.bottomAnchor, constant: 6), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: addField.topAnchor, constant: -8),
            addField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), addField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            addField.bottomAnchor.constraint(equalTo: relCaption.topAnchor, constant: -14),
            relCaption.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), relCaption.bottomAnchor.constraint(equalTo: relScroll.topAnchor, constant: -4),
            relScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), relScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), relScroll.bottomAnchor.constraint(equalTo: addRelationshipButton.topAnchor, constant: -6),
            addRelationshipButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), addRelationshipButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        return root
    }

    private func caption(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func box(_ tv: NSTextView, height: CGFloat) -> NSScrollView {
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.delegate = self
        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.borderType = .bezelBorder
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.heightAnchor.constraint(equalToConstant: height).isActive = true
        return sv
    }

    private func buildCard() -> NSView {
        let root = NSView()
        nameField.font = .systemFont(ofSize: 24, weight: .semibold)
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.placeholderString = L("Name")
        nameField.delegate = self
        nameField.setAccessibilityLabel(L("Name"))
        aliasField.placeholderString = L("Other names, separated by commas")
        aliasField.delegate = self
        aliasField.setAccessibilityLabel(L("Also called"))
        mainBox.target = self; mainBox.action = #selector(mainChanged)
        profile.setAccessibilityLabel(L("Profile")); notes.setAccessibilityLabel(L("Notes"))

        let columns: [(String, String, CGFloat)] = [("scene", L("Scene"), 220), ("mentions", L("Named"), 54), ("pov", L("POV"), 40), ("text", L("What the character does here"), 260)]
        for (id, title, width) in columns {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            c.minWidth = id == "text" ? 140 : 36
            sceneTable.addTableColumn(c)
        }
        sceneTable.dataSource = self
        sceneTable.delegate = self
        sceneTable.rowHeight = 22
        sceneTable.target = self
        sceneTable.doubleAction = #selector(openSceneRow)
        sceneTable.setAccessibilityLabel(L("Scenes of the character"))
        let tableScroll = NSScrollView()
        tableScroll.documentView = sceneTable
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 200).isActive = true
        deleteButton.target = self; deleteButton.action = #selector(deletePressed)
        deleteButton.bezelStyle = .rounded
        mergeButton.target = self; mergeButton.action = #selector(mergePressed)
        mergeButton.bezelStyle = .rounded
        mergeButton.toolTip = L("The same person under another name: its name and what is known of it go to the character you choose")
        let cardButtons = NSStackView(views: [mergeButton, deleteButton])
        cardButtons.spacing = 10
        addSceneButton.controlSize = .small
        removeSceneButton.target = self; removeSceneButton.action = #selector(removeSceneLinkPressed)
        removeSceneButton.controlSize = .small; removeSceneButton.bezelStyle = .rounded
        removeSceneButton.toolTip = L("Takes away the line and the point of view of the chosen scene. A scene whose text names the character stays in the list.")
        let sceneButtons = NSStackView(views: [addSceneButton, removeSceneButton])
        sceneButtons.spacing = 8

        let profileBox = box(profile, height: 150), notesBox = box(notes, height: 90)
        relationshipsLabel.font = .systemFont(ofSize: 12)
        relationshipsLabel.textColor = .secondaryLabelColor
        card.setViews([nameField, aliasField, mainBox, relationshipsLabel, caption(L("Profile, appearance, speech")), profileBox, caption(L("Notes (one per line)")), notesBox,
                       caption(L("Scenes: where the name is, point of view, what the character does (double-click opens the scene)")), tableScroll, sceneButtons, cardButtons])
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(card)
        cardScroll.documentView = document
        cardScroll.hasVerticalScroller = true
        cardScroll.drawsBackground = false
        cardScroll.translatesAutoresizingMaskIntoConstraints = false
        nothing.font = .systemFont(ofSize: 15)
        nothing.textColor = .secondaryLabelColor
        nothing.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(cardScroll)
        root.addSubview(nothing)
        addChild(relCard)
        relCard.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(relCard.view)
        relCard.view.isHidden = true
        NSLayoutConstraint.activate([relCard.view.topAnchor.constraint(equalTo: root.topAnchor), relCard.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                                     relCard.view.leadingAnchor.constraint(equalTo: root.leadingAnchor), relCard.view.trailingAnchor.constraint(equalTo: root.trailingAnchor)])
        let clip = cardScroll.contentView
        NSLayoutConstraint.activate([
            cardScroll.topAnchor.constraint(equalTo: root.topAnchor), cardScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            cardScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), cardScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor), document.leadingAnchor.constraint(equalTo: clip.leadingAnchor), document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            card.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), card.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24), card.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            nameField.widthAnchor.constraint(equalTo: card.widthAnchor), aliasField.widthAnchor.constraint(equalTo: card.widthAnchor), relationshipsLabel.widthAnchor.constraint(equalTo: card.widthAnchor),
            profileBox.widthAnchor.constraint(equalTo: card.widthAnchor), notesBox.widthAnchor.constraint(equalTo: card.widthAnchor),
            tableScroll.widthAnchor.constraint(equalTo: card.widthAnchor),
            nothing.centerXAnchor.constraint(equalTo: root.centerXAnchor), nothing.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    private final class FlippedView: NSView { override var isFlipped: Bool { true } }

    // MARK: The list

    /// Reads the list again (after a change from outside), keeping the chosen character when it is still there.
    func reload(keepingRelations: Bool = false) {
        guard isViewLoaded else { return }
        if !keepingRelations { relationFilter.invalidate(); relationFilter.rebuild() }
        reloadRelationships()
        let needle = filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let allowed = relationFilter.allowed()
        shown = store.characters.filter { (needle.isEmpty || ($0.name ?? "").lowercased().contains(needle) || $0.aliases.contains { $0.lowercased().contains(needle) }) && (allowed == nil || allowed!.contains($0.id ?? "")) }
        relationFilter.setCount(shown: shown.count, of: store.characters.count)
        list.reloadData()
        emptyLabel.isHidden = !store.characters.isEmpty
        if let id = selected, let row = shown.firstIndex(where: { $0.id == id }) {
            list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if selected == nil || !store.characters.contains(where: { $0.id == selected }), let first = shown.first {
            if let firstID = first.id { select(firstID) }
        } else if shown.isEmpty {
            selected = nil
        }
        showCard()
    }

    func select(_ id: String) {
        commitEdits()
        selected = id
        leaveRelationship()
        if let row = shown.firstIndex(where: { $0.id == id }) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        showCard()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === list ? shown.count : (tableView === relList ? shownRelationships.count : rows.count) }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === relList {
            let label = NSTextField(labelWithString: relationshipTitle(shownRelationships[row]))
            label.lineBreakMode = .byTruncatingTail
            return CenteredCell(label)
        }
        if tableView === list {
            let record = shown[row]
            let label = NSTextField(labelWithString: record.name ?? "")
            label.font = .systemFont(ofSize: 13, weight: record.main ? .semibold : .regular)
            return CenteredCell(label)
        }
        guard let id = tableColumn?.identifier.rawValue, rows.indices.contains(row) else { return nil }
        let r = rows[row]
        switch id {
        case "scene": return NSTextField(labelWithString: r.title)
        case "mentions":
            let l = NSTextField(labelWithString: r.mentions > 0 ? String(r.mentions) : "")
            l.alignment = .right
            l.textColor = .secondaryLabelColor
            return l
        case "pov":
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(povToggled(_:)))
            b.state = r.pov ? .on : .off
            return b
        default:
            let f = NSTextField(string: r.text)
            f.isBezeled = true; f.bezelStyle = .squareBezel; f.isEditable = true
            f.drawsBackground = true; f.backgroundColor = .textBackgroundColor; f.textColor = .textColor
            f.delegate = self
            f.placeholderString = L("Type what the character does here")
            return f
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView === sceneTable ? QuietRowView() : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === relList {
            let row = relList.selectedRow
            guard row >= 0, shownRelationships.indices.contains(row) else { return }
            commitEdits()
            selectedRelationship = shownRelationships[row].id
            list.deselectAll(nil)
            cardScroll.isHidden = true; nothing.isHidden = true
            relCard.show(selectedRelationship)
            return
        }
        guard (notification.object as? NSTableView) === list else { return }
        let row = list.selectedRow
        guard row >= 0, shown.indices.contains(row), shown[row].id != selected else { return }
        commitEdits()
        selected = shown[row].id
        leaveRelationship()
        showCard()
    }

    // MARK: The card

    private func showCard() {
        guard isViewLoaded, selectedRelationship == nil else { return }
        let record = selected.flatMap { store.character($0) }
        cardScroll.isHidden = record == nil
        nothing.isHidden = record != nil
        nothing.stringValue = store.characters.isEmpty ? L("No characters yet. Type a name at the bottom left.") : L("Choose a character")
        guard let record, let id = record.id else { return }
        nameField.stringValue = record.name ?? ""
        aliasField.stringValue = record.aliases.joined(separator: ", ")
        mainBox.state = record.main ? .on : .off
        relationshipsLabel.stringValue = relationshipsSummary(of: id)
        setText(profile, store.profile(id))
        setText(notes, record.notes.joined(separator: "\n"))
        rebuildRows(for: record)
        rebuildAddSceneMenu()
    }

    // MARK: Adding a scene

    /// The "Add a Scene…" menu: the scenes that are not in the list yet, in the order of the book.
    private func rebuildAddSceneMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Add a Scene…"), action: nil, keyEquivalent: ""))
        let shown = Set(rows.map(\.sceneID))
        let free = scenes().filter { !shown.contains($0.id) }
        if free.isEmpty {
            let none = NSMenuItem(title: L("None left"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for s in free { menu.addItem(ClosureMenuItem(title: s.title) { [weak self] in self?.addScene(s.id) }) }
        addSceneButton.menu = menu
    }

    /// Links the character to a scene where the name is not written (a nickname, a mention without it, a plan): the line is empty, the cursor goes to it.
    func addScene(_ scene: String) {
        update { r in var links = r.links; if links[scene] == nil { links[scene] = "" }; r.links = links }
        guard let row = rows.firstIndex(where: { $0.sceneID == scene }),
              let column = sceneTable.tableColumns.firstIndex(where: { $0.identifier.rawValue == "text" }) else { return }
        sceneTable.scrollRowToVisible(row)
        sceneTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        sceneTable.editColumn(column, row: row, with: nil, select: false)
    }

    /// Takes away what the card says about the scene of this row: the line and the point of view.
    func removeSceneLink(row: Int) {
        guard rows.indices.contains(row) else { return }
        let scene = rows[row].sceneID
        update { r in
            var links = r.links; links.removeValue(forKey: scene); r.links = links
            r.povScenes = r.povScenes.filter { $0 != scene }
        }
    }

    /// For the checks: the scenes in the card's list, and the ones the "Add a Scene…" menu offers.
    var sceneRowIDs: [String] { rows.map(\.sceneID) }
    var addableScenes: [String] { (addSceneButton.menu?.items.dropFirst() ?? []).compactMap { $0 is ClosureMenuItem ? $0.title : nil } }

    @objc private func removeSceneLinkPressed() { removeSceneLink(row: sceneTable.selectedRow) }

    private func setText(_ tv: NSTextView, _ text: String) {
        if tv.string != text { tv.string = text }
        tv.undoManager?.removeAllActions()
    }

    /// The scenes that matter for the character: the name is in them, or they are its point of view, or it has a line there.
    private func rebuildRows(for record: CharacterRecord) {
        guard let id = record.id else { return }
        let named = mentions(id)
        let links = record.links
        let pov = Set(record.povScenes)
        rows = scenes().compactMap { s in
            let n = named[s.id] ?? 0
            let line = links[s.id]
            guard n > 0 || line != nil || pov.contains(s.id) else { return nil }
            return CharacterSceneRow(sceneID: s.id, title: s.title, mentions: n, pov: pov.contains(s.id), text: line ?? "")
        }
        sceneTable.reloadData()
    }

    // MARK: Relationships

    private func relationshipTitle(_ r: RelationshipRecord) -> String {
        let names = r.characters.compactMap { store.character($0)?.name }.joined(separator: ", ")
        return "\(names) — \(r.kind ?? "")"
    }

    /// "Мира (сёстры), Лев (друзья)": what the character is to the others.
    private func relationshipsSummary(of id: String) -> String {
        let list = relationships.relationships(of: id).map { r -> String in
            let others = r.characters.filter { $0 != id }.compactMap { store.character($0)?.name }.joined(separator: ", ")
            return "\(others) (\(r.kind ?? ""))"
        }
        return list.isEmpty ? "" : L("Relationships: {list}", ["list": list.joined(separator: "; ")])
    }

    func reloadRelationships() {
        guard isViewLoaded else { return }
        relationships.reload()
        let allowed = relationFilter.allowed()
        shownRelationships = relationships.relationships.filter { r in allowed == nil || r.characters.allSatisfy { allowed!.contains($0) } }.sorted { relationshipTitle($0).localizedLowercase < relationshipTitle($1).localizedLowercase }
        relList.reloadData()
        if let id = selectedRelationship, let row = shownRelationships.firstIndex(where: { $0.id == id }) {
            relList.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        if let id = selected { relationshipsLabel.stringValue = relationshipsSummary(of: id) }
    }

    private func leaveRelationship() {
        guard selectedRelationship != nil else { return }
        selectedRelationship = nil
        relList.deselectAll(nil)
        relCard.show(nil)
    }

    func selectRelationship(_ id: String) {
        commitEdits()
        guard let row = shownRelationships.firstIndex(where: { $0.id == id }) else { return }
        relList.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    var relationshipTitles: [String] { shownRelationships.map(relationshipTitle) }

    @objc private func addRelationshipPressed() {
        guard store.characters.count >= 2 else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = L("New Relationship")
        alert.informativeText = L("Choose two characters and say what they are to each other. More can be added on the card.")
        func popup(_ selectedIndex: Int) -> NSPopUpButton {
            let p = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 160, height: 26), pullsDown: false)
            for c in store.characters { p.addItem(withTitle: c.name ?? ""); p.lastItem?.representedObject = c.id }
            p.selectItem(at: min(selectedIndex, store.characters.count - 1))
            return p
        }
        let first = popup(0), second = popup(1)
        let kind = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
        kind.placeholderString = L("What they are to each other")
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 64))
        first.frame.origin = NSPoint(x: 0, y: 36); second.frame.origin = NSPoint(x: 170, y: 36); kind.frame.origin = NSPoint(x: 0, y: 4)
        [first, second, kind].forEach(box.addSubview)
        alert.accessoryView = box
        alert.addButton(withTitle: L("Create"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = kind
        guard alert.runModal() == .alertFirstButtonReturn,
              let a = first.selectedItem?.representedObject as? String, let b = second.selectedItem?.representedObject as? String, a != b else { return }
        addRelationship([a, b], kind: kind.stringValue)
    }

    /// Makes a relationship; its card opens.
    @discardableResult
    func addRelationship(_ ids: [String], kind raw: String) -> String? {
        let kind = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ids.count >= 2, let id = try? relationships.add(characters: ids, kind: kind.isEmpty ? L("related") : kind) else { return nil }
        reloadRelationships()
        selectRelationship(id)
        onChange?()
        return id
    }

    // MARK: Editing

    @objc private func mainChanged() { update { $0.main = self.mainBox.state == .on } }

    @objc private func povToggled(_ sender: NSButton) {
        let row = sceneTable.row(for: sender)
        setScenePOV(row: row, sender.state == .on)
    }

    /// Makes the scene in this row of the card the character's point of view, or not.
    func setScenePOV(row: Int, _ on: Bool) {
        guard rows.indices.contains(row) else { return }
        let scene = rows[row].sceneID
        update { r in
            var list = r.povScenes
            if on { if !list.contains(scene) { list.append(scene) } } else { list.removeAll { $0 == scene } }
            r.povScenes = list
        }
    }

    /// What the character does in the scene of this row (empty removes the line).
    func setSceneLine(row: Int, _ raw: String) {
        guard rows.indices.contains(row) else { return }
        let scene = rows[row].sceneID
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        update(rebuild: false) { r in
            var links = r.links
            if text.isEmpty { links.removeValue(forKey: scene) } else { links[scene] = text }
            r.links = links
        }
        rows[row].text = text
    }

    @objc private func openSceneRow() {
        let row = sceneTable.clickedRow
        let column = sceneTable.clickedColumn
        // A double-click in the text column is for typing, not for going away.
        if sceneTable.tableColumns.indices.contains(column), sceneTable.tableColumns[column].identifier.rawValue == "text" { return }
        guard rows.indices.contains(row) else { return }
        onOpenScene?(rows[row].sceneID)
    }

    private func update(rebuild: Bool = true, _ change: @escaping (inout CharacterRecord) -> Void) {
        guard let id = selected else { return }
        try? store.update(id, change)
        if rebuild { reload() }
        onChange?()
    }

    /// The cursor in a field being typed in is drawn in the text colour, so that it shows on the field's background.
    func controlTextDidBeginEditing(_ obj: Notification) {
        (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = .textColor
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === nameField {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { showCard() } else { update { $0.name = name } }
        } else if field === aliasField {
            let aliases = aliasField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            update { $0.aliases = aliases }
        } else if field === addField {
            // Return in the quick-add field is handled in `control(_:textView:doCommandBy:)`.
        } else if let row = sceneTableRow(of: field) {
            setSceneLine(row: row, field.stringValue)
        }
    }

    private func sceneTableRow(of view: NSView) -> Int? {
        let row = sceneTable.row(for: view)
        return row >= 0 ? row : nil
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === filterField { reload(keepingRelations: true) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === addField, selector == #selector(NSResponder.insertNewline(_:)) { addCharacter(named: addField.stringValue); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)), control === filterField || control === addField { onEscape?(); return true }
        return false
    }

    /// Makes a character from a typed name; the card opens on it with the profile ready to fill.
    @discardableResult
    func addCharacter(named raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let id = try? store.add(name: name) else { return nil }
        addField.stringValue = ""
        filterField.stringValue = ""
        selected = id
        reload()
        onChange?()
        view.window?.makeFirstResponder(profile)
        return id
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === profile || tv === notes else { return }
        dirty.insert(tv === profile ? "profile" : "notes")
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.commitEdits() }
    }

    func textDidEndEditing(_ notification: Notification) { commitEdits() }

    /// Writes the profile and the notes typed and not yet saved.
    @objc func commitEdits() {
        relCard.commitEdits()   // a relationship's text is saved by its own card: it waits for its timer too
        saveTimer?.invalidate()
        saveTimer = nil
        guard !dirty.isEmpty, let id = selected else { dirty = []; return }
        let pending = dirty
        dirty = []
        if pending.contains("profile") { try? store.setProfile(id, profile.string) }
        if pending.contains("notes") {
            let lines = notes.string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            try? store.update(id) { $0.notes = lines }
        }
        onChange?()
    }

    // MARK: Merging

    @objc private func mergePressed() { mergeSelected() }

    /// Right click on a character: the commands for it (the clicked character is the chosen one).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === list.menu else { return }
        menu.removeAllItems()
        menu.autoenablesItems = false
        let row = list.clickedRow
        guard row >= 0, shown.indices.contains(row), let id = shown[row].id else { return }
        select(id)
        let merge = ClosureMenuItem(title: L("Merge Into…")) { [weak self] in self?.mergeSelected() }
        merge.isEnabled = shown.count >= 2 || store.characters.count >= 2
        menu.addItem(merge)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L("Delete Character…")) { [weak self] in self?.deleteSelected(confirm: true) })
    }

    /// Asks which character keeps the data (Cancel is the default), then hands the merge to the owner of the book.
    func mergeSelected() {
        guard let id = selected, let record = store.character(id) else { return }
        let others = store.characters.filter { $0.id != id }
        guard !others.isEmpty else {
            let alert = NSAlert()
            alert.messageText = L("There is no other character to merge into.")
            alert.runModal()
            return
        }
        commitEdits()
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for other in others { popup.addItem(withTitle: other.name ?? ""); popup.lastItem?.representedObject = other.id }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Merge “{name}” into…", ["name": record.name ?? ""])
        alert.informativeText = L("Choose the character to keep. “{name}” is taken out of the book: its name and aliases become aliases of the kept character, and its profile, notes, scenes and relationships are added to theirs. The card goes to the book's trash folder (.quilland/trash). You can undo this.", ["name": record.name ?? ""])
        alert.accessoryView = popup
        let cancel = alert.addButton(withTitle: L("Cancel"))
        cancel.keyEquivalent = "\r"
        let go = alert.addButton(withTitle: L("Merge"))
        go.keyEquivalent = ""
        go.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn, let target = popup.selectedItem?.representedObject as? String else { return }
        onMerge?(id, target)
    }

    // MARK: Deleting

    @objc private func deletePressed() { deleteSelected(confirm: true) }

    /// Asks (Cancel is the default), then takes the character out of the book, into the trash folder. The scenes keep the name in their text.
    func deleteSelected(confirm: Bool) {
        guard let id = selected, let record = store.character(id) else { return }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Delete the character “{name}”?", ["name": record.name ?? ""])
            alert.informativeText = L("The card, the profile and the lines about the scenes go to the book's trash folder (.quilland/trash). The name stays in the text of the scenes.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Delete"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        commitEdits()
        do { try store.delete(id) } catch { return }
        _ = try? relationships.characterDeleted(id)
        selected = nil
        reload()
        onChange?()
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    var rowCount: Int { shown.count }
    var shownNames: [String] { shown.compactMap(\.name) }
}

private extension NSStackView {
    func setViews(_ views: [NSView]) { views.forEach { addArrangedSubview($0) } }
}
