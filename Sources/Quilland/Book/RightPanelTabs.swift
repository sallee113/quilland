import AppKit
import QuillandCore

/// A list with a card under it, the shape of the World and Events tabs of the right panel: the things found in the scene (or all of them), and the chosen one.
class PanelListTab: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    let allBox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let table = Hover.rows(NSTableView())
    let openButton = NSButton(title: "", target: nil, action: nil)
    let sceneLinkButton = NSButton(title: "", target: nil, action: nil)
    private var sceneLinkRun: (() -> Void)?
    let heading = NSTextField(labelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    let notes = NSTextView()
    var onChange: (() -> Void)?
    var onOpen: ((String) -> Void)?
    /// The column of the tab; a subclass can put one more row at its top.
    let stack = NSStackView()
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
        sceneLinkButton.bezelStyle = .rounded; sceneLinkButton.controlSize = .small
        sceneLinkButton.target = self; sceneLinkButton.action = #selector(sceneLinkPressed)
        sceneLinkButton.isHidden = true
        let row = NSStackView(views: [allBox, openButton])
        row.distribution = .equalSpacing
        let caption = NSTextField(labelWithString: L("Notes"))
        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = .secondaryLabelColor
        stack.setViews([row, scroll, sceneLinkButton, heading, detail, caption, notesScroll], in: .leading)
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
    /// For a subclass: a button that links the chosen row to the scene, or takes the link away (nil: none for this row).
    func sceneLink(for id: String, scene: String) -> (title: String, run: () -> Void)? { nil }

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
        updateSceneLink()
        cardShown()
    }

    private func updateSceneLink() {
        if let id = selectedID, let scene = shownScene, let link = sceneLink(for: id, scene: scene) {
            sceneLinkButton.title = link.title
            sceneLinkRun = link.run
            sceneLinkButton.isHidden = false
        } else {
            sceneLinkRun = nil
            sceneLinkButton.isHidden = true
        }
    }

    @objc private func sceneLinkPressed() {
        sceneLinkRun?()
        refresh(scene: shownScene)
        onChange?()
    }

    /// For the checks: the title of the button under the list, or nil when there is none.
    var sceneLinkTitle: String? { sceneLinkButton.isHidden ? nil : sceneLinkButton.title }

    /// For a subclass: the card of the chosen row has just been filled in.
    func cardShown() {}

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
            let found = scene.map { SceneMembers.places(inScene: $0, text: sceneText($0), store: store) } ?? []
            shown = entries.filter { found.contains($0.id ?? "") }
        }
        return shown.compactMap { e in e.id.flatMap { id in e.name.map { (id, $0) } } }
    }

    override func sceneLink(for id: String, scene: String) -> (title: String, run: () -> Void)? {
        guard let e = store.entry(id), !SceneMembers.named(entries: store.nameEntries, in: sceneText(scene)).contains(id) else { return nil }
        if e.links[scene] != nil {
            return (L("Remove from This Scene"), { [store] in try? store?.updateEntry(id) { var l = $0.links; l.removeValue(forKey: scene); $0.links = l } })
        }
        return (L("Add to This Scene"), { [store] in try? store?.updateEntry(id) { var l = $0.links; if l[scene] == nil { l[scene] = "" }; $0.links = l } })
    }

    override func card(for id: String) -> (title: String, detail: String, notes: String)? {
        guard let e = store.entry(id) else { return nil }
        let path = store.path(of: id).joined(separator: " › ")
        let world = e.world.flatMap { store.world($0)?.name } ?? ""
        let text = store.text(id).trimmingCharacters(in: .whitespacesAndNewlines)
        let excerpt = text.isEmpty ? "" : String(text.prefix(300))
        let head = [world, path].filter { !$0.isEmpty }.joined(separator: " · ")
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

/// The research documents linked to the scene (or all of them): the source and the file of the chosen one, and its typed text, which can be changed here.
final class ResearchTab: PanelListTab {
    var store: ResearchStore!

    init() { super.init(allTitle: L("All research"), openTitle: L("Open in Research")); buildAddRow(); buildFileLink() }
    required init?(coder: NSCoder) { fatalError() }

    override func rows(for scene: String?, all: Bool) -> [(id: String, title: String)] {
        let shown = all ? store.ordered : (scene.map { store.linked(to: $0) } ?? [])
        return shown.compactMap { r in r.id.flatMap { id in r.title.map { (id, $0) } } }
    }

    override func card(for id: String) -> (title: String, detail: String, notes: String)? {
        guard let r = store.document(id) else { return nil }
        var lines: [String] = []
        if !r.source.isEmpty { lines.append(r.source) }
        if let remark = shownScene.flatMap({ r.links[$0] }), !remark.isEmpty { lines.append(remark) }
        return (r.title ?? "", lines.joined(separator: "\n"), store.text(id))
    }

    override func saveNotes(_ text: String, for id: String) { try? store.setText(id, text) }

    // MARK: The short way to add

    /// Type a title and press Return: a document, linked to the scene shown, is made and its text is ready to type in.
    let addField = NSTextField()
    private let fileButton = NSButton(title: L("From a File…"), target: nil, action: nil)

    private func buildAddRow() {
        addField.placeholderString = L("Add a note — type a title, press Return")
        addField.setAccessibilityLabel(L("Add a note"))
        addField.target = self; addField.action = #selector(addPressed)
        fileButton.target = self; fileButton.action = #selector(fromFilePressed)
        fileButton.bezelStyle = .rounded; fileButton.controlSize = .small
        fileButton.toolTip = L("Makes a document from a file: it is copied into the book, or linked if it is over 20 MB")
        let line = NSStackView(views: [addField, fileButton])
        line.spacing = 6
        stack.insertArrangedSubview(line, at: 0)
        line.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: The file as a link

    /// The file's name, as a link: a click opens it in the program the system uses for that kind of file.
    let fileLink = NSButton(title: "", target: nil, action: nil)

    private func buildFileLink() {
        fileLink.isBordered = false
        fileLink.alignment = .left
        fileLink.target = self; fileLink.action = #selector(openFile)
        fileLink.setAccessibilityRole(.link)
        fileLink.lineBreakMode = .byTruncatingMiddle
        fileLink.isHidden = true
        let at = (stack.arrangedSubviews.firstIndex(of: detail) ?? 3) + 1
        stack.insertArrangedSubview(fileLink, at: at)
        fileLink.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    override func cardShown() {
        guard let id = selectedID, let file = store.document(id)?.file else { fileLink.isHidden = true; return }
        let missing = store.fileState(id) == .missing
        let title = missing ? L("{name} — the file is missing", ["name": file.name]) : file.name
        fileLink.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: missing ? NSColor.systemOrange : NSColor.linkColor,
            .underlineStyle: missing ? 0 : NSUnderlineStyle.single.rawValue,
        ])
        fileLink.isEnabled = !missing
        fileLink.toolTip = missing ? L("The file is not where it was") : L("Open in the program the system uses for this kind of file")
        fileLink.isHidden = false
    }

    /// For the checks: what opening does.
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    @objc func openFile() {
        guard let id = selectedID, store.fileState(id) == .present, let url = store.fileURL(id) else { return }
        openURL(url)
    }

    @objc private func addPressed() { addDocument(titled: addField.stringValue) }

    /// Makes the document and links it to the scene shown; returns its id.
    @discardableResult
    func addDocument(titled raw: String, file: URL? = nil) -> String? {
        let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let id = try? store.add(title: title) else { return nil }
        if let scene = shownScene { try? store.update(id) { $0.links[scene] = "" } }
        if let file { try? store.attach(id, file: file, embed: ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int ?? 0) <= ResearchStore.embedWarningBytes) }
        addField.stringValue = ""
        selectedID = id
        if shownScene == nil { allBox.state = .on }
        refresh(scene: shownScene)
        onChange?()
        if file == nil { window?.makeFirstResponder(notes) }
        return id
    }

    @objc private func fromFilePressed() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addDocument(titled: url.deletingPathExtension().lastPathComponent, file: url)
    }
}
