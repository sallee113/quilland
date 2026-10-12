import AppKit
import QuillandCore

/// File ▸ Import…: one window with three parts, top to bottom. The file and its encoding; the analysis (the kinds of lines that could be
/// titles, what each becomes, and beside it the tree that results); where it goes.
final class ImportWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    final class Node {
        let title: String
        let size: Int
        let children: [Node]
        init(_ title: String, _ size: Int, _ children: [Node] = []) { self.title = title; self.size = size; self.children = children }
    }

    let window: NSWindow
    /// The open book's name and the way to import into it (nil when no book is open); the new book is made by `intoNewBook`.
    var openBookName: String?
    var intoOpenBook: ((ImportPlan) -> Bool)?
    var intoNewBook: ((ImportPlan, String, String) -> Bool)?
    var language = "en"
    var onClose: (() -> Void)?

    private(set) var raw: String?
    private(set) var source = ImportSource.text
    private(set) var options = ImportOptions()
    private(set) var kinds: [TitleKind] = []
    private(set) var plan = ImportPlan()
    private var data: Data?
    private var tree: [Node] = []

    private let pathLabel = NSTextField(labelWithString: L("No file chosen"))
    private let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let kindsTable = Hover.rows(NSTableView())
    private let splitBox = NSButton(checkboxWithTitle: L("Split a chapter into scenes at the scene breaks"), target: nil, action: nil)
    private let joinBox = NSButton(checkboxWithTitle: L("Join wrapped lines into paragraphs"), target: nil, action: nil)
    private let outline = Hover.rows(NSOutlineView())
    private let summaryLabel = NSTextField(labelWithString: "")
    private let openRadio = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
    private let newRadio = NSButton(radioButtonWithTitle: L("Into a new book called"), target: nil, action: nil)
    private let titleField = NSTextField()
    private let importButton = NSButton(title: L("Import"), target: nil, action: nil)
    private let resultLabel = NSTextField(labelWithString: "")

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Import")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 860, height: 560)
        build()
        window.center()
    }

    func show() { window.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: Building

    private func caption(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func build() {
        // 1. The file.
        let chooseButton = NSButton(title: L("Choose File…"), target: self, action: #selector(chooseFile))
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.textColor = .secondaryLabelColor
        for e in ImportEncoding.allCases { encodingPopup.addItem(withTitle: e.label); encodingPopup.lastItem?.representedObject = e.rawValue }
        encodingPopup.target = self; encodingPopup.action = #selector(encodingChanged)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.font = .systemFont(ofSize: 11)
        let fileRow = NSStackView(views: [chooseButton, pathLabel, caption(L("Encoding")), encodingPopup])
        fileRow.spacing = 10

        // 2. The analysis and the preview.
        for (id, title, width) in [("kind", L("Kind of line"), 190), ("count", L("Count"), 52), ("examples", L("Examples"), 230), ("role", L("Becomes"), 120)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width; c.minWidth = 40
            kindsTable.addTableColumn(c)
        }
        kindsTable.dataSource = self; kindsTable.delegate = self
        kindsTable.rowHeight = 26
        kindsTable.setAccessibilityLabel(L("Kinds of lines that could be titles"))
        let kindsScroll = NSScrollView()
        kindsScroll.documentView = kindsTable
        kindsScroll.hasVerticalScroller = true; kindsScroll.borderType = .bezelBorder
        kindsScroll.heightAnchor.constraint(equalToConstant: 250).isActive = true
        for b in [splitBox, joinBox] { b.target = self; b.action = #selector(optionsChanged) }
        splitBox.state = .on
        let left = NSStackView(views: [caption(L("The kinds of lines that could be titles")), kindsScroll, splitBox, joinBox])
        left.orientation = .vertical; left.alignment = .leading; left.spacing = 6
        kindsScroll.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self; outline.delegate = self
        outline.rowHeight = 20
        outline.setAccessibilityLabel(L("The book that will be made"))
        let outlineScroll = NSScrollView()
        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true; outlineScroll.borderType = .bezelBorder
        summaryLabel.textColor = .secondaryLabelColor
        let right = NSStackView(views: [caption(L("What will be made")), outlineScroll, summaryLabel])
        right.orientation = .vertical; right.alignment = .leading; right.spacing = 6
        outlineScroll.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        outlineScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        let middle = NSStackView(views: [left, right])
        middle.orientation = .horizontal; middle.alignment = .top; middle.spacing = 18; middle.distribution = .fillEqually

        // 3. Where it goes.
        openRadio.target = self; openRadio.action = #selector(destinationChanged)
        newRadio.target = self; newRadio.action = #selector(destinationChanged)
        titleField.placeholderString = L("Title of the new book")
        titleField.delegate = self
        titleField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        importButton.target = self; importButton.action = #selector(importPressed)
        importButton.keyEquivalent = "\r"
        importButton.isEnabled = false
        let destination = NSStackView(views: [openRadio, newRadio, titleField, NSView(), resultLabel, importButton])
        destination.spacing = 10

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        let noteRow = NSStackView(views: [spinner, noteLabel])
        noteRow.spacing = 6
        let root = NSStackView(views: [caption(L("1. The file")), fileRow, noteRow, caption(L("2. The analysis")), middle, caption(L("3. Where it goes")), destination])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        root.setCustomSpacing(14, after: noteRow)
        root.setCustomSpacing(14, after: middle)
        let content = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            middle.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36), destination.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
            fileRow.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
        ])
        window.contentView = content
        applyDestinationChoices()
    }

    /// Call after `openBookName` and the closures are set.
    func applyDestinationChoices() {
        if let name = openBookName {
            openRadio.title = L("Into the open book “{name}”, at the end", ["name": name])
            openRadio.isEnabled = true
            openRadio.state = .on
            newRadio.state = .off
        } else {
            openRadio.title = L("Into the open book (no book is open)")
            openRadio.isEnabled = false
            openRadio.state = .off
            newRadio.state = .on
        }
        updateEnabled()
    }

    // MARK: Reading the file

    @objc private func chooseFile() {
        // A sheet on the window, and no filter by type: the Open button of a filtered dialog did nothing for some files (a double click worked). A file that is not text
        // is told about when it is read.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            self?.loadFile(url)
        }
    }

    func loadFile(_ url: URL) {
        let bytes: Data
        do { bytes = try Data(contentsOf: url) } catch {
            // Said loudly: a small grey note is easy to miss.
            noteLabel.stringValue = L("The file could not be read.")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("The file could not be read.")
            alert.informativeText = (error as NSError).localizedDescription
            alert.beginSheetModal(for: window)
            return
        }
        data = bytes
        pathLabel.stringValue = url.path
        source = ImportSource.guess(extension: url.pathExtension)
        if titleField.stringValue.isEmpty { titleField.stringValue = url.deletingPathExtension().lastPathComponent }
        decodeAndAnalyze(preferred: .utf8)
    }

    private var encoding: ImportEncoding { ImportEncoding(rawValue: encodingPopup.selectedItem?.representedObject as? String ?? "") ?? .utf8 }

    @objc private func encodingChanged() { decodeAndAnalyze(preferred: encoding) }

    private func decodeAndAnalyze(preferred: ImportEncoding) {
        guard let data else { return }
        var used = preferred
        var text = TextImporter.decode(data, encoding: preferred)
        var note = ""
        if text == nil {
            // Not valid in the chosen encoding: the other one is tried, and the author is told.
            used = preferred == .utf8 ? .windows1251 : .utf8
            text = TextImporter.decode(data, encoding: used)
            note = L("The bytes are not valid {from}; read as {to}. Choose the encoding if the letters are wrong.", ["from": preferred.label, "to": used.label])
        }
        encodingPopup.selectItem(at: ImportEncoding.allCases.firstIndex(of: used) ?? 0)
        guard let text else { raw = nil; noteLabel.stringValue = L("The file could not be read in either encoding."); return }
        loadText(text, source: source)
        noteLabel.stringValue = note.isEmpty ? "\(source.rawValue.capitalized) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))" : note
    }

    /// The text to import (also the way the automatic checks and "paste" give it).
    func loadText(_ text: String, source: ImportSource) {
        raw = text
        self.source = source
        reanalyze()
    }

    // MARK: Analysis

    /// A text longer than this is read in the background, with the window saying so, instead of freezing it.
    private static let backgroundSize = 300_000
    private var generation = 0
    private let spinner = NSProgressIndicator()

    private func setBusy(_ busy: Bool) {
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        spinner.isHidden = !busy
        if busy { importButton.isEnabled = false }
    }

    private func reanalyze() {
        guard let raw else { return }
        options.splitAtSceneBreaks = splitBox.state == .on
        options.joinWrappedLines = joinBox.state == .on
        options.language = language
        if raw.utf8.count > Self.backgroundSize { reanalyzeInBackground(raw); return }
        let analysis = TextImporter.analyze(raw, source: source, joinWrappedLines: options.joinWrappedLines)
        apply(analysis: analysis)
        replan(analysis: analysis)
    }

    private func reanalyzeInBackground(_ raw: String) {
        generation += 1
        let mine = generation, source = self.source, options = self.options
        setBusy(true)
        summaryLabel.stringValue = L("Reading…")
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> ((kinds: [TitleKind], suggestedTitle: String?), ImportPlan) in
                let analysis = TextImporter.analyze(raw, source: source, joinWrappedLines: options.joinWrappedLines)
                var used = options
                used.roles = options.roles.filter { key, _ in analysis.kinds.contains { $0.id == key } }
                return (analysis, TextImporter.plan(raw, source: source, options: used, analysis: analysis))
            }.value
            guard let self, mine == self.generation else { return }
            self.apply(analysis: result.0)
            self.show(plan: result.1)
            self.setBusy(false)
            self.updateEnabled()
        }
    }

    private func apply(analysis: (kinds: [TitleKind], suggestedTitle: String?)) {
        kinds = analysis.kinds
        options.roles = options.roles.filter { key, _ in kinds.contains { $0.id == key } }
        if let title = analysis.suggestedTitle, titleField.stringValue.isEmpty || titleField.stringValue == pendingSuggestion { titleField.stringValue = title; pendingSuggestion = title }
        kindsTable.reloadData()
    }

    private var pendingSuggestion = ""

    private func replan(analysis: (kinds: [TitleKind], suggestedTitle: String?)? = nil) {
        guard let raw else { return }
        show(plan: TextImporter.plan(raw, source: source, options: options, analysis: analysis))
    }

    private func show(plan newPlan: ImportPlan) {
        plan = newPlan
        func scene(_ s: ImportPlan.Scene) -> Node { Node(s.title, s.characters) }
        func chapter(_ c: ImportPlan.Chapter) -> Node { Node(c.title, c.characters, c.scenes.map(scene)) }
        tree = plan.items.map { item in
            switch item {
            case .chapter(let c): return chapter(c)
            case .part(let p): return Node(p.title, p.characters, p.chapters.map(chapter))
            }
        }
        outline.reloadData()
        for n in tree { outline.expandItem(n); n.children.forEach { outline.expandItem($0) } }
        let n = { (v: Int) in NumberFormatter.localizedString(from: NSNumber(value: v), number: .decimal) }
        summaryLabel.stringValue = L("{parts}, {chapters}, {scenes}, {size}", ["parts": Lp("{n} part", "{n} parts", plan.partCount), "chapters": Lp("{n} chapter", "{n} chapters", plan.chapterCount), "scenes": Lp("{n} scene", "{n} scenes", plan.sceneCount), "size": Lp("{n} character||text", "{n} characters||text", plan.characters)])
        updateEnabled()
    }

    @objc private func optionsChanged() { reanalyze() }

    var summaryText: String { summaryLabel.stringValue }
    var treeTitles: [String] {
        var out: [String] = []
        func walk(_ n: Node, _ depth: Int) { out.append(String(repeating: "  ", count: depth) + n.title); n.children.forEach { walk($0, depth + 1) } }
        tree.forEach { walk($0, 0) }
        return out
    }

    /// The role a kind has now (the author's choice or its default).
    func role(of kind: String) -> ImportRole { options.roles[kind] ?? kinds.first { $0.id == kind }?.defaultRole ?? .none }

    func setRole(_ kind: String, _ role: ImportRole) {
        options.roles[kind] = role
        kindsTable.reloadData()
        if let raw, raw.utf8.count > Self.backgroundSize { reanalyzeInBackground(raw) } else { replan() }
    }

    func setOptions(split: Bool? = nil, join: Bool? = nil) {
        if let split { splitBox.state = split ? .on : .off }
        if let join { joinBox.state = join ? .on : .off }
        reanalyze()
    }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int { kinds.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard kinds.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let k = kinds[row]
        switch id {
        case "kind": return CenteredCell(NSTextField(labelWithString: k.label))
        case "count":
            let l = NSTextField(labelWithString: String(k.count)); l.alignment = .right; return l
        case "examples":
            let l = NSTextField(labelWithString: k.examples.map { "“\($0.prefix(28))”" }.joined(separator: "  "))
            l.textColor = .secondaryLabelColor; l.lineBreakMode = .byTruncatingTail
            return l
        default:
            if k.isBreak { let l = NSTextField(labelWithString: L("Scene break")); l.textColor = .secondaryLabelColor; return l }
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            for r in ImportRole.allCases { popup.addItem(withTitle: r.label); popup.lastItem?.representedObject = r.rawValue }
            popup.selectItem(at: ImportRole.allCases.firstIndex(of: role(of: k.id)) ?? 0)
            popup.controlSize = .small
            popup.identifier = NSUserInterfaceItemIdentifier(k.id)
            popup.target = self; popup.action = #selector(roleChosen(_:))
            return popup
        }
    }

    @objc private func roleChosen(_ sender: NSPopUpButton) {
        guard let kind = sender.identifier?.rawValue, let raw = sender.selectedItem?.representedObject as? String, let role = ImportRole(rawValue: raw) else { return }
        setRole(kind, role)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? tree.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? Node)?.children[index] ?? tree[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Node)?.children.isEmpty ?? true) }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? Node else { return nil }
        let size = NumberFormatter.localizedString(from: NSNumber(value: n.size), number: .decimal)
        let s = NSMutableAttributedString(string: n.title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: n.children.isEmpty ? .regular : .semibold)])
        s.append(NSAttributedString(string: "   \(size)", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        let l = NSTextField(labelWithAttributedString: s)
        l.lineBreakMode = .byTruncatingTail
        return CenteredCell(l, leading: 0)
    }

    // MARK: Where it goes

    @objc private func destinationChanged() { updateEnabled() }

    var importsIntoOpenBook: Bool { openRadio.state == .on && openBookName != nil }

    func chooseDestination(openBook: Bool) {
        openRadio.state = openBook ? .on : .off
        newRadio.state = openBook ? .off : .on
        updateEnabled()
    }

    func setNewBookTitle(_ t: String) { titleField.stringValue = t; updateEnabled() }

    func controlTextDidChange(_ obj: Notification) { updateEnabled() }

    private func updateEnabled() {
        titleField.isEnabled = !importsIntoOpenBook
        let titled = !titleField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        importButton.isEnabled = plan.sceneCount > 0 && (importsIntoOpenBook || titled)
    }

    @objc private func importPressed() { _ = performImport() }

    /// Does the import; returns whether it went through.
    @discardableResult
    func performImport() -> Bool {
        guard plan.sceneCount > 0 else { return false }
        let ok: Bool
        if importsIntoOpenBook { ok = intoOpenBook?(plan) ?? false }
        else { ok = intoNewBook?(plan, titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), language) ?? false }
        resultLabel.stringValue = ok ? Lp("Imported {n} scene.", "Imported {n} scenes.", plan.sceneCount) : L("The import could not be done.")
        if ok { window.close() }
        return ok
    }

    var importEnabled: Bool { importButton.isEnabled }
}
