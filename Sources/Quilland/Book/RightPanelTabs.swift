import AppKit
import QuillandCore

/// A list with a card under it, the shape of the World and Events tabs of the right panel: the things found in the scene (or all of them), and the chosen one.
class PanelListTab: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    let allBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let table = Hover.rows(NSTableView())
    let openButton = NSButton(title: "", target: nil, action: nil)
    let heading = NSTextField(labelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    let notes = NSTextView()
    var onChange: (() -> Void)?
    var onOpen: ((String) -> Void)?
    private(set) var rowIDs: [String] = []
    var selectedID: String?
    var shownScene: String?
    private var saveTimer: Timer?
    private var notesDirty = false

    init(allTitle: String, openTitle: String) {
        super.init(frame: .zero)
        allBox.title = allTitle
        allBox.controlSize = .small
        allBox.target = self; allBox.action = #selector(allChanged)
        openButton.title = openTitle
        openButton.bezelStyle = .rounded; openButton.controlSize = .small
        openButton.target = self; openButton.action = #selector(openPressed)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.rowHeight = 22
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = 240
        notes.isRichText = false; notes.allowsUndo = true
        notes.font = .systemFont(ofSize: 13)
        notes.textContainerInset = NSSize(width: 4, height: 4)
        notes.isVerticallyResizable = true
        notes.autoresizingMask = [.width]
        notes.delegate = self
        let notesScroll = NSScrollView()
        notesScroll.documentView = notes
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .bezelBorder
        notesScroll.translatesAutoresizingMaskIntoConstraints = false
        notesScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [allBox, openButton])
        row.distribution = .equalSpacing
        let caption = NSTextField(labelWithString: L("Notes"))
        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [row, scroll, heading, detail, caption, notesScroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.widthAnchor.constraint(equalTo: stack.widthAnchor), scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            notesScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // To override.
    func rows(for scene: String?, all: Bool) -> [(id: String, title: String)] { [] }
    func card(for id: String) -> (title: String, detail: String, notes: String)? { nil }
    func saveNotes(_ text: String, for id: String) {}

    func refresh(scene: String?) {
        shownScene = scene
        let list = rows(for: scene, all: allBox.state == .on)
        rowIDs = list.map(\.id)
        titles = list.map(\.title)
        table.reloadData()
        if let selected = selectedID, let row = rowIDs.firstIndex(of: selected) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else if !rowIDs.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        else { selectedID = nil }
        showCard()
    }

    private var titles: [String] = []

    @objc private func allChanged() { commitEdits(); refresh(scene: shownScene) }
    @objc private func openPressed() { if let id = selectedID { onOpen?(id) } }

    func numberOfRows(in tableView: NSTableView) -> Int { titles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: titles[row])
        cell.font = .systemFont(ofSize: 13)
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        commitEdits()
        let row = table.selectedRow
        selectedID = row >= 0 && row < rowIDs.count ? rowIDs[row] : nil
        showCard()
    }

    private func showCard() {
        let card = selectedID.flatMap { self.card(for: $0) }
        heading.stringValue = card?.title ?? ""
        detail.stringValue = card?.detail ?? ""
        notes.isEditable = card != nil
        openButton.isEnabled = card != nil
        let text = card?.notes ?? ""
        if notes.string != text { notes.string = text }
        notes.undoManager?.removeAllActions()
    }

    func textDidChange(_ notification: Notification) {
        notesDirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.commitEdits() }
    }

    func textDidEndEditing(_ notification: Notification) { commitEdits() }

    @objc func commitEdits() {
        saveTimer?.invalidate(); saveTimer = nil
        guard notesDirty, let id = selectedID else { notesDirty = false; return }
        notesDirty = false
        saveNotes(notes.string, for: id)
        onChange?()
    }
}

/// The places and things whose names are in the scene (or all of them), with the notes of the chosen one.
final class WorldTab: PanelListTab {
    var store: WorldStore!
    var sceneText: (String) -> String = { _ in "" }

    init() { super.init(allTitle: L("All places and things"), openTitle: L("Open in World")) }
    required init?(coder: NSCoder) { fatalError() }

    override func rows(for scene: String?, all: Bool) -> [(id: String, title: String)] {
        let entries = store.entries
        var shown = entries
        if !all {
            let found = scene.map { Set(ParadigmMatcher(entries: store.nameEntries).matches(in: sceneText($0)).map(\.entry)) } ?? []
            shown = entries.filter { found.contains($0.id ?? "") }
        }
        return shown.compactMap { e in e.id.flatMap { id in e.name.map { (id, $0) } } }
    }

    override func card(for id: String) -> (title: String, detail: String, notes: String)? {
        guard let e = store.entry(id) else { return nil }
        let path = store.path(of: id).joined(separator: " › ")
        let world = e.world.flatMap { store.world($0)?.name } ?? ""
        let text = store.text(id).trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = text.isEmpty ? "" : String(text.prefix(300))
        let head = [world, path].filter { !$0.isEmpty }.joined(separator: " · ") + (e.type == "place" ? "" : "  (\(L(e.type)))")
        return (e.name ?? "", [head, excerpt].filter { !$0.isEmpty }.joined(separator: "\n\n"), e.notes.joined(separator: "\n"))
    }

    override func saveNotes(_ text: String, for id: String) {
        let notes = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        try? store.updateEntry(id) { $0.notes = notes }
    }
}

/// The events linked to the scene (or all of them), with the date and notes of the chosen one.
final class EventsTab: PanelListTab {
    var store: EventStore!
    var worlds: WorldStore!
    var sceneOrder: () -> [String] = { [] }

    init() { super.init(allTitle: L("All events"), openTitle: L("Open in Events")) }
    required init?(coder: NSCoder) { fatalError() }

    override func rows(for scene: String?, all: Bool) -> [(id: String, title: String)] {
        let ordered = store.ordered(sceneOrder: sceneOrder())
        let shown = all ? ordered : ordered.filter { e in scene.map { e.links.keys.contains($0) } ?? false }
        return shown.compactMap { e in e.id.flatMap { id in e.title.map { (id, $0) } } }
    }

    override func card(for id: String) -> (title: String, detail: String, notes: String)? {
        guard let e = store.event(id) else { return nil }
        let places = e.places.keys.compactMap { worlds.entry($0)?.name }.sorted().joined(separator: ", ")
        let lines = [e.date.isEmpty ? "" : e.date, places.isEmpty ? "" : L("Places: {places}", ["places": places])].filter { !$0.isEmpty }
        return (e.title ?? "", lines.joined(separator: "\n"), e.notes.joined(separator: "\n"))
    }

    override func saveNotes(_ text: String, for id: String) {
        let notes = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        try? store.update(id) { $0.notes = notes }
    }
}
