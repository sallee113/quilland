import AppKit
import QuillandCore

/// The Suggestions tab of the bottom panel: what the model found, grouped by kind, each with the quote it comes from; ticked ones are accepted.
final class SuggestionsView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    weak var main: MainAreaController? { didSet { attach() } }
    /// Told when a run starts or ends, so that the tab can show it is busy even when another tab is open.
    var onBusyChanged: ((Bool) -> Void)?
    private enum Row { case group(String, Int); case item(CollectedItem); case finding(ConsistencyFinding) }
    private var rows: [Row] = []
    private let table = Hover.rows(NSTableView())
    private let status = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let collectButton = NSButton(title: L("Collect from the Book…"), target: nil, action: nil)
    private let stopButton = NSButton(title: L("Stop"), target: nil, action: nil)
    private let acceptButton = NSButton(title: "", target: nil, action: nil)
    private let dismissButton = NSButton(title: L("Dismiss Checked"), target: nil, action: nil)
    private let checkAllButton = NSButton(title: L("Check All"), target: nil, action: nil)
    private let openCardButton = NSButton(title: L("Open the Card"), target: nil, action: nil)
    private let replaceButton = NSButton(title: L("Replace a Name…"), target: nil, action: nil)
    private let report = NSTextField(wrappingLabelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1
        bar.controlSize = .small
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: 160).isActive = true
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("suggestion"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.usesAutomaticRowHeights = false
        table.setAccessibilityLabel(L("Suggestions"))
        table.target = self; table.action = #selector(rowClicked)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        for b in [collectButton, stopButton, acceptButton, dismissButton, checkAllButton, openCardButton, replaceButton] { b.bezelStyle = .rounded; b.controlSize = .small; b.target = self; b.keyEquivalent = "" }
        collectButton.action = #selector(collectPressed); stopButton.action = #selector(stopPressed)
        replaceButton.action = #selector(replacePressed)
        replaceButton.toolTip = L("A name the model made up («Hero» for the narrator) is replaced by the card it really is, in this suggestion or in all of them")
        let rowMenu = NSMenu(); rowMenu.delegate = self; table.menu = rowMenu
        openCardButton.action = #selector(openCardPressed); acceptButton.action = #selector(acceptPressed); dismissButton.action = #selector(dismissPressed); checkAllButton.action = #selector(checkAllPressed)
        report.font = .systemFont(ofSize: 11)
        report.textColor = .secondaryLabelColor
        let top = NSStackView(views: [collectButton, bar, status, stopButton])
        top.spacing = 10
        let bottom = NSStackView(views: [acceptButton, dismissButton, checkAllButton, replaceButton, openCardButton])
        bottom.spacing = 8
        let stack = NSStackView(views: [top, scroll, bottom])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70),
            top.trailingAnchor.constraint(lessThanOrEqualTo: stack.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private var session: CollectSession? { main?.collect }

    private func attach() {
        session?.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    // MARK: Showing

    static func groupTitle(_ kind: CollectKind) -> String {
        switch kind {
        case .characters: return L("Characters")
        case .places: return L("Places")
        case .events: return L("Events")
        case .relationships: return L("Relationships")
        case .observations: return L("Observations")
        case .changes: return L("Changes")
        }
    }

    func refresh() {
        guard let session else { return }
        rows = []
        if !session.findings.isEmpty {
            rows.append(.group(L("Contradictions"), session.findings.count))
            rows += session.findings.map { .finding($0) }
        }
        if !session.running { session.refreshAdditions() }   // (the book may have changed since: while a run goes on, the findings do it as they come)
        let shown = session.visibleItems
        let hidden = session.alreadyInBookCount
        for kind in CollectKind.allCases {
            let items = shown.filter { $0.kind == kind }
            guard !items.isEmpty else { continue }
            rows.append(.group(Self.groupTitle(kind), items.count))
            rows += items.map { .item($0) }
        }
        table.reloadData()
        let running = session.running
        onBusyChanged?(running)
        stopButton.isHidden = !running
        collectButton.isEnabled = !running
        collectButton.title = running ? L("Working…") : L("Collect from the Book…")
        status.font = .systemFont(ofSize: 11, weight: running ? .semibold : .regular)
        status.textColor = running ? .systemOrange : .secondaryLabelColor
        bar.isHidden = !running
        // The bar moves with every request the model is asked (the steps done out of all of them), not only from one scene to the next.
        if let p = session.progress { bar.doubleValue = p.pieces > 0 ? Double(p.piece) / Double(p.pieces) : Double(p.scene - 1) / Double(max(1, p.of)) }
        if running {
            let p = session.progress
            status.stringValue = p.map { q in L("Scene {n} of {total}: {title} · {found} found", ["n": q.scene, "total": q.of, "title": q.title, "found": max(0, q.found - session.alreadyInBookCount)]) + (q.pieces > 1 ? " · " + L("part {piece} of {pieces}", ["piece": min(q.piece + 1, q.pieces), "pieces": q.pieces]) : "") } ?? session.message
        } else {
            let base = session.message.isEmpty ? (rows.isEmpty && hidden == 0 ? L("Nothing yet. Collect from the Book… asks the model to read the scenes, and Check Consistency… looks for contradictions.") : "") : session.message
            let left = hidden > 0 ? Lp("{n} finding already in the book: not listed", "{n} findings already in the book: not listed", hidden) : ""
            status.stringValue = [base, left].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        updateButtons()
    }

    private func updateButtons() {
        guard let session else { return }
        let n = session.checked.count
        let acceptable = session.visibleItems.filter { session.checked.contains($0.id) }.count
        let total = session.visibleItems.count + session.findings.count
        acceptButton.title = Lp("Accept {n} Checked", "Accept {n} Checked", acceptable)
        acceptButton.isEnabled = acceptable > 0 && !session.running
        dismissButton.isEnabled = n > 0
        checkAllButton.isEnabled = total > 0
        checkAllButton.title = n == total && n > 0 ? L("Uncheck All") : L("Check All")
        replaceButton.isEnabled = selectedItem.map { !$0.nameSlots.isEmpty } ?? false && !session.running
        if case .finding(let f)? = selectedRow { openCardButton.isEnabled = true; openCardButton.title = f.source.kind == .scene ? L("Open the Other Scene") : L("Open the Card") } else { openCardButton.isEnabled = false; openCardButton.title = L("Open the Card") }
    }

    private var selectedRow: Row? { table.selectedRow >= 0 && table.selectedRow < rows.count ? rows[table.selectedRow] : nil }
    /// For the checks: how far the bar is, and what the status line says.
    var barFraction: Double { bar.doubleValue }
    var statusText: String { status.stringValue }
    var itemCount: Int { session?.visibleItems.count ?? 0 }
    var findingCount: Int { session?.findings.count ?? 0 }
    var checkedCount: Int { session?.checked.count ?? 0 }
    /// For the checks: what the row of a finding says (its text).
    func rowText(for id: UUID) -> String {
        guard let row = rows.firstIndex(where: { if case .item(let i) = $0 { return i.id == id } else { return false } }), let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? SuggestionCell else { return "" }
        return cell.shownText
    }

    /// For the checks: does the row of this finding show why it was not accepted?
    func reasonShown(for id: UUID) -> Bool {
        guard let session, let row = rows.firstIndex(where: { if case .item(let i) = $0 { return i.id == id } else { return false } }), let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? SuggestionCell else { return false }
        return cell.shownText.contains("not accepted: ") && session.skipReason(for: id) != nil
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { if case .group = rows[row] { return true }; return false }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { if case .group = rows[row] { return false }; return true }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { { if case .group = rows[row] { return 22 }; return 58 }() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .group(let title, let n):
            let l = NSTextField(labelWithString: "\(title)  ·  \(n)")
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return l
        case .finding(let f):
            let cell = SuggestionCell()
            cell.configure(f, sceneTitle: main?.session.structure.scenes.first { $0.id == f.scene }?.node.title ?? "", checked: session?.checked.contains(f.id) == true)
            cell.onToggle = { [weak self] on in
                if on { self?.session?.checked.insert(f.id) } else { self?.session?.checked.remove(f.id) }
                self?.updateButtons()
            }
            return cell
        case .item(let item):
            let cell = SuggestionCell()
            cell.configure(item, existing: session?.existingMatch(item), adds: session?.additions[item.id], sceneTitle: { [weak self] id in self?.main?.session.structure.scenes.first { $0.id == id }?.node.title ?? "" }, checked: session?.checked.contains(item.id) == true, skipReason: session?.skipReason(for: item.id), lookAlike: session?.lookAlikes[item.id])
            cell.onToggle = { [weak self] on in
                if on { self?.session?.checked.insert(item.id) } else { self?.session?.checked.remove(item.id) }
                self?.updateButtons()
            }
            return cell
        }
    }

    @objc private func rowClicked() {
        let row = table.clickedRow
        guard row >= 0, row < rows.count else { return }
        switch rows[row] {
        case .item(let item): if let e = item.evidence.first { main?.reveal(scene: e.scene, range: e.range) }
        case .finding(let f): main?.reveal(scene: f.scene, range: f.range)
        case .group: break
        }
    }

    // MARK: Actions

    @objc private func collectPressed() { main?.showCollectSheet() }
    @objc private func stopPressed() { session?.stop() }

    @objc private func checkAllPressed() {
        guard let session else { return }
        let all = Set(session.visibleItems.map(\.id) + session.findings.map(\.id))
        session.checked = session.checked.count == all.count ? [] : all
        refresh()
    }

    func checkAll() { session?.checked = Set((session?.visibleItems.map(\.id) ?? []) + (session?.findings.map(\.id) ?? [])); refresh() }

    @objc private func openCardPressed() { openSource() }

    /// Goes to the card (or the scene) the selected contradiction is with.
    func openSource() {
        guard case .finding(let f)? = selectedRow, let main else { return }
        switch f.source.kind {
        case .character: main.setMode(.characters); main.charactersView?.select(f.source.ref)
        case .relationship: if let event = main.eventHolding(relationship: f.source.ref) { main.setMode(.events); main.eventsView?.select(event) }
        case .place: main.setMode(.world); main.worldView?.select(f.source.ref)
        case .event: main.setMode(.events); main.eventsView?.select(f.source.ref)
        case .scene: main.reveal(scene: f.source.ref, range: nil)
        }
    }

    func selectFirstFinding() {
        guard let i = rows.firstIndex(where: { if case .finding = $0 { return true }; return false }) else { return }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        updateButtons()
    }

    private var selectedItem: CollectedItem? { if case .item(let i)? = selectedRow { return i } else { return nil } }

    @objc private func replacePressed() { if let item = selectedItem { askToReplaceName(in: item) } }

    /// The row's menu: Replace a Name… for the suggestion under the pointer.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard rows.indices.contains(row), case .item(let item) = rows[row], !item.nameSlots.isEmpty, session?.running != true else { return }
        menu.addItem(ClosureMenuItem(title: L("Replace a Name…")) { [weak self] in self?.askToReplaceName(in: item) })
    }

    /// Asks which name and which card, then replaces it.
    private func askToReplaceName(in item: CollectedItem) {
        guard let main else { return }
        let characters = main.characters.characters.compactMap(\.name)
        let places = main.worlds.entries.compactMap { $0.name }
        guard let r = ReplaceNameDialog(slots: item.nameSlots, characters: characters, places: places).run() else { return }
        replaceName(in: item.id, slot: r.slot, with: r.card, inAll: r.inAll)
    }

    /// Replaces a name of the suggestion with a card's name (in all suggestions, or this one alone). Returns how many suggestions changed.
    @discardableResult
    func replaceName(in id: UUID, slot: NameSlot, with card: String, inAll: Bool) -> Int {
        let n = session?.replaceName(slot.name, role: slot.role, with: card, only: inAll ? nil : id) ?? 0
        refresh()
        return n
    }

    /// For the checks: the names of the suggestion with this id that can be replaced.
    func nameSlots(of id: UUID) -> [NameSlot] { session?.items.first { $0.id == id }?.nameSlots ?? [] }
    var replaceNameEnabled: Bool { replaceButton.isEnabled }
    func selectItemRow(_ id: UUID) {
        guard let row = rows.firstIndex(where: { if case .item(let i) = $0 { return i.id == id } else { return false } }) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        updateButtons()
    }

    @objc private func acceptPressed() { acceptChecked() }

    @discardableResult
    func acceptChecked() -> AcceptReport? {
        guard let session, !session.items.filter({ session.checked.contains($0.id) }).isEmpty else { return nil }
        let r = session.accept(session.checked)
        refresh()
        return r
    }

    @objc private func dismissPressed() { guard let session else { return }; session.dismiss(session.checked) }
}

/// A row of the list: a tick box, the name with what kind of thing it is, the model's description, and the quote with its scene.
final class SuggestionCell: NSTableCellView {
    private let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let text = NSTextField(wrappingLabelWithString: "")
    var shownText: String { text.stringValue }
    var onToggle: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        box.target = self; box.action = #selector(toggled)
        text.maximumNumberOfLines = 3
        text.lineBreakMode = .byWordWrapping
        text.alignment = .left
        text.font = .systemFont(ofSize: 12)
        text.isSelectable = false
        // Laid out by hand (see `layout`): a wrapping label under Auto Layout takes its one-line width and slides to the right edge.
        for v in [box, text] { v.translatesAutoresizingMaskIntoConstraints = true; addSubview(v) }
    }

    override func layout() {
        super.layout()
        box.frame = NSRect(x: 4, y: bounds.height - 22, width: 20, height: 18)
        let width = max(80, bounds.width - 34)
        text.preferredMaxLayoutWidth = width
        text.frame = NSRect(x: 28, y: 2, width: width, height: max(20, bounds.height - 4))
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggled() { onToggle?(box.state == .on) }

    func configure(_ f: ConsistencyFinding, sceneTitle: String, checked: Bool) {
        box.state = checked ? .on : .off
        let s = NSMutableAttributedString(string: f.problem, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        s.append(NSAttributedString(string: "\n«" + f.quote + "»" + (sceneTitle.isEmpty ? "" : "  —  " + sceneTitle), attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]))
        s.append(NSAttributedString(string: "\n≠ " + f.source.title + ": «" + f.sourceQuote + "»", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange]))
        text.attributedStringValue = s
    }

    /// What the row says about a card the finding repeats: what accepting adds to it.
    static func cardText(_ adds: CardAddition?, sceneTitle: (String) -> String) -> String {
        guard let adds, !adds.isEmpty else { return L("already has a card") }
        var parts: [String] = []
        if adds.scenes.count == 1 { parts.append(L("the scene “{title}”", ["title": sceneTitle(adds.scenes[0])])) }
        else if adds.scenes.count > 1 { parts.append(Lp("{n} scene", "{n} scenes", adds.scenes.count)) }
        if !adds.people.isEmpty { parts.append(L("people: {names}", ["names": adds.people.joined(separator: ", ")])) }
        if !adds.names.isEmpty { parts.append(L("other names: {names}", ["names": adds.names.joined(separator: ", ")])) }
        return L("already has a card: adds {what}", ["what": parts.joined(separator: "; ")])
    }

    func configure(_ item: CollectedItem, existing: String?, adds: CardAddition? = nil, sceneTitle: (String) -> String, checked: Bool, skipReason: String? = nil, lookAlike: LookAlike? = nil) {
        box.state = checked ? .on : .off
        let s = NSMutableAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        var tags: [String] = []
        if item.kind == .places, !item.parent.isEmpty { tags.append(L("in {place}", ["place": item.parent])) }
        if item.kind == .events, !item.date.isEmpty { tags.append(item.date) }
        if item.kind == .events, !item.members.isEmpty { tags.append(L("with {names}", ["names": item.members.joined(separator: ", ")])) }
        if item.kind == .changes { tags.append(item.eventTitle.isEmpty ? L("a new event is made for it") : L("in the event “{title}”", ["title": item.eventTitle])) }
        if item.kind == .relationships { tags.append(item.when == "starts" ? L("begins in the story") : (item.when == "changes" ? L("changes in the story") : (item.when == "ends" ? L("ends in the story") : L("from the start of the book")))) }
        if !item.aliases.isEmpty { tags.append(L("also {names}", ["names": item.aliases.joined(separator: ", ")])) }
        let scenes = Set(item.evidence.map(\.scene)).count
        tags.append(Lp("{n} scene", "{n} scenes", scenes))
        s.append(NSAttributedString(string: "   " + tags.joined(separator: " · "), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        if existing != nil { s.append(NSAttributedString(string: "   " + Self.cardText(adds, sceneTitle: sceneTitle), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange])) }
        // Not the same for sure, but alike: a card of the book, or another row of the list. The reason is in the tooltip.
        if let lookAlike {
            s.append(NSAttributedString(string: "   " + (lookAlike.isCard ? L("looks like the card “{name}”", ["name": lookAlike.title]) : L("looks like another row: “{name}”", ["name": lookAlike.title])), attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.systemYellow]))
            toolTip = L("It may be the same thing: {reason}. Check before accepting.", ["reason": lookAlike.reason])
        } else { toolTip = nil }
        if let skipReason { s.append(NSAttributedString(string: "\n" + L("not accepted: {reason}", ["reason": skipReason]), attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.systemOrange])) }
        if !item.detail.isEmpty { s.append(NSAttributedString(string: "\n" + item.detail, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])) }
        if let e = item.evidence.first {
            let place = sceneTitle(e.scene)
            s.append(NSAttributedString(string: "\n«" + e.quote + "»" + (place.isEmpty ? "" : "  —  " + place), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        text.attributedStringValue = s
    }
}
