import AppKit
import QuillandCore

/// One line of a document's links: the book, a scene, a character, a place or an event, and a remark.
struct ResearchLink {
    enum Kind: String { case book = "Book", scene = "Scene", character = "Character", place = "Place", event = "Event" }
    var kind: Kind
    var refID: String
    var name: String
    var text: String
    var missing: Bool
}

/// The Research view: the documents on the left (a file, typed text, or both), the card of the chosen one on the right.
final class ResearchViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextViewDelegate {
    var research: ResearchStore!
    var characters: CharacterStore!
    var worlds: WorldStore!
    var events: EventStore!
    var bookID: () -> String? = { nil }
    var scenes: () -> [(id: String, title: String)] = { [] }
    var onOpenScene: ((String) -> Void)?
    var onOpenPlace: ((String) -> Void)?
    var onOpenCharacter: ((String) -> Void)?
    var onOpenEvent: ((String) -> Void)?
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?
    /// For the checks: a large file is only embedded after a question; this answers it.
    var confirmLargeEmbed: (String) -> Bool = { name in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Copy “{name}” into the book?", ["name": name])
        alert.informativeText = L("The file is large. Git keeps every version of a file in the book, so the book's history grows with it. You can link to the file where it is instead.")
        alert.addButton(withTitle: L("Cancel")).keyEquivalent = "\r"
        let go = alert.addButton(withTitle: L("Copy Anyway"))
        go.keyEquivalent = ""
        return alert.runModal() == .alertSecondButtonReturn
    }

    private(set) var selected: String?
    private var shown: [ResearchRecord] = []
    private(set) var links: [ResearchLink] = []

    let filterField = NSSearchField()
    let addField = NSTextField()
    private let list = Hover.rows(NSTableView())
    private let emptyLabel = NSTextField(labelWithString: L("Add your first research document"))

    private let cardScroll = NSScrollView()
    private let card = NSStackView()
    private let nothing = NSTextField(labelWithString: "")
    let titleField = NSTextField()
    let sourceField = NSTextField()
    let textView = NSTextView()
    private let fileLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: L("Copy a File into the Book…"), target: nil, action: nil)
    private let linkFileButton = NSButton(title: L("Link to a File…"), target: nil, action: nil)
    private let openButton = NSButton(title: L("Open"), target: nil, action: nil)
    private let revealButton = NSButton(title: L("Show in Finder"), target: nil, action: nil)
    private let takeOffButton = NSButton(title: L("Take the File Off"), target: nil, action: nil)
    private let table = Hover.rows(NSTableView())
    private let addButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let removeButton = NSButton(title: L("Remove Link"), target: nil, action: nil)
    private let deleteButton = NSButton(title: L("Delete Document…"), target: nil, action: nil)
    private var dirty = false
    private var saveTimer: Timer?

    // MARK: View

    override func loadView() {
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "QuillandResearch"
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
        addField.placeholderString = L("Add a document — type a title, press Return")
        addField.delegate = self
        addField.setAccessibilityLabel(L("Add a document"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        list.addTableColumn(column)
        list.headerView = nil
        list.dataSource = self
        list.delegate = self
        list.rowHeight = 36
        list.style = .sourceList
        list.setAccessibilityLabel(L("Research"))
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

    private final class FlippedView: NSView { override var isFlipped: Bool { true } }

    private func buildCard() -> NSView {
        let root = NSView()
        titleField.font = .systemFont(ofSize: 24, weight: .semibold)
        titleField.isBordered = false; titleField.drawsBackground = false; titleField.focusRingType = .none
        titleField.placeholderString = L("Title"); titleField.delegate = self
        titleField.setAccessibilityLabel(L("Title"))
        sourceField.placeholderString = L("Where it comes from (a book, an article, an address)")
        sourceField.delegate = self
        sourceField.setAccessibilityLabel(L("Source"))

        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        for (b, action) in [(copyButton, #selector(copyFilePressed)), (linkFileButton, #selector(linkFilePressed)), (openButton, #selector(openFilePressed)),
                            (revealButton, #selector(revealFilePressed)), (takeOffButton, #selector(takeOffPressed))] {
            b.target = self; b.action = action; b.controlSize = .small; b.bezelStyle = .rounded
        }
        let fileButtons = NSStackView(views: [copyButton, linkFileButton, openButton, revealButton, takeOffButton])
        fileButtons.spacing = 8

        textView.setAccessibilityLabel(L("Text"))
        textView.isRichText = false; textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = self
        let textBox = NSScrollView()
        textBox.documentView = textView; textBox.hasVerticalScroller = true; textBox.borderType = .bezelBorder
        textBox.translatesAutoresizingMaskIntoConstraints = false
        textBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        for (id, title, width) in [("kind", "", 80), ("name", L("What it is about"), 220), ("text", L("Remark"), 280)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width; c.minWidth = id == "text" ? 140 : 60
            table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self
        table.rowHeight = 22
        table.target = self; table.doubleAction = #selector(openLink)
        table.setAccessibilityLabel(L("Links"))
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true; tableScroll.borderType = .bezelBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        addButton.controlSize = .small
        removeButton.target = self; removeButton.action = #selector(removeLinkPressed)
        removeButton.controlSize = .small; removeButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.spacing = 8
        deleteButton.target = self; deleteButton.action = #selector(deletePressed)
        deleteButton.bezelStyle = .rounded

        for v in [titleField, sourceField, caption(L("File")), fileLabel, fileButtons, caption(L("Text")), textBox,
                  caption(L("Linked to (double-click opens one)")), tableScroll, buttons, deleteButton] { card.addArrangedSubview(v) }
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
            titleField.widthAnchor.constraint(equalTo: card.widthAnchor), sourceField.widthAnchor.constraint(equalTo: card.widthAnchor),
            fileLabel.widthAnchor.constraint(equalTo: card.widthAnchor), textBox.widthAnchor.constraint(equalTo: card.widthAnchor),
            tableScroll.widthAnchor.constraint(equalTo: card.widthAnchor),
            nothing.centerXAnchor.constraint(equalTo: root.centerXAnchor), nothing.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    // MARK: The list

    func reload() {
        guard isViewLoaded else { return }
        shown = research.matching(filterField.stringValue)
        list.reloadData()
        emptyLabel.isHidden = !research.documents.isEmpty
        if let id = selected, let row = shown.firstIndex(where: { $0.id == id }) {
            list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if selected == nil || research.document(selected ?? "") == nil, let first = shown.first, let id = first.id {
            selected = id
            list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else if shown.isEmpty { selected = nil }
        showCard()
    }

    // MARK: Where it was left (kept for the book)

    /// The chosen document, the place in the list and the filter.
    var memory: ViewMemory { ViewMemory(selected: selected, scroll: Double(list.scrolledBy), filter: filterField.stringValue) }

    /// Puts the view back as it was left.
    func restore(_ m: ViewMemory?) {
        guard let m else { return }
        filterField.stringValue = m.filter
        if let id = m.selected, research.document(id) != nil { selected = id }
        reload()
        list.restoreScroll(m.scroll)
    }

    func select(_ id: String) {
        commitEdits()
        selected = id
        filterField.stringValue = ""
        shown = research.ordered
        list.reloadData()
        if let row = shown.firstIndex(where: { $0.id == id }) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); list.scrollRowToVisible(row) }
        showCard()
    }

    var shownTitles: [String] { shown.compactMap(\.title) }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === list ? shown.count : links.count }

    private func hint(_ r: ResearchRecord) -> String {
        if !r.source.isEmpty { return r.source }
        if let name = r.file?.name { return name }
        let first = research.text(r.id ?? "").split(separator: "\n").first.map(String.init) ?? ""
        return first.isEmpty ? L("empty") : first
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === list {
            let r = shown[row]
            let s = NSMutableAttributedString(string: r.title ?? "", attributes: [.font: NSFont.systemFont(ofSize: 13)])
            s.append(NSAttributedString(string: "\n" + hint(r), attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.secondaryLabelColor]))
            let l = NSTextField(labelWithAttributedString: s)
            l.lineBreakMode = .byTruncatingTail
            return CenteredCell(l)
        }
        guard links.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let c = links[row]
        switch id {
        case "kind":
            let l = NSTextField(labelWithString: L(c.kind.rawValue))
            l.textColor = .secondaryLabelColor
            return l
        case "name":
            let l = NSTextField(labelWithString: c.missing ? L("(missing)") : c.name)
            if c.missing { l.textColor = .systemOrange }
            return l
        default:
            let f = NSTextField(string: c.text)
            f.isBezeled = true; f.bezelStyle = .squareBezel; f.isEditable = true
            f.drawsBackground = true; f.backgroundColor = .textBackgroundColor; f.textColor = .textColor
            f.delegate = self; f.placeholderString = L("Type a remark")
            return f
        }
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView === table ? QuietRowView() : nil
    }

    /// "Remove Link" works on the chosen row, so with none chosen it is off (and does not light under the pointer).
    private func syncRemoveButton() { removeButton.isEnabled = links.indices.contains(table.selectedRow) }
    var removeLinkEnabled: Bool { removeButton.isEnabled }
    var addLinkEnabled: Bool { addButton.isEnabled }
    /// For the checks: what the Place part of the "Link to…" menu lists.
    var placeMenuItems: [(title: String, heading: Bool)] { PlaceMenu.titles(of: addButton.menu?.items.first { $0.title == L("Place") }?.submenu) }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === table { syncRemoveButton(); return }
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
        guard let id = selected, let r = research.document(id) else {
            cardScroll.isHidden = true
            nothing.isHidden = false
            nothing.stringValue = research.documents.isEmpty ? L("No research yet. Type a title at the bottom left.") : L("Choose a document")
            return
        }
        cardScroll.isHidden = false
        nothing.isHidden = true
        titleField.stringValue = r.title ?? ""
        sourceField.stringValue = r.source
        let body = research.text(id)
        if textView.string != body { textView.string = body }
        textView.undoManager?.removeAllActions()
        showFile(id)
        rebuildLinks(r)
        rebuildAddMenu()
    }

    /// What the file row says now (for the checks too).
    var fileText: String { fileLabel.stringValue }

    private func showFile(_ id: String) {
        let state = research.fileState(id)
        let file = research.document(id)?.file
        switch state {
        case .none:
            fileLabel.stringValue = L("No file. The text below is the whole document.")
            fileLabel.textColor = .secondaryLabelColor
        case .present, .missing:
            let size = ByteCountFormatter.string(fromByteCount: Int64(file?.size ?? 0), countStyle: .file)
            let where_ = file?.embedded == true ? L("copied into the book") : (file?.path ?? "")
            fileLabel.stringValue = state == .missing ? L("{name} — the file is missing from {where}", ["name": file?.name ?? "", "where": where_])
                                                      : L("{name} · {size} · {where}", ["name": file?.name ?? "", "size": size, "where": where_])
            fileLabel.textColor = state == .missing ? .systemOrange : .labelColor
        }
        openButton.isEnabled = state == .present
        revealButton.isEnabled = state == .present
        takeOffButton.isHidden = state == .none
        copyButton.title = state == .none ? L("Copy a File into the Book…") : L("Replace by a Copy…")
        linkFileButton.title = state == .none ? L("Link to a File…") : L("Replace by a Link…")
    }

    func rebuildLinks(_ r: ResearchRecord) {
        var rows: [ResearchLink] = []
        let scenesByID = Dictionary(uniqueKeysWithValues: scenes().map { ($0.id, $0.title) })
        let book = bookID()
        func kind(_ key: String) -> (ResearchLink.Kind, String)? {
            if key == book { return (.book, L("The whole book")) }
            if let t = scenesByID[key] { return (.scene, t) }
            if let c = characters.characters.first(where: { $0.id == key }) { return (.character, c.name ?? "") }
            if worlds.entry(key) != nil { return (.place, worlds.path(of: key).dropFirst().joined(separator: " › ")) }
            if let e = events.event(key) { return (.event, e.title ?? "") }
            return nil
        }
        let order = ["Book": 0, "Scene": 1, "Character": 2, "Place": 3, "Event": 4]
        let sceneOrder = scenes().map(\.id)
        for (key, text) in r.links {
            if let (k, name) = kind(key) { rows.append(ResearchLink(kind: k, refID: key, name: name, text: text, missing: false)) }
            else { rows.append(ResearchLink(kind: .scene, refID: key, name: "", text: text, missing: true)) }
        }
        rows.sort { a, b in
            if a.missing != b.missing { return !a.missing }
            if a.kind != b.kind { return order[a.kind.rawValue]! < order[b.kind.rawValue]! }
            if a.kind == .scene { return (sceneOrder.firstIndex(of: a.refID) ?? 0) < (sceneOrder.firstIndex(of: b.refID) ?? 0) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        links = rows
        table.reloadData()
        syncRemoveButton()
    }

    /// The "Add…" menu: what is not yet linked.
    private func rebuildAddMenu() {
        guard let id = selected, let r = research.document(id) else { return }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Link to…"), action: nil, keyEquivalent: ""))
        if let book = bookID(), r.links[book] == nil {
            menu.addItem(ClosureMenuItem(title: L("The whole book")) { [weak self] in self?.addLink(book) })
        }
        func sub(_ title: String, items: [NSMenuItem]) {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu()
            if !items.contains(where: { $0 is ClosureMenuItem }) { let none = NSMenuItem(title: L("None left"), action: nil, keyEquivalent: ""); none.isEnabled = false; m.addItem(none) }
            else { items.forEach { m.addItem($0) } }
            parent.submenu = m
            menu.addItem(parent)
        }
        func plain(_ list: [(String, () -> Void)]) -> [NSMenuItem] { list.map { ClosureMenuItem(title: $0.0, action: $0.1) } }
        sub(L("Scene"), items: plain(scenes().filter { r.links[$0.id] == nil }.map { s in (s.title, { [weak self] in self?.addLink(s.id) }) }))
        sub(L("Character"), items: plain(characters.characters.filter { $0.id.map { r.links[$0] == nil } ?? false }.map { c in (c.name ?? "", { [weak self] in self?.addLink(c.id ?? "") }) }))
        sub(L("Place"), items: PlaceMenu.items(in: worlds, include: { r.links[$0] == nil }, choose: { [weak self] in self?.addLink($0) }))
        sub(L("Event"), items: plain(events.events.filter { $0.id.map { r.links[$0] == nil } ?? false }.map { e in (e.title ?? "", { [weak self] in self?.addLink(e.id ?? "") }) }))
        addButton.menu = menu
        addButton.isEnabled = menu.offersAnything
    }

    // MARK: Links

    func addLink(_ target: String) {
        update { var l = $0.links; l[target] = ""; $0.links = l }
        guard let row = links.firstIndex(where: { $0.refID == target }),
              let column = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "text" }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.editColumn(column, row: row, with: nil, select: false)
    }

    private func isTextColumn(_ column: Int) -> Bool {
        table.tableColumns.indices.contains(column) && table.tableColumns[column].identifier.rawValue == "text"
    }

    func removeLink(row: Int) {
        guard links.indices.contains(row) else { return }
        let key = links[row].refID
        update { var l = $0.links; l.removeValue(forKey: key); $0.links = l }
    }

    func setLinkText(row: Int, _ text: String) {
        guard links.indices.contains(row) else { return }
        let key = links[row].refID, clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        update(rebuild: false) { var l = $0.links; l[key] = clean; $0.links = l }
        links[row].text = clean
    }

    @objc private func removeLinkPressed() { removeLink(row: table.selectedRow) }

    @objc private func openLink() {
        let row = table.clickedRow
        guard !isTextColumn(table.clickedColumn), links.indices.contains(row), !links[row].missing else { return }
        let c = links[row]
        switch c.kind {
        case .book: break
        case .scene: onOpenScene?(c.refID)
        case .character: onOpenCharacter?(c.refID)
        case .place: onOpenPlace?(c.refID)
        case .event: onOpenEvent?(c.refID)
        }
    }

    private func update(rebuild: Bool = true, _ change: @escaping (inout ResearchRecord) -> Void) {
        guard let id = selected else { return }
        try? research.update(id, change)
        if rebuild { refreshAfterChange() }
        onChange?()
    }

    private func refreshAfterChange() {
        commitEdits()   // the card is drawn again from the files: what was typed must be in them first
        let keep = selected
        reload()
        selected = keep
        showCard()
        if let keep, let row = shown.firstIndex(where: { $0.id == keep }) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        onChange?()
    }

    // MARK: The file

    /// Gives the chosen document a file. A copy over `embedWarningBytes` is first asked about. Returns whether the file was taken.
    @discardableResult
    func attachFile(_ url: URL, embed: Bool) -> Bool {
        guard let id = selected else { return false }
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
        if embed, size > ResearchStore.embedWarningBytes, !confirmLargeEmbed(url.lastPathComponent) { return false }
        do { try research.attach(id, file: url, embed: embed) } catch {
            let alert = NSAlert()
            alert.messageText = L("The file could not be added")
            alert.informativeText = "\(error)"
            alert.runModal()
            return false
        }
        refreshAfterChange()
        return true
    }

    private func chooseFile(embed: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.prompt = embed ? L("Copy") : L("Link")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        attachFile(url, embed: embed)
    }

    @objc private func copyFilePressed() { chooseFile(embed: true) }
    @objc private func linkFilePressed() { chooseFile(embed: false) }

    @objc private func openFilePressed() {
        guard let id = selected, let url = research.fileURL(id) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealFilePressed() {
        guard let id = selected, let url = research.fileURL(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func takeOffPressed() { takeFileOff() }

    /// The document keeps its text; a copy that was in the book goes to the trash folder, a file left where it was is not touched.
    func takeFileOff() {
        guard let id = selected else { return }
        try? research.detachFile(id)
        refreshAfterChange()
    }

    // MARK: Text fields

    func controlTextDidBeginEditing(_ obj: Notification) {
        (obj.userInfo?["NSFieldEditor"] as? NSTextView)?.insertionPointColor = .textColor
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === titleField {
            let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { showCard() } else { update { $0.title = title } }
        } else if field === sourceField {
            let source = sourceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            update { $0.source = source }
        } else if field !== addField, field !== filterField {
            let row = table.row(for: field)
            if row >= 0 { setLinkText(row: row, field.stringValue) }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === filterField { reload() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === addField, selector == #selector(NSResponder.insertNewline(_:)) { addDocument(titled: addField.stringValue); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)), control === filterField || control === addField { onEscape?(); return true }
        return false
    }

    @discardableResult
    func addDocument(titled raw: String) -> String? {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let id = try? research.add(title: title) else { return nil }
        addField.stringValue = ""
        filterField.stringValue = ""
        selected = id
        reload()
        select(id)
        onChange?()
        view.window?.makeFirstResponder(sourceField)
        return id
    }

    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === textView else { return }
        dirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.commitEdits() }
    }

    func textDidEndEditing(_ notification: Notification) { commitEdits() }

    @objc func commitEdits() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard dirty, let id = selected else { dirty = false; return }
        dirty = false
        try? research.setText(id, textView.string)
        onChange?()
    }

    // MARK: Deleting

    @objc private func deletePressed() { deleteSelected(confirm: true) }

    func deleteSelected(confirm: Bool) {
        guard let id = selected, let r = research.document(id) else { return }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Delete the document “{title}”?", ["title": r.title ?? ""])
            alert.informativeText = L("The document, its text and the copy of its file go to the book's trash folder (.quilland/trash). A file you only linked to is not touched.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Delete"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        dirty = false
        saveTimer?.invalidate()
        do { try research.delete(id) } catch { return }
        selected = nil
        reload()
        onChange?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}
