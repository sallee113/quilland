import AppKit
import QuillandCore

/// An outline view that tells its controller about the keys the tree owns (Return renames, ⌘⌫ deletes, Tab goes to the text).
final class TreeOutlineView: NSOutlineView {
    var onKey: ((NSEvent) -> Bool)?
    /// ⌘Z (Edit ▸ Undo) while the tree has the focus undoes the last structural change.
    var onUndo: (() -> Void)?
    var canUndo: () -> Bool = { false }
    var onRedo: (() -> Void)?
    var canRedo: () -> Bool = { false }
    @objc func undo(_ sender: Any?) { onUndo?() }
    @objc func redo(_ sender: Any?) { onRedo?() }
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == Selector(("undo:")) { return canUndo() }
        if item.action == Selector(("redo:")) { return canRedo() }
        return super.validateUserInterfaceItem(item)
    }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
}

/// The structure of the book as a tree, docked on the left in Panels mode: parts, chapters and scenes with their statuses and sizes.
final class StructureTreeController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    final class Item {
        let node: BookStructure.Node
        let children: [Item]
        init(_ node: BookStructure.Node) {
            self.node = node
            children = node.children.map(Item.init)
        }
        var id: String { node.id }
    }

    private let outline = TreeOutlineView()
    private let scroll = NSScrollView()
    private var roots: [Item] = []
    private var byID: [String: Item] = [:]
    private var characters: (String) -> Int = { _ in 0 }
    private var reloading = false
    /// The jump list: one click or Return chooses a scene; no editing commands.
    var choosesOnClick = false
    /// The Outline view: several rows can be chosen and the rows can be dragged; every section is selectable.
    var isOutline = false {
        didSet {
            guard isViewLoaded else { return }
            outline.allowsMultipleSelection = isOutline
            if isOutline { outline.registerForDraggedTypes([Self.dragType]) } else { outline.unregisterDraggedTypes() }
        }
    }
    static let dragType = NSPasteboard.PasteboardType("com.quilland.section")
    /// What the Outline shows on hover and beside a title: the synopsis and whether the section has a note.
    var synopsisOf: (String) -> String? = { _ in nil }
    var hasNote: (String) -> Bool = { _ in false }

    /// A scene was chosen (by a click or the arrow keys).
    var onSelectScene: ((String) -> Void)?
    /// The author asked to go into the text (double-click, Tab).
    var onEnterText: (() -> Void)?
    /// Any row (a part or a chapter too) was chosen; the Outline's information area follows it.
    var onSelectNode: (([String]) -> Void)?
    /// Rows were dropped: the ids in book order, the new parent (nil: the book) and the place among its children (nil: the end).
    var onMove: (([String], String?, Int?) -> Void)?
    var onEscape: (() -> Void)?
    /// The + button at the foot of the tree: a new section of this kind, before or after the chosen one (or at the end).
    var onNew: ((BookStructure.Kind, BookEditor.Place) -> Void)?
    private let footer = NSView()
    private let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    var onUndo: (() -> Void)? { didSet { outline.onUndo = onUndo } }
    var canUndo: () -> Bool = { false } { didSet { outline.canUndo = canUndo } }
    var onRedo: (() -> Void)? { didSet { outline.onRedo = onRedo } }
    var canRedo: () -> Bool = { false } { didSet { outline.canRedo = canRedo } }
    var onRename: ((String, String) -> Void)?
    /// A command from the context menu or a key: its name and the section it is about.
    var onCommand: ((Command, String) -> Void)?

    enum Command { case newSceneAfter, newSceneBefore, newChapter, newPart, moveUp, moveDown, delete, status(String), mergeNext, mergePrevious, group, ungroup }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.indentationPerLevel = 14
        outline.floatsGroupRows = false
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.doubleAction = #selector(doubleClicked)
        outline.action = #selector(clicked)
        outline.allowsMultipleSelection = isOutline
        if isOutline { outline.registerForDraggedTypes([Self.dragType]) }
        outline.draggingDestinationFeedbackStyle = .gap
        outline.setAccessibilityLabel(L("Structure"))
        outline.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        buildFooter()
        let container = NSView()
        for v in [scroll, footer] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor), scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor), footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: footerHeight),
        ])
        view = container
    }

    private var footerHeight: CGFloat { choosesOnClick ? 0 : 30 }

    /// A + at the foot of the tree, with a small menu: the sections that can be added, so adding does not depend on knowing a key or a right-click.
    private func buildFooter() {
        guard !choosesOnClick else { footer.isHidden = true; return }
        addButton.removeAllItems()
        addButton.addItem(withTitle: "")
        addButton.item(at: 0)?.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add a section")
        for (title, kind, place) in [("New Scene", BookStructure.Kind.scene, BookEditor.Place.after), ("New Scene Before", .scene, .before),
                                     ("New Chapter", .chapter, .after), ("New Part", .part, .after)] {
            addButton.menu?.addItem(ClosureMenuItem(title: title) { [weak self] in self?.requestNew(kind, place) })
        }
        addButton.isBordered = false
        addButton.controlSize = .small
        addButton.setAccessibilityLabel(L("Add a section"))
        addButton.toolTip = L("Add a scene, a chapter or a part (⌘N adds a scene)")
        addButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(addButton)
        NSLayoutConstraint.activate([
            addButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8), addButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 46),
        ])
    }

    /// What the + menu asks for.
    func requestNew(_ kind: BookStructure.Kind, _ place: BookEditor.Place) { onNew?(kind, place) }

    /// The titles in the + menu (for the checks).
    var newMenuTitles: [String] { (addButton.menu?.items ?? []).dropFirst().map(\.title) }
    var hasFooter: Bool { !footer.isHidden }

    var selectedID: String? {
        let row = outline.selectedRow
        return row >= 0 ? (outline.item(atRow: row) as? Item)?.id : nil
    }

    /// The titles of the rows now shown, in order (for the checks).
    var visibleTitles: [String] { (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? Item)?.node.title } }

    var isFirstResponder: Bool { view.window?.firstResponder === outline }
    func focus() { view.window?.makeFirstResponder(outline) }

    /// Shows the structure (again). `characters` gives a scene's size. The selection and the open chapters are kept.
    func reload(structure: BookStructure, characters: @escaping (String) -> Int, selecting id: String? = nil, expandAll: Bool = false) {
        self.characters = characters
        let keep = id ?? selectedID
        let open = Set(byID.values.filter { outline.isItemExpanded($0) }.map(\.id))
        reloading = true
        roots = structure.roots.map(Item.init)
        byID = [:]
        func index(_ item: Item) { byID[item.id] = item; item.children.forEach(index) }
        roots.forEach(index)
        outline.reloadData()
        let firstTime = open.isEmpty || expandAll
        for item in byID.values where item.node.kind != .scene && (firstTime || open.contains(item.id)) { outline.expandItem(item) }
        reloading = false
        if let keep { select(keep, notify: false) }
    }

    /// Updates the sizes and statuses shown, without changing the structure.
    func refreshCounts() { outline.reloadData(forRowIndexes: IndexSet(0..<outline.numberOfRows), columnIndexes: IndexSet(integer: 0)) }

    func select(_ id: String, notify: Bool = true) {
        guard let item = byID[id] else { return }
        // Open its chapter and part so that it can be seen.
        var chain: [Item] = []
        for root in roots { if let path = path(to: id, in: root) { chain = path } }
        for parent in chain.dropLast() { outline.expandItem(parent) }
        let row = outline.row(forItem: item)
        guard row >= 0 else { return }
        reloading = !notify
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        reloading = false
        outline.scrollRowToVisible(row)
    }

    private func path(to id: String, in item: Item) -> [Item]? {
        if item.id == id { return [item] }
        for child in item.children { if let p = path(to: id, in: child) { return [item] + p } }
        return nil
    }

    // MARK: Data

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Item)?.children.count ?? roots.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? Item)?.children[index] ?? roots[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Item)?.children.isEmpty ?? true) || (item as? Item)?.node.kind != .scene }

    private func total(_ item: Item) -> Int { item.node.kind == .scene ? characters(item.id) : item.children.reduce(0) { $0 + total($1) } }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? Item else { return nil }
        let cell = TreeCell()
        cell.configure(node: item.node, count: total(item), note: isOutline && hasNote(item.id))
        cell.title.delegate = self
        cell.title.identifier = NSUserInterfaceItemIdentifier(item.id)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !reloading else { return }
        if isOutline { onSelectNode?(selectedIDs); return }
        guard let id = selectedID, let item = byID[id], item.node.kind == .scene else { return }
        onSelectScene?(id)
    }

    /// The chosen rows, in book order.
    var selectedIDs: [String] { outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? Item)?.id } }

    func outlineView(_ outlineView: NSOutlineView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, item: Any, mouseLocation: NSPoint) -> String {
        guard isOutline, let item = item as? Item, let text = synopsisOf(item.id) else { return "" }
        return text
    }

    // MARK: Dragging (the Outline)

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard isOutline, let item = item as? Item else { return nil }
        let board = NSPasteboardItem()
        board.setString(item.id, forType: Self.dragType)
        return board
    }

    private func parent(of item: Item) -> Item? { roots.contains { $0 === item } ? nil : byID.values.first { $0.children.contains { $0 === item } } }

    private func draggedIDs(_ info: NSDraggingInfo) -> [String] {
        let all = info.draggingPasteboard.pasteboardItems?.compactMap { $0.string(forType: Self.dragType) } ?? []
        return selectedIDs.filter(all.contains)
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        let ids = draggedIDs(info)
        guard isOutline, let first = ids.first.flatMap({ byID[$0] }), ids.allSatisfy({ byID[$0]?.node.kind == first.node.kind }) else { return [] }
        var target = item as? Item
        var at = index
        // A drop on a row of the dragged kind's own level means "next to it".
        if let t = target, t.node.kind == first.node.kind {
            at = (parent(of: t)?.children ?? roots).firstIndex { $0 === t } ?? 0
            target = parent(of: t)
        }
        switch first.node.kind {
        case .scene: guard target?.node.kind == .chapter else { return [] }
        case .chapter: guard target == nil || target?.node.kind == .part else { return [] }
        case .part: guard target == nil else { return [] }
        }
        // Not into itself.
        if let t = target, ids.contains(t.id) { return [] }
        outlineView.setDropItem(target, dropChildIndex: at)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let ids = draggedIDs(info)
        guard !ids.isEmpty else { return false }
        onMove?(ids, (item as? Item)?.id, index < 0 ? nil : index)
        return true
    }

    // MARK: Renaming

    func beginRename() {
        let row = outline.selectedRow
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? TreeCell else { return }
        if let id = selectedID, let item = byID[id] { cell.title.stringValue = item.node.title }
        cell.title.isEditable = true
        view.window?.makeFirstResponder(cell.title)
        cell.title.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let raw = field.identifier?.rawValue, let item = byID[raw] else { return }
        field.isEditable = false
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cancelled = (obj.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.cancel.rawValue
        if cancelled || text.isEmpty || text == item.node.title {
            field.stringValue = item.node.title
        } else {
            onRename?(item.id, text)
        }
        focus()
    }

    // MARK: Keys and clicks

    @objc private func clicked() {
        guard choosesOnClick, let id = selectedID, byID[id]?.node.kind == .scene else { return }
        onEnterText?()
    }

    /// Moves the selection by rows (the filter field of the jump list forwards the arrow keys here); only scenes are stopped on.
    func moveSelection(by step: Int) {
        var row = outline.selectedRow
        let count = outline.numberOfRows
        guard count > 0 else { return }
        repeat {
            row += step
            if row < 0 || row >= count { return }
        } while (outline.item(atRow: row) as? Item)?.node.kind != .scene
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    func selectFirstScene() {
        outline.deselectAll(nil)
        moveSelection(by: 1)
    }

    @objc private func doubleClicked() {
        guard let id = selectedID, byID[id]?.node.kind == .scene else { return }
        onEnterText?()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch (event.keyCode, flags) {
        case (36, []), (76, []): if choosesOnClick { onEnterText?() } else { beginRename() }; return true // Return
        case (48, []): onEnterText?(); return true                       // Tab
        case (53, []): if isOutline { onEscape?(); return true }; return false // Esc
        case (51, [.command]): if let id = selectedID { onCommand?(.delete, id) }; return true // ⌘⌫
        default: return false
        }
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard !choosesOnClick else { return }
        let clicked = outline.clickedRow
        if clicked >= 0 { outline.selectRowIndexes(IndexSet(integer: clicked), byExtendingSelection: false) }
        guard let id = selectedID, let item = byID[id] else { return }
        func add(_ title: String, _ command: Command) { menu.addItem(ClosureMenuItem(title: title) { [weak self] in self?.onCommand?(command, id) }) }
        add(L("New Scene After"), .newSceneAfter)
        add(L("New Scene Before"), .newSceneBefore)
        add(L("New Chapter"), .newChapter)
        add(L("New Part"), .newPart)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L("Rename")) { [weak self] in self?.beginRename() })
        if item.node.kind == .scene {
            let statuses = NSMenuItem(title: L("Status"), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for s in SceneRecord.knownStatuses {
                let it = ClosureMenuItem(title: L(s).capitalized) { [weak self] in self?.onCommand?(.status(s), id) }
                it.state = item.node.status == s ? .on : .off
                sub.addItem(it)
            }
            statuses.submenu = sub
            menu.addItem(statuses)
        }
        menu.addItem(.separator())
        if item.node.kind == .scene {
            add(L("Merge with Next Scene"), .mergeNext)
            add(L("Merge with Previous Scene"), .mergePrevious)
        }
        if item.node.kind == .chapter { add(L("Group into a New Part…"), .group) }
        if item.node.kind == .part { add(L("Ungroup Part…"), .ungroup) }
        menu.addItem(.separator())
        add(L("Move Up"), .moveUp)
        add(L("Move Down"), .moveDown)
        menu.addItem(.separator())
        add(L("Delete…"), .delete)
    }
}

/// One row of the tree: a status dot for scenes, the title, the size.
final class TreeCell: NSTableCellView {
    let title = NSTextField(string: "")
    private let count = NSTextField(labelWithString: "")
    private let dot = NSView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 22))
        title.isBordered = false
        title.drawsBackground = false
        title.isEditable = false
        title.lineBreakMode = .byTruncatingTail
        title.focusRingType = .none
        count.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        count.textColor = .tertiaryLabelColor
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        for v in [dot, title, count] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2), dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7), dot.heightAnchor.constraint(equalToConstant: 7),
            title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5), title.centerYAnchor.constraint(equalTo: centerYAnchor),
            count.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), count.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(node: BookStructure.Node, count n: Int, note: Bool = false) {
        title.stringValue = note ? node.title + "  ✎" : node.title
        title.font = node.kind == .scene ? .systemFont(ofSize: 13) : .systemFont(ofSize: 13, weight: node.kind == .part ? .bold : .semibold)
        count.stringValue = NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
        dot.isHidden = node.kind != .scene
        dot.layer?.backgroundColor = SceneHeaderView.color(for: node.status).cgColor
    }
}
