import AppKit
import QuillandCore

/// One line of an event's connections: a scene, a place or a character, and what happens there.
struct EventConnection {
    enum Kind: String { case scene = "Scene", place = "Place", character = "Character" }
    var kind: Kind
    var refID: String
    var name: String
    var text: String
    var missing: Bool
}

/// The Events view: the events in the order of the book on the left, the card of the chosen one on the right.
final class EventsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate {
    var events: EventStore!
    var characters: CharacterStore!
    var worlds: WorldStore!
    var planStore: () -> PlanStore? = { nil }
    var scenes: () -> [(id: String, title: String)] = { [] }
    var onOpenScene: ((String) -> Void)?
    var onOpenPlace: ((String) -> Void)?
    var onOpenCharacter: ((String) -> Void)?
    var onShowPlan: (() -> Void)?
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?

    private(set) var selected: String?
    private var shown: [EventRecord] = []
    private(set) var connections: [EventConnection] = []

    let filterField = NSSearchField()
    let addField = NSTextField()
    private let list = Hover.rows(NSTableView())
    private let emptyLabel = NSTextField(labelWithString: L("Add your first event"))

    private let cardScroll = NSScrollView()
    private let card = NSStackView()
    private let nothing = NSTextField(labelWithString: "")
    let titleField = NSTextField()
    let dateField = NSTextField()
    let descriptionView = NSTextView()
    let notesView = NSTextView()
    private let table = Hover.rows(NSTableView())
    private let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeButton = NSButton(title: L("Remove Link"), target: nil, action: nil)
    private let planLabel = NSTextField(labelWithString: "")
    private let planButton = NSButton(title: "", target: nil, action: nil)
    private let deleteButton = NSButton(title: L("Delete Event…"), target: nil, action: nil)
    private var dirty: Set<String> = []
    private var saveTimer: Timer?

    // MARK: View

    override func loadView() {
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
        for v in [filterField, scroll, addField, emptyLabel] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            filterField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), filterField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            filterField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
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
        titleField.font = .systemFont(ofSize: 24, weight: .semibold)
        titleField.isBordered = false; titleField.drawsBackground = false; titleField.focusRingType = .none
        titleField.placeholderString = L("Title"); titleField.delegate = self
        titleField.setAccessibilityLabel(L("Title"))
        dateField.placeholderString = L("When (free text: “spring, year 214”, “several years later”)")
        dateField.delegate = self
        dateField.setAccessibilityLabel(L("Date"))
        descriptionView.setAccessibilityLabel(L("Description")); notesView.setAccessibilityLabel(L("Notes"))

        for (id, title, width) in [("kind", "", 80), ("name", L("Who or where"), 220), ("text", L("What happens"), 280)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width; c.minWidth = id == "text" ? 140 : 60
            table.addTableColumn(c)
        }
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
                  caption(L("Scenes, places and characters (double-click opens one)")), tableScroll, buttons, deleteButton] { card.addArrangedSubview(v) }
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

    func reload() {
        guard isViewLoaded else { return }
        let needle = filterField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        shown = events.ordered(sceneOrder: sceneOrder).filter { needle.isEmpty || ($0.title ?? "").lowercased().contains(needle) }
        list.reloadData()
        emptyLabel.isHidden = !events.events.isEmpty
        if let id = selected, let row = shown.firstIndex(where: { $0.id == id }) {
            list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if selected == nil || events.event(selected ?? "") == nil, let first = shown.first, let id = first.id {
            selected = id
            list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else if shown.isEmpty { selected = nil }
        showCard()
    }

    func select(_ id: String) {
        commitEdits()
        selected = id
        filterField.stringValue = ""
        shown = events.ordered(sceneOrder: sceneOrder)
        list.reloadData()
        if let row = shown.firstIndex(where: { $0.id == id }) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); list.scrollRowToVisible(row) }
        showCard()
    }

    var shownTitles: [String] { shown.compactMap(\.title) }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === list ? shown.count : connections.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === list {
            let e = shown[row]
            let titles = Dictionary(uniqueKeysWithValues: scenes().map { ($0.id, $0.title) })
            let firstScene = sceneOrder.first { e.links[$0] != nil }
            let s = NSMutableAttributedString(string: e.title ?? "", attributes: [.font: NSFont.systemFont(ofSize: 13)])
            let hint = firstScene.flatMap { titles[$0] } ?? L("not in a scene yet")
            s.append(NSAttributedString(string: "\n" + hint, attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.secondaryLabelColor]))
            let l = NSTextField(labelWithAttributedString: s)
            l.lineBreakMode = .byTruncatingTail
            return CenteredCell(l)
        }
        guard connections.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let c = connections[row]
        switch id {
        case "kind":
            let l = NSTextField(labelWithString: c.kind.rawValue)
            l.textColor = .secondaryLabelColor
            return l
        case "name":
            let l = NSTextField(labelWithString: c.missing ? "(missing)" : c.name)
            if c.missing { l.textColor = .systemOrange }
            return l
        default:
            // A field with a visible edge, so that it is plain that it can be typed in.
            let f = NSTextField(string: c.text)
            f.isBezeled = true; f.bezelStyle = .squareBezel; f.isEditable = true
            f.drawsBackground = true; f.backgroundColor = .textBackgroundColor; f.textColor = .textColor
            f.delegate = self; f.placeholderString = L("Type what happens here")
            return f
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView === table ? QuietRowView() : nil
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === list else { return }
        let row = list.selectedRow
        guard row >= 0, shown.indices.contains(row), shown[row].id != selected else { return }
        commitEdits()
        selected = shown[row].id
        showCard()
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
    }

    private func setText(_ tv: NSTextView, _ text: String) {
        if tv.string != text { tv.string = text }
        tv.undoManager?.removeAllActions()
    }

    func rebuildConnections(_ e: EventRecord) {
        guard let id = e.id else { return }
        var rows: [EventConnection] = []
        let sceneTitles = Dictionary(uniqueKeysWithValues: scenes().map { ($0.id, $0.title) })
        for scene in sceneOrder where e.links[scene] != nil {
            rows.append(EventConnection(kind: .scene, refID: scene, name: sceneTitles[scene] ?? "", text: e.links[scene] ?? "", missing: false))
        }
        for (key, text) in e.links.sorted(by: { $0.key < $1.key }) where sceneTitles[key] == nil {
            rows.append(EventConnection(kind: .scene, refID: key, name: "", text: text, missing: true))
        }
        for (key, text) in e.places.sorted(by: { (worlds.entry($0.key)?.name ?? "~") < (worlds.entry($1.key)?.name ?? "~") }) {
            let entry = worlds.entry(key)
            rows.append(EventConnection(kind: .place, refID: key, name: entry?.name ?? "", text: text, missing: entry == nil))
        }
        for c in characters.characters {
            if let cid = c.id, let text = c.links[id] { rows.append(EventConnection(kind: .character, refID: cid, name: c.name ?? "", text: text, missing: false)) }
        }
        connections = rows
        table.reloadData()
    }

    /// The "Add…" menu: scenes, places and characters that are not yet connected.
    private func rebuildAddMenu() {
        guard let id = selected, let e = events.event(id) else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Add…"), action: nil, keyEquivalent: ""))
        func sub(_ title: String, _ items: [(String, () -> Void)]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu()
            if items.isEmpty { let none = NSMenuItem(title: L("None left"), action: nil, keyEquivalent: ""); none.isEnabled = false; m.addItem(none) }
            for (t, a) in items { m.addItem(ClosureMenuItem(title: t, action: a)) }
            parent.submenu = m
            menu.addItem(parent)
        }
        sub(L("Scene"), scenes().filter { e.links[$0.id] == nil }.map { s in (s.title, { [weak self] in self?.addScene(s.id) }) })
        sub(L("Place"), worlds.entries.filter { $0.id.map { e.places[$0] == nil } ?? false }.map { p in (worlds.path(of: p.id ?? "").dropFirst().joined(separator: " › "), { [weak self] in self?.addPlace(p.id ?? "") }) })
        sub(L("Character"), characters.characters.filter { $0.links[id] == nil }.map { c in (c.name ?? "", { [weak self] in self?.addCharacter(c.id ?? "") }) })
        addButton.menu = menu
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
        guard let event = selected else { return }
        try? characters.update(id) { var l = $0.links; l[event] = ""; $0.links = l }
        refreshAfterChange()
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
        guard connections.indices.contains(row), let event = selected else { return }
        let c = connections[row]
        switch c.kind {
        case .scene: update { var l = $0.links; l.removeValue(forKey: c.refID); $0.links = l }
        case .place: update { var p = $0.places; p.removeValue(forKey: c.refID); $0.places = p }
        case .character:
            try? characters.update(c.refID) { var l = $0.links; l.removeValue(forKey: event); $0.links = l }
            refreshAfterChange()
        }
    }

    /// What happens in the row's scene, place or character (the text only; the connection stays).
    func setConnectionText(row: Int, _ text: String) {
        guard connections.indices.contains(row), let event = selected else { return }
        let c = connections[row]
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch c.kind {
        case .scene: update(rebuild: false) { var l = $0.links; l[c.refID] = clean; $0.links = l }
        case .place: update(rebuild: false) { var p = $0.places; p[c.refID] = clean; $0.places = p }
        case .character:
            try? characters.update(c.refID) { var l = $0.links; l[event] = clean; $0.links = l }
            onChange?()
        }
        connections[row].text = clean
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
        if let keep, let row = shown.firstIndex(where: { $0.id == keep }) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
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
            let row = table.row(for: field)
            if row >= 0 { setConnectionText(row: row, field.stringValue) }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === filterField { reload() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === addField, selector == #selector(NSResponder.insertNewline(_:)) { addEvent(titled: addField.stringValue); return true }
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

    func commitEdits() {
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
        try? planStore()?.removeEntry(forEvent: id)
        do { try events.delete(id) } catch { return }
        selected = nil
        reload()
        onChange?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
