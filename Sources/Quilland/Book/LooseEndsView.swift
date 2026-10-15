import AppKit
import QuillandCore

/// The Loose Ends tab of the bottom panel: links that point to nothing, and data files that cannot be read, each with what can be done about it.
final class LooseEndsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var main: MainAreaController?
    private(set) var ends: [LooseEnd] = []
    private let summary = NSTextField(labelWithString: "")
    private let table = Hover.rows(NSTableView())
    private let explanation = NSTextField(wrappingLabelWithString: "")
    private let repointButton = NSButton(title: L("Point to…"), target: nil, action: nil)
    private let removeButton = NSButton(title: L("Remove"), target: nil, action: nil)
    private let keepButton = NSButton(title: L("Keep"), target: nil, action: nil)
    private let openButton = NSButton(title: L("Show the File"), target: nil, action: nil)
    private let restoreButton = NSButton(title: L("Restore from a Snapshot"), target: nil, action: nil)
    private let againButton = NSButton(title: L("Check Again"), target: nil, action: nil)
    private let showKeptButton = NSButton(title: L("Show Kept Again"), target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 3
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("end"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.rowSizeStyle = .small
        table.setAccessibilityLabel(L("Loose ends"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let buttons: [(NSButton, Selector)] = [(repointButton, #selector(repointPressed)), (removeButton, #selector(removePressed)), (keepButton, #selector(keepPressed)),
                                               (openButton, #selector(showFilePressed)), (restoreButton, #selector(restorePressed)), (againButton, #selector(refreshAction)),
                                               (showKeptButton, #selector(showKeptPressed))]
        for (b, action) in buttons { b.bezelStyle = .rounded; b.controlSize = .small; b.target = self; b.action = action; b.keyEquivalent = "" }
        let top = NSStackView(views: [againButton, summary])
        top.spacing = 10
        let bottom = NSStackView(views: [repointButton, removeButton, keepButton, openButton, restoreButton, showKeptButton])
        bottom.spacing = 8
        let stack = NSStackView(views: [top, scroll, explanation, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70),
            explanation.leadingAnchor.constraint(equalTo: stack.leadingAnchor), explanation.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func refreshAction() { refresh() }

    func refresh() {
        guard let main else { return }
        let keep = selectedEnd?.key
        ends = LooseEnds(book: main.folder).scan(ignoring: LooseEnds.ignored(book: main.folder))
        table.reloadData()
        if let keep, let i = ends.firstIndex(where: { $0.key == keep }) { table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false) }
        summary.stringValue = ends.isEmpty ? L("Nothing is loose") : Lp("{n} loose end", "{n} loose ends", ends.count)
        updateButtons()
    }

    var selectedEnd: LooseEnd? { table.selectedRow >= 0 && table.selectedRow < ends.count ? ends[table.selectedRow] : nil }

    func select(where match: (LooseEnd) -> Bool) {
        guard let i = ends.firstIndex(where: match) else { return }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        updateButtons()
    }

    private func updateButtons() {
        let end = selectedEnd
        let link = end?.kind == .missingLink
        repointButton.isEnabled = link && end?.field != "entries"
        removeButton.isEnabled = link
        keepButton.isEnabled = end != nil
        openButton.isEnabled = end != nil
        restoreButton.isEnabled = end?.kind == .damagedFile
        showKeptButton.isEnabled = !LooseEnds.ignored(book: main?.folder ?? URL(fileURLWithPath: "/")).isEmpty
        explanation.stringValue = Self.explanation(for: end)
    }

    static func what(_ end: LooseEnd) -> String {
        if end.kind == .damagedFile { return L("The file cannot be read") }
        switch end.field {
        case "links": return L("a link to a scene or thing that is gone")
        case "pov_scenes": return L("a scene told from this side, which is gone")
        case "places": return L("a place that is gone")
        case "worlds": return L("a world that is gone")
        default: return L("an event that is gone, still on the plan")
        }
    }

    static func explanation(for end: LooseEnd?) -> String {
        guard let end else { return L("Choose a loose end. The app never changes a damaged file by itself, and never removes a link without being asked.") }
        if end.kind == .damagedFile { return L("Show the File to look at it yourself. Restore from a Snapshot puts back the newest readable copy and keeps the damaged one beside it, named “….damaged”.") }
        return L("Point to… gives the link to another thing, Remove deletes the link, Keep leaves it as it is and stops listing it.")
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { ends.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let end = ends[row]
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: end.kind == .damagedFile ? "⚠︎ " : "↯ ", attributes: [.foregroundColor: NSColor.systemOrange, .font: NSFont.systemFont(ofSize: 12)])
        s.append(NSAttributedString(string: end.owner, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]))
        s.append(NSAttributedString(string: " — " + Self.what(end), attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        s.append(NSAttributedString(string: "   " + end.file, attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 10)]))
        label.attributedStringValue = s
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    // MARK: Doing something about it

    private var tool: LooseEnds? { main.map { LooseEnds(book: $0.folder) } }

    /// The book's data was changed under the stores: they read it again.
    private func changed() {
        main?.reloadFromDisk()
        refresh()
    }

    @objc private func removePressed() { remove() }

    @discardableResult
    func remove() -> Bool {
        guard let end = selectedEnd, end.kind == .missingLink, let tool else { return false }
        do { try tool.remove(end) } catch { main?.reportError(error); return false }
        changed()
        return true
    }

    @objc private func keepPressed() { keep() }

    func keep() {
        guard let end = selectedEnd, let main else { return }
        LooseEnds.ignore(end, book: main.folder)
        refresh()
    }

    @objc private func showKeptPressed() {
        guard let main else { return }
        LooseEnds.forgetIgnored(book: main.folder)
        refresh()
    }

    @objc private func showFilePressed() {
        guard let end = selectedEnd, let main else { return }
        NSWorkspace.shared.activateFileViewerSelecting([main.folder.appendingPathComponent(end.file)])
    }

    @objc private func restorePressed() { restoreDamaged(confirm: true) }

    @discardableResult
    func restoreDamaged(confirm: Bool) -> Bool {
        guard let end = selectedEnd, end.kind == .damagedFile, let tool, let main else { return false }
        if confirm {
            let alert = NSAlert()
            alert.messageText = L("Restore “{file}” from a snapshot?", ["file": (end.file as NSString).lastPathComponent])
            alert.informativeText = L("The newest snapshot with a readable copy is used. The damaged file is kept beside it, named “….damaged”.")
            alert.addButton(withTitle: L("Restore"))
            alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        do { _ = try tool.restoreDamaged(end) } catch { main.reportError(error); return false }
        changed()
        return true
    }

    @objc private func repointPressed() { repoint() }

    /// Asks which thing the link should point to.
    func repoint() {
        guard let end = selectedEnd, end.kind == .missingLink, let tool, let main else { return }
        var choices: [(id: String, title: String)] = []
        switch end.field {
        case "places": choices = main.worlds.entries.compactMap { e in e.id.flatMap { id in e.name.map { (id, $0) } } }
        case "worlds": choices = main.worlds.worlds.compactMap { w in w.id.flatMap { id in w.name.map { (id, $0) } } }
        default: choices = main.session.structure.sceneChoices
        }
        guard !choices.isEmpty else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = L("Point the link of “{owner}” to…", ["owner": end.owner])
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26), pullsDown: false)
        for c in choices { popup.addItem(withTitle: c.title); popup.lastItem?.representedObject = c.id }
        alert.accessoryView = popup
        alert.addButton(withTitle: L("Point"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, let id = popup.selectedItem?.representedObject as? String else { return }
        do { try tool.repoint(end, to: id) } catch { main.reportError(error); return }
        changed()
    }
}
