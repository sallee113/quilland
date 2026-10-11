import AppKit
import WebKit
import QuillandCore

/// File ▸ Export…: one window. The profile at the top, what is included on the left, the choices on the right, the titles the book
/// will have (and, where the app can draw the file itself, a preview) below them, and the folder and Export at the bottom.
final class ExportWindowController: NSObject, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    final class Node {
        let id: String
        let title: String
        let sceneIDs: [String]
        let children: [Node]
        init(id: String, title: String, sceneIDs: [String], children: [Node]) { self.id = id; self.title = title; self.sceneIDs = sceneIDs; self.children = children }
    }

    let window: NSWindow
    let folder: URL
    private let store: ExportStore
    private var model: BookModel
    /// Called before the book is read from disk, so that the scenes being typed in are saved first.
    var prepare: () -> Void = {}
    var onClose: (() -> Void)?

    private(set) var working: ExportFile.Profile
    private var saved: ExportFile.Profile
    private(set) var excluded: Set<String> = []
    private var nodes: [Node] = []
    private(set) var chosenFolder: URL?
    private var lastExported: URL?
    private var showingPage = false

    // Controls
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let editedLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: L("Save"), target: nil, action: nil)
    private let revertButton = NSButton(title: L("Revert"), target: nil, action: nil)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let titlePagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let coverBox = NSButton(checkboxWithTitle: L("Cover"), target: nil, action: nil)
    private let tocBox = NSButton(checkboxWithTitle: L("Table of contents"), target: nil, action: nil)
    private let tocScenesBox = NSButton(checkboxWithTitle: L("with the scenes"), target: nil, action: nil)
    private let numberingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let restartBox = NSButton(checkboxWithTitle: L("Restart numbering in each part"), target: nil, action: nil)
    private let sceneBreakPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var headingPopups: [String: NSPopUpButton] = [:]
    private var headingTemplates: [String: NSTextField] = [:]
    private var headingNewPage: [String: NSButton] = [:]
    private var statusBoxes: [String: NSButton] = [:]
    private let tagsField = NSTextField()
    private let outline = Hover.rows(NSOutlineView())
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let previewSwitch = Hover.segments(NSSegmentedControl(labels: [L("Titles"), L("Page")], trackingMode: .selectOne, target: nil, action: nil))
    private let titlesView = NSTextView()
    private let titlesScroll = NSScrollView()
    private let webView = WKWebView(frame: .zero)
    private let pageNote = NSTextField(wrappingLabelWithString: "")
    private let openPreviewButton = NSButton(title: L("Preview in the Default App"), target: nil, action: nil)
    private let folderLabel = NSTextField(labelWithString: L("No folder chosen"))
    private let exportButton = NSButton(title: L("Export"), target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let resultLabel = NSTextField(labelWithString: "")
    private let finderButton = NSButton(title: L("Show in Finder"), target: nil, action: nil)
    private let openButton = NSButton(title: L("Open"), target: nil, action: nil)

    init(folder: URL) throws {
        self.folder = folder
        let profiles = ExportStore(book: folder)
        store = profiles
        model = try BookLoader.load(folder: folder)
        let start = profiles.lastProfile.flatMap { profiles.profile(named: $0) } ?? profiles.profiles[0]
        working = start
        saved = start
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Export")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 860, height: 620)
        chosenFolder = LocalBookState.load(book: folder).exportFolder.map { URL(fileURLWithPath: $0) }
        build()
        rebuildProfileMenu()
        buildNodes()
        showProfile()
        window.center()
    }

    func show() { window.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: Building the window

    private func label(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        s.alignment = .centerY
        return s
    }

    private func build() {
        // The profile bar.
        profilePopup.target = self; profilePopup.action = #selector(profileChosen)
        let newButton = NSButton(title: L("New"), target: self, action: #selector(newProfile))
        let duplicateButton = NSButton(title: L("Duplicate"), target: self, action: #selector(duplicateProfile))
        let deleteButton = NSButton(title: L("Delete"), target: self, action: #selector(deleteProfile))
        saveButton.target = self; saveButton.action = #selector(saveProfile)
        revertButton.target = self; revertButton.action = #selector(revertProfile)
        editedLabel.textColor = .systemOrange
        editedLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        let profileBar = row([label(L("Profile")), profilePopup, newButton, duplicateButton, deleteButton, editedLabel, saveButton, revertButton])

        // What is included.
        outline.addTableColumn({ let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item")); c.resizingMask = .autoresizingMask; return c }())
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.rowHeight = 22
        outline.setAccessibilityLabel(L("What is included"))
        let outlineScroll = NSScrollView()
        outlineScroll.documentView = outline
        outlineScroll.hasVerticalScroller = true
        outlineScroll.borderType = .bezelBorder
        let statusRow = row([label(L("Only scenes that are"))] + ["idea", "draft", "revised", "done"].map { name -> NSButton in
            let b = NSButton(checkboxWithTitle: name, target: self, action: #selector(controlsChanged))
            b.controlSize = .small
            statusBoxes[name] = b
            return b
        })
        statusRow.spacing = 6
        tagsField.placeholderString = L("Tags (comma separated)")
        tagsField.delegate = self
        let left = NSStackView(views: [label(L("Included")), outlineScroll, statusRow, tagsField])
        left.orientation = .vertical; left.alignment = .leading; left.spacing = 6
        outlineScroll.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        tagsField.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        left.widthAnchor.constraint(equalToConstant: 300).isActive = true

        // The choices.
        for f in ExportFormat.allCases { formatPopup.addItem(withTitle: f.label); formatPopup.lastItem?.representedObject = f.rawValue }
        formatPopup.target = self; formatPopup.action = #selector(controlsChanged)
        for (title, key) in [(L("Made from the book's data"), "auto"), (L("My own title page"), "manual"), (L("None"), "none")] { titlePagePopup.addItem(withTitle: title); titlePagePopup.lastItem?.representedObject = key }
        titlePagePopup.target = self; titlePagePopup.action = #selector(controlsChanged)
        for b in [coverBox, tocBox, tocScenesBox, restartBox] { b.target = self; b.action = #selector(controlsChanged) }
        for (title, key) in [(L("Arabic (1, 2, 3)"), "arabic"), (L("Roman (I, II, III)"), "roman")] { numberingPopup.addItem(withTitle: title); numberingPopup.lastItem?.representedObject = key }
        numberingPopup.target = self; numberingPopup.action = #selector(controlsChanged)
        for (title, key) in [(L("A mark (* * *)"), "mark"), (L("A blank line"), "blank"), (L("Nothing"), "none")] { sceneBreakPopup.addItem(withTitle: title); sceneBreakPopup.lastItem?.representedObject = key }
        sceneBreakPopup.target = self; sceneBreakPopup.action = #selector(controlsChanged)

        var headingRows: [NSView] = []
        for (level, name) in [("part", "Part"), ("chapter", "Chapter"), ("scene", "Scene")] {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            for (title, key) in [(L("None"), "none"), (L("Title"), "title"), (L("Number"), "number"), (L("Number and title"), "number_and_title")] { popup.addItem(withTitle: title); popup.lastItem?.representedObject = key }
            popup.target = self; popup.action = #selector(controlsChanged)
            let template = NSTextField()
            template.placeholderString = L("Template: Chapter {number}. {title}")
            template.delegate = self
            template.widthAnchor.constraint(equalToConstant: 230).isActive = true
            let newPage = NSButton(checkboxWithTitle: L("New page"), target: self, action: #selector(controlsChanged))
            headingPopups[level] = popup; headingTemplates[level] = template; headingNewPage[level] = newPage
            var views: [NSView] = [label(name), popup, template]
            if level != "scene" { views.append(newPage) }
            headingRows.append(row(views))
        }
        let choices = NSStackView(views: [
            label(L("Format")), row([formatPopup]),
            label(L("Front matter")), row([label(L("Title page")), titlePagePopup, coverBox, tocBox, tocScenesBox]),
            label(L("Headings (a heading typed in the text always wins)"))] + headingRows + [row([label(L("Numbers")), numberingPopup, restartBox]),
            label(L("Between scenes")), row([sceneBreakPopup])])
        choices.orientation = .vertical; choices.alignment = .leading; choices.spacing = 6

        // The preview.
        previewSwitch.selectedSegment = 0
        previewSwitch.target = self; previewSwitch.action = #selector(previewSwitched)
        titlesView.isEditable = false
        titlesView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        titlesView.textContainerInset = NSSize(width: 6, height: 6)
        titlesScroll.documentView = titlesView
        titlesScroll.hasVerticalScroller = true
        titlesScroll.borderType = .bezelBorder
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isHidden = true
        pageNote.textColor = .secondaryLabelColor
        pageNote.isHidden = true
        openPreviewButton.target = self; openPreviewButton.action = #selector(previewInApp)
        openPreviewButton.isHidden = true
        summaryLabel.textColor = .secondaryLabelColor
        let previewBox = NSView()
        for v in [titlesScroll, webView, pageNote, openPreviewButton] { v.translatesAutoresizingMaskIntoConstraints = false; previewBox.addSubview(v) }
        NSLayoutConstraint.activate([
            titlesScroll.topAnchor.constraint(equalTo: previewBox.topAnchor), titlesScroll.bottomAnchor.constraint(equalTo: previewBox.bottomAnchor),
            titlesScroll.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor), titlesScroll.trailingAnchor.constraint(equalTo: previewBox.trailingAnchor),
            webView.topAnchor.constraint(equalTo: previewBox.topAnchor), webView.bottomAnchor.constraint(equalTo: previewBox.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor), webView.trailingAnchor.constraint(equalTo: previewBox.trailingAnchor),
            pageNote.topAnchor.constraint(equalTo: previewBox.topAnchor, constant: 12), pageNote.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor, constant: 12),
            pageNote.trailingAnchor.constraint(equalTo: previewBox.trailingAnchor, constant: -12),
            openPreviewButton.topAnchor.constraint(equalTo: pageNote.bottomAnchor, constant: 10), openPreviewButton.leadingAnchor.constraint(equalTo: previewBox.leadingAnchor, constant: 12),
            previewBox.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        let right = NSStackView(views: [choices, row([label(L("The book will have")), previewSwitch]), summaryLabel, previewBox])
        right.orientation = .vertical; right.alignment = .leading; right.spacing = 8
        previewBox.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
        summaryLabel.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true

        // The bottom bar.
        let chooseButton = NSButton(title: L("Choose Folder…"), target: self, action: #selector(chooseFolder))
        exportButton.target = self; exportButton.action = #selector(exportPressed)
        exportButton.keyEquivalent = "\r"
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        finderButton.target = self; finderButton.action = #selector(showInFinder)
        openButton.target = self; openButton.action = #selector(openFile)
        finderButton.isHidden = true; openButton.isHidden = true
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        let bottom = row([chooseButton, folderLabel, NSView(), resultLabel, finderButton, openButton, spinner, exportButton])
        folderLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)

        let middle = NSStackView(views: [left, right])
        middle.orientation = .horizontal; middle.alignment = .top; middle.spacing = 18
        let root = NSStackView(views: [profileBar, middle, bottom])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        let content = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            middle.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36), bottom.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
            left.heightAnchor.constraint(equalTo: middle.heightAnchor),
        ])
        window.contentView = content
        updateFolderLabel()
    }

    // MARK: The tree of what is included

    private func buildNodes() {
        func chapter(_ c: BookModel.Chapter) -> Node {
            Node(id: c.id, title: c.title, sceneIDs: c.scenes.map(\.id), children: c.scenes.map { Node(id: $0.id, title: $0.title, sceneIDs: [$0.id], children: []) })
        }
        nodes = model.items.map { item in
            switch item {
            case .chapter(let c): return chapter(c)
            case .part(let p):
                let kids = p.chapters.map(chapter)
                return Node(id: p.id, title: p.title, sceneIDs: kids.flatMap(\.sceneIDs), children: kids)
            }
        }
        outline.reloadData()
        outline.expandItem(nil, expandChildren: false)
        for n in nodes { outline.expandItem(n) }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node)?.children.count ?? nodes.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? Node)?.children[index] ?? nodes[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Node)?.children.isEmpty ?? true) }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let n = item as? Node else { return nil }
        let box = NSButton(checkboxWithTitle: n.title.isEmpty ? "(untitled)" : n.title, target: self, action: #selector(nodeToggled(_:)))
        box.allowsMixedState = true
        let off = n.sceneIDs.filter { excluded.contains($0) }.count
        box.state = off == 0 ? .on : (off == n.sceneIDs.count ? .off : .mixed)
        box.allowsMixedState = false
        box.identifier = NSUserInterfaceItemIdentifier(n.id)
        box.controlSize = .small
        box.font = .systemFont(ofSize: 12, weight: n.children.isEmpty ? .regular : .semibold)
        return CenteredCell(box, leading: 0)
    }

    @objc private func nodeToggled(_ sender: NSButton) {
        let row = outline.row(for: sender.superview ?? sender)
        guard row >= 0, let n = outline.item(atRow: row) as? Node else { return }
        setIncluded(n.sceneIDs, sender.state != .off)
    }

    /// Ticks or unticks scenes (a chapter or a part does it for its scenes).
    func setIncluded(_ scenes: [String], _ on: Bool) {
        for s in scenes { if on { excluded.remove(s) } else { excluded.insert(s) } }
        outline.reloadData()
        refresh()
    }

    var sceneIDs: [String] { nodes.flatMap(\.sceneIDs) }

    // MARK: Profile ⇄ controls

    private func rebuildProfileMenu() {
        profilePopup.removeAllItems()
        for p in store.profiles { profilePopup.addItem(withTitle: p.name ?? "?") }
        profilePopup.selectItem(withTitle: saved.name ?? "")
    }

    private func select(_ popup: NSPopUpButton, key: String?) {
        if let i = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == key }) { popup.selectItem(at: i) }
    }

    private func key(_ popup: NSPopUpButton) -> String? { popup.selectedItem?.representedObject as? String }

    private var loading = false

    private func showProfile() {
        loading = true
        select(formatPopup, key: working.format ?? "docx")
        select(titlePagePopup, key: working.titlePage ?? "auto")
        coverBox.state = working.cover == true ? .on : .off
        tocBox.state = working.toc ?? true ? .on : .off
        tocScenesBox.state = working.tocScenes == true ? .on : .off
        select(numberingPopup, key: working.numbering ?? "arabic")
        restartBox.state = working.restartInParts == true ? .on : .off
        select(sceneBreakPopup, key: working.sceneBreak ?? "mark")
        for level in ["part", "chapter", "scene"] {
            let rule = working.headingRule(level) ?? .init(print: "none")
            select(headingPopups[level]!, key: rule.print)
            headingTemplates[level]!.stringValue = rule.template ?? ""
            headingNewPage[level]?.state = rule.newPage == true ? .on : .off
        }
        let wanted = Set(working.statuses)
        for (name, box) in statusBoxes { box.state = wanted.isEmpty || wanted.contains(name) ? .on : .off }
        tagsField.stringValue = working.tags.joined(separator: ", ")
        loading = false
        refresh()
    }

    /// Reads the controls into the working profile.
    private func readControls() {
        guard !loading else { return }
        working.format = key(formatPopup)
        working.titlePage = key(titlePagePopup)
        working.cover = coverBox.state == .on
        working.toc = tocBox.state == .on
        working.tocScenes = tocScenesBox.state == .on ? true : nil
        working.numbering = key(numberingPopup)
        working.restartInParts = restartBox.state == .on ? true : nil
        working.sceneBreak = key(sceneBreakPopup)
        for level in ["part", "chapter", "scene"] {
            let template = headingTemplates[level]!.stringValue.trimmingCharacters(in: .whitespaces)
            working.setHeadingRule(level, .init(print: key(headingPopups[level]!) ?? "none", template: template.isEmpty ? nil : template, newPage: level == "scene" ? nil : headingNewPage[level]!.state == .on))
        }
        let ticked = ["idea", "draft", "revised", "done"].filter { statusBoxes[$0]?.state == .on }
        working.setFilters(statuses: ticked.count == 4 ? [] : ticked, tags: tagsField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    @objc private func controlsChanged() { readControls(); refresh() }
    func controlTextDidChange(_ obj: Notification) { readControls(); refresh() }

    // MARK: Profiles: new, duplicate, delete, save, revert

    var isEdited: Bool { working != saved }

    @objc private func profileChosen() {
        guard let name = profilePopup.titleOfSelectedItem, name != saved.name, let next = store.profile(named: name) else { return }
        if isEdited, !confirmDiscard() { profilePopup.selectItem(withTitle: saved.name ?? ""); return }
        switchTo(next)
    }

    private func switchTo(_ profile: ExportFile.Profile) {
        working = profile
        saved = profile
        try? store.setLast(profile.name ?? "")
        showProfile()
    }

    private func confirmDiscard() -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Discard the changes to “{name}”?", ["name": saved.name ?? ""])
        alert.informativeText = L("The profile has been edited and not saved.")
        alert.addButton(withTitle: L("Cancel")).keyEquivalent = "\r"
        let go = alert.addButton(withTitle: L("Discard"))
        go.keyEquivalent = ""
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func askName(_ title: String, _ initial: String) -> String? {
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = field
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    @objc private func newProfile() {
        guard let name = askName(L("New profile"), L("My profile")), store.profile(named: name) == nil else { return }
        addProfile(ExportStore.defaultProfile(name: name))
    }

    @objc private func duplicateProfile() {
        guard let name = askName(L("Duplicate profile"), (working.name ?? "") + L(" copy")), store.profile(named: name) == nil else { return }
        var copy = working
        copy.name = name
        addProfile(copy)
    }

    func addProfile(_ profile: ExportFile.Profile) {
        try? store.save(profile)
        working = profile; saved = profile
        rebuildProfileMenu()
        showProfile()
    }

    @objc private func deleteProfile() {
        guard let name = saved.name else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Delete the profile “{name}”?", ["name": name])
        alert.addButton(withTitle: L("Cancel")).keyEquivalent = "\r"
        let go = alert.addButton(withTitle: L("Delete"))
        go.keyEquivalent = ""
        go.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        removeProfile(name)
    }

    func removeProfile(_ name: String) {
        try? store.delete(name)
        let next = store.lastProfile.flatMap { store.profile(named: $0) } ?? store.profiles[0]
        working = next; saved = next
        rebuildProfileMenu()
        showProfile()
    }

    @objc private func saveProfile() { saveCurrent() }

    func saveCurrent() {
        try? store.save(working)
        saved = working
        refresh()
    }

    @objc private func revertProfile() { revertCurrent() }

    func revertCurrent() {
        working = saved
        showProfile()
    }

    // MARK: The plan and the preview

    var options: ExportOptions {
        var o = ExportOptions(profile: working)
        o.excludedScenes = excluded
        return o
    }

    var format: ExportFormat { ExportFormat(rawValue: working.format ?? "docx") ?? .docx }

    private func refresh() {
        editedLabel.stringValue = isEdited ? "edited" : ""
        saveButton.isEnabled = isEdited
        revertButton.isEnabled = isEdited
        for level in ["part", "chapter", "scene"] {
            let print = key(headingPopups[level]!) ?? "none"
            headingTemplates[level]?.isEnabled = print == "number" || print == "number_and_title"
        }
        tocScenesBox.isEnabled = tocBox.state == .on
        restartBox.isEnabled = true
        let summary = BookExporter.summarize(model, options: options)
        var lines = ""
        for l in summary.lines {
            lines += String(repeating: "   ", count: max(0, l.level - 1)) + (l.text.isEmpty ? "(untitled)" : l.text) + (l.newPage ? "  ⤓" : "") + "\n"
        }
        titlesView.string = lines.isEmpty ? L("(no headings: the profile prints none)") : lines
        let n = { (v: Int) in NumberFormatter.localizedString(from: NSNumber(value: v), number: .decimal) }
        var text = L("{scenes}, {size}, {footnotes}.", ["scenes": Lp("{n} scene", "{n} scenes", summary.scenes), "size": Lp("{n} character||text", "{n} characters||text", summary.characters), "footnotes": Lp("{n} footnote", "{n} footnotes", summary.footnotes)])
        if summary.typedHeadings > 0 { text += " " + Lp("{n} section has a heading of its own in the text, so the profile adds none there.", "{n} sections have a heading of their own in the text, so the profile adds none there.", summary.typedHeadings) }
        summaryLabel.stringValue = text
        updatePagePreview()
    }

    var summary: ExportSummary { BookExporter.summarize(model, options: options) }
    var titlesText: String { titlesView.string }
    var summaryText: String { summaryLabel.stringValue }

    @objc private func previewSwitched() { showingPage = previewSwitch.selectedSegment == 1; updatePagePreview() }

    private func updatePagePreview() {
        titlesScroll.isHidden = showingPage
        webView.isHidden = true
        pageNote.isHidden = true
        openPreviewButton.isHidden = true
        guard showingPage else { return }
        switch format {
        case .txt:
            titlesScroll.isHidden = false
            titlesView.string = String(decoding: TxtExporter.export(model, options: options), as: UTF8.self)
        case .html, .pdf:
            webView.isHidden = false
            webView.loadHTMLString(String(decoding: HtmlExporter.export(model, options: options), as: UTF8.self), baseURL: nil)
        default:
            pageNote.isHidden = false
            openPreviewButton.isHidden = false
            pageNote.stringValue = L("The system has no faithful viewer for {format} here (Quick Look ignores page breaks and footnotes). Open the real file in its own app:", ["format": format.rawValue.uppercased()])
        }
    }

    @objc private func previewInApp() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QuillandPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(BookExporter.fileName(title: model.title, format: format))
        try? BookExporter.export(model, format: format, options: options).write(to: url, options: .atomic)
        NSWorkspace.shared.open(url)
    }

    // MARK: Exporting

    private func updateFolderLabel() {
        folderLabel.stringValue = chosenFolder.map { $0.path } ?? "No folder chosen"
        exportButton.isEnabled = chosenFolder != nil
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = chosenFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    func setFolder(_ url: URL) {
        chosenFolder = url
        var state = LocalBookState.load(book: folder)
        state.exportFolder = url.path
        state.save(book: folder)
        updateFolderLabel()
    }

    @objc private func exportPressed() {
        guard let target = chosenFolder else { return }
        // The book is read again, so that what was typed a moment ago is in the file.
        prepare()
        guard let fresh = try? BookLoader.load(folder: folder) else { resultLabel.stringValue = L("The book could not be read."); return }
        model = fresh
        spinner.startAnimation(nil)
        exportButton.isEnabled = false
        resultLabel.stringValue = L("Exporting…")
        finderButton.isHidden = true; openButton.isHidden = true
        let (book, format, options) = (model, self.format, self.options)
        if format == .pdf {
            let url = target.appendingPathComponent(BookExporter.fileName(title: book.title, format: format))
            let html = String(decoding: BookExporter.export(book, format: .pdf, options: options), as: UTF8.self)
            PDFRenderer.render(html: html, to: url, layout: options.layout) { [weak self] result in
                let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int) ?? 0
                self?.finished(url, bytes: size, result: result.map { _ in () })
            }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = BookExporter.export(book, format: format, options: options)
            let url = target.appendingPathComponent(BookExporter.fileName(title: book.title, format: format))
            let result = Result { try data.write(to: url, options: .atomic) }
            DispatchQueue.main.async { self?.finished(url, bytes: data.count, result: result) }
        }
    }

    private func finished(_ url: URL, bytes: Int, result: Result<Void, Error>) {
        spinner.stopAnimation(nil)
        exportButton.isEnabled = chosenFolder != nil
        switch result {
        case .success:
            lastExported = url
            resultLabel.stringValue = L("Exported {file} ({size})", ["file": url.lastPathComponent, "size": ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)])
            finderButton.isHidden = false; openButton.isHidden = false
        case .failure(let error):
            resultLabel.stringValue = L("Could not write the file: {error}", ["error": error.localizedDescription])
        }
    }

    /// The same without the progress, for the automatic checks: returns the file written.
    @discardableResult
    func exportNow(to target: URL) throws -> URL {
        prepare()
        model = try BookLoader.load(folder: folder)
        let data = BookExporter.export(model, format: format, options: options)
        let url = target.appendingPathComponent(BookExporter.fileName(title: model.title, format: format))
        if format == .pdf {
            _ = try PDFRenderer.renderAndWait(html: String(decoding: data, as: UTF8.self), to: url, layout: options.layout).get()
        } else {
            try data.write(to: url, options: .atomic)
        }
        lastExported = url
        return url
    }

    @objc private func showInFinder() { lastExported.map { NSWorkspace.shared.activateFileViewerSelecting([$0]) } }
    @objc private func openFile() { lastExported.map { NSWorkspace.shared.open($0) } }

    // MARK: For the checks

    func setFormat(_ f: ExportFormat) { select(formatPopup, key: f.rawValue); controlsChanged() }
    func setTOC(_ on: Bool) { tocBox.state = on ? .on : .off; controlsChanged() }
    func setTOCScenes(_ on: Bool) { tocScenesBox.state = on ? .on : .off; controlsChanged() }
    func setHeading(_ level: String, print: String, template: String? = nil, newPage: Bool? = nil) {
        select(headingPopups[level]!, key: print)
        headingTemplates[level]!.stringValue = template ?? ""
        if let newPage { headingNewPage[level]?.state = newPage ? .on : .off }
        controlsChanged()
    }
    func setStatuses(_ names: [String]) { for (n, b) in statusBoxes { b.state = names.contains(n) ? .on : .off }; controlsChanged() }
    var profileNames: [String] { profilePopup.itemArray.map(\.title) }
}
