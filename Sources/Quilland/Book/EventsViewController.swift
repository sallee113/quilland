import AppKit
import QuillandCore

/// One line of an event's connections: a scene, a place or a character, and what happens there.
struct EventConnection {
    enum Kind: String { case scene = "Scene", place = "Place", character = "Character", relationship = "Relationship" }
    var kind: Kind
    var refID: String
    var name: String
    var text: String
    var missing: Bool
    /// How many fields the event changes in it (characters, places and relationships).
    var changes = 0
    /// A relationship row: `starts`, `ends` or empty (the event only changes it).
    var marker = ""
    /// A relationship whose order is broken, or one that cannot apply: what is wrong, for a warning on the row.
    var warning: String?
}

/// The Events view: the events in the order of the book on the left, the card of the chosen one on the right.
final class EventsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate, NSMenuDelegate {
    var events: EventStore!
    var characters: CharacterStore!
    var relationships: RelationshipStore!
    /// The owner of the book opens the windows of the changes (it keeps one for each event and target, and shows the cards again when one is saved).
    var onOpenChanges: ((String, String, EffectTarget) -> Void)?
    var changesWindowProvider: ((String, String) -> ChangesWindowController?)?
    private var subscriptions: [Subscription] = []
    var worlds: WorldStore!
    var planStore: () -> PlanStore? = { nil }
    var scenes: () -> [(id: String, title: String)] = { [] }
    var onOpenScene: ((String) -> Void)?
    var onOpenPlace: ((String) -> Void)?
    /// Delete…: the owner of the book deletes the event with everything that refers to it (and can undo it), and is told what becomes of the relationships that start in it.
    var onDelete: ((String, BookIntegrity.StartedRelationships) -> Void)?
    var onOpenCharacter: ((String) -> Void)?
    var onShowPlan: (() -> Void)?
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?

    private(set) var selected: String?
    private var shown: [EventRecord] = []
    private enum ListRow { case heading(String), event(EventRecord) }
    private var listRows: [ListRow] = []
    private var draggedID: String?
    private static let rowType = NSPasteboard.PasteboardType("com.quilland.event-row")
    private(set) var connections: [EventConnection] = []

    let filterField = NSSearchField()
    /// "Filter by…": the events of a section, a character or a place.
    let relationFilter = RelationFilter(kind: .event)
    let addField = NSTextField()
    private let list = Hover.rows(EventListTable())
    private let emptyLabel = NSTextField(labelWithString: L("Add your first event"))

    private let cardScroll = NSScrollView()
    private let card = NSStackView()
    private let nothing = NSTextField(labelWithString: "")
    let titleField = NSTextField()
    let dateField = NSTextField()
    let descriptionView = NSTextView()
    let notesView = NSTextView()
    private let table = Hover.rows(NSTableView())
    /// The text being typed in a connection's "What happens" cell, so that its row grows as the lines come.
    private var editingText: (row: Int, text: String)?
    private let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeButton = NSButton(title: L("Remove Link"), target: nil, action: nil)
    private let planLabel = NSTextField(labelWithString: "")
    private let planButton = NSButton(title: "", target: nil, action: nil)
    private let deleteButton = NSButton(title: L("Delete Event…"), target: nil, action: nil)
    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private var dirty: Set<String> = []
    private var saveTimer: Timer?

    // MARK: View

    override func loadView() {
        subscriptions.append(subscribe(to: .bookDataChanged) { [weak self] in self?.refreshAfterChange() })
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "QuillandEvents"
        let left = NSViewController(); left.view = buildList()
        let right = NSViewController(); right.view = buildCard()
        let a = NSSplitViewItem(viewController: left)
        a.minimumThickness = 240; a.maximumThickness = 520
        a.holdingPriority = NSLayoutConstraint.Priority(260)
        let b = NSSplitViewItem(viewController: right)
        b.minimumThickness = 440
        split.addSplitViewItem(a); split.addSplitViewItem(b)
        addChild(split)
        view = split.view
        reload()
    }

    private func buildList() -> NSView {
        let root = NSView()
        filterField.placeholderString = L("Filter")
        filterField.delegate = self
        addField.placeholderString = L("Add an event — type a title, press Return")
        addField.delegate = self
        addField.setAccessibilityLabel(L("Add an event"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        list.addTableColumn(column)
        list.headerView = nil
        list.dataSource = self
        list.delegate = self
        list.rowHeight = 36
        list.style = .sourceList
        list.setAccessibilityLabel(L("Events"))
        let scroll = NSScrollView()
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        list.registerForDraggedTypes([Self.rowType])
        list.draggingDestinationFeedbackStyle = .gap
        (list as? EventListTable)?.moveHandler = { [weak self] by in self?.move(by: by) }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: L("Move Up")) { [weak self] in self?.move(by: -1) })
        menu.addItem(ClosureMenuItem(title: L("Move Down")) { [weak self] in self?.move(by: 1) })
        list.menu = menu
        relationFilter.onChange = { [weak self] in self?.reload(keepingRelations: true) }
        for v in [filterField, relationFilter.view, scroll, addField, emptyLabel] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            filterField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
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
        titleField.font = .systemFont(ofSize: 24, weight: .semibold)
        titleField.isBordered = false; titleField.drawsBackground = false; titleField.focusRingType = .none
        titleField.placeholderString = L("Title"); titleField.delegate = self
        titleField.setAccessibilityLabel(L("Title"))
        dateField.placeholderString = L("When (free text: “spring, year 214”, “several years later”)")
        dateField.delegate = self
        dateField.setAccessibilityLabel(L("Date"))
        descriptionView.setAccessibilityLabel(L("Description")); notesView.setAccessibilityLabel(L("Notes"))

        // Only "What happens" stretches and shrinks with the pane, so that the changes button at the right end is always in view.
        for (id, title, width) in [("kind", "", 76), ("name", L("Who or where"), 170), ("text", L("What happens"), 260), ("changes", L("Changes"), 100)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width; c.minWidth = id == "text" ? 120 : (id == "changes" ? 100 : 50)
            c.resizingMask = id == "text" ? [.autoresizingMask, .userResizingMask] : (id == "changes" ? [] : .userResizingMask)
            table.addTableColumn(c)
        }
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let rowMenu = NSMenu(); rowMenu.delegate = self; table.menu = rowMenu
        table.dataSource = self; table.delegate = self
        table.rowHeight = 22
        table.target = self; table.doubleAction = #selector(openConnection)
        table.setAccessibilityLabel(L("Connections"))
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true; tableScroll.borderType = .bezelBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 190).isActive = true
        addButton.controlSize = .small
        removeButton.target = self; removeButton.action = #selector(removeLink)
        removeButton.controlSize = .small; removeButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.spacing = 8
        planLabel.textColor = .secondaryLabelColor
        planButton.target = self; planButton.action = #selector(planPressed)
        planButton.controlSize = .small; planButton.bezelStyle = .rounded
        let planRow = NSStackView(views: [planLabel, planButton])
        planRow.spacing = 10
        deleteButton.target = self; deleteButton.action = #selector(deletePressed)
        deleteButton.bezelStyle = .rounded

        let descBox = box(descriptionView, height: 130), notesBox = box(notesView, height: 70)
        for v in [titleField, dateField, planRow, caption(L("Description")), descBox, caption(L("Notes (one per line)")), notesBox,
                  caption(L("Scenes, places, characters and relationships (double-click opens one)")), tableScroll, buttons, warningLabel, deleteButton] { card.addArrangedSubview(v) }
        warningLabel.textColor = .systemOrange; warningLabel.font = .systemFont(ofSize: 12); warningLabel.isHidden = true
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
            titleField.widthAnchor.constraint(equalTo: card.widthAnchor), dateField.widthAnchor.constraint(equalTo: card.widthAnchor),
            descBox.widthAnchor.constraint(equalTo: card.widthAnchor), notesBox.widthAnchor.constraint(equalTo: card.widthAnchor),
            tableScroll.widthAnchor.constraint(equalTo: card.widthAnchor),
            nothing.centerXAnchor.constraint(equalTo: root.centerXAnchor), nothing.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    // MARK: The list

    private var sceneOrder: [String] { scenes().map(\.id) }

    /// The rows of the list: a heading for each scene (the first one an event is linked to) and its events beneath it, in the order of the book.
    private func makeRows(needle: String) {
        let allowed = relationFilter.allowed()
        func matches(_ e: EventRecord) -> Bool { (needle.isEmpty || (e.title ?? "").lowercased().contains(needle)) && (allowed == nil || allowed!.contains(e.id ?? "")) }
        let titles = Dictionary(uniqueKeysWithValues: scenes().map { ($0.id, $0.title) })
        listRows = []
        // The default event comes first, under a heading of its own.
        if let start = events.startEvent, matches(start) {
            listRows.append(.heading(L("At the start of the book")))
            listRows.append(.event(start))
        }
        for group in events.groups(sceneOrder: sceneOrder) {
            let members = group.events.filter(matches)
            guard !members.isEmpty else { continue }
            listRows.append(.heading(group.scene.flatMap { titles[$0] } ?? L("not in a scene yet")))
            listRows += members.map { .event($0) }
        }
        shown = listRows.compactMap { if case .event(let e) = $0 { return e } else { return nil } }
    }

    private func row(of id: String) -> Int? {
        listRows.firstIndex { if case .event(let e) = $0 { return e.id == id } else { return false } }
    }

    func reload(keepingRelations: Bool = false) {
        guard isViewLoaded else { return }
        if !keepingRelations { relationFilter.invalidate(); relationFilter.rebuild() }
        makeRows(needle: filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased())
        relationFilter.setCount(shown: shown.filter { !$0.start }.count, of: events.events.count)
        list.reloadData()
        emptyLabel.isHidden = !events.events.isEmpty
        if let id = selected, let row = row(of: id) {
            list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if selected == nil || events.event(selected ?? "") == nil, let first = shown.first(where: { !$0.start }) ?? shown.first, let id = first.id, let row = row(of: id) {
            selected = id
            list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if shown.isEmpty { selected = nil }
        showCard()
    }

    func select(_ id: String) {
        commitEdits()
        selected = id
        filterField.stringValue = ""
        makeRows(needle: "")
        list.reloadData()
        if let row = row(of: id) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); list.scrollRowToVisible(row) }
        showCard()
    }

    /// The titles of the events of the story that are listed (the default event, "Book starts", is apart).
    var shownTitles: [String] { shown.filter { !$0.start }.compactMap(\.title) }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === list ? listRows.count : connections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === list {
            guard listRows.indices.contains(row) else { return nil }
            if case .heading(let title) = listRows[row] {
                let l = NSTextField(labelWithString: title)
                l.font = .systemFont(ofSize: 11, weight: .semibold)
                l.textColor = .secondaryLabelColor
                l.lineBreakMode = .byTruncatingTail
                return CenteredCell(l, leading: 2)
            }
            guard case .event(let e) = listRows[row] else { return nil }
            // The scene is the heading above: the row is the title alone, after a slot of a fixed width for the Δ of an event that changes something (so that the
            // first letters of all the titles stay in one line).
            let l = NSTextField(labelWithString: e.title ?? "")
            l.font = .systemFont(ofSize: 13)
            l.lineBreakMode = .byTruncatingTail
            let mark = NSTextField(labelWithString: e.changesSomething && !e.start ? "Δ" : "")
            mark.font = .systemFont(ofSize: 11, weight: .semibold)
            mark.textColor = .controlAccentColor
            mark.alignment = .center
            mark.toolTip = mark.stringValue.isEmpty ? nil : L("This event changes something")
            mark.translatesAutoresizingMaskIntoConstraints = false
            mark.widthAnchor.constraint(equalToConstant: 14).isActive = true
            let row = NSStackView(views: [mark, l])
            row.spacing = 2
            let cell = CenteredCell(row, leading: 4)
            cell.textField = l   // (so that the title turns light on a chosen row)
            return cell
        }
        guard connections.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let c = connections[row]
        switch id {
        case "kind":
            let l = NSTextField(labelWithString: L(c.kind.rawValue))
            l.textColor = .secondaryLabelColor
            return TopCell(l)
        case "name":
            let l = NSTextField(labelWithString: c.missing ? "(missing)" : c.name)
            if c.missing || c.warning != nil { l.textColor = .systemOrange }
            if let w = c.warning { l.toolTip = w }
            l.lineBreakMode = .byTruncatingTail
            return TopCell(l)
        case "changes":
            guard c.kind != .scene, !c.missing else { return nil }
            return ChangesButton.make(count: c.changes, row: row, target: self, action: #selector(changesPressed(_:)))
        default:
            if c.kind == .relationship {
                // What the event does to the relationship: its marker; nothing to type.
                let l = NSTextField(labelWithString: c.marker == "starts" ? L("starts here") : (c.marker == "ends" ? L("ends here") : ""))
                l.textColor = .secondaryLabelColor
                return TopCell(l)
            }
            // A field with a visible edge, so that it is plain that it can be typed in.
            let f = NSTextField(string: c.text)
            f.isBezeled = true; f.bezelStyle = .squareBezel; f.isEditable = true
            f.drawsBackground = true; f.backgroundColor = .textBackgroundColor; f.textColor = .textColor
            f.delegate = self; f.placeholderString = L("Type what happens here")
            // Long text goes on to the next line, and the row grows; ⌥Return makes a line break of its own.
            f.cell?.wraps = true; f.cell?.isScrollable = false
            f.lineBreakMode = .byWordWrapping; f.maximumNumberOfLines = 0
            return f
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView === table ? QuietRowView() : nil
    }

    /// "Remove Link" works on the chosen row, so with none chosen it is off (and does not light under the pointer).
    private func syncRemoveButton() { removeButton.isEnabled = connections.indices.contains(table.selectedRow) }
    var removeLinkEnabled: Bool { removeButton.isEnabled }
    var addLinkEnabled: Bool { addButton.isEnabled }
    /// For the checks: what the Place part of the "Add…" menu lists.
    var placeMenuItems: [(title: String, heading: Bool)] { PlaceMenu.titles(of: addButton.menu?.items.first { $0.title == L("Place") }?.submenu) }
    /// For the checks: chooses a row of the list of connections.
    func selectConnectionRow(_ row: Int?) { if let row { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) } else { table.deselectAll(nil) } }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === table { syncRemoveButton(); return }
        guard (notification.object as? NSTableView) === list else { return }
        let row = list.selectedRow
        guard row >= 0, listRows.indices.contains(row), case .event(let e) = listRows[row], e.id != selected else { return }
        commitEdits()
        selected = e.id
        showCard()
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if tableView === table { return connectionRowHeight(row) }
        guard tableView === list, listRows.indices.contains(row) else { return tableView.rowHeight }
        if case .heading = listRows[row] { return 24 }
        return 26
    }

    /// A row is as tall as its "What happens" text needs at the width of the column (at least one line).
    func connectionRowHeight(_ row: Int) -> CGFloat {
        guard connections.indices.contains(row), let column = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("text")) else { return table.rowHeight }
        let text = editingText?.row == row ? editingText!.text : connections[row].text
        guard !text.isEmpty else { return table.rowHeight }
        let width = max(column.width - 12, 40)
        let box = (text + "\u{200B}" as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)])
        return max(table.rowHeight, ceil(box.height) + 8)
    }

    func tableViewColumnDidResize(_ notification: Notification) {
        guard (notification.object as? NSTableView) === table, connections.count > 0 else { return }
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<connections.count))
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        tableView === list && listRows.indices.contains(row) && { if case .heading = listRows[row] { return true } else { return false } }()
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView === list else { return true }
        return listRows.indices.contains(row) && { if case .event = listRows[row] { return true } else { return false } }()
    }

    // MARK: Putting the events in order by hand

    /// Ordering by hand is off while the list is filtered (the rows are not the whole story then).
    private var canReorder: Bool { filterField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The events among which the chosen one is put in order: the events of its scene.
    private func sequence(containing id: String) -> [String] {
        guard let r = row(of: id) else { return [] }
        var start = r, end = r
        while start > 0, case .event = listRows[start - 1] { start -= 1 }
        while end + 1 < listRows.count, case .event = listRows[end + 1] { end += 1 }
        return listRows[start...end].compactMap { if case .event(let e) = $0 { return e.id } else { return nil } }
    }

    /// Moves the chosen event up (-1) or down (+1) among the events it is put in order with.
    func move(by delta: Int) {
        guard canReorder, let id = selected else { return }
        var ids = sequence(containing: id)
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + delta) else { NSSound.beep(); return }
        ids.swapAt(i, i + delta)
        commitEdits()
        try? events.reorder(ids)
        reload()
        onChange?()
    }

    /// For the checks: moves an event to a place among those it is put in order with (an index in that sequence).
    func moveEvent(_ id: String, toIndex target: Int) {
        var ids = sequence(containing: id)
        guard let from = ids.firstIndex(of: id) else { return }
        ids.remove(at: from)
        ids.insert(id, at: min(max(0, target), ids.count))
        try? events.reorder(ids)
        reload()
        onChange?()
    }

    /// For the checks: what each row of the list shows.
    var rowTexts: [String] { listRows.indices.map { ((list.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue) ?? "" } }

    /// For the checks: the titles in the order of the list, headings included (marked with "—").
    var listTitles: [String] { listRows.map { if case .heading(let t) = $0 { return "— " + t } else if case .event(let e) = $0 { return e.title ?? "" } else { return "" } } }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === list, canReorder, listRows.indices.contains(row), case .event(let e) = listRows[row], let id = e.id, !e.start else { return nil }
        draggedID = id
        let item = NSPasteboardItem()
        item.setString(id, forType: Self.rowType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard tableView === list, let id = draggedID ?? info.draggingPasteboard.string(forType: Self.rowType), dropAllowed(id, aboveRow: row) else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    /// May the event be dropped above this row? Only inside its scene's group (the row after the last event of the group counts): an event does not change
    /// its scene by being moved, its links decide that.
    func dropAllowed(_ id: String, aboveRow row: Int) -> Bool {
        guard canReorder, let from = self.row(of: id) else { return false }
        var start = from, end = from
        while start > 0, case .event = listRows[start - 1] { start -= 1 }
        while end + 1 < listRows.count, case .event = listRows[end + 1] { end += 1 }
        return row >= start && row <= end + 1
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard tableView === list, let id = draggedID ?? info.draggingPasteboard.string(forType: Self.rowType) else { return false }
        draggedID = nil
        return performDrop(id, aboveRow: row)
    }

    /// Puts the event where it was dropped: above this row of the list (also called directly by the checks).
    @discardableResult
    func performDrop(_ id: String, aboveRow row: Int) -> Bool {
        guard dropAllowed(id, aboveRow: row), let from = self.row(of: id) else { return false }
        // The index among the sequence: the events before the drop row, within the group.
        var ids = sequence(containing: id)
        var groupStart = from
        while groupStart > 0, case .event = listRows[groupStart - 1] { groupStart -= 1 }
        var target = row - groupStart
        if let i = ids.firstIndex(of: id) { ids.remove(at: i); if i < target { target -= 1 } }
        ids.insert(id, at: min(max(0, target), ids.count))
        selected = id
        try? events.reorder(ids)
        reload()
        onChange?()
        return true
    }

    // MARK: The card

    private func showCard() {
        guard isViewLoaded else { return }
        guard let id = selected, let e = events.event(id) else {
            cardScroll.isHidden = true
            nothing.isHidden = false
            nothing.stringValue = events.events.isEmpty ? L("No events yet. Type a title at the bottom left.") : L("Choose an event")
            return
        }
        cardScroll.isHidden = false
        nothing.isHidden = true
        titleField.stringValue = e.title ?? ""
        dateField.stringValue = e.date
        setText(descriptionView, events.text(id))
        setText(notesView, e.notes.joined(separator: "\n"))
        rebuildConnections(e)
        rebuildAddMenu()
        updatePlanRow()
        // The default event cannot be deleted or put on the plan.
        deleteButton.isHidden = e.start
        if e.start { planLabel.stringValue = L("Where the relationships that are only stated start"); planButton.isHidden = true } else { planButton.isHidden = false }
        warningLabel.stringValue = !e.start && e.changesSomething && RelationshipTimeline(events: events, sceneOrder: sceneOrder).order(of: id) == nil ? L("This event changes something but has no scene, so its changes do not apply.") : ""
        warningLabel.isHidden = warningLabel.stringValue.isEmpty
    }

    private func setText(_ tv: NSTextView, _ text: String) {
        if tv.string != text { tv.string = text }
        tv.undoManager?.removeAllActions()
    }

    func rebuildConnections(_ e: EventRecord) {
        guard e.id != nil else { return }
        var rows: [EventConnection] = []
        let sceneTitles = Dictionary(uniqueKeysWithValues: scenes().map { ($0.id, $0.title) })
        // (The default event, "Book starts", holds relationships only.)
        for scene in sceneOrder where e.links[scene] != nil && !e.start {
            rows.append(EventConnection(kind: .scene, refID: scene, name: sceneTitles[scene] ?? "", text: e.links[scene] ?? "", missing: false))
        }
        for (key, text) in e.links.sorted(by: { $0.key < $1.key }) where sceneTitles[key] == nil && !e.start {
            rows.append(EventConnection(kind: .scene, refID: key, name: "", text: text, missing: true))
        }
        for (key, text) in e.places.sorted(by: { (worlds.entry($0.key)?.name ?? "~") < (worlds.entry($1.key)?.name ?? "~") }) where !e.start {
            let entry = worlds.entry(key)
            rows.append(EventConnection(kind: .place, refID: key, name: entry?.name ?? "", text: text, missing: entry == nil, changes: e.effectCount(of: key)))
        }
        // The characters are the event's own (the links are kept in the event); in the order of their names.
        for (cid, text) in e.characters.sorted(by: { (characters.character($0.key)?.name ?? "~").localizedLowercase < (characters.character($1.key)?.name ?? "~").localizedLowercase }) where !e.start {
            let c = characters.character(cid)
            rows.append(EventConnection(kind: .character, refID: cid, name: c?.name ?? "", text: text, missing: c == nil, changes: e.effectCount(of: cid)))
        }
        // The relationships that start, change or end here.
        let timeline = RelationshipTimeline(events: events, sceneOrder: sceneOrder)
        let relationshipIDs = Set(e.relationships.keys).union(e.effects.keys.filter { relationships.relationship($0) != nil })
        let named = relationshipIDs.map { ($0, ChangesWindowController.title(of: $0, relationships, characters)) }.sorted { $0.1.localizedLowercase < $1.1.localizedLowercase }
        for (rid, title) in named {
            guard relationships.relationship(rid) != nil else { continue }
            var row = EventConnection(kind: .relationship, refID: rid, name: title, text: "", missing: false, changes: e.effectCount(of: rid), marker: e.relationships[rid] ?? "")
            if let problem = timeline.broken(rid).first { row.warning = describe(problem) }
            else if !e.start, timeline.order(of: e.id ?? "") == nil { row.warning = L("This event has no scene, so it does not apply") }
            rows.append(row)
        }
        connections = rows
        table.reloadData()
        syncRemoveButton()
    }

    /// The "Add…" menu: scenes, places and characters that are not yet connected.
    private func rebuildAddMenu() {
        guard let id = selected, let e = events.event(id) else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Add…"), action: nil, keyEquivalent: ""))
        func sub(_ title: String, items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu()
            if !items.contains(where: { $0 is ClosureMenuItem }) { let none = NSMenuItem(title: L("None left"), action: nil, keyEquivalent: ""); none.isEnabled = false; m.addItem(none) }
            else { items.forEach { m.addItem($0) } }
            parent.submenu = m
            menu.addItem(parent)
        }
        func plain(_ list: [(String, () -> Void)]) -> [NSMenuItem] { list.map { ClosureMenuItem(title: $0.0, action: $0.1) } }
        if e.start {
            menu.addItem(relationshipMenuItem(for: e))
            addButton.menu = menu
            addButton.isEnabled = true
            return
        }
        sub(L("Scene"), items: plain(scenes().filter { e.links[$0.id] == nil }.map { s in (s.title, { [weak self] in self?.addScene(s.id) }) }))
        sub(L("Place"), items: PlaceMenu.items(in: worlds, include: { e.places[$0] == nil }, choose: { [weak self] in self?.addPlace($0) }))
        sub(L("Character"), items: plain(characters.characters.filter { $0.id.map { e.characters[$0] == nil } ?? false }.map { c in (c.name ?? "", { [weak self] in self?.addCharacter(c.id ?? "") }) }))
        menu.addItem(relationshipMenuItem(for: e))
        addButton.menu = menu
        addButton.isEnabled = menu.offersAnything
    }

    private func updatePlanRow() {
        guard let id = selected else { return }
        if let plan = planStore(), let entry = plan.entry(forEvent: id), let line = plan.lines.first(where: { $0.id == entry.lane }) {
            planLabel.stringValue = L("On the plan: line “{name}”", ["name": line.name ?? ""])
            planButton.title = L("Show the Plan")
            planButton.isEnabled = true
        } else {
            planLabel.stringValue = L("Not on the plan yet")
            planButton.title = L("Put on the Plan")
            planButton.isEnabled = !(planStore()?.lines.isEmpty ?? true)
            planButton.toolTip = planButton.isEnabled ? nil : L("Make a plot line on the Plan first")
        }
        // The cards (ideas on the plan) this event realises.
        if let plan = planStore() {
            let planned = plan.plannedBy(event: id).compactMap { plan.cards[$0]?.title }
            if !planned.isEmpty { planLabel.stringValue += " · " + L("Planned by: {cards}", ["cards": planned.joined(separator: ", ")]) }
        }
    }

    // MARK: Editing the connections

    func addScene(_ id: String) {
        update { $0.links[id] = "" }
        beginTyping(.scene, id)
    }

    func addPlace(_ id: String) {
        update { $0.places[id] = "" }
        beginTyping(.place, id)
    }

    func addCharacter(_ id: String) {
        update { var l = $0.characters; if l[id] == nil { l[id] = "" }; $0.characters = l }
        beginTyping(.character, id)
    }

    private func isTextColumn(_ column: Int) -> Bool {
        table.tableColumns.indices.contains(column) && table.tableColumns[column].identifier.rawValue == "text"
    }

    /// After a connection is added, the cursor goes into its "What happens" cell: that is what the author does next.
    private func beginTyping(_ kind: EventConnection.Kind, _ id: String) {
        guard let row = connections.firstIndex(where: { $0.kind == kind && $0.refID == id }),
              let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "text" }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.editColumn(column, row: row, with: nil, select: false)
    }

    /// For the checks: is a double-click in this column of the table a click for typing?
    func doubleClickOpens(column: Int) -> Bool { !isTextColumn(column) }

    /// Takes a connection away (the row's number in the table).
    func removeConnection(row: Int) {
        guard connections.indices.contains(row), selected != nil else { return }
        let c = connections[row]
        switch c.kind {
        case .scene: update { var l = $0.links; l.removeValue(forKey: c.refID); $0.links = l }
        case .place: update { var p = $0.places; p.removeValue(forKey: c.refID); $0.places = p }
        case .character: update { var l = $0.characters; l.removeValue(forKey: c.refID); $0.characters = l }
        case .relationship:
            // A relationship must start at some event: taking the row away from the event where it starts is refused (start it in another event instead).
            guard c.marker != "starts" else { warn(L("It starts here"), L("A relationship starts at some event. Start it in another event first (right-click the row).")); return }
            update { var m = $0.relationships; m.removeValue(forKey: c.refID); $0.relationships = m; var e = $0.effects; e.removeValue(forKey: c.refID); $0.effects = e }
        }
    }

    /// What happens in the row's scene, place or character (the text only; the connection stays).
    func setConnectionText(row: Int, _ text: String) {
        guard connections.indices.contains(row), selected != nil else { return }
        let c = connections[row]
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch c.kind {
        case .scene: update(rebuild: false) { var l = $0.links; l[c.refID] = clean; $0.links = l }
        case .place: update(rebuild: false) { var p = $0.places; p[c.refID] = clean; $0.places = p }
        case .character: update(rebuild: false) { var l = $0.characters; l[c.refID] = clean; $0.characters = l }
        case .relationship: return   // (a relationship row has no text to type: its marker says what the event does)
        }
        connections[row].text = clean
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
    }

    /// For the checks: does the last column (the changes button) stay inside the visible part of the table when the pane is `width` wide?
    func changesColumnFits(paneWidth width: CGFloat) -> Bool {
        guard let scroll = table.enclosingScrollView else { return false }
        let old = scroll.frame
        scroll.setFrameSize(NSSize(width: width, height: old.height)); scroll.layoutSubtreeIfNeeded()
        defer { scroll.setFrameSize(old.size); scroll.layoutSubtreeIfNeeded() }
        guard let last = table.tableColumns.last, let index = table.tableColumns.firstIndex(of: last) else { return false }
        return table.rect(ofColumn: index).maxX <= scroll.contentView.bounds.width + 0.5
    }

    @objc private func removeLink() { removeConnection(row: table.selectedRow) }

    @objc private func openConnection() {
        let row = table.clickedRow
        // A double-click in the text column is for typing, not for going away.
        guard !isTextColumn(table.clickedColumn), connections.indices.contains(row), !connections[row].missing else { return }
        let c = connections[row]
        switch c.kind {
        case .scene: onOpenScene?(c.refID)
        case .place: onOpenPlace?(c.refID)
        case .character: onOpenCharacter?(c.refID)
        case .relationship: changeTapped(row: row)
        }
    }

    private func update(rebuild: Bool = true, _ change: @escaping (inout EventRecord) -> Void) {
        guard let id = selected else { return }
        try? events.update(id, change)
        if rebuild { refreshAfterChange() }
        onChange?()
    }

    private func refreshAfterChange() {
        let keep = selected
        reload()
        selected = keep
        showCard()
        // (A row of the list, not a place among the events: the headings of the scenes are rows too.)
        if let keep, let row = row(of: keep) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        onChange?()
    }

    // MARK: The plan

    @objc private func planPressed() { putOnPlanOrShow() }

    /// "Put on the Plan" places the event at the end of the first line; once it is there the button shows the Plan.
    func putOnPlanOrShow() {
        guard let id = selected, let plan = planStore() else { return }
        if plan.entry(forEvent: id) == nil {
            guard let line = plan.lines.first?.id else { return }
            let start = (plan.rowStarts.last ?? 0) + PlanPositions.step
            try? plan.placeEvent(id, onLine: line, start: start)
            updatePlanRow()
            onChange?()
        } else {
            onShowPlan?()
        }
    }

    /// For the checks: what the plan row says.
    var planText: String { planLabel.stringValue }

    // MARK: Text fields

    /// The cursor in a field being typed in is drawn in the text colour, so that it shows on the field's background.
    func controlTextDidBeginEditing(_ obj: Notification) {
        (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = .textColor
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === titleField {
            let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { showCard() } else { update { $0.title = title } }
        } else if field === dateField {
            let date = dateField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            update(rebuild: false) { $0.date = date }
        } else if field !== addField, field !== filterField {
            editingText = nil
            let row = table.row(for: field)
            if row >= 0 { setConnectionText(row: row, field.stringValue) }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === filterField { reload(keepingRelations: true) }
        else if let field = obj.object as? NSTextField, field !== titleField, field !== dateField, field !== addField, field !== filterField, field.isDescendant(of: table) {
            let row = table.row(for: field)
            guard row >= 0 else { return }
            editingText = (row, (field.currentEditor() as? NSTextView)?.string ?? field.stringValue)
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === addField, selector == #selector(NSResponder.insertNewline(_:)) { addEvent(titled: addField.stringValue); return true }
        // ⌥Return in a "What happens" cell: a line break (Return alone ends the typing).
        if selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), control.isDescendant(of: table) { textView.insertText("\n", replacementRange: textView.selectedRange()); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)), control === filterField || control === addField { onEscape?(); return true }
        return false
    }

    @discardableResult
    func addEvent(titled raw: String) -> String? {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let id = try? events.add(title: title) else { return nil }
        addField.stringValue = ""
        filterField.stringValue = ""
        selected = id
        reload()
        select(id)
        onChange?()
        view.window?.makeFirstResponder(dateField)
        return id
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
        if pending.contains("text") { try? events.setText(id, descriptionView.string) }
        if pending.contains("notes") {
            let lines = notesView.string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            try? events.update(id) { $0.notes = lines }
        }
        onChange?()
    }

    // MARK: Deleting

    @objc private func deletePressed() { deleteSelected(confirm: true) }

    /// Asks (Cancel is the default), then takes the event out of the book and off the plan, into the trash folder.
    func deleteSelected(confirm: Bool) {
        guard let id = selected, let e = events.event(id) else { return }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Delete the event “{title}”?", ["title": e.title ?? ""])
            alert.informativeText = L("The card and its text go to the book's trash folder (.quilland/trash), and the event leaves the plan. Characters keep their lines about it.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Delete"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        commitEdits()
        if let onDelete {
            var started = BookIntegrity.StartedRelationships.deleteThem
            if confirm, !BookIntegrity.relationshipsStarting(in: id, book: events.book).isEmpty {
                guard let choice = askAboutStartedRelationships(of: id) else { return }
                started = choice
            }
            selected = nil
            onDelete(id, started)
            return
        }
        try? planStore()?.removeEntry(forEvent: id)
        do { try events.delete(id) } catch { return }
        selected = nil
        reload()
        onChange?()
    }

    /// The relationships that start in the event need a decision: they are deleted with it, or they start in another event (the default one, "Book starts", or any).
    private func askAboutStartedRelationships(of id: String) -> BookIntegrity.StartedRelationships? {
        let count = BookIntegrity.relationshipsStarting(in: id, book: events.book).count
        let alert = NSAlert()
        alert.messageText = Lp("{n} relationship starts in this event", "{n} relationships start in this event", count)
        alert.informativeText = L("They can be deleted with the event, or start in another event instead.")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        popup.addItem(withTitle: L("Delete them with the event"))
        var targets: [String?] = [nil]
        if let start = events.startEvent, let sid = start.id, sid != id { popup.addItem(withTitle: L("Start them at “{title}”", ["title": start.title ?? ""])); targets.append(sid) }
        for e in events.ordered(sceneOrder: sceneOrder) where e.id != id {
            guard let eid = e.id else { continue }
            popup.addItem(withTitle: L("Start them at “{title}”", ["title": e.title ?? ""])); targets.append(eid)
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: L("Delete the Event"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, targets.indices.contains(popup.indexOfSelectedItem) else { return nil }
        return targets[popup.indexOfSelectedItem].map { .moveStart(to: $0) } ?? .deleteThem
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}


/// The Events list: ⌥⌘↑ and ⌥⌘↓ move the chosen event up and down.
final class EventListTable: NSTableView {
    var moveHandler: ((Int) -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .option, .shift, .control]) == [.command, .option], event.keyCode == 126 || event.keyCode == 125 {
            moveHandler?(event.keyCode == 126 ? -1 : 1)
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: Changes and relationships

extension EventsViewController {
    /// What is wrong with an order that would break, in a sentence.
    func describe(_ problem: RelationshipTimeline.Problem) -> String { problem.sentence }

    func warn(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if !CommandLine.arguments.contains("--selftest-app") { alert.runModal() }
        lastWarning = (title, text)
    }

    private var timeline: RelationshipTimeline { RelationshipTimeline(events: events, sceneOrder: scenes().map(\.id)) }

    // MARK: The changes window

    @objc func changesPressed(_ sender: NSButton) { changeTapped(row: sender.tag) }

    /// Opens the window of the changes of this event for the row's character, place or relationship (the owner keeps one window for each).
    func changeTapped(row: Int) {
        guard connections.indices.contains(row), let eid = selected else { return }
        let c = connections[row]
        switch c.kind {
        case .character: onOpenChanges?(eid, c.refID, .character)
        case .place: onOpenChanges?(eid, c.refID, .place)
        case .relationship: onOpenChanges?(eid, c.refID, .relationship)
        case .scene: return
        }
    }

    /// For the checks: the window that is open for a row.
    func changesWindow(forRow row: Int) -> ChangesWindowController? {
        guard connections.indices.contains(row), let eid = selected else { return nil }
        return changesWindowProvider?(eid, connections[row].refID)
    }

    // MARK: Relationships

    /// Has the event a place in the book (a scene), or is it the default event, which comes before everything?
    private func hasPlace(_ id: String) -> Bool { events.event(id)?.start == true || timeline.order(of: id) != nil }

    private func relationshipTitle(_ id: String) -> String { ChangesWindowController.title(of: id, relationships, characters) }

    /// "Add… ▸ Relationship": start a new one, start an existing one, change one, end one.
    func relationshipMenuItem(for e: EventRecord) -> NSMenuItem {
        let parent = NSMenuItem(title: L("Relationship"), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: L("Start a New One…")) { [weak self] in self?.startNewRelationship() })
        func list(_ title: String, _ ids: [String], _ action: @escaping (String) -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            if ids.isEmpty { let none = NSMenuItem(title: L("None left"), action: nil, keyEquivalent: ""); none.isEnabled = false; sub.addItem(none) }
            for id in ids { sub.addItem(ClosureMenuItem(title: relationshipTitle(id)) { action(id) }) }
            item.submenu = sub
            menu.addItem(item)
        }
        let all = relationships.relationships.compactMap(\.id).sorted { relationshipTitle($0).localizedLowercase < relationshipTitle($1).localizedLowercase }
        list(L("Start an Existing One…"), all.filter { e.relationships[$0] != "starts" }) { [weak self] in self?.startExisting($0) }
        if !e.start, let eid = e.id {
            let t = timeline
            let active = t.active(at: eid, among: all)
            list(L("Change One…"), active.filter { e.relationships[$0] == nil }) { [weak self] in self?.changeExisting($0) }
            list(L("End One…"), active.filter { e.relationships[$0] != "ends" && t.marks(of: $0).end == nil }) { [weak self] in self?.endExisting($0) }
        }
        parent.submenu = menu
        return parent
    }

    func startNewRelationship() {
        guard let eid = selected else { return }
        let people = characters.characters.compactMap { c in c.id.map { ($0, c.name ?? "") } }.sorted { $0.1.localizedLowercase < $1.1.localizedLowercase }
        guard people.count >= 2 else { warn(L("Two characters are needed"), L("Make the characters first.")); return }
        if !hasPlace(eid) { warn(L("This event cannot start a relationship"), describe(.noScene)); return }
        let a = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 26), pullsDown: false), b = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 26), pullsDown: false)
        for (_, name) in people { a.addItem(withTitle: name); b.addItem(withTitle: name) }
        b.selectItem(at: 1)
        let kind = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        kind.placeholderString = L("What they are to each other: “sisters”, “rivals”")
        let pair = NSStackView(views: [a, NSTextField(labelWithString: "—"), b]); pair.spacing = 8
        let stack = NSStackView(views: [pair, kind]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 330, height: 66)
        let alert = NSAlert()
        alert.messageText = L("A relationship starts here")
        alert.informativeText = L("Choose the two characters and say what they are to each other.")
        alert.accessoryView = stack
        alert.addButton(withTitle: L("Start"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = kind
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        createRelationship(between: people[a.indexOfSelectedItem].0, and: people[b.indexOfSelectedItem].0, kind: kind.stringValue)
    }

    /// Makes a relationship that starts in the chosen event. Returns its id (nil when it cannot be made).
    @discardableResult
    func createRelationship(between a: String, and b: String, kind raw: String) -> String? {
        guard let eid = selected else { return nil }
        let kind = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a != b, !kind.isEmpty else { warn(L("A relationship needs two different characters and a kind"), ""); return nil }
        guard hasPlace(eid) else { warn(L("This event cannot start a relationship"), describe(.noScene)); return nil }
        guard let rid = try? relationships.add(characters: [a, b], kind: kind) else { return nil }
        update { var m = $0.relationships; m[rid] = "starts"; $0.relationships = m }
        return rid
    }

    func startExisting(_ rel: String) {
        guard let eid = selected else { return }
        if let problem = timeline.problem(starting: rel, at: eid) { warn(L("It cannot start here"), describe(problem)); return }
        let old = timeline.marks(of: rel).start
        if let old, old != eid {
            let alert = NSAlert()
            alert.messageText = L("Move the start of “{name}” to this event?", ["name": relationshipTitle(rel)])
            alert.informativeText = L("It starts in “{event}” now.", ["event": events.event(old)?.title ?? ""])
            alert.addButton(withTitle: L("Move"))
            alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try? events.update(old) { var m = $0.relationships; m.removeValue(forKey: rel); $0.relationships = m }
        }
        update { var m = $0.relationships; m[rel] = "starts"; $0.relationships = m }
    }

    func changeExisting(_ rel: String) {
        guard let eid = selected else { return }
        if let problem = timeline.problem(changing: rel, at: eid) { warn(L("It cannot change here"), describe(problem)); return }
        update { var m = $0.relationships; if m[rel] == nil { m[rel] = "" }; $0.relationships = m }
    }

    func endExisting(_ rel: String) {
        guard let eid = selected else { return }
        if let problem = timeline.problem(ending: rel, at: eid) { warn(L("It cannot end here"), describe(problem)); return }
        update { var m = $0.relationships; m[rel] = "ends"; $0.relationships = m }
    }

    /// The start of a relationship moves to another event (refused when the order would break). Returns whether it moved.
    @discardableResult
    func moveStart(of rel: String, to event: String) -> Bool {
        if let problem = timeline.problem(starting: rel, at: event) { warn(L("It cannot start there"), describe(problem)); return false }
        if let old = timeline.marks(of: rel).start, old != event { try? events.update(old) { var m = $0.relationships; m.removeValue(forKey: rel); $0.relationships = m } }
        try? events.update(event) { var m = $0.relationships; m[rel] = "starts"; $0.relationships = m }
        refreshAfterChange()
        return true
    }

    @discardableResult
    func moveEnd(of rel: String, to event: String) -> Bool {
        if let problem = timeline.problem(ending: rel, at: event) { warn(L("It cannot end there"), describe(problem)); return false }
        if let old = timeline.marks(of: rel).end, old != event { try? events.update(old) { var m = $0.relationships; m.removeValue(forKey: rel); $0.relationships = m } }
        try? events.update(event) { var m = $0.relationships; m[rel] = "ends"; $0.relationships = m }
        refreshAfterChange()
        return true
    }

    /// Takes the end away: the relationship is not deleted, it stays active.
    func keepActive(_ rel: String) {
        for e in events.allEvents where e.relationships[rel] == "ends" {
            guard let id = e.id else { continue }
            try? events.update(id) { var m = $0.relationships; m.removeValue(forKey: rel); $0.relationships = m }
        }
        refreshAfterChange()
    }

    // MARK: The row's menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard connections.indices.contains(row), connections[row].kind == .relationship else { return }
        buildRowMenu(for: connections[row], into: menu)
    }

    func buildRowMenu(for c: EventConnection, into menu: NSMenu) {
        let rel = c.refID
        func events(_ title: String, _ action: @escaping (String) -> Void) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let t = timeline
            var list: [EventRecord] = []
            if let start = self.events.startEvent { list.append(start) }
            list += self.events.ordered(sceneOrder: scenes().map(\.id))
            for e in list {
                guard let id = e.id, id != selected else { continue }
                let entry = ClosureMenuItem(title: e.title ?? "") { action(id) }
                // (An event with no scene has no place in the book: it is greyed.)
                if t.order(of: id) == nil { entry.isEnabled = false; entry.toolTip = L("This event has no scene") }
                sub.addItem(entry)
            }
            item.submenu = sub
            menu.addItem(item)
        }
        events(L("Start It in Another Event…")) { [weak self] in self?.moveStart(of: rel, to: $0) }
        events(L("End It in Another Event…")) { [weak self] in self?.moveEnd(of: rel, to: $0) }
        if c.marker == "ends" { menu.addItem(ClosureMenuItem(title: L("Keep It Active")) { [weak self] in self?.keepActive(rel) }) }
    }

    // MARK: For the checks

    var lastWarning: (title: String, text: String)? {
        get { objc_getAssociatedObject(self, &EventsViewController.warningKey) as? (title: String, text: String) }
        set { objc_setAssociatedObject(self, &EventsViewController.warningKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    nonisolated(unsafe) private static var warningKey = 0
    var warningText: String { warningLabel.stringValue }
    var deleteHidden: Bool { deleteButton.isHidden }
    var addMenuTitles: [String] { (addButton.menu?.items ?? []).map(\.title) }
    func deltaShown(forEvent id: String) -> Bool? {
        guard let r = row(of: id), let cell = list.view(atColumn: 0, row: r, makeIfNecessary: true) else { return nil }
        func labels(_ v: NSView) -> [NSTextField] { ((v as? NSTextField).map { [$0] } ?? []) + v.subviews.flatMap(labels) }
        return labels(cell).contains { $0.stringValue == "Δ" }
    }
}

extension RelationshipTimeline.Problem {
    /// What is wrong with an order that would break, in a sentence.
    var sentence: String {
        switch self {
        case .noScene: return L("This event has no scene, so it has no place in the book.")
        case .endsBeforeStart(let t): return L("It would end before it starts (it starts in “{title}”).", ["title": t])
        case .startsAfterEnd(let t): return L("It would start after it ends (it ends in “{title}”).", ["title": t])
        case .startsAfterChange(let t): return L("It would start after a change in “{title}”.", ["title": t])
        case .endsBeforeChange(let t): return L("It would end before a change in “{title}”.", ["title": t])
        case .endsWhereItStarts: return L("It cannot end in the event where it starts.")
        }
    }
}
