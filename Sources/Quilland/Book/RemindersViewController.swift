import AppKit
import QuillandCore

/// A row of the Reminders list: a check box, the text (which can be changed), and a button that deletes it.
final class ReminderRowView: NSTableCellView, NSTextFieldDelegate {
    let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let field = NSTextField()
    let deleteButton = NSButton(title: "✕", target: nil, action: nil)
    var onToggle: ((Bool) -> Void)?
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?

    init(_ r: Reminder) {
        super.init(frame: .zero)
        box.state = r.done ? .on : .off
        box.target = self; box.action = #selector(toggled)
        box.setAccessibilityLabel(L("Done"))
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        // The text wraps and can have several lines; Return finishes, Shift-Return or Option-Return starts a new line.
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        field.delegate = self
        field.setAccessibilityLabel(L("Reminder"))
        field.attributedStringValue = NSAttributedString(string: r.text, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: r.done ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .strikethroughStyle: r.done ? NSUnderlineStyle.single.rawValue : 0,
        ])
        field.toolTip = r.text
        deleteButton.isBordered = false
        deleteButton.target = self; deleteButton.action = #selector(deleted)
        deleteButton.setAccessibilityLabel(L("Delete"))
        deleteButton.toolTip = L("Delete")
        for v in [box, field, deleteButton] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), box.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            field.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 6), field.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            field.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), deleteButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            box.widthAnchor.constraint(equalToConstant: 18), deleteButton.widthAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggled() { onToggle?(box.state == .on) }
    @objc private func deleted() { onDelete?() }

    func controlTextDidEndEditing(_ obj: Notification) { onText?(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        RemindersViewController.newLineWanted(textView, selector)
    }
}

/// The Reminders view: what is still to do, then (under a heading) what is done. A check box marks one, ✕ deletes it, a click on the text changes it.
final class RemindersViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var store: RemindersStore!
    var onChange: (() -> Void)?
    var onEscape: (() -> Void)?

    private enum Row { case reminder(Reminder), heading(String) }
    private var rows: [Row] = []

    private let table = Hover.rows(NSTableView())
    let addField = NSTextField()
    private let emptyLabel = NSTextField(labelWithString: L("Nothing to remember. Type a reminder below and press Return."))
    private let bannerLabel = NSTextField(labelWithString: "")
    private let undoButton = NSButton(title: L("Undo"), target: nil, action: nil)
    private let banner = NSStackView()
    private var bannerTimer: Timer?

    override func loadView() {
        let root = NSView()
        let title = NSTextField(labelWithString: L("Reminders"))
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.rowHeight = 30
        // Each row is as tall as its text needs at the width the list has; a change of the width measures them again.
        table.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: table, queue: .main) { [weak self] _ in
            guard let self, self.lastWidth != self.table.bounds.width else { return }
            self.table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<self.rows.count))
        }
        table.selectionHighlightStyle = .none
        table.setAccessibilityLabel(L("Reminders"))
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: L("Delete")) { [weak self] in
            guard let self, self.table.clickedRow >= 0, case .reminder(let r)? = self.row(self.table.clickedRow) else { return }
            self.delete(r.id)
        })
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        addField.placeholderString = L("Add a reminder — Return adds it, Shift-Return starts a new line")
        addField.setAccessibilityLabel(L("Add a reminder"))
        addField.lineBreakMode = .byWordWrapping
        addField.cell?.wraps = true
        addField.cell?.isScrollable = false
        addField.maximumNumberOfLines = 3
        addField.delegate = self
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        bannerLabel.font = .systemFont(ofSize: 12)
        undoButton.bezelStyle = .rounded; undoButton.controlSize = .small
        undoButton.target = self; undoButton.action = #selector(undoPressed)
        banner.setViews([bannerLabel, undoButton], in: .leading)
        banner.spacing = 10
        banner.isHidden = true
        for v in [title, scroll, addField, emptyLabel, banner] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        // A column of a comfortable width in the middle, as a list of notes should be.
        let width = root.widthAnchor
        let column1 = scroll.widthAnchor.constraint(equalToConstant: 640)
        column1.priority = NSLayoutConstraint.Priority(750)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            scroll.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            column1, scroll.widthAnchor.constraint(lessThanOrEqualTo: width, constant: -40),
            scroll.bottomAnchor.constraint(equalTo: banner.topAnchor, constant: -8),
            banner.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 8),
            banner.bottomAnchor.constraint(equalTo: addField.topAnchor, constant: -10),
            addField.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), addField.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            addField.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20), addField.heightAnchor.constraint(equalToConstant: 54),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        view = root
        reload()
    }

    func reload() {
        guard isViewLoaded else { return }
        rows = store.open.map { .reminder($0) }
        if !store.done.isEmpty {
            rows.append(.heading(L("Done ({n})", ["n": store.done.count])))
            rows += store.done.map { .reminder($0) }
        }
        table.reloadData()
        emptyLabel.isHidden = !store.reminders.isEmpty
    }

    // MARK: Where it was left (kept for the book)

    var memory: ViewMemory { ViewMemory(scroll: Double(table.scrolledBy)) }

    func restore(_ m: ViewMemory?) {
        guard let m else { return }
        reload()
        table.restoreScroll(m.scroll)
    }

    private func row(_ i: Int) -> Row? { rows.indices.contains(i) ? rows[i] : nil }

    /// What the list shows now, for the checks: the texts of the open ones, then the done ones.
    var shownTexts: (open: [String], done: [String]) { (store.open.map(\.text), store.done.map(\.text)) }
    /// For the checks: the height of each row now.
    var rowHeights: [CGFloat] { view.layoutSubtreeIfNeeded(); return rows.indices.map { table.rect(ofRow: $0).height } }
    var bannerText: String? { banner.isHidden ? nil : bannerLabel.stringValue }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row i: Int) -> NSView? {
        switch rows[i] {
        case .heading(let text):
            let l = NSTextField(labelWithString: text)
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return CenteredCell(l, leading: 10)
        case .reminder(let r):
            let cell = ReminderRowView(r)
            cell.onToggle = { [weak self] done in self?.mark(r.id, done) }
            cell.onText = { [weak self] text in self?.rename(r.id, text) }
            cell.onDelete = { [weak self] in self?.delete(r.id) }
            return cell
        }
    }

    private var lastWidth: CGFloat = 0
    /// What a row's text leaves for the width: the box, the ✕ and the gaps.
    private static let sideSpace: CGFloat = 64 + 6

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row), case .reminder(let r) = rows[row] else { return 30 }
        lastWidth = tableView.bounds.width
        let width = max(tableView.bounds.width - Self.sideSpace, 120)
        let h = (r.text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 14)]).height
        return max(30, ceil(h) + 14)
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    // MARK: Changing

    @discardableResult
    func add(_ text: String) -> String? {
        guard let id = try? store.add(text) else { return nil }
        addField.stringValue = ""
        reload()
        onChange?()
        return id
    }

    func mark(_ id: String, _ done: Bool) {
        try? store.setDone(id, done)
        reload()
        onChange?()
    }

    func rename(_ id: String, _ text: String) {
        let current = store.reminders.first { $0.id == id }?.text
        // An emptied text keeps the old one: deleting is the ✕.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == current { reload(); return }
        try? store.setText(id, text)
        reload()
        onChange?()
    }

    func delete(_ id: String) {
        guard let r = store.reminders.first(where: { $0.id == id }), (try? store.delete(id)) != nil else { return }
        reload()
        bannerLabel.stringValue = L("Deleted “{text}”", ["text": String(r.text.prefix(40))])
        banner.isHidden = false
        bannerTimer?.invalidate()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in self?.banner.isHidden = true }
        onChange?()
    }

    @objc private func undoPressed() { undoDelete() }

    func undoDelete() {
        _ = try? store.undoDelete()
        banner.isHidden = true
        bannerTimer?.invalidate()
        reload()
        onChange?()
    }

    /// A text being changed in a row is finished (and so saved) when the view is left.
    @objc func commitEdits() {
        if let editor = view.window?.firstResponder as? NSTextView, editor.isFieldEditor, editor.isDescendant(of: table) { view.window?.makeFirstResponder(nil) }
    }

    /// Shift-Return and Option-Return put a new line in the text being typed instead of finishing it.
    static func newLineWanted(_ textView: NSTextView, _ selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)),
              NSApp.currentEvent.map({ !$0.modifierFlags.intersection([.shift, .option]).isEmpty }) == true else { return false }
        textView.insertNewlineIgnoringFieldEditor(nil)
        return true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if Self.newLineWanted(textView, selector) { return true }
        if control === addField, selector == #selector(NSResponder.insertNewline(_:)) { add(addField.stringValue); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)), control === addField { onEscape?(); return true }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

/// The window shown over a book when it opens and has reminders not yet done: each can be marked there; there is nothing else to do but close it.
/// Its width is fixed: a long text wraps, it never makes the window wider.
final class RemindersPopup: NSViewController {
    static let width: CGFloat = 460
    let store: RemindersStore
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?
    private(set) var boxes: [(id: String, box: NSButton)] = []
    private(set) var labels: [NSTextField] = []

    init(store: RemindersStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let textWidth = width - 40 - 24 - 6

    /// About how tall the list is, so that the window fits what it holds (up to a limit; then the list scrolls).
    private func listHeight() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        return store.open.reduce(CGFloat(8)) { total, r in
            let h = (r.text as NSString).boundingRect(with: NSSize(width: Self.textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
            return total + ceil(h) + 8
        }
    }

    override func loadView() {
        let height = min(max(listHeight(), 40), 340) + 100
        let root = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        let title = NSTextField(labelWithString: L("Reminders"))
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        let list = NSStackView()
        list.orientation = .vertical; list.alignment = .leading; list.spacing = 8
        for r in store.open {
            let b = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggled(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(r.id)
            b.setAccessibilityLabel(r.text)
            let label = NSTextField(wrappingLabelWithString: r.text)
            label.font = .systemFont(ofSize: 13)
            label.maximumNumberOfLines = 0
            label.preferredMaxLayoutWidth = Self.textWidth
            label.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
            // A click on the text ticks the box too.
            let click = NSClickGestureRecognizer(target: self, action: #selector(textClicked(_:)))
            label.addGestureRecognizer(click)
            label.identifier = NSUserInterfaceItemIdentifier(r.id)
            let line = NSStackView(views: [b, label])
            line.orientation = .horizontal; line.alignment = .firstBaseline; line.spacing = 6
            list.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            boxes.append((r.id, b)); labels.append(label)
        }
        let scroll = NSScrollView()
        let flipped = FlippedDocument()
        list.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(list)
        flipped.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = flipped
        scroll.hasVerticalScroller = true; scroll.borderType = .noBorder; scroll.drawsBackground = false
        let close = NSButton(title: L("Close"), target: self, action: #selector(closePressed))
        close.keyEquivalent = "\r"
        close.bezelStyle = .rounded
        for v in [title, scroll, close] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.width),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 18), title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20), scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
            flipped.topAnchor.constraint(equalTo: clip.topAnchor), flipped.leadingAnchor.constraint(equalTo: clip.leadingAnchor), flipped.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            list.topAnchor.constraint(equalTo: flipped.topAnchor, constant: 4), list.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: flipped.trailingAnchor), list.bottomAnchor.constraint(equalTo: flipped.bottomAnchor, constant: -4),
            close.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20), close.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        view = root
    }

    private final class FlippedDocument: NSView { override var isFlipped: Bool { true } }

    @objc private func toggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        try? store.setDone(id, sender.state == .on)
        onChange?()
    }

    @objc private func textClicked(_ g: NSClickGestureRecognizer) {
        guard let id = g.view?.identifier?.rawValue, let box = boxes.first(where: { $0.id == id })?.box else { return }
        box.performClick(nil)
    }

    @objc func closePressed() { onClose?() }
}
