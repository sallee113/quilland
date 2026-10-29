import AppKit
import QuillandCore

/// The World view: worlds at the top, their places (and peoples, things, terms) as a tree below; the card of the chosen one on the right.
final class WorldViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate, NSMenuDelegate {
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
    /// What events change in a place, in the order of the book, a tooltip for each, and the window of one (the owner of the book opens it).
    var changes: (String) -> [EntityChange] = { _ in [] }
    var changeTooltip: (EntityChange) -> String = { $0.eventTitle }
    var onOpenChange: ((String, String) -> Void)?
    private let changeRows = ChangeRowsView()
    private var subscriptions: [Subscription] = []
    /// Delete…: the owner of the book deletes the place or world with everything that refers to it (and can undo it). Without it the card is only taken out.
    var onDelete: ((String, Bool) -> Void)?
    var onPlaceToWorld: ((String) -> Void)?
    /// The world, the world it goes into and the place there it goes inside (nil: at the top).
    var onWorldToPlace: ((String, String, String?) -> Void)?

    private(set) var selected: String?
    private var roots: [Node] = []
    private var byID: [String: Node] = [:]
    private(set) var rows: [CharacterSceneRow] = []
    var eventStore: EventStore!
    /// The events of the book in order, for the rows and the "Add an Event…" menu.
    var events: () -> [EventChoice] = { [] }
    var onOpenEvent: ((String) -> Void)?
    private static let dragType = NSPasteboard.PasteboardType("com.quilland.place")

    let filterField = NSSearchField()
    /// "Filter by…": the places of a section, a character or an event.
    let relationFilter = RelationFilter(kind: .place)
    let addField = NSTextField()
    private let outline = Hover.rows(NSOutlineView())
    private let newWorldButton = NSButton(title: L("New World"), target: nil, action: nil)
    private let emptyLabel = NSTextField(labelWithString: "")

    private let cardScroll = NSScrollView()
    private let card = NSStackView()
    private let nothing = NSTextField(labelWithString: "")
    let nameField = NSTextField()
    private let pathLabel = NSTextField(labelWithString: "")
    let aliasField = NSTextField()
    let descriptionView = NSTextView()
    let notesView = NSTextView()
    private let scenesCaption = NSTextField(labelWithString: "")
    private let sceneTable = Hover.rows(NSTableView())
    private var sceneScroll = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton(title: L("Delete…"), target: nil, action: nil)
    private let addSceneButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeSceneButton = NSButton(title: L("Remove Link"), target: nil, action: nil)
    private let sceneButtons = NSStackView()
    private let mentionsBox = NSButton(checkboxWithTitle: L("Also scenes that name it"), target: nil, action: nil)
    /// Does the list also have the scenes that only name the place? (Off: it has what is linked: the lines on the card and the events held here.)
    private(set) var showsMentions = false
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
        relationFilter.onChange = { [weak self] in self?.reload(keepingRelations: true) }
        for v in [filterField, newWorldButton, relationFilter.view, scroll, addField, emptyLabel] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            newWorldButton.leadingAnchor.constraint(equalTo: filterField.trailingAnchor, constant: 6), newWorldButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            newWorldButton.centerYAnchor.constraint(equalTo: filterField.centerYAnchor),
            relationFilter.view.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 6), relationFilter.view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            relationFilter.view.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: relationFilter.view.bottomAnchor, constant: 6), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
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
        changeRows.onOpen = { [weak self] event in if let id = self?.selected { self?.onOpenChange?(event, id) } }
        subscriptions.append(subscribe(to: .bookDataChanged) { [weak self] in self?.refreshChanges() })
        nameField.font = .systemFont(ofSize: 24, weight: .semibold)
        nameField.isBordered = false; nameField.drawsBackground = false; nameField.focusRingType = .none
        nameField.placeholderString = L("Name"); nameField.delegate = self
        nameField.setAccessibilityLabel(L("Name"))
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        aliasField.placeholderString = L("Other names, separated by commas"); aliasField.delegate = self
        aliasField.setAccessibilityLabel(L("Also called"))
        descriptionView.setAccessibilityLabel(L("Description")); notesView.setAccessibilityLabel(L("Notes"))
        scenesCaption.stringValue = L("Scenes and events (◆) linked to it, and what happens here (double-click opens it)")
        scenesCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        scenesCaption.textColor = .secondaryLabelColor
        for (id, title, width) in [("scene", L("Scene"), 240), ("mentions", L("Named"), 54), ("text", L("What happens here"), 280), ("changes", L("Changes"), 100)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width; c.minWidth = id == "text" ? 140 : (id == "changes" ? 100 : 40)
            sceneTable.addTableColumn(c)
        }
        ChangesButton.adjust(sceneTable, textColumn: "text")
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
        addSceneButton.controlSize = .small
        removeSceneButton.target = self; removeSceneButton.action = #selector(removeSceneLinkPressed)
        removeSceneButton.controlSize = .small; removeSceneButton.bezelStyle = .rounded
        removeSceneButton.toolTip = removeTip
        mentionsBox.controlSize = .small
        mentionsBox.target = self; mentionsBox.action = #selector(mentionsChanged)
        mentionsBox.toolTip = L("Shows the scenes that name the place in their text, dimmed: they are not links, and cannot be taken away here")
        sceneButtons.setViews([addSceneButton, removeSceneButton, mentionsBox], in: .leading)
        sceneButtons.spacing = 8

        let descBox = box(descriptionView, height: 150), notesBox = box(notesView, height: 80)
        for v in [nameField, pathLabel, aliasField, countLabel, caption(L("Description and rules")), descBox, changeRows, caption(L("Notes (one per line)")), notesBox, scenesCaption, sceneScroll, sceneButtons, cardButtons] {
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
            descBox.widthAnchor.constraint(equalTo: card.widthAnchor), notesBox.widthAnchor.constraint(equalTo: card.widthAnchor), changeRows.widthAnchor.constraint(equalTo: card.widthAnchor),
            sceneScroll.widthAnchor.constraint(equalTo: card.widthAnchor),
            nothing.centerXAnchor.constraint(equalTo: root.centerXAnchor), nothing.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    // MARK: The tree

    private func buildNodes() -> [Node] {
        let needle = filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        let allowed = relationFilter.allowed()
        func entryNode(_ e: PlaceRecord) -> Node? {
            let kids = store.children(of: e.id, in: e.world ?? "").compactMap(entryNode)
            let own = (needle.isEmpty || (e.name ?? "").lowercased().contains(needle) || e.aliases.contains { $0.lowercased().contains(needle) }) && (allowed == nil || allowed!.contains(e.id ?? ""))
            guard own || !kids.isEmpty else { return nil }
            return Node(id: e.id ?? "", isWorld: false, name: e.name ?? "", children: kids)
        }
        return store.worlds.compactMap { w in
            guard let id = w.id else { return nil }
            let kids = store.children(of: nil, in: id).compactMap(entryNode)
            // With a filter on, a world is shown for the places in it that match (it is only their container).
            let own = (needle.isEmpty || (w.name ?? "").lowercased().contains(needle)) && allowed == nil
            guard own || !kids.isEmpty else { return nil }
            return Node(id: id, isWorld: true, name: w.name ?? "", children: kids)
        }
    }

    /// Reads the tree again, keeping what was chosen and what was open.
    func reload(keepingRelations: Bool = false) {
        guard isViewLoaded else { return }
        if !keepingRelations { relationFilter.invalidate(); relationFilter.rebuild() }
        let open = Set(byID.values.filter { outline.isItemExpanded($0) }.map(\.id))
        let firstTime = byID.isEmpty
        roots = buildNodes()
        byID = [:]
        func index(_ n: Node) { byID[n.id] = n; n.children.forEach(index) }
        roots.forEach(index)
        relationFilter.setCount(shown: byID.values.filter { !$0.isWorld }.count, of: store.entries.count)
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

    // MARK: Where it was left (kept for the book)

    /// The chosen place, the place in the tree, what is open, and the filters.
    var memory: ViewMemory {
        ViewMemory(selected: selected, scroll: Double(outline.scrolledBy), filter: filterField.stringValue, anchors: relationFilter.memory,
                   closed: byID.values.filter { !$0.children.isEmpty && !outline.isItemExpanded($0) }.map(\.id).sorted(), flags: showsMentions ? ["mentions"] : [])
    }

    /// Puts the view back as it was left.
    func restore(_ m: ViewMemory?) {
        guard let m else { return }
        filterField.stringValue = m.filter
        relationFilter.restore(m.anchors)
        showsMentions = m.flags.contains("mentions"); mentionsBox.state = showsMentions ? .on : .off
        if let id = m.selected, store.entry(id) != nil || store.world(id) != nil { selected = id }
        reload()
        // (A tree is opened wholly the first time; here what was left shut is shut again, and the chosen place is shown. A filter opens everything, as it does.)
        if m.filter.isEmpty {
            let closed = Set(m.closed)
            for n in byID.values where closed.contains(n.id) { outline.collapseItem(n) }
            if let id = selected { for n in path(to: id).dropLast() { outline.expandItem(n) }; let row = outline.row(forItem: byID[id]); if row >= 0 { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } }
        }
        outline.restoreScroll(m.scroll)
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
            pathLabel.stringValue = L("World")
            let n = store.entries.filter { $0.world == id }.count
            countLabel.stringValue = Lp("{n} place in this world", "{n} places in this world", n)
            countLabel.isHidden = false
            setText(descriptionView, store.text(id))
            setText(notesView, w.notes.joined(separator: "\n"))
            sceneScroll.isHidden = true; scenesCaption.isHidden = true; sceneButtons.isHidden = true
            changeRows.set([], text: { _ in nil }, tooltip: { _ in "" })
            rows = []
            deleteButton.title = L("Delete World…")
            convertButton.title = L("Turn Into a Place…")
            mergeButton.isEnabled = store.worlds.count > 1
            convertButton.isEnabled = store.worlds.count > 1
        } else if let e = store.entry(id) {
            nameField.stringValue = e.name ?? ""
            aliasField.stringValue = e.aliases.joined(separator: ", ")
            pathLabel.stringValue = store.path(of: id).dropLast().joined(separator: " › ")
            countLabel.isHidden = true
            setText(descriptionView, store.text(id))
            setText(notesView, e.notes.joined(separator: "\n"))
            sceneScroll.isHidden = false; scenesCaption.isHidden = false; sceneButtons.isHidden = false
            rebuildRows(for: e)
            rebuildAddSceneMenu()
            refreshChanges()
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

    /// The rows under the description: what events change in the description of the place, in the order of the book.
    func refreshChanges() {
        guard isViewLoaded, let id = selected, store.entry(id) != nil else { return }
        changeRows.set(changes(id), text: { $0.text(.description) }, tooltip: changeTooltip)
        let column = sceneTable.column(withIdentifier: NSUserInterfaceItemIdentifier("changes"))
        if column >= 0, !rows.isEmpty { sceneTable.reloadData(forRowIndexes: IndexSet(integersIn: 0..<rows.count), columnIndexes: IndexSet(integer: column)) }
    }

    @objc private func changesPressed(_ sender: NSButton) { openChangesOfRow(sender.tag) }

    var eventRowFlags: [Bool] { rows.map(\.isEvent) }
    var rowTitles: [String] { rows.map(\.title) }
    /// For the checks: the title of the Changes button of each row of the list (nil: the row has none).
    var changesButtonTitles: [String?] { rows.indices.map { ChangesButton.title(in: sceneTable, row: $0) } }

    /// Opens the window of what the event of a row changes in this place.
    func openChangesOfRow(_ row: Int) {
        guard rows.indices.contains(row), rows[row].isEvent, let id = selected else { return }
        onOpenChange?(rows[row].sceneID, id)
    }

    /// For the checks: the texts of the rows under the description, and their tooltips.
    var changeRowTexts: [String] { changeRows.texts }
    var changeRowTooltips: [String] { changeRows.rows.map { $0.toolTip ?? "" } }
    var changeRowsDimmed: [Bool] { changeRows.rows.map { !$0.applies } }
    func clickChangeRow(_ index: Int) { if changeRows.rows.indices.contains(index) { changeRows.rows[index].onClick?(changeRows.rows[index].event) } }

    private func rebuildRows(for e: PlaceRecord) {
        guard let id = e.id, let name = e.name else { return }
        let named = mentions(NameEntry(id: id, name: name, aliases: e.aliases, ignoresCapitals: true))
        let links = e.links
        rows = scenes().compactMap { s in
            let n = named[s.id] ?? 0
            let line = links[s.id]
            guard n > 0 || line != nil else { return nil }
            // (A scene that only names the place is not a link: it is listed only when asked.)
            guard line != nil || showsMentions else { return nil }
            return CharacterSceneRow(sceneID: s.id, title: s.title, mentions: n, pov: false, text: line ?? "", mentionOnly: line == nil)
        }
        // The events held here: the link is kept in the event's file.
        for ev in events() {
            if let line = eventStore.event(ev.id)?.places[id] { rows.append(CharacterSceneRow(sceneID: ev.id, title: ev.label, mentions: 0, pov: false, text: line, isEvent: true)) }
        }
        sceneTable.reloadData()
        syncRemoveButton()
    }

    /// "Remove Link" works on the chosen row, so with none chosen it is off (and does not light under the pointer).
    private func syncRemoveButton() {
        let row = sceneTable.selectedRow
        let chosen = rows.indices.contains(row)
        removeSceneButton.isEnabled = chosen && !rows[row].mentionOnly
        removeSceneButton.toolTip = chosen && rows[row].mentionOnly ? L("The text of this scene names the place. Change the text or the place's names to take it out.") : removeTip
    }

    private var removeTip: String { L("Takes away the line of the chosen scene, or the place from the chosen event.") }

    @objc private func mentionsChanged() {
        showsMentions = mentionsBox.state == .on
        if let id = selected, let e = store.entry(id) { rebuildRows(for: e) }
    }

    /// For the checks: the switch for the scenes that only name the place, and which rows are such.
    func setShowsMentions(_ on: Bool) { mentionsBox.state = on ? .on : .off; mentionsChanged() }
    var mentionOnlyFlags: [Bool] { rows.map(\.mentionOnly) }
    var removeLinkTip: String { removeSceneButton.toolTip ?? "" }
    func selectSceneRow(_ row: Int) { sceneTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    var removeLinkEnabled: Bool { removeSceneButton.isEnabled }
    var addLinkEnabled: Bool { addSceneButton.isEnabled }
    /// For the checks: chooses a row of the list of scenes and events.
    func selectLinkRow(_ row: Int?) { if let row { sceneTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } else { sceneTable.deselectAll(nil) } }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === sceneTable { syncRemoveButton() }
    }

    // MARK: Adding a scene

    /// The "Add a Scene…" menu: the scenes that are not in the list yet, in the order of the book.
    private func rebuildAddSceneMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Add a Scene or Event…"), action: nil, keyEquivalent: ""))
        let shown = Set(rows.map(\.sceneID))
        let free = scenes().filter { !shown.contains($0.id) }
        let freeEvents = events().filter { !shown.contains($0.id) }
        if free.isEmpty && freeEvents.isEmpty {
            let none = NSMenuItem(title: L("None left"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for s in free { menu.addItem(ClosureMenuItem(title: s.title) { [weak self] in self?.addScene(s.id) }) }
        if !freeEvents.isEmpty {
            menu.addItem(.separator())
            let heading = NSMenuItem(title: L("Events"), action: nil, keyEquivalent: "")
            heading.isEnabled = false
            menu.addItem(heading)
            for e in freeEvents {
                let item = ClosureMenuItem(title: "◆ " + e.label) { [weak self] in self?.addEvent(e.id) }
                item.representedObject = e.id
                menu.addItem(item)
            }
        }
        addSceneButton.menu = menu
        addSceneButton.isEnabled = menu.offersAnything
    }

    /// Links the place to a scene where its name is not written: the line is empty and the cursor goes to it.
    func addScene(_ scene: String) {
        updateSelected(entry: { r in var links = r.links; if links[scene] == nil { links[scene] = "" }; r.links = links })
        guard let row = rows.firstIndex(where: { $0.sceneID == scene }),
              let column = sceneTable.tableColumns.firstIndex(where: { $0.identifier.rawValue == "text" }) else { return }
        sceneTable.scrollRowToVisible(row)
        sceneTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        sceneTable.editColumn(column, row: row, with: nil, select: false)
    }

    /// Holds the event at this place: the place goes into the event's file, and the cursor into the row's "What happens here" cell.
    func addEvent(_ event: String) {
        guard let place = selected, store.entry(place) != nil else { return }
        try? eventStore.update(event) { var p = $0.places; if p[place] == nil { p[place] = "" }; $0.places = p }
        onChange?()
        reload()
        guard let row = rows.firstIndex(where: { $0.sceneID == event }),
              let column = sceneTable.tableColumns.firstIndex(where: { $0.identifier.rawValue == "text" }) else { return }
        sceneTable.scrollRowToVisible(row)
        sceneTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        sceneTable.editColumn(column, row: row, with: nil, select: false)
    }

    /// Takes away the line of the scene of this row, or the place from the event of this row.
    func removeSceneLink(row: Int) {
        guard rows.indices.contains(row), !rows[row].mentionOnly else { return }
        let scene = rows[row].sceneID
        if rows[row].isEvent, let place = selected {
            try? eventStore.update(scene) { var p = $0.places; p.removeValue(forKey: place); $0.places = p }
            onChange?()
            reload()
            return
        }
        updateSelected(entry: { r in var links = r.links; links.removeValue(forKey: scene); r.links = links })
    }

    @objc private func removeSceneLinkPressed() { removeSceneLink(row: sceneTable.selectedRow) }

    /// For the checks: the scenes in the card's list, and the ones the "Add a Scene…" menu offers.
    var sceneRowIDs: [String] { rows.filter { !$0.isEvent }.map(\.sceneID) }
    var addableScenes: [String] { (addSceneButton.menu?.items.dropFirst() ?? []).compactMap { $0 is ClosureMenuItem && $0.representedObject == nil ? $0.title : nil } }
    /// The events in the card's list, and the ones the menu offers (ids).
    var eventRowIDs: [String] { rows.filter(\.isEvent).map(\.sceneID) }
    var addableEvents: [String] { (addSceneButton.menu?.items ?? []).compactMap { $0.representedObject as? String } }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let r = rows[row]
        switch id {
        case "scene":
            let l = NSTextField(labelWithString: r.isEvent ? "◆ " + r.title : r.title)
            if r.mentionOnly { l.textColor = .secondaryLabelColor }
            return l
        case "mentions":
            let l = NSTextField(labelWithString: r.mentions > 0 ? String(r.mentions) : "")
            l.alignment = .right; l.textColor = .secondaryLabelColor
            return l
        case "changes":
            guard r.isEvent, let id = selected, store.entry(id) != nil, eventStore.event(r.sceneID) != nil else { return nil }
            return ChangesButton.make(count: changes(id).first { $0.event == r.sceneID }?.effect.count ?? 0, row: row, target: self, action: #selector(changesPressed(_:)))
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
        if rows[row].isEvent { onOpenEvent?(rows[row].sceneID) } else { onOpenScene?(rows[row].sceneID) }
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
        } else if field !== addField, field !== filterField {
            let row = sceneTable.row(for: field)
            if row >= 0 { setSceneLine(row: row, field.stringValue) }
        }
    }


    /// What happens in the scene of this row (empty removes the line; an event stays held here with no text).
    func setSceneLine(row: Int, _ raw: String) {
        guard rows.indices.contains(row) else { return }
        let scene = rows[row].sceneID
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if rows[row].isEvent, let place = selected {
            try? eventStore.update(scene) { var p = $0.places; p[place] = text; $0.places = p }
            rows[row].text = text
            onChange?()
            return
        }
        updateSelected(rebuild: false, entry: { r in
            var links = r.links
            if text.isEmpty { links.removeValue(forKey: scene) } else { links[scene] = text }
            r.links = links
        })
        rows[row].text = text
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === filterField { reload(keepingRelations: true) }
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

    @objc func commitEdits() {
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
        if let onDelete { selected = nil; onDelete(id, isWorld); return }
        do { if isWorld { try store.deleteWorld(id) } else { try store.deleteEntry(id) } } catch { return }
        selected = nil
        reload()
        onChange?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
