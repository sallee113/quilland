import AppKit
import QuillandCore

/// The World view: worlds at the top, their places (and peoples, things, terms) as a tree below; the card of the chosen one on the right.
final class WorldViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate, NSComboBoxDelegate, NSMenuDelegate {
    final class Node {
        let id: String
        let isWorld: Bool
        let name: String
        let children: [Node]
        init(id: String, isWorld: Bool, name: String, children: [Node]) { self.id = id; self.isWorld = isWorld; self.name = name; self.children = children }
    }

    var store: WorldStore!
    var scenes: () -> [(id: String, title: String)] = { [] }
    /// How many times the name of a world or an entry is in each scene.
    var mentions: (NameEntry) -> [String: Int] = { _ in [:] }
    var onOpenScene: ((String) -> Void)?
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?
    /// The merges and conversions: the owner of the book does them (with a snapshot, so that Undo takes them back).
    var onMergePlace: ((String, String) -> Void)?
    var onMergeWorld: ((String, String) -> Void)?
    var onPlaceToWorld: ((String) -> Void)?
    /// The world, the world it goes into and the place there it goes inside (nil: at the top).
    var onWorldToPlace: ((String, String, String?) -> Void)?

    private(set) var selected: String?
    private var roots: [Node] = []
    private var byID: [String: Node] = [:]
    private(set) var rows: [CharacterSceneRow] = []
    private static let dragType = NSPasteboard.PasteboardType("com.quilland.place")

    let filterField = NSSearchField()
    let addField = NSTextField()
    private let outline = Hover.rows(NSOutlineView())
    private let newWorldButton = NSButton(title: L("New World"), target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "")

    private let cardScroll = NSScrollView()
    private let card = NSStackView()
    private let nothing = NSTextField(labelWithString: "")
    let nameField = NSTextField()
    let typeBox = NSComboBox()
    private let pathLabel = NSTextField(labelWithString: "")
    let aliasField = NSTextField()
    let descriptionView = NSTextView()
    let notesView = NSTextView()
    private let scenesCaption = NSTextField(labelWithString: "")
    private let sceneTable = Hover.rows(NSTableView())
    private var sceneScroll = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton(title: L("Delete…"), target: nil, action: nil)
    private let mergeButton = NSButton(title: L("Merge Into…"), target: nil, action: nil)
    private let convertButton = NSButton(title: L("Turn Into a World…"), target: nil, action: nil)
    private var dirty: Set<String> = []
    private var saveTimer: Timer?

    // MARK: View

    override func loadView() {
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "QuillandWorld"
        let left = NSViewController(); left.view = buildList()
        let right = NSViewController(); right.view = buildCard()
        let a = NSSplitViewItem(viewController: left)
        a.minimumThickness = 240; a.maximumThickness = 520
        a.holdingPriority = NSLayoutConstraint.Priority(260)
        let b = NSSplitViewItem(viewController: right)
        b.minimumThickness = 420
        split.addSplitViewItem(a); split.addSplitViewItem(b)
        addChild(split)
        view = split.view
        reload()
    }

    private func buildList() -> NSView {
        let root = NSView()
        filterField.placeholderString = L("Filter")
        filterField.delegate = self
        addField.placeholderString = L("Add a place inside the chosen one — type a name, press Return")
        addField.delegate = self
        addField.setAccessibilityLabel(L("Add a place"))
        newWorldButton.target = self; newWorldButton.action = #selector(newWorldPressed)
        newWorldButton.bezelStyle = .rounded
        newWorldButton.controlSize = .small
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.style = .sourceList
        outline.rowHeight = 24
        outline.registerForDraggedTypes([Self.dragType])
        outline.draggingDestinationFeedbackStyle = .regular
        outline.setAccessibilityLabel(L("Worlds and places"))
        let menu = NSMenu(); menu.delegate = self
        outline.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        for v in [filterField, newWorldButton, scroll, addField, emptyLabel] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            newWorldButton.leadingAnchor.constraint(equalTo: filterField.trailingAnchor, constant: 6), newWorldButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            newWorldButton.centerYAnchor.constraint(equalTo: filterField.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: addField.topAnchor, constant: -8),
            addField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), addField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            addField.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
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
        tv.isRichText = false; tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.delegate = self
        let sv = NSScrollView()
        sv.documentView = tv; sv.hasVerticalScroller = true; sv.borderType = .bezelBorder
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.heightAnchor.constraint(equalToConstant: height).isActive = true
        return sv
    }

    private final class FlippedView: NSView { override var isFlipped: Bool { true } }

    private func buildCard() -> NSView {
        let root = NSView()
        nameField.font = .systemFont(ofSize: 24, weight: .semibold)
        nameField.isBordered = false; nameField.drawsBackground = false; nameField.focusRingType = .none
        nameField.placeholderString = L("Name"); nameField.delegate = self
        nameField.setAccessibilityLabel(L("Name"))
        typeBox.addItems(withObjectValues: ["place", "people", "thing", "term"])
        typeBox.completes = false
        typeBox.delegate = self
        typeBox.setAccessibilityLabel(L("Kind of entry"))
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        aliasField.placeholderString = L("Other names, separated by commas"); aliasField.delegate = self
        aliasField.setAccessibilityLabel(L("Also called"))
        descriptionView.setAccessibilityLabel(L("Description")); notesView.setAccessibilityLabel(L("Notes"))
        scenesCaption.stringValue = L("Scenes: where the name is, and what happens here (double-click opens the scene)")
        scenesCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        scenesCaption.textColor = .secondaryLabelColor
        for (id, title, width) in [("scene", L("Scene"), 240), ("mentions", L("Named"), 54), ("text", L("What happens here"), 280)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width; c.minWidth = id == "text" ? 140 : 40
            sceneTable.addTableColumn(c)
        }
        sceneTable.dataSource = self; sceneTable.delegate = self
        sceneTable.rowHeight = 22
        sceneTable.target = self; sceneTable.doubleAction = #selector(openSceneRow)
        sceneTable.setAccessibilityLabel(L("Scenes of the place"))
        sceneScroll.documentView = sceneTable
        sceneScroll.hasVerticalScroller = true; sceneScroll.borderType = .bezelBorder
        sceneScroll.translatesAutoresizingMaskIntoConstraints = false
        sceneScroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        countLabel.textColor = .secondaryLabelColor
        deleteButton.target = self; deleteButton.action = #selector(deletePressed)
        deleteButton.bezelStyle = .rounded
        mergeButton.target = self; mergeButton.action = #selector(mergePressed)
        mergeButton.bezelStyle = .rounded
        mergeButton.toolTip = L("The same one under another name: its name and what is known of it go to the one you choose")
        convertButton.target = self; convertButton.action = #selector(convertPressed)
        convertButton.bezelStyle = .rounded
        let cardButtons = NSStackView(views: [mergeButton, convertButton, deleteButton])
        cardButtons.spacing = 10

        let descBox = box(descriptionView, height: 150), notesBox = box(notesView, height: 80)
        for v in [nameField, typeBox, pathLabel, aliasField, countLabel, caption(L("Description and rules")), descBox, caption(L("Notes (one per line)")), notesBox, scenesCaption, sceneScroll, cardButtons] {
            card.addArrangedSubview(v)
        }
        card.orientation = .vertical; card.alignment = .leading; card.spacing = 8
        card.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(card)
        cardScroll.documentView = document
        cardScroll.hasVerticalScroller = true; cardScroll.drawsBackground = false
        cardScroll.translatesAutoresizingMaskIntoConstraints = false
        nothing.font = .systemFont(ofSize: 15); nothing.textColor = .secondaryLabelColor
        nothing.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(cardScroll); root.addSubview(nothing)
        let clip = cardScroll.contentView
        NSLayoutConstraint.activate([
            cardScroll.topAnchor.constraint(equalTo: root.topAnchor), cardScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            cardScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), cardScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor), document.leadingAnchor.constraint(equalTo: clip.leadingAnchor), document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            card.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), card.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24), card.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
            nameField.widthAnchor.constraint(equalTo: card.widthAnchor), aliasField.widthAnchor.constraint(equalTo: card.widthAnchor),
            descBox.widthAnchor.constraint(equalTo: card.widthAnchor), notesBox.widthAnchor.constraint(equalTo: card.widthAnchor),
            sceneScroll.widthAnchor.constraint(equalTo: card.widthAnchor), typeBox.widthAnchor.constraint(equalToConstant: 160),
            nothing.centerXAnchor.constraint(equalTo: root.centerXAnchor), nothing.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    // MARK: The tree

    private func buildNodes() -> [Node] {
        let needle = filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        func entryNode(_ e: PlaceRecord) -> Node? {
            let kids = store.children(of: e.id, in: e.world ?? "").compactMap(entryNode)
            let own = needle.isEmpty || (e.name ?? "").lowercased().contains(needle) || e.aliases.contains { $0.lowercased().contains(needle) }
            guard own || !kids.isEmpty else { return nil }
            return Node(id: e.id ?? "", isWorld: false, name: e.name ?? "", children: kids)
        }
        return store.worlds.compactMap { w in
            guard let id = w.id else { return nil }
            let kids = store.children(of: nil, in: id).compactMap(entryNode)
            let own = needle.isEmpty || (w.name ?? "").lowercased().contains(needle)
            guard own || !kids.isEmpty else { return nil }
            return Node(id: id, isWorld: true, name: w.name ?? "", children: kids)
        }
    }

    /// Reads the tree again, keeping what was chosen and what was open.
    func reload() {
        guard isViewLoaded else { return }
        let open = Set(byID.values.filter { outline.isItemExpanded($0) }.map(\.id))
        let firstTime = byID.isEmpty
        roots = buildNodes()
        byID = [:]
        func index(_ n: Node) { byID[n.id] = n; n.children.forEach(index) }
        roots.forEach(index)
        outline.reloadData()
        let filtering = !filterField.stringValue.isEmpty
        for n in byID.values where !n.children.isEmpty && (firstTime || filtering || open.contains(n.id)) { outline.expandItem(n) }
        let empty = store.entries.isEmpty
        emptyLabel.stringValue = ""
        emptyLabel.isHidden = true
        _ = empty
        if let id = selected, byID[id] != nil { select(id, expandTo: false) }
        else if let first = roots.first { select(first.id, expandTo: false) }
        else { selected = nil }
        showCard()
    }

    private func path(to id: String) -> [Node] {
        func find(_ n: Node, _ trail: [Node]) -> [Node]? {
            if n.id == id { return trail + [n] }
            for c in n.children { if let r = find(c, trail + [n]) { return r } }
            return nil
        }
        for r in roots { if let t = find(r, []) { return t } }
        return []
    }

    func select(_ id: String, expandTo: Bool = true) {
        commitEdits()
        guard byID[id] != nil else { return }
        if expandTo { for n in path(to: id).dropLast() { outline.expandItem(n) } }
        selected = id
        let row = outline.row(forItem: byID[id])
        if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); outline.scrollRowToVisible(row) }
        showCard()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? roots.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? Node)?.children[index] ?? roots[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Node)?.children.isEmpty ?? true) }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? Node else { return nil }
        let l = NSTextField(labelWithString: n.name)
        l.font = n.isWorld ? .systemFont(ofSize: 13, weight: .bold) : .systemFont(ofSize: 13)
        return CenteredCell(l, leading: 0)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outline.selectedRow
        guard row >= 0, let n = outline.item(atRow: row) as? Node, n.id != selected else { return }
        commitEdits()
        selected = n.id
        showCard()
    }

    /// The titles of the rows now shown, in order, with two spaces of indent per level (for the checks).
    var visibleTitles: [String] {
        (0..<outline.numberOfRows).compactMap { row in
            guard let n = outline.item(atRow: row) as? Node else { return nil }
            return String(repeating: "  ", count: outline.level(forRow: row)) + n.name
        }
    }

    // MARK: Dragging a place (into a world or inside another place)

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let n = item as? Node, !n.isWorld else { return nil }
        let b = NSPasteboardItem()
        b.setString(n.id, forType: Self.dragType)
        return b
    }

    private func draggedID(_ info: NSDraggingInfo) -> String? { info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.dragType) }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let id = draggedID(info), let target = item as? Node else { return [] }
        if target.id == id || store.descendants(of: id).contains(where: { $0.id == target.id }) { return [] }
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let id = draggedID(info), let target = item as? Node else { return false }
        return movePlace(id, into: target.id)
    }

    /// Puts a place (with what is inside it) into a world or inside another place.
    @discardableResult
    func movePlace(_ id: String, into targetID: String) -> Bool {
        let world: String, parent: String?
        if store.world(targetID) != nil { world = targetID; parent = nil }
        else if let t = store.entry(targetID), let w = t.world { world = w; parent = targetID }
        else { return false }
        do { try store.move(entry: id, toWorld: world, parent: parent) } catch { return false }
        selected = id
        reload()
        onChange?()
        return true
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if outline.clickedRow >= 0, let n = outline.item(atRow: outline.clickedRow) as? Node { select(n.id) }
        guard selected != nil else { return }
        menu.addItem(ClosureMenuItem(title: L("New Place Inside")) { [weak self] in self?.promptNewPlace(inside: true) })
        if let id = selected, store.entry(id) != nil {
            menu.addItem(ClosureMenuItem(title: L("New Place Beside")) { [weak self] in self?.promptNewPlace(inside: false) })
        }
        menu.addItem(ClosureMenuItem(title: L("New World")) { [weak self] in self?.newWorldPressed() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L("Rename")) { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.nameField)
            self.nameField.currentEditor()?.selectAll(nil)
        })
        menu.addItem(.separator())
        let isWorld = selected.map { store.world($0) != nil } ?? false
        let merge = ClosureMenuItem(title: L("Merge Into…")) { [weak self] in self?.mergeSelected() }
        merge.isEnabled = isWorld ? store.worlds.count > 1 : store.entries.count > 1
        menu.addItem(merge)
        let convert = ClosureMenuItem(title: isWorld ? L("Turn Into a Place…") : L("Turn Into a World…")) { [weak self] in self?.convertSelected() }
        convert.isEnabled = isWorld ? store.worlds.count > 1 : true
        menu.addItem(convert)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L("Delete…")) { [weak self] in self?.deleteSelected(confirm: true) })
    }

    // MARK: Merging and converting

    @objc private func mergePressed() { mergeSelected() }
    @objc private func convertPressed() { convertSelected() }

    /// A dialog with a list to choose from (Cancel is the default); the id of the chosen one, or nil.
    private func choose(message: String, info: String, button: String, options: [(title: String, id: String)]) -> String? {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26), pullsDown: false)
        for o in options { popup.addItem(withTitle: o.title); popup.lastItem?.representedObject = o.id }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        alert.accessoryView = popup
        let cancel = alert.addButton(withTitle: L("Cancel"))
        cancel.keyEquivalent = "\r"
        let go = alert.addButton(withTitle: button)
        go.keyEquivalent = ""
        go.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return nil }
        return popup.selectedItem?.representedObject as? String
    }

    func mergeSelected() {
        guard let id = selected else { return }
        commitEdits()
        if let world = store.world(id) {
            let others = store.worlds.filter { $0.id != id }.map { (title: $0.name ?? "", id: $0.id ?? "") }
            guard !others.isEmpty else { return }
            let name = world.name ?? ""
            if let target = choose(message: L("Merge “{name}” into…", ["name": name]),
                                   info: L("Choose the world to keep. “{name}” is taken out of the book: its name and aliases become aliases of the kept world, and all its places move to the top of the kept world. The card goes to the book's trash folder (.quilland/trash). You can undo this.", ["name": name]),
                                   button: L("Merge"), options: others) { onMergeWorld?(id, target) }
        } else if let entry = store.entry(id) {
            let inside = Set(store.descendants(of: id).compactMap(\.id))
            let others = store.entries.filter { $0.id != id && !inside.contains($0.id ?? "") }
                .map { (title: store.path(of: $0.id ?? "").joined(separator: " › "), id: $0.id ?? "") }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            guard !others.isEmpty else { return }
            let name = entry.name ?? ""
            if let target = choose(message: L("Merge “{name}” into…", ["name": name]),
                                   info: L("Choose the place to keep. “{name}” is taken out of the book: its name and aliases become aliases of the kept place, its description, notes and scenes are added to theirs, and what is inside it moves into the kept place. The card goes to the book's trash folder (.quilland/trash). You can undo this.", ["name": name]),
                                   button: L("Merge"), options: others) { onMergePlace?(id, target) }
        }
    }

    func convertSelected() {
        guard let id = selected else { return }
        commitEdits()
        if let world = store.world(id) {
            // Where it goes: another world (at the top) or a place in one.
            var options: [(title: String, id: String)] = []
            for other in store.worlds where other.id != id {
                guard let wid = other.id else { continue }
                options.append((other.name ?? "", "w:" + wid))
                for e in store.entries.filter({ $0.world == wid }).sorted(by: { store.path(of: $0.id ?? "").joined().localizedCaseInsensitiveCompare(store.path(of: $1.id ?? "").joined()) == .orderedAscending }) {
                    options.append((store.path(of: e.id ?? "").joined(separator: " › "), "e:" + (e.id ?? "")))
                }
            }
            guard !options.isEmpty else { return }
            let name = world.name ?? ""
            guard let pick = choose(message: L("Turn “{name}” into a place?", ["name": name]),
                                    info: L("Choose where the place goes. The world becomes a place there, and its places are inside it. You can undo this."),
                                    button: L("Turn Into a Place"), options: options) else { return }
            if pick.hasPrefix("w:") { onWorldToPlace?(id, String(pick.dropFirst(2)), nil) }
            else if let entry = store.entry(String(pick.dropFirst(2))), let target = entry.world { onWorldToPlace?(id, target, entry.id) }
        } else if let entry = store.entry(id) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Turn “{name}” into a world?", ["name": entry.name ?? ""])
            alert.informativeText = L("The place becomes a world of its own, and the places inside it are at the top of that world. Its description, notes, scenes and the links to it go with it. You can undo this.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Turn Into a World"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            onPlaceToWorld?(id)
        }
    }

    private func promptNewPlace(inside: Bool) {
        view.window?.makeFirstResponder(addField)
        addField.stringValue = ""
        pendingInside = inside
    }
    private var pendingInside = true

    // MARK: Adding

    /// A new place with this name, inside the chosen world or place (or beside the chosen place).
    @discardableResult
    func addPlace(named raw: String, inside: Bool = true) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let sel = selected else { return nil }
        let world: String, parent: String?
        if store.world(sel) != nil { world = sel; parent = nil }
        else if let e = store.entry(sel), let w = e.world { world = w; parent = inside ? sel : e.parent }
        else { return nil }
        guard let id = try? store.addEntry(name: name, world: world, parent: parent) else { return nil }
        addField.stringValue = ""
        selected = id
        pendingInside = true
        reload()
        select(id)
        onChange?()
        view.window?.makeFirstResponder(descriptionView)
        return id
    }

    @discardableResult
    func addWorld(named raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let id = try? store.addWorld(name: name) else { return nil }
        selected = id
        reload()
        select(id)
        onChange?()
        return id
    }

    @objc private func newWorldPressed() {
        guard let id = addWorld(named: "New World") else { return }
        _ = id
        view.window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    // MARK: The card

    private func showCard() {
        guard isViewLoaded else { return }
        guard let id = selected, byID[id] != nil else {
            cardScroll.isHidden = true
            nothing.isHidden = false
            nothing.stringValue = L("Choose a world or a place")
            return
        }
        cardScroll.isHidden = false
        nothing.isHidden = true
        if let w = store.world(id) {
            nameField.stringValue = w.name ?? ""
            aliasField.stringValue = w.aliases.joined(separator: ", ")
            typeBox.isHidden = true
            pathLabel.stringValue = L("World")
            let n = store.entries.filter { $0.world == id }.count
            countLabel.stringValue = Lp("{n} place in this world", "{n} places in this world", n)
            countLabel.isHidden = false
            setText(descriptionView, store.text(id))
            setText(notesView, w.notes.joined(separator: "\n"))
            sceneScroll.isHidden = true; scenesCaption.isHidden = true
            rows = []
            deleteButton.title = L("Delete World…")
            convertButton.title = L("Turn Into a Place…")
            mergeButton.isEnabled = store.worlds.count > 1
            convertButton.isEnabled = store.worlds.count > 1
        } else if let e = store.entry(id) {
            nameField.stringValue = e.name ?? ""
            aliasField.stringValue = e.aliases.joined(separator: ", ")
            typeBox.isHidden = false
            typeBox.stringValue = e.type
            pathLabel.stringValue = store.path(of: id).dropLast().joined(separator: " › ")
            countLabel.isHidden = true
            setText(descriptionView, store.text(id))
            setText(notesView, e.notes.joined(separator: "\n"))
            sceneScroll.isHidden = false; scenesCaption.isHidden = false
            rebuildRows(for: e)
            deleteButton.title = L("Delete Place…")
            convertButton.title = L("Turn Into a World…")
            mergeButton.isEnabled = store.entries.count > 1
            convertButton.isEnabled = true
        }
    }

    private func setText(_ tv: NSTextView, _ text: String) {
        if tv.string != text { tv.string = text }
        tv.undoManager?.removeAllActions()
    }

    private func rebuildRows(for e: PlaceRecord) {
        guard let id = e.id, let name = e.name else { return }
        let named = mentions(NameEntry(id: id, name: name, aliases: e.aliases, ignoresCapitals: true))
        let links = e.links
        rows = scenes().compactMap { s in
            let n = named[s.id] ?? 0
            let line = links[s.id]
            guard n > 0 || line != nil else { return nil }
            return CharacterSceneRow(sceneID: s.id, title: s.title, mentions: n, pov: false, text: line ?? "")
        }
        sceneTable.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let r = rows[row]
        switch id {
        case "scene": return NSTextField(labelWithString: r.title)
        case "mentions":
            let l = NSTextField(labelWithString: r.mentions > 0 ? String(r.mentions) : "")
            l.alignment = .right; l.textColor = .secondaryLabelColor
            return l
        default:
            let f = NSTextField(string: r.text)
            f.isBezeled = true; f.bezelStyle = .squareBezel; f.isEditable = true
            f.drawsBackground = true; f.backgroundColor = .textBackgroundColor; f.textColor = .textColor
            f.delegate = self; f.placeholderString = L("Type what happens here")
            return f
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { QuietRowView() }

    @objc private func openSceneRow() {
        let row = sceneTable.clickedRow
        let column = sceneTable.clickedColumn
        // A double-click in the text column is for typing, not for going away.
        if sceneTable.tableColumns.indices.contains(column), sceneTable.tableColumns[column].identifier.rawValue == "text" { return }
        guard rows.indices.contains(row) else { return }
        onOpenScene?(rows[row].sceneID)
    }

    // MARK: Editing

    private func updateSelected(rebuild: Bool = true, world: ((inout WorldRecord) -> Void)? = nil, entry: ((inout PlaceRecord) -> Void)? = nil) {
        guard let id = selected else { return }
        if store.world(id) != nil, let world { try? store.updateWorld(id, world) }
        if store.entry(id) != nil, let entry { try? store.updateEntry(id, entry) }
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
            if name.isEmpty { showCard() } else { updateSelected(world: { $0.name = name }, entry: { $0.name = name }) }
        } else if field === aliasField {
            let aliases = aliasField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            updateSelected(world: { $0.aliases = aliases }, entry: { $0.aliases = aliases })
        } else if field === typeBox {
            let type = typeBox.stringValue.trimmingCharacters(in: .whitespaces)
            updateSelected(rebuild: false, entry: { $0.type = type.isEmpty ? "place" : type })
        } else if field !== addField, field !== filterField {
            let row = sceneTable.row(for: field)
            if row >= 0 { setSceneLine(row: row, field.stringValue) }
        }
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        let type = typeBox.objectValueOfSelectedItem as? String ?? typeBox.stringValue
        updateSelected(rebuild: false, entry: { $0.type = type })
    }

    /// What happens in the scene of this row (empty removes the line).
    func setSceneLine(row: Int, _ raw: String) {
        guard rows.indices.contains(row) else { return }
        let scene = rows[row].sceneID
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        updateSelected(rebuild: false, entry: { r in
            var links = r.links
            if text.isEmpty { links.removeValue(forKey: scene) } else { links[scene] = text }
            r.links = links
        })
        rows[row].text = text
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === filterField { reload() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === addField, selector == #selector(NSResponder.insertNewline(_:)) { addPlace(named: addField.stringValue, inside: pendingInside); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)), control === filterField || control === addField { onEscape?(); return true }
        return false
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === descriptionView || tv === notesView else { return }
        dirty.insert(tv === descriptionView ? "text" : "notes")
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.commitEdits() }
    }

    func textDidEndEditing(_ notification: Notification) { commitEdits() }

    func commitEdits() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard !dirty.isEmpty, let id = selected else { dirty = []; return }
        let pending = dirty
        dirty = []
        if pending.contains("text") { try? store.setText(id, descriptionView.string) }
        if pending.contains("notes") {
            let lines = notesView.string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            try? store.updateWorld(id) { $0.notes = lines }
            try? store.updateEntry(id) { $0.notes = lines }
        }
        onChange?()
    }

    // MARK: Deleting

    @objc private func deletePressed() { deleteSelected(confirm: true) }

    func deleteSelected(confirm: Bool) {
        guard let id = selected else { return }
        let isWorld = store.world(id) != nil
        let name = store.world(id)?.name ?? store.entry(id)?.name ?? ""
        if isWorld {
            if store.worlds.count <= 1 || store.entries.contains(where: { $0.world == id }) {
                if confirm {
                    let alert = NSAlert()
                    alert.messageText = L("This world cannot be deleted yet")
                    alert.informativeText = store.worlds.count <= 1 ? L("A book keeps at least one world.") : L("Move or delete the places of this world first.")
                    alert.runModal()
                }
                return
            }
        }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = isWorld ? L("Delete the world “{name}”?", ["name": name]) : L("Delete the place “{name}”?", ["name": name])
            let inside = isWorld ? 0 : store.descendants(of: id).count
            alert.informativeText = L("The card and its text go to the book's trash folder (.quilland/trash).") + (inside > 0 ? " " + Lp("The {n} place inside it stays and moves up one level.", "The {n} places inside it stay and move up one level.", inside) : "")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Delete"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        commitEdits()
        do { if isWorld { try store.deleteWorld(id) } else { try store.deleteEntry(id) } } catch { return }
        selected = nil
        reload()
        onChange?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
