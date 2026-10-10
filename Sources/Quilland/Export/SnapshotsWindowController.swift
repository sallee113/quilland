import AppKit
import QuillandCore

/// File ▸ Snapshots…: the snapshots of the book on the left, newest first, grouped by day; on the right what differs between the chosen one
/// and the book now, a comparison of the text, and the buttons that put things back. Every restore asks first (Cancel is the default)
/// and takes a snapshot of the present state before it, so a restore can itself be undone from this list.
final class SnapshotsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Filter: Int, CaseIterable {
        case all, saved, beforeActions, deleted
        var title: String { [L("All"), L("Named and saved"), L("Before actions"), L("Deleted items")][rawValue] }
    }

    private enum Row {
        case day(String)
        case snapshot(SnapshotStore.Info, SnapshotCounts)
    }

    struct SnapshotCounts { var changed = 0, added = 0, deleted = 0; var total: Int { changed + added + deleted } }

    let window: NSWindow
    let folder: URL
    private let store: SnapshotStore
    /// Called before the book is looked at (open scenes are saved) and after something was put back (the views read the files again).
    var prepare: () -> Void = {}
    var onChanged: () -> Void = {}
    var onClose: (() -> Void)?

    private var infos: [SnapshotStore.Info] = []
    private var counts: [String: SnapshotCounts] = [:]
    private var rows: [Row] = []
    private(set) var selected: SnapshotStore.Info?
    private(set) var changes: [ItemChange] = []
    private(set) var selectedChange: ItemChange?
    private var shownChanges: [ItemChange] = []
    private var generation = 0
    private(set) var filter = Filter.all

    private let filterPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let snapshotTable = NSTableView()
    private let changeTable = NSTableView()
    private let compareView = NSTextView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let restoreButton = NSButton(title: L("Restore This…"), target: nil, action: nil)
    private let copyButton = NSButton(title: L("Restore as a Copy"), target: nil, action: nil)
    private let recoverButton = NSButton(title: L("Recover Deleted…"), target: nil, action: nil)
    private let nameButton = NSButton(title: L("Name…"), target: nil, action: nil)
    private let wholeButton = NSButton(title: L("Restore the Whole Book…"), target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(folder: URL) {
        self.folder = folder
        store = SnapshotStore(bookFolder: folder)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Snapshots")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentMinSize = NSSize(width: 900, height: 560)
        build()
        reload()
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
        for f in Filter.allCases { filterPopup.addItem(withTitle: f.title) }
        filterPopup.target = self; filterPopup.action = #selector(filterChanged)
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snapshot"))
        snapshotTable.addTableColumn(c)
        snapshotTable.headerView = nil
        snapshotTable.dataSource = self; snapshotTable.delegate = self
        snapshotTable.rowHeight = 40
        snapshotTable.setAccessibilityLabel(L("Snapshots"))
        let listScroll = NSScrollView()
        listScroll.documentView = snapshotTable
        listScroll.hasVerticalScroller = true; listScroll.borderType = .bezelBorder
        let left = NSStackView(views: [filterPopup, listScroll])
        left.orientation = .vertical; left.alignment = .leading; left.spacing = 8
        listScroll.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        left.widthAnchor.constraint(equalToConstant: 340).isActive = true

        for (id, title, width) in [("status", "", 96), ("group", "", 84), ("item", L("What differs"), 230), ("place", L("Where"), 170)] as [(String, String, CGFloat)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title; col.width = width; col.minWidth = 50
            changeTable.addTableColumn(col)
        }
        changeTable.dataSource = self; changeTable.delegate = self
        changeTable.rowHeight = 22
        changeTable.setAccessibilityLabel(L("What differs from the book now"))
        let changeScroll = NSScrollView()
        changeScroll.documentView = changeTable
        changeScroll.hasVerticalScroller = true; changeScroll.borderType = .bezelBorder
        changeScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true

        compareView.isEditable = false
        compareView.font = .systemFont(ofSize: 13)
        compareView.textContainerInset = NSSize(width: 8, height: 8)
        let compareScroll = NSScrollView()
        compareScroll.documentView = compareView
        compareScroll.hasVerticalScroller = true; compareScroll.borderType = .bezelBorder
        compareScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true

        for b in [restoreButton, copyButton, recoverButton, nameButton, wholeButton] { b.bezelStyle = .rounded }
        restoreButton.target = self; restoreButton.action = #selector(restorePressed)
        copyButton.target = self; copyButton.action = #selector(copyPressed)
        recoverButton.target = self; recoverButton.action = #selector(recoverPressed)
        nameButton.target = self; nameButton.action = #selector(namePressed)
        wholeButton.target = self; wholeButton.action = #selector(wholePressed)
        wholeButton.hasDestructiveAction = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        let buttons = NSStackView(views: [restoreButton, copyButton, recoverButton, NSView(), spinner, nameButton, wholeButton])
        buttons.spacing = 8

        headerLabel.textColor = .secondaryLabelColor
        let right = NSStackView(views: [headerLabel, changeScroll, caption(L("The text, snapshot against now")), compareScroll, buttons])
        right.orientation = .vertical; right.alignment = .leading; right.spacing = 8
        for v in [changeScroll, compareScroll, buttons] { v.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true }

        let middle = NSStackView(views: [left, right])
        middle.orientation = .horizontal; middle.alignment = .top; middle.spacing = 18
        left.heightAnchor.constraint(equalTo: middle.heightAnchor).isActive = true

        let cleanButton = NSButton(title: L("Clean Up Now"), target: self, action: #selector(cleanUpPressed))
        sizeLabel.textColor = .secondaryLabelColor
        let warning = NSTextField(labelWithString: L("Snapshots are on this disk only. Use Git or Time Machine as a backup."))
        warning.textColor = .systemOrange
        warning.font = .systemFont(ofSize: 12, weight: .semibold)
        let footer = NSStackView(views: [sizeLabel, cleanButton, NSView(), warning])
        footer.spacing = 12

        let root = NSStackView(views: [middle, footer])
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 14, right: 18)
        let content = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor), root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor), root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            middle.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36), footer.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
        ])
        window.contentView = content
    }

    // MARK: The list

    /// Reads the snapshots again (and how far each is from the book now).
    func reload() {
        prepare()
        infos = store.list().sorted { $0.date > $1.date }
        counts = [:]
        for info in infos {
            let q = store.quickDiff(info)
            counts[info.id] = SnapshotCounts(changed: q.changed, added: q.added, deleted: q.deleted)
        }
        rebuildRows()
        updateSize()
        if let id = selected?.id, let info = infos.first(where: { $0.id == id }) { select(info) } else { select(nil) }
    }

    private func rebuildRows() {
        func keep(_ info: SnapshotStore.Info) -> Bool {
            switch filter {
            case .all: return true
            case .saved: return info.kind == .manual || info.name != nil
            case .beforeActions: return info.kind == .beforeOperation
            case .deleted: return (counts[info.id]?.deleted ?? 0) > 0
            }
        }
        rows = []
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        var lastDay = ""
        for info in infos where keep(info) {
            let day = f.string(from: info.date)
            if day != lastDay { rows.append(.day(day)); lastDay = day }
            rows.append(.snapshot(info, counts[info.id] ?? SnapshotCounts()))
        }
        snapshotTable.reloadData()
    }

    var snapshotCount: Int { rows.filter { if case .snapshot = $0 { return true }; return false }.count }
    var allSnapshots: [SnapshotStore.Info] { infos }

    @objc private func filterChanged() { setFilter(Filter(rawValue: filterPopup.indexOfSelectedItem) ?? .all) }

    func setFilter(_ f: Filter) {
        filter = f
        filterPopup.selectItem(at: f.rawValue)
        rebuildRows()
    }

    func countsFor(_ info: SnapshotStore.Info) -> SnapshotCounts { counts[info.id] ?? SnapshotCounts() }

    private func updateSize() {
        let bytes = store.diskUsage()
        sizeLabel.stringValue = L("Snapshots take about {size} on this disk (cloned files share the book's space).", ["size": ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)])
    }

    // MARK: Choosing a snapshot

    /// Chooses a snapshot and works out what differs (`sync` for the checks; the window does it in the background).
    func select(_ info: SnapshotStore.Info?, sync: Bool = true) {
        selected = info
        selectedChange = nil
        changes = []
        shownChanges = []
        changeTable.reloadData()
        compareView.string = ""
        if let info, let row = rows.firstIndex(where: { if case .snapshot(let i, _) = $0 { return i.id == info.id }; return false }) {
            snapshotTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if info == nil { snapshotTable.deselectAll(nil) }
        updateButtons()
        guard let info else { headerLabel.stringValue = infos.isEmpty ? L("No snapshots yet. One is taken every 15 minutes while you write, before big changes, and with ⌘S.") : L("Choose a snapshot."); return }
        headerLabel.stringValue = describe(info)
        generation += 1
        let mine = generation
        let source = (store.filesFolder(info), folder)
        let work = { SnapshotInspector.diff(snapshot: source.0, book: source.1) }
        if sync { apply(work(), generation: mine) } else {
            spinner.startAnimation(nil)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = work()
                DispatchQueue.main.async { self?.apply(result, generation: mine) }
            }
        }
    }

    private func apply(_ result: [ItemChange], generation g: Int) {
        guard g == generation else { return }
        spinner.stopAnimation(nil)
        changes = result
        shownChanges = result
        changeTable.reloadData()
        if let info = selected {
            let n = result.count
            headerLabel.stringValue = describe(info) + "  ·  " + (n == 0 ? L("the book is the same as this snapshot") : Lp("{n} item differs", "{n} items differ", n))
        }
        if let first = result.first { selectChange(first) }
        updateButtons()
    }

    private func describe(_ info: SnapshotStore.Info) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .medium
        let kind: String
        switch info.kind {
        case .automatic: kind = L("automatic")
        case .beforeOperation: kind = info.reason ?? L("before an action")
        case .manual: kind = info.name ?? L("saved")
        }
        return "\(f.string(from: info.date)) · \(kind)"
    }

    // MARK: Choosing an item

    func selectChange(_ change: ItemChange) {
        selectedChange = change
        if let row = shownChanges.firstIndex(where: { $0.item.key == change.item.key }) { changeTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        showComparison(change)
        updateButtons()
    }

    var comparisonText: String { compareView.string }

    private func showComparison(_ change: ItemChange) {
        guard let info = selected else { return }
        let root = store.filesFolder(info)
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        let out = NSMutableAttributedString()
        func line(_ text: String, _ attrs: [NSAttributedString.Key: Any]) { out.append(NSAttributedString(string: text + "\n\n", attributes: attrs)) }
        switch change.status {
        case .deletedSince:
            line(L("Deleted since this snapshot. The text as it was:"), [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
            for p in ParagraphDiff.paragraphs(SnapshotInspector.text(of: change.snapshot!, in: root)) { line(p, plain) }
        case .addedSince:
            line(L("Added after this snapshot. The text now:"), [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
            for p in ParagraphDiff.paragraphs(SnapshotInspector.text(of: change.book!, in: folder)) { line(p, plain) }
        case .changed:
            let old = ParagraphDiff.paragraphs(SnapshotInspector.text(of: change.snapshot!, in: root))
            let new = ParagraphDiff.paragraphs(SnapshotInspector.text(of: change.book!, in: folder))
            line(L("Red was in the snapshot and is gone; green is new since."), [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
            for op in ParagraphDiff.diff(old: old, new: new) {
                switch op.kind {
                case .same: line(op.text, plain)
                case .removed: line(op.text, [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.systemRed, .strikethroughStyle: NSUnderlineStyle.single.rawValue])
                case .added: line(op.text, [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.systemGreen])
                }
            }
        }
        compareView.textStorage?.setAttributedString(out)
    }

    // MARK: Tables

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === snapshotTable ? rows.count : shownChanges.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard tableView === snapshotTable, rows.indices.contains(row), case .day = rows[row] else { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView === snapshotTable, rows.indices.contains(row) else { return true }
        if case .day = rows[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === snapshotTable {
            switch rows[row] {
            case .day(let text):
                let l = NSTextField(labelWithString: text)
                l.font = .systemFont(ofSize: 11, weight: .semibold)
                l.textColor = .secondaryLabelColor
                return l
            case .snapshot(let info, let c):
                let time = DateFormatter()
                time.dateStyle = .none; time.timeStyle = .short
                let icon: String, title: String
                switch info.kind {
                case .automatic: icon = "◷"; title = L("Automatic")
                case .beforeOperation: icon = "⚑"; title = info.reason ?? L("Before an action")
                case .manual: icon = "★"; title = info.name ?? L("Saved")
                }
                let s = NSMutableAttributedString(string: "\(icon)  \(time.string(from: info.date))   ", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
                s.append(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: info.name == nil ? .regular : .semibold)]))
                s.append(NSAttributedString(string: "\n" + (c.total == 0 ? L("same as the book now") : Lp("{n} file differs", "{n} files differ", c.total)), attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
                let l = NSTextField(labelWithAttributedString: s)
                l.lineBreakMode = .byTruncatingTail
                return l
            }
        }
        guard shownChanges.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let c = shownChanges[row]
        let l = NSTextField(labelWithString: "")
        switch id {
        case "status":
            l.stringValue = c.label
            l.textColor = c.status == .deletedSince ? .systemRed : (c.status == .addedSince ? .systemGreen : .systemOrange)
        case "group": l.stringValue = c.item.group.label; l.textColor = .secondaryLabelColor
        case "item": l.stringValue = c.item.title.isEmpty ? "(untitled)" : c.item.title
        default: l.stringValue = c.item.place; l.textColor = .secondaryLabelColor
        }
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === snapshotTable {
            let row = snapshotTable.selectedRow
            guard rows.indices.contains(row), case .snapshot(let info, _) = rows[row], info.id != selected?.id else { return }
            select(info, sync: false)
        } else {
            let row = changeTable.selectedRow
            guard shownChanges.indices.contains(row) else { return }
            selectedChange = shownChanges[row]
            showComparison(shownChanges[row])
            updateButtons()
        }
    }

    private func updateButtons() {
        let hasSnapshot = selected != nil
        nameButton.isEnabled = hasSnapshot
        wholeButton.isEnabled = hasSnapshot
        let status = selectedChange?.status
        restoreButton.isEnabled = status == .changed
        recoverButton.isEnabled = status == .deletedSince
        let copyable: [ItemCatalog.Group] = [.scene, .character, .world, .place, .event, .relationship, .card]
        copyButton.isEnabled = status == .changed && copyable.contains(selectedChange!.item.group)
    }

    var buttonStates: (restore: Bool, copy: Bool, recover: Bool, name: Bool, whole: Bool) {
        (restoreButton.isEnabled, copyButton.isEnabled, recoverButton.isEnabled, nameButton.isEnabled, wholeButton.isEnabled)
    }

    // MARK: The buttons

    private func confirm(_ title: String, _ detail: String, go: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail + "\n\n" + L("A snapshot of the book as it is now is taken first, so this can be undone from this list.")
        alert.addButton(withTitle: L("Cancel")).keyEquivalent = "\r"
        let button = alert.addButton(withTitle: go)
        button.keyEquivalent = ""
        button.hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    @objc private func restorePressed() { restoreSelected(confirm: true) }
    @objc private func recoverPressed() { restoreSelected(confirm: true) }
    @objc private func copyPressed() { copySelected() }
    @objc private func namePressed() { nameSelected(nil) }
    @objc private func wholePressed() { restoreWholeBook(confirm: true) }
    @objc private func cleanUpPressed() { cleanUp() }

    /// Takes the safety snapshot of the present state; false (and a message) when that fails, in which case nothing is restored.
    private func safety(_ reason: String) -> Bool {
        prepare()
        do { _ = try store.take(.beforeOperation, reason: reason); return true } catch {
            let alert = NSAlert()
            alert.messageText = L("A snapshot of the book could not be taken, so nothing was changed.")
            alert.informativeText = "\(error)"
            alert.runModal()
            return false
        }
    }

    private func done() {
        onChanged()
        reload()
    }

    /// Restore This… (a changed item goes back to how the snapshot had it) and Recover Deleted… (a deleted one comes back).
    func restoreSelected(confirm confirmed: Bool) {
        guard let info = selected, let change = selectedChange, change.status != .addedSince else { return }
        let title = change.item.title.isEmpty ? "(untitled)" : change.item.title
        if confirmed {
            let text = change.status == .changed
                ? L("“{title}” goes back to how it was in this snapshot. What it is now is replaced.", ["title": title])
                : L("“{title}” ({group}) comes back in its old place. If that place is gone, it goes into a chapter called “Recovered” at the end.", ["title": title, "group": change.item.group.label.lowercased()])
            guard confirm(change.status == .changed ? L("Restore “{title}”?", ["title": title]) : L("Recover “{title}”?", ["title": title]), text, go: change.status == .changed ? L("Restore") : L("Recover")) else { return }
        }
        guard safety(L("Before restoring “{title}”", ["title": title])) else { return }
        do { try SnapshotRecovery(book: folder).restore(change, snapshotRoot: store.filesFolder(info)) } catch { report(error); return }
        done()
    }

    func recoverSelected(confirm confirmed: Bool) { restoreSelected(confirm: confirmed) }

    /// Restore as a Copy: the item as it was, beside the present one, titled "… (restored)". Nothing is replaced, so no warning.
    func copySelected() {
        guard let info = selected, let change = selectedChange, change.status == .changed else { return }
        guard safety(L("Before restoring a copy of “{title}”", ["title": change.item.title])) else { return }
        do { try SnapshotRecovery(book: folder).restoreAsCopy(change, snapshotRoot: store.filesFolder(info)) } catch { report(error); return }
        done()
    }

    func nameSelected(_ given: String?) {
        guard let info = selected else { return }
        var name = given
        if name == nil {
            let field = NSTextField(string: info.name ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
            let alert = NSAlert()
            alert.messageText = L("Name this snapshot")
            alert.informativeText = L("A named snapshot is kept for good; it is never thinned out.")
            alert.accessoryView = field
            alert.addButton(withTitle: L("Name"))
            alert.addButton(withTitle: L("Cancel"))
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            name = field.stringValue
        }
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        try? store.name(info, as: name)
        reload()
    }

    func restoreWholeBook(confirm confirmed: Bool) {
        guard let info = selected else { return }
        if confirmed {
            let f = DateFormatter()
            f.dateStyle = .medium; f.timeStyle = .medium
            guard confirm(L("Restore the whole book?"), L("Every file of the book goes back to how it was on {date}. Everything written since is replaced.", ["date": f.string(from: info.date)]), go: L("Restore the Book")) else { return }
        }
        prepare()
        do { _ = try store.restoreAll(from: info) } catch { report(error); return }
        done()
    }

    /// Clean Up Now: the thinning rule is applied (all of the last day, then one a day; named ones always stay).
    @discardableResult
    func cleanUp() -> Int {
        let removed = (try? store.thin()) ?? []
        reload()
        return removed.count
    }

    private func report(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("That could not be done")
        alert.informativeText = "\(error)"
        alert.runModal()
    }
}
