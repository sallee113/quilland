import AppKit
import QuillandCore

/// The bottom panel: Search (read-only, neutral) and Replace (its own tinted look; it changes the book).
final class SearchPanelController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    enum Mode: Int { case search, replace, proofread, looseEnds, suggestions }

    weak var main: MainAreaController?
    var onClose: (() -> Void)?
    private(set) var mode: Mode = .search
    private(set) var hits: [SearchHit] = []
    private(set) var ticked: Set<UUID> = []
    private var groups: [(title: String, hits: [SearchHit])] = []
    private var undoRecords: [ReplaceRecord]?
    private var currentIndex: Int?

    let findField = NSSearchField()
    let replaceField = NSTextField()
    private let modeControl = NSSegmentedControl(labels: [L("Search"), L("Replace"), L("Proofreading"), L("Loose Ends"), L("Suggestions")], trackingMode: .selectOne, target: nil, action: nil)
    private let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var optionBoxes: [NSButton] = []
    private var sourceBoxes: [SearchSource: NSButton] = [:]
    private let header = NSView()
    private let headerLabel = NSTextField(labelWithString: L("Replace — this changes your book"))
    private let summary = NSTextField(labelWithString: "")
    private let outline = NSOutlineView()
    private let checkAll = NSButton(title: L("Check All"), target: nil, action: nil)
    let replaceButton = NSButton(title: L("Replace 0 checked"), target: nil, action: nil)
    private let banner = NSTextField(labelWithString: "")
    private let undoButton = NSButton(title: L("Undo Replace"), target: nil, action: nil)
    private let footer = NSStackView()
    private let replaceRow = NSStackView()
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    let proofView = ProofreadingView()
    let looseView = LooseEndsView()
    let suggestView = SuggestionsView()
    private var optionsRow = NSStackView()
    private var resultsScroll = NSScrollView()

    // MARK: View

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 260))
        view = root
        modeControl.selectedSegment = 0
        modeControl.target = self; modeControl.action = #selector(modeChanged)
        proofView.onBusyChanged = { [weak self] busy in self?.markBusy(2, L("Proofreading"), busy) }
        suggestView.onBusyChanged = { [weak self] busy in self?.markBusy(4, L("Suggestions"), busy) }
        findField.placeholderString = L("Find")
        findField.delegate = self
        findField.sendsSearchStringImmediately = true
        replaceField.delegate = self
        replaceField.setAccessibilityLabel(L("Replacement"))
        closeButton.isBordered = false
        closeButton.target = self; closeButton.action = #selector(close)
        closeButton.toolTip = L("Close (Esc)")
        for s in SearchScope.allCases { scopePopup.addItem(withTitle: s.title) }
        scopePopup.selectItem(at: SearchScope.book.rawValue)
        scopePopup.target = self; scopePopup.action = #selector(queryChanged)
        for title in [L("Match case"), L("Whole words"), L("Word endings"), "ё = е"] {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(queryChanged))
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            optionBoxes.append(b)
        }
        optionBoxes[3].state = .on
        for source in SearchSource.allCases {
            let b = NSButton(checkboxWithTitle: L(source.rawValue), target: self, action: #selector(queryChanged))
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.state = source == .text ? .on : .off
            sourceBoxes[source] = b
        }

        let top = NSStackView(views: [modeControl, findField, replaceField, closeButton])
        top.spacing = 8
        let options = NSStackView(views: [label(L("Where")), scopePopup] + optionBoxes + [label(L("In")), sourceBoxes[.text]!, sourceBoxes[.synopsis]!, sourceBoxes[.note]!])
        options.spacing = 10
        options.alignment = .centerY
        optionsRow = options

        header.wantsLayer = true
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .systemOrange
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerLabel)
        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12), headerLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(equalToConstant: 22),
        ])

        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hit"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.dataSource = self
        outline.delegate = self
        outline.indentationPerLevel = 12
        outline.rowSizeStyle = .small
        outline.target = self
        outline.action = #selector(rowClicked)
        outline.setAccessibilityLabel(L("Results"))
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        resultsScroll = scroll

        checkAll.target = self; checkAll.action = #selector(checkAllPressed); checkAll.controlSize = .small
        replaceButton.target = self; replaceButton.action = #selector(replacePressed)
        replaceButton.bezelStyle = .rounded
        replaceButton.keyEquivalent = ""
        replaceButton.isEnabled = false
        replaceButton.hasDestructiveAction = true
        banner.font = .systemFont(ofSize: 11)
        undoButton.target = self; undoButton.action = #selector(undoPressed); undoButton.controlSize = .small
        undoButton.isHidden = true
        replaceRow.setViews([checkAll, replaceButton, banner, undoButton])
        replaceRow.spacing = 10
        replaceRow.alignment = .centerY

        let stack = NSStackView(views: [top, options, header, summary, scroll, replaceRow, proofView, looseView, suggestView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            top.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -10),
            header.leadingAnchor.constraint(equalTo: stack.leadingAnchor), header.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 10), scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -10),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70),
            proofView.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 10), proofView.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -10),
            looseView.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 10), looseView.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -10),
            suggestView.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 10), suggestView.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -10),
        ])
        findField.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        replaceField.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        applyMode()
    }

    private func label(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    // MARK: Modes

    /// A tab whose work goes on in the background says so in its name, so that it shows when another tab is open.
    private func markBusy(_ segment: Int, _ title: String, _ busy: Bool) {
        guard isViewLoaded else { return }
        modeControl.setLabel(busy ? title + " ⟳" : title, forSegment: segment)
    }

    /// Switches between Search and Replace. Entering Replace forgets the sources and the scope: they are chosen each time.
    func setMode(_ new: Mode) {
        _ = view
        let entering = new == .replace && mode != .replace
        mode = new
        modeControl.selectedSegment = new.rawValue
        if entering { resetReplaceChoices() }
        applyMode()
        if new == .suggestions { suggestView.main = main } else if new == .looseEnds { looseView.main = main; looseView.refresh() } else if new == .proofread { proofView.main = main; if !proofView.isWatching { proofView.watchTyping() }; proofView.refresh() } else { queryChanged() }
    }

    private func resetReplaceChoices() {
        for (source, box) in sourceBoxes { box.state = source == .text ? .on : .off }
        scopePopup.selectItem(at: SearchScope.scene.rawValue)
        replaceField.stringValue = ""
        ticked = []
        banner.stringValue = ""
        undoButton.isHidden = true
        undoRecords = nil
    }

    @objc private func modeChanged() { setMode(Mode(rawValue: modeControl.selectedSegment) ?? .search) }

    private func applyMode() {
        let replacing = mode == .replace, proofreading = mode == .proofread || mode == .looseEnds || mode == .suggestions
        replaceField.isHidden = !replacing
        header.isHidden = !replacing
        replaceRow.isHidden = !replacing
        findField.isHidden = proofreading
        optionsRow.isHidden = proofreading
        summary.isHidden = proofreading
        resultsScroll.isHidden = proofreading
        proofView.isHidden = mode != .proofread
        looseView.isHidden = mode != .looseEnds
        suggestView.isHidden = mode != .suggestions
        header.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.16).cgColor
        view.layer?.backgroundColor = replacing ? NSColor.systemOrange.withAlphaComponent(0.05).cgColor : nil
        view.wantsLayer = true
        updateReplacePlaceholder()
    }

    private func updateReplacePlaceholder() {
        let empty = replaceField.stringValue.isEmpty
        replaceField.placeholderAttributedString = NSAttributedString(
            string: L("(nothing — the matches will be deleted)"), attributes: [.foregroundColor: NSColor.systemOrange])
        replaceField.toolTip = empty ? L("Empty: the matches will be deleted") : nil
    }

    func focusFind() {
        view.window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
    }

    func prefill(_ text: String) {
        guard !text.isEmpty, !text.contains("\n") else { return }
        findField.stringValue = text
    }

    @objc private func close() { onClose?() }

    // MARK: The query

    /// For the checks and for opening with a given choice.
    func setChoices(scope: SearchScope? = nil, sources: Set<SearchSource>? = nil, matchCase: Bool? = nil, wholeWords: Bool? = nil, endings: Bool? = nil) {
        _ = view
        if let scope { scopePopup.selectItem(at: scope.rawValue) }
        if let sources { for (s, b) in sourceBoxes { b.state = sources.contains(s) ? .on : .off } }
        if let matchCase { optionBoxes[0].state = matchCase ? .on : .off }
        if let wholeWords { optionBoxes[1].state = wholeWords ? .on : .off }
        if let endings { optionBoxes[2].state = endings ? .on : .off }
        queryChanged()
    }

    var currentQuery: SearchQuery {
        var q = SearchQuery()
        q.text = findField.stringValue
        q.scope = SearchScope(rawValue: scopePopup.indexOfSelectedItem) ?? .book
        q.options = SearchOptions(matchCase: optionBoxes[0].state == .on, wholeWords: optionBoxes[1].state == .on, endings: optionBoxes[2].state == .on, yoAsYe: optionBoxes[3].state == .on)
        q.sources = Set(sourceBoxes.filter { $0.value.state == .on }.map(\.key))
        return q
    }

    /// The query, the replacement, the scope or an option changed: the results are made again and the ticks cleared.
    @objc func queryChanged() {
        guard isViewLoaded, mode == .search || mode == .replace else { return }
        updateReplacePlaceholder()
        ticked = []
        hits = main?.search(currentQuery) ?? []
        currentIndex = nil
        var order: [String] = []
        var map: [String: [SearchHit]] = [:]
        for hit in hits {
            let key = hit.groupTitle + "\u{1}" + hit.source.rawValue
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(hit)
        }
        groups = order.map { key in
            let h = map[key]!
            let source = h[0].source == .text ? "" : "  (\(L(h[0].source.rawValue).lowercased()))"
            return (h[0].groupTitle + source, h)
        }
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        updateSummary()
    }

    private func scopeSentence() -> String {
        let q = currentQuery
        let sources = SearchSource.allCases.filter { q.sources.contains($0) }.map { L($0.rawValue).lowercased() }.joined(separator: L(" and "))
        let owners = Set(hits.map(\.owner)).count
        let counts = hits.isEmpty ? (q.text.isEmpty ? "" : L("nothing found")) : L("{places} in {sections}", ["places": Lp("{n} place", "{n} places", hits.count), "sections": Lp("{n} section", "{n} sections", owners)])
        return "\(q.scope.title) · \(sources.isEmpty ? L("no sources") : sources): \(counts)"
    }

    private func updateSummary() {
        if mode == .replace {
            summary.stringValue = scopeSentence()
        } else {
            let owners = Set(hits.map(\.owner)).count
            summary.stringValue = hits.isEmpty ? (findField.stringValue.isEmpty ? "" : L("Nothing found")) : L("{places} in {sections}", ["places": Lp("{n} place", "{n} places", hits.count), "sections": Lp("{n} section", "{n} sections", owners)])
        }
        let n = ticked.count
        let deleting = replaceField.stringValue.isEmpty
        replaceButton.title = deleting ? L("Delete {n} checked", ["n": n]) : L("Replace {n} checked", ["n": n])
        replaceButton.isEnabled = n > 0
        checkAll.title = n == hits.count && n > 0 ? L("Uncheck All") : "Check All"
        checkAll.isEnabled = !hits.isEmpty
    }

    // MARK: Results

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return groups.count }
        if let g = item as? GroupBox { return g.hits.count }
        return 0
    }

    private final class GroupBox { let title: String; let hits: [SearchHit]; init(_ t: String, _ h: [SearchHit]) { title = t; hits = h } }
    private final class HitBox { let hit: SearchHit; init(_ h: SearchHit) { hit = h } }
    private var boxes: [GroupBox] = []
    private var hitBoxes: [UUID: HitBox] = [:]

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            if index == 0 { boxes = groups.map { GroupBox($0.title, $0.hits) }; hitBoxes = [:] }
            return boxes[index]
        }
        let g = item as! GroupBox
        let hit = g.hits[index]
        let box = hitBoxes[hit.id] ?? HitBox(hit)
        hitBoxes[hit.id] = box
        return box
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is GroupBox }
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { item is GroupBox }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let g = item as? GroupBox {
            let l = NSTextField(labelWithString: "\(g.title)  ·  \(g.hits.count)")
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return l
        }
        guard let box = item as? HitBox else { return nil }
        let cell = HitCell()
        cell.configure(box.hit, replacement: mode == .replace ? replaceField.stringValue : nil, checkable: mode == .replace, checked: ticked.contains(box.hit.id))
        cell.onToggle = { [weak self] on in
            if on { self?.ticked.insert(box.hit.id) } else { self?.ticked.remove(box.hit.id) }
            self?.updateSummary()
        }
        return cell
    }

    @objc private func rowClicked() {
        let row = outline.clickedRow
        guard row >= 0, let box = outline.item(atRow: row) as? HitBox else { return }
        if let i = hits.firstIndex(where: { $0.id == box.hit.id }) { currentIndex = i }
        jump(to: box.hit)
    }

    private func jump(to hit: SearchHit) {
        if hit.source == .text { main?.reveal(scene: hit.owner, range: hit.range) } else { main?.revealSection(hit.owner) }
    }

    /// ⌘G and ⇧⌘G (and Return in the fields): to the next or the previous result.
    func step(_ by: Int) {
        guard !hits.isEmpty else { return }
        let next = currentIndex.map { ($0 + by + hits.count) % hits.count } ?? (by > 0 ? 0 : hits.count - 1)
        currentIndex = next
        let hit = hits[next]
        // Show the row too.
        for row in 0..<outline.numberOfRows { if let b = outline.item(atRow: row) as? HitBox, b.hit.id == hit.id { outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false); outline.scrollRowToVisible(row) } }
        jump(to: hit)
    }

    // MARK: Replacing

    @objc private func checkAllPressed() {
        ticked = ticked.count == hits.count ? [] : Set(hits.map(\.id))
        outline.reloadData()
        outline.expandItem(nil, expandChildren: true)
        updateSummary()
    }

    func checkAllResults() { ticked = Set(hits.map(\.id)); outline.reloadData(); outline.expandItem(nil, expandChildren: true); updateSummary() }

    @objc private func replacePressed() { replaceChecked(confirm: true) }

    /// Replaces the checked results, after a modal warning with Cancel as its default button (`confirm: false` is for the checks only).
    func replaceChecked(confirm: Bool) {
        let chosen = hits.filter { ticked.contains($0.id) }
        guard !chosen.isEmpty, let main else { return }
        let replacement = replaceField.stringValue
        let deleting = replacement.isEmpty
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = deleting ? Lp("Delete {n} place?", "Delete {n} places?", chosen.count) : Lp("Replace {n} place?", "Replace {n} places?", chosen.count)
            let samples = chosen.prefix(3).map { "“\($0.match)” → " + (deleting ? L("(deleted)") : "“\(replacement)”") }.joined(separator: "\n")
            alert.informativeText = L("{scope}\n\nFor example:\n{samples}\n\nA snapshot of the book is taken first. Right after, Undo Replace puts everything back.", ["scope": scopeSentence(), "samples": samples])
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: deleting ? "Delete" : "Replace")
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        guard let result = main.replace(chosen, with: replacement) else { return }
        undoRecords = result.records
        let places = result.records.reduce(0) { $0 + $1.places.count }
        let done = deleting ? Lp("Deleted {n} place", "Deleted {n} places", places) : Lp("Replaced {n} place", "Replaced {n} places", places)
        banner.stringValue = result.skipped > 0 ? L("{done} ({skipped} changed meanwhile, skipped).", ["done": done, "skipped": result.skipped]) : L("{done}.", ["done": done])
        undoButton.isHidden = places == 0
        let keep = (banner.stringValue, undoButton.isHidden)
        queryChanged()
        banner.stringValue = keep.0
        undoButton.isHidden = keep.1
    }

    @objc private func undoPressed() { undoReplace() }

    func undoReplace() {
        guard let records = undoRecords, let main else { return }
        let left = main.undoReplace(records)
        undoRecords = nil
        queryChanged()
        banner.stringValue = left == 0 ? L("Replace undone.") : Lp("Undone, except {n} place changed since.", "Undone, except {n} places changed since.", left)
        undoButton.isHidden = true
    }

    var banners: String { banner.stringValue }
    var canUndo: Bool { undoRecords != nil }

    // MARK: Fields

    func controlTextDidChange(_ obj: Notification) { queryChanged() }

    /// Return in a field goes to the next result and never replaces; Esc closes the panel.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { step(1); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
}

/// One result: a line of context with the match marked; in Replace, a tick box and the change shown.
final class HitCell: NSTableCellView {
    private let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let text = NSTextField(labelWithString: "")
    var onToggle: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        box.target = self; box.action = #selector(toggled)
        text.lineBreakMode = .byTruncatingTail
        text.font = .systemFont(ofSize: 12)
        for v in [box, text] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2), box.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 2), text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggled() { onToggle?(box.state == .on) }

    func configure(_ hit: SearchHit, replacement: String?, checkable: Bool, checked: Bool) {
        box.isHidden = !checkable
        box.state = checked ? .on : .off
        let plain: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 12)]
        let s = NSMutableAttributedString(string: hit.before, attributes: plain)
        if let replacement {
            s.append(NSAttributedString(string: hit.match, attributes: [.foregroundColor: NSColor.systemRed, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .font: NSFont.systemFont(ofSize: 12)]))
            if !replacement.isEmpty { s.append(NSAttributedString(string: replacement, attributes: [.foregroundColor: NSColor.systemGreen, .font: NSFont.boldSystemFont(ofSize: 12)])) }
        } else {
            s.append(NSAttributedString(string: hit.match, attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.boldSystemFont(ofSize: 12), .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35)]))
        }
        s.append(NSAttributedString(string: hit.after, attributes: plain))
        text.attributedStringValue = s
    }
}

private extension NSStackView {
    func setViews(_ views: [NSView]) { views.forEach { addArrangedSubview($0) } }
}
