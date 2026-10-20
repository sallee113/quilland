import AppKit
import QuillandCore

enum PlanMode { case plan, events }

/// Where everything is on the canvas, worked out from the plan: the lines are columns, the story goes down, and
/// everything with the same position (`start`) is in the same row, so what happens at the same moment is level.
struct PlanLayout {
    static let columnWidth: CGFloat = 190
    static let columnGap: CGFloat = 30
    static let leftMargin: CGFloat = 24
    static let topMargin: CGFloat = 12
    static let headerHeight: CGFloat = 34
    static let cardHeight: CGFloat = 92
    static let eventHeight: CGFloat = 70
    static let rowGap: CGFloat = 20
    /// The layer below is drawn a little to the left and up of the layer on top.
    static let layerOffset = NSPoint(x: -22, y: -16)

    struct Row { var start: Int; var y: CGFloat; var height: CGFloat }

    var lineIDs: [String]
    var rows: [Row]
    var rowsTop: CGFloat { Self.topMargin + Self.headerHeight + 20 }

    func columnX(_ index: Int) -> CGFloat { Self.leftMargin + CGFloat(index) * (Self.columnWidth + Self.columnGap) }
    var columnsRight: CGFloat { columnX(max(0, lineIDs.count)) - Self.columnGap }

    func row(forStart start: Int) -> Row? { rows.first { $0.start == start } }

    /// The column a point is over (the band of a column includes half the gaps beside it).
    func lineIndex(atX x: CGFloat) -> Int? {
        for i in lineIDs.indices where x >= columnX(i) - Self.columnGap / 2 && x <= columnX(i) + Self.columnWidth + Self.columnGap / 2 { return i }
        return nil
    }

    /// What dropping at height `y` means: level with a row (its middle half), or a new row between two rows.
    func dropTarget(atY y: CGFloat) -> PlanStore.Drop {
        guard !rows.isEmpty else { return .between(nil, nil) }
        for r in rows where y >= r.y + r.height * 0.25 && y <= r.y + r.height * 0.75 { return .row(r.start) }
        for (i, r) in rows.enumerated() where y < r.y + r.height / 2 {
            return .between(i > 0 ? rows[i - 1].start : nil, r.start)
        }
        return .between(rows.last?.start, nil)
    }

    /// Builds the layout; the item being dragged is left out, so that a row it alone made does not count.
    static func make(from store: PlanStore, excluding excluded: String? = nil, hidden: Set<String> = []) -> PlanLayout {
        let lineIDs = store.visibleLines.compactMap(\.id)
        var hasCard: [Int: Bool] = [:]
        for card in store.cards.values where card.id != excluded && !hidden.contains(card.id ?? "") {
            if card.line != nil, let s = card.start { hasCard[s] = true }
        }
        var starts = Set(hasCard.keys)
        for e in store.entries where e.event != excluded && !hidden.contains(e.event ?? "") { if let s = e.start { starts.insert(s) } }
        var layout = PlanLayout(lineIDs: lineIDs, rows: [])
        var y = layout.rowsTop
        for s in starts.sorted() {
            let h = hasCard[s] == true ? cardHeight : eventHeight
            layout.rows.append(Row(start: s, y: y, height: h))
            y += h + rowGap
        }
        return layout
    }
}

/// The canvas itself: line headers, guides and the cards and events as views.
final class PlanCanvasView: NSView {
    private(set) var layout = PlanLayout(lineIDs: [], rows: [])
    private(set) var headers: [PlanLineHeaderView] = []
    private(set) var itemViews: [PlanItemView] = []
    var contextMenuProvider: ((NSPoint, NSView?) -> NSMenu?)?
    var deleteKeyHandler: (() -> Void)?
    var undoHandler: (() -> Void)?
    var redoHandler: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    func reload(store: PlanStore, mode: PlanMode, selected: Set<String>, hidden: Set<String> = [], delegate: PlanItemViewDelegate) {
        layout = PlanLayout.make(from: store, hidden: hidden)
        headers.forEach { $0.removeFromSuperview() }
        itemViews.forEach { $0.removeFromSuperview() }
        headers = []
        itemViews = []
        for (i, lane) in store.visibleLines.enumerated() {
            let h = PlanLineHeaderView(lineID: lane.id ?? "", name: lane.name ?? "", summary: lane.summary, colorName: lane.color,
                                       frame: NSRect(x: layout.columnX(i), y: PlanLayout.topMargin, width: PlanLayout.columnWidth, height: PlanLayout.headerHeight))
            h.onToggle = { [weak delegate] in (delegate as? PlanCanvasController)?.setLine(lane.id ?? "", visible: false) }
            h.onEdit = { [weak delegate] in (delegate as? PlanCanvasController)?.editLine(lane.id ?? "") }
            h.onDrop = { [weak delegate] index in (delegate as? PlanCanvasController)?.moveLine(lane.id ?? "", toVisible: index) }
            h.onMenu = { [weak delegate] in (delegate as? PlanCanvasController)?.lineMenu(lane.id ?? "") ?? NSMenu() }
            addSubview(h)
            headers.append(h)
        }
        let lineIndex = { (id: String?) -> Int? in store.visibleLines.firstIndex { $0.id == id } }
        var cardViews: [PlanItemView] = []
        var eventViews: [PlanItemView] = []
        var maxX = layout.columnsRight + 320
        var maxY = (layout.rows.last.map { $0.y + $0.height } ?? layout.rowsTop) + 240
        for id in store.cards.keys.sorted() {
            guard let card = store.cards[id], !hidden.contains(id) else { continue }
            var item = PlanItem(kind: .card, id: id, title: card.title ?? "", text: card.text ?? "", colorName: card.color, lineIndex: nil, start: card.start, floatingAt: nil)
            var frame = NSRect(x: 0, y: 0, width: PlanLayout.columnWidth, height: PlanLayout.cardHeight)
            if let li = lineIndex(card.line), let s = card.start, let row = layout.row(forStart: s) {
                item.lineIndex = li
                frame.origin = NSPoint(x: layout.columnX(li), y: row.y)
            } else {
                let p = NSPoint(x: CGFloat(card.x ?? 0), y: CGFloat(card.y ?? 0))
                item.floatingAt = p
                frame.origin = p
                maxX = max(maxX, p.x + PlanLayout.columnWidth + 40)
                maxY = max(maxY, p.y + PlanLayout.cardHeight + 40)
            }
            let v = PlanItemView(item: item, frame: frame)
            cardViews.append(v)
        }
        for entry in store.entries {
            guard let event = entry.event, !hidden.contains(event), let li = lineIndex(entry.lane), let s = entry.start, let row = layout.row(forStart: s) else { continue }
            let item = PlanItem(kind: .event, id: event, title: store.events[event] ?? "(event)", text: "", colorName: store.eventColors[event], lineIndex: li, start: s, floatingAt: nil)
            let v = PlanItemView(item: item, frame: NSRect(x: layout.columnX(li), y: row.y, width: PlanLayout.columnWidth, height: PlanLayout.eventHeight))
            eventViews.append(v)
        }
        // Positions never depend on the mode: the real events are always a little to the left and up of the cards. Only which layer is on top
        // (and which is grayed) changes when the mode does.
        for v in eventViews { v.frame.origin.x += PlanLayout.layerOffset.x; v.frame.origin.y += PlanLayout.layerOffset.y }
        let lower = mode == .plan ? eventViews : cardViews
        let upper = mode == .plan ? cardViews : eventViews
        for v in lower { v.isTopLayer = false }
        for v in lower + upper {
            v.delegate = delegate
            v.isSelected = selected.contains(v.item.id)
            addSubview(v)
            itemViews.append(v)
        }
        lineColors = store.visibleLines.map { PlanColors.color($0.color) }
        frame.size = NSSize(width: maxX, height: maxY)
        needsDisplay = true
    }

    var lineColors: [NSColor] = []
    /// While a card or event is dragged: the line it would join, and where in it (a row to be level with, or a gap for a new row).
    struct DropHint: Equatable { var lineIndex: Int; var rowRect: NSRect?; var gapY: CGFloat? }
    var dropHint: DropHint? { didSet { if dropHint != oldValue { needsDisplay = true } } }

    override func draw(_ dirtyRect: NSRect) {
        // Each plot line: a tinted band the width of its column, and a clear line down its middle with a dot at every row.
        for i in layout.lineIDs.indices {
            let color = i < lineColors.count ? lineColors[i] : NSColor.systemGray
            let x = layout.columnX(i)
            let top = PlanLayout.topMargin + PlanLayout.headerHeight
            color.withAlphaComponent(dropHint?.lineIndex == i ? 0.2 : 0.07).setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 8, y: top, width: PlanLayout.columnWidth + 16, height: max(0, bounds.height - top - 8)), xRadius: 8, yRadius: 8).fill()
            let mid = x + PlanLayout.columnWidth / 2
            color.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: mid, y: top))
            path.line(to: NSPoint(x: mid, y: bounds.height - 8))
            path.lineWidth = 2
            path.stroke()
            color.setFill()
            for r in layout.rows { NSBezierPath(ovalIn: NSRect(x: mid - 4, y: r.y - 14, width: 8, height: 8)).fill() }
            if let hint = dropHint, hint.lineIndex == i {
                color.setStroke()
                if let r = hint.rowRect {
                    let p = NSBezierPath(roundedRect: r.insetBy(dx: -4, dy: -4), xRadius: 10, yRadius: 10)
                    p.lineWidth = 2
                    p.setLineDash([5, 3], count: 2, phase: 0)
                    p.stroke()
                } else if let y = hint.gapY {
                    let p = NSBezierPath()
                    p.move(to: NSPoint(x: x - 4, y: y)); p.line(to: NSPoint(x: x + PlanLayout.columnWidth + 4, y: y))
                    p.lineWidth = 3
                    p.stroke()
                }
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return contextMenuProvider?(point, hitTest(point) === self ? nil : hitTest(point))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { deleteKeyHandler?() } else { super.keyDown(with: event) }
    }

    /// A click on empty canvas (a click with ⌘ or Shift is not a clearing one).
    var backgroundClickHandler: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.modifierFlags.intersection([.command, .shift]).isEmpty { backgroundClickHandler?() }
    }

    @objc func undo(_ sender: Any?) { undoHandler?() }
    @objc func redo(_ sender: Any?) { redoHandler?() }
}

/// The Plan view: the canvas in a scroll view that zooms, and everything the author does on it.
final class PlanCanvasController: NSViewController, PlanItemViewDelegate {
    let store: PlanStore
    let scrollView = NSScrollView()
    let canvas = PlanCanvasView()
    private(set) var mode = PlanMode.plan
    /// The card or event the author acted on last; a click on another makes it the only one chosen, ⌘- or Shift-click adds to the choice.
    private(set) var selectedID: String? {
        didSet { if !changingSelection { selection = selectedID.map { [$0] } ?? [] } }
    }
    private(set) var selection: Set<String> = []
    private var changingSelection = false
    var onChange: (() -> Void)?
    /// The colour of a real event is kept in the event's own file: whoever holds the events reads them again.
    var onEventsChanged: (() -> Void)?
    /// Over the canvas: the mode, + Line, + Card and the zoom (the Plan view of the application; the Lab has its own).
    var showsControls = false
    private let modeControl = Hover.segments(NSSegmentedControl(labels: [L("Plan"), L("Events")], trackingMode: .selectOne, target: nil, action: nil))
    private var undoStack: [(label: String, state: PlanStore.State)] = []
    private var redoStack: [(label: String, state: PlanStore.State)] = []
    private let banner = NSVisualEffectView()
    private let bannerLabel = NSTextField(labelWithString: "")
    private let bannerButton = NSButton(title: L("Undo"), target: nil, action: nil)
    private var bannerTimer: Timer?
    /// The text of the banner that is showing, or nil.
    private(set) var bannerText: String?

    init(store: PlanStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 3
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.documentView = canvas
        selectionNoteLabel.font = .systemFont(ofSize: 12, weight: .medium)
        selectionNoteLabel.textColor = .secondaryLabelColor
        selectionNoteLabel.isHidden = true
        canvas.contextMenuProvider = { [weak self] point, view in self?.menu(at: point, over: view) }
        canvas.deleteKeyHandler = { [weak self] in self?.deleteSelected() }
        canvas.backgroundClickHandler = { [weak self] in self?.clearSelection() }
        canvas.undoHandler = { [weak self] in self?.undo() }
        canvas.redoHandler = { [weak self] in self?.redo() }
        let container = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        banner.material = .hudWindow
        banner.blendingMode = .withinWindow
        banner.wantsLayer = true
        banner.layer?.cornerRadius = 8
        banner.isHidden = true
        bannerLabel.font = .systemFont(ofSize: 12)
        bannerButton.target = self
        bannerButton.action = #selector(bannerUndo)
        bannerButton.bezelStyle = .inline
        for v in [bannerLabel, bannerButton] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; banner.addSubview(v) }
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        var scrollTop = scrollView.topAnchor.constraint(equalTo: container.topAnchor)
        if showsControls {
            func button(_ title: String, _ action: Selector) -> NSButton { let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; return b }
            modeControl.target = self
            modeControl.action = #selector(modeSegmentChanged)
            modeControl.selectedSegment = mode == .plan ? 0 : 1
            let bar = NSStackView(views: [modeControl, button(L("+ Line"), #selector(addLineAction)), button(L("+ Card"), #selector(addCardAction)),
                                          button("−", #selector(zoomOutAction)), button("+", #selector(zoomInAction)), button(L("Fit"), #selector(fitAction)),
                                          linesButton, NSTextField(labelWithString: L("Show from")), fromPopup, selectionNoteLabel])
            fromPopup.target = self; fromPopup.action = #selector(fromChanged)
            fillFromPopup()
            bar.spacing = 8
            bar.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(bar)
            NSLayoutConstraint.activate([bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 8), bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12)])
            scrollTop = scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8)
        }
        NSLayoutConstraint.activate([
            scrollTop, scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor), banner.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            bannerLabel.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14), bannerLabel.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            bannerButton.leadingAnchor.constraint(equalTo: bannerLabel.trailingAnchor, constant: 12), bannerButton.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -10),
            bannerButton.centerYAnchor.constraint(equalTo: banner.centerYAnchor), banner.heightAnchor.constraint(equalToConstant: 34),
        ])
        view = container
        // A pinch zoom goes around the pointer; when it ends, the selected card is brought back into view if it was left out.
        NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main) { [weak self] _ in self?.keepSelectionVisible() }
        reload()
    }

    /// Where the plan starts (a section id of the book), and what that hides. Set by the book's window.
    var showFrom: String? { didSet { if showFrom != oldValue { fromPopupSync(); reload() } } }
    var sectionChoices: [(id: String, title: String, depth: Int)] = [] { didSet { fillFromPopup() } }
    var hiddenFor: (String) -> Set<String> = { _ in [] }
    var onShowFromChanged: ((String?) -> Void)?
    private(set) var hidden: Set<String> = []
    private let fromPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let linesButton = NSPopUpButton(frame: .zero, pullsDown: true)

    private func fillFromPopup() {
        fromPopup.removeAllItems()
        fromPopup.addItem(withTitle: L("Whole book")); fromPopup.lastItem?.representedObject = ""
        for c in sectionChoices {
            fromPopup.addItem(withTitle: String(repeating: "   ", count: c.depth) + c.title)
            fromPopup.lastItem?.representedObject = c.id
        }
        fromPopupSync()
    }

    private func fromPopupSync() {
        let i = fromPopup.itemArray.firstIndex { ($0.representedObject as? String) == (showFrom ?? "") } ?? 0
        fromPopup.selectItem(at: i)
    }

    @objc private func fromChanged() {
        let id = fromPopup.selectedItem?.representedObject as? String
        let chosen = (id?.isEmpty ?? true) ? nil : id
        showFrom = chosen
        onShowFromChanged?(chosen)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func reload() {
        hidden = showFrom.map(hiddenFor) ?? []
        // What stands on a line that is switched off is left out too, so that the columns close up.
        let off = Set(store.lines.filter(\.isHidden).compactMap(\.id))
        if !off.isEmpty {
            for e in store.entries { if let ev = e.event, let l = e.lane, off.contains(l) { hidden.insert(ev) } }
            for (id, card) in store.cards { if let l = card.line, off.contains(l) { hidden.insert(id) } }
        }
        fillLinesMenu()
        if let id = selectedID, hidden.contains(id) { selectedID = nil }
        selection = selection.filter { !hidden.contains($0) && (store.cards[$0] != nil || store.events[$0] != nil) }
        canvas.reload(store: store, mode: mode, selected: selection, hidden: hidden, delegate: self)
        updateSelectionNote()
        onChange?()
    }

    // MARK: Undo

    /// Remembers the plan as it is, before an operation changes it.
    private func registerUndo(_ label: String) {
        undoStack.append((label, store.captureState()))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var undoLabel: String? { undoStack.last?.label }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append((last.label, store.captureState()))
        attempt { try store.restore(last.state) }
        if let id = selectedID, store.cards[id] == nil, store.events[id] == nil { selectedID = nil }
        hideBanner()
        onEventsChanged?()
        reload()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((next.label, store.captureState()))
        attempt { try store.restore(next.state) }
        hideBanner()
        onEventsChanged?()
        reload()
    }

    @objc private func bannerUndo() { undo() }

    /// Does a change to the plan's files. A failure (a full disk, a folder that cannot be written) is told in the banner; it used to be dropped without a word.
    @discardableResult
    private func attempt<T>(_ work: () throws -> T) -> T? {
        do { return try work() } catch {
            showBanner(L("That could not be saved: {error}", ["error": "\(error)"]))
            return nil
        }
    }

    private func showBanner(_ text: String) {
        bannerText = text
        bannerLabel.stringValue = text
        banner.isHidden = false
        bannerTimer?.invalidate()
        bannerTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in self?.hideBanner() }
    }

    private func hideBanner() {
        bannerTimer?.invalidate()
        banner.isHidden = true
        bannerText = nil
    }

    func setMode(_ new: PlanMode) {
        guard new != mode else { return }
        mode = new
        modeControl.selectedSegment = mode == .plan ? 0 : 1
        reload()
    }

    @objc private func modeSegmentChanged() { setMode(modeControl.selectedSegment == 0 ? .plan : .events) }
    @objc private func addLineAction() { addLine() }
    @objc private func addCardAction() { addCard() }
    @objc private func zoomOutAction() { zoomOut() }
    @objc private func zoomInAction() { zoomIn() }
    @objc private func fitAction() { zoomToFit() }

    // MARK: Clicking and dragging

    /// A card opens its edit window; an event opens in the Events view.
    func itemDoubleClicked(_ view: PlanItemView) {
        if view.item.kind == .card { editCard(view.item.id) } else { onOpenEvent?(view.item.id) }
    }

    var onOpenEvent: ((String) -> Void)?

    /// A small window for a card: its title, text and color.
    func editCard(_ id: String) {
        guard let card = store.cards[id] else { return }
        let alert = NSAlert()
        alert.messageText = L("Edit Card")
        let titleField = NSTextField(frame: NSRect(x: 0, y: 150, width: 340, height: 24))
        titleField.stringValue = card.title ?? ""
        titleField.placeholderString = L("Title")
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 340, height: 80))
        textView.string = card.text ?? ""
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 40, width: 340, height: 100))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let colors = PlanColors.palette
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 8, width: 160, height: 26), pullsDown: false)
        for (name, title) in colors { popup.addItem(withTitle: title); popup.lastItem?.representedObject = name; popup.lastItem?.image = PlanColors.swatch(name) }
        popup.selectItem(at: colors.firstIndex { $0.0 == (card.color ?? "indigo") } ?? colors.count - 1)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 178))
        [titleField, scroll, popup].forEach(box.addSubview)
        alert.accessoryView = box
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = titleField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = popup.selectedItem?.representedObject as? String
        let newTitle = title.isEmpty ? (card.title ?? "") : title
        guard newTitle != (card.title ?? "") || textView.string != (card.text ?? "") || color != (card.color ?? "indigo") else { return }
        registerUndo(L("Edit Card"))
        attempt { try store.updateCard(id) { $0.title = newTitle; $0.text = textView.string.isEmpty ? nil : textView.string; $0.color = color } }
        reload()
    }

    func itemClicked(_ view: PlanItemView) {
        let flags = view.clickModifiers
        click(view, extending: flags.contains(.command) || flags.contains(.shift))
    }

    /// A click on a card or an event: it becomes the chosen one, or with ⌘ or Shift it is added to the chosen ones (or taken out of them).
    func click(_ view: PlanItemView, extending: Bool) {
        let id = view.item.id
        if extending {
            if selection.contains(id) {
                setSelection(selection.subtracting([id]), primary: selection.subtracting([id]).first)
            } else {
                setSelection(selection.union([id]), primary: id)
            }
        } else {
            setSelection([id], primary: id)
        }
        // The mode follows what is clicked: a card means the plan, an event means the real events.
        let wanted: PlanMode = view.item.kind == .card ? .plan : .events
        if wanted != mode { mode = wanted; modeControl.selectedSegment = mode == .plan ? 0 : 1; reload() } else { canvas.itemViews.forEach { $0.isSelected = selection.contains($0.item.id) } }
        view.window?.makeFirstResponder(canvas)
    }

    private func setSelection(_ ids: Set<String>, primary: String?) {
        changingSelection = true
        selectedID = primary
        selection = ids
        changingSelection = false
        updateSelectionNote()
    }

    /// A click on empty canvas: nothing is chosen.
    func clearSelection() {
        guard !selection.isEmpty || selectedID != nil else { return }
        setSelection([], primary: nil)
        canvas.itemViews.forEach { $0.isSelected = false }
    }

    private let selectionNoteLabel = NSTextField(labelWithString: "")

    /// "3 chosen" in the toolbar while two or more are chosen.
    private func updateSelectionNote() {
        let n = selection.count
        selectionNoteLabel.stringValue = n >= 2 ? Lp("{n} chosen", "{n} chosen", n) : ""
        selectionNoteLabel.isHidden = n < 2
    }

    /// For the checks: the note in the toolbar, or nil when it is not shown.
    var selectionNote: String? { selectionNoteLabel.isHidden ? nil : selectionNoteLabel.stringValue }

    func itemDragged(_ view: PlanItemView) {
        // Shows where the item would go if it were let go now: the line it would join, level with a row or in a new row between two.
        let layout = PlanLayout.make(from: store, excluding: view.item.id, hidden: hidden)
        guard let li = layout.lineIndex(atX: view.frame.midX), view.frame.midY >= layout.rowsTop - 20 else { canvas.dropHint = nil; return }
        switch layout.dropTarget(atY: view.frame.midY) {
        case .row(let start):
            let r = layout.row(forStart: start)!
            canvas.dropHint = PlanCanvasView.DropHint(lineIndex: li, rowRect: NSRect(x: layout.columnX(li), y: r.y, width: PlanLayout.columnWidth, height: r.height), gapY: nil)
        case .between(let a, let b):
            let above = a.flatMap { layout.row(forStart: $0) }, below = b.flatMap { layout.row(forStart: $0) }
            let y = above.map { $0.y + $0.height + PlanLayout.rowGap / 2 } ?? (below.map { $0.y - PlanLayout.rowGap / 2 } ?? layout.rowsTop)
            canvas.dropHint = PlanCanvasView.DropHint(lineIndex: li, rowRect: nil, gapY: y)
        }
    }

    func itemDropped(_ view: PlanItemView) {
        canvas.dropHint = nil
        apply(drop: view.frame, of: view.item)
    }

    /// What a drop does (also called directly by the tests). The frame is where the dragged item was let go.
    func apply(drop frame: NSRect, of item: PlanItem) {
        registerUndo("Move")
        let layout = PlanLayout.make(from: store, excluding: item.id, hidden: hidden)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        do {
            if let li = layout.lineIndex(atX: center.x), center.y >= layout.rowsTop - 20, let line = store.visibleLines[li].id {
                let start = try store.resolve(layout.dropTarget(atY: center.y))
                switch item.kind {
                case .card: try store.updateCard(item.id) { $0.place(onLine: line, start: start) }
                case .event: try store.placeEvent(item.id, onLine: line, start: start)
                }
            } else if item.kind == .card {
                try store.updateCard(item.id) { $0.float(x: max(0, Int(frame.minX)), y: max(0, Int(frame.minY))) }
            }
        } catch { NSSound.beep() }
        reload()
    }

    // MARK: Adding and deleting

    @discardableResult
    func addLine() -> String? {
        registerUndo("New Line")
        let colors = ["teal", "pink", "amber", "green", "purple", "blue"]
        let n = store.lines.count
        let id = attempt { try store.addLine(name: L("Line {n}", ["n": n + 1]), color: colors[n % colors.count]) }
        reload()
        return id
    }

    @discardableResult
    func addCard(at point: NSPoint? = nil) -> String? {
        registerUndo(L("New Card"))
        mode = .plan
        let spot = point ?? NSPoint(x: canvas.layout.columnsRight + 60, y: scrollView.contentView.bounds.origin.y + 60)
        let id = attempt { try store.addCard(title: L("New card"), x: max(0, Int(spot.x)), y: max(0, Int(spot.y))) }
        selectedID = id
        reload()
        return id
    }

    func deleteSelected() {
        guard let id = selectedID, let card = store.cards[id] else { NSSound.beep(); return }
        registerUndo("Delete Card")
        attempt { try store.deleteCard(id) }
        showBanner(L("Deleted card “{title}”", ["title": card.title ?? ""]))
        selectedID = nil
        reload()
    }

    func renameLine(_ id: String, to name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, store.lines.first(where: { $0.id == id })?.name != text else { reload(); return }
        registerUndo(L("Rename Line"))
        attempt { try store.renameLine(id, to: text) }
        reload()
    }

    /// A small window for the line's title and its short description (a double click on the header, or the menu).
    func editLine(_ id: String) {
        guard let lane = store.lines.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = L("Edit Line")
        alert.informativeText = L("The description is a few words on what the line is about. It shows under the title.")
        let nameField = NSTextField(frame: NSRect(x: 0, y: 34, width: 320, height: 24))
        nameField.stringValue = lane.name ?? ""
        nameField.placeholderString = L("Title")
        let summaryField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        summaryField.stringValue = lane.summary ?? ""
        summaryField.placeholderString = L("Description")
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        box.addSubview(nameField); box.addSubview(summaryField)
        alert.accessoryView = box
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = summaryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (name.isEmpty ? lane.name ?? "" : name) != (lane.name ?? "") || summary != (lane.summary ?? "") else { return }
        registerUndo(L("Edit Line"))
        if !name.isEmpty { attempt { try store.renameLine(id, to: name) } }
        attempt { try store.setLineDescription(id, to: summary) }
        reload()
    }

    /// Moves a line to the place of the visible line number `index` (a header was dragged there).
    func moveLine(_ id: String, toVisible index: Int) {
        let visible = store.visibleLines.compactMap(\.id)
        let all = store.lines.compactMap(\.id)
        guard visible.indices.contains(index), let i = all.firstIndex(of: id), let j = all.firstIndex(of: visible[index]), i != j else { reload(); return }
        registerUndo(L("Move Line"))
        for _ in 0..<abs(j - i) { _ = attempt { try store.moveLine(id, by: j > i ? 1 : -1) } }
        reload()
    }

    func setLineColor(_ id: String, to color: String) {
        registerUndo(L("Line Color"))
        attempt { try store.setLineColor(id, to: color) }
        reload()
    }

    func moveLine(_ id: String, by step: Int) {
        registerUndo(L("Move Line"))
        // Hidden lines are passed over, so that one step is one visible place.
        let ids = store.lines.compactMap(\.id)
        let off = Set(store.lines.filter(\.isHidden).compactMap(\.id))
        guard let i = ids.firstIndex(of: id) else { return }
        var j = i + step
        while ids.indices.contains(j), off.contains(ids[j]) { j += step }
        guard ids.indices.contains(j) else { undoStack.removeLast(); NSSound.beep(); return }
        for _ in 0..<abs(j - i) { _ = attempt { try store.moveLine(id, by: step) } }
        reload()
    }

    func setLine(_ id: String, visible: Bool) {
        registerUndo(visible ? L("Show Line") : L("Hide Line"))
        attempt { try store.setLine(id, visible: visible) }
        reload()
    }

    /// What can be done with one line: rename, color, move, delete.
    func lineMenu(_ id: String) -> NSMenu {
        let menu = NSMenu()
        let lines = store.visibleLines, index = lines.firstIndex { $0.id == id } ?? 0
        let current = lines.first { $0.id == id }?.color
        menu.addItem(ClosureMenuItem(title: L("Edit…")) { [weak self] in self?.editLine(id) })
        let colorItem = NSMenuItem(title: L("Color"), action: nil, keyEquivalent: "")
        let colors = NSMenu()
        for (name, title) in PlanColors.palette {
            let item = ClosureMenuItem(title: title) { [weak self] in self?.setLineColor(id, to: name) }
            item.image = PlanColors.swatch(name)
            item.state = (current ?? "indigo") == name ? .on : .off
            colors.addItem(item)
        }
        colorItem.submenu = colors
        menu.addItem(colorItem)
        let left = ClosureMenuItem(title: L("Move Left")) { [weak self] in self?.moveLine(id, by: -1) }
        left.isEnabled = index > 0
        let right = ClosureMenuItem(title: L("Move Right")) { [weak self] in self?.moveLine(id, by: 1) }
        right.isEnabled = index < lines.count - 1
        menu.addItem(left); menu.addItem(right)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: L("Delete Line")) { [weak self] in self?.deleteLine(id) })
        return menu
    }

    /// The "Lines" button of the top bar: every line with a check mark, to switch each on and off.
    private func fillLinesMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Lines"), action: nil, keyEquivalent: ""))
        for lane in store.lines {
            guard let id = lane.id else { continue }
            let item = ClosureMenuItem(title: lane.name ?? "") { [weak self] in self?.setLine(id, visible: lane.isHidden) }
            item.state = lane.isHidden ? .off : .on
            menu.addItem(item)
        }
        if menu.items.count == 1 { let none = NSMenuItem(title: L("No lines"), action: nil, keyEquivalent: ""); none.isEnabled = false; menu.addItem(none) }
        linesButton.menu = menu
    }

    func deleteLine(_ id: String) {
        registerUndo("Delete Line")
        let name = store.lines.first { $0.id == id }?.name ?? ""
        defer { showBanner(L("Deleted line “{name}”", ["name": name])) }
        var places: [String: (x: Int, y: Int)] = [:]
        for v in canvas.itemViews where v.item.kind == .card {
            if store.cards[v.item.id]?.line == id { places[v.item.id] = (Int(v.frame.minX), Int(v.frame.minY)) }
        }
        attempt { try store.deleteLine(id, floatingAt: places) }
        reload()
    }

    // MARK: Zoom

    var zoom: CGFloat { scrollView.magnification }
    func zoomIn() {
        scrollView.setMagnification(min(scrollView.maxMagnification, scrollView.magnification * 1.25), centeredAt: zoomCenter)
        keepSelectionVisible()
    }

    func zoomOut() {
        scrollView.setMagnification(max(scrollView.minMagnification, scrollView.magnification / 1.25), centeredAt: zoomCenter)
        keepSelectionVisible()
    }

    /// Zooming goes around the selected card when there is one (so it stays where the author is looking), else around the middle of what is visible.
    private var zoomCenter: NSPoint {
        if let v = selectedView { return NSPoint(x: v.frame.midX, y: v.frame.midY) }
        return visibleCenter
    }

    private var selectedView: PlanItemView? {
        guard let id = selectedID else { return nil }
        return canvas.itemViews.first { $0.item.id == id && $0.isTopLayer } ?? canvas.itemViews.first { $0.item.id == id }
    }

    /// The selected card is never left outside the visible area by a change of zoom.
    func keepSelectionVisible() {
        guard let v = selectedView else { return }
        if !scrollView.documentVisibleRect.contains(v.frame) { canvas.scrollToVisible(v.frame.insetBy(dx: -40, dy: -40)) }
    }
    func zoomToFit() { scrollView.magnify(toFit: canvas.frame) }
    private var visibleCenter: NSPoint { NSPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY) }

    // MARK: Context menus

    /// The right-click menu at a point of the canvas, over a view (a card, an event, a line header) or nothing.
    func menu(at point: NSPoint, over view: NSView?) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title, action: action)
            menu.addItem(item)
        }
        var target: NSView? = view
        while let t = target, !(t is PlanItemView), !(t is PlanLineHeaderView), t !== canvas { target = t.superview }
        // A right click on one of the chosen ones is about all of them; on another it chooses that one alone.
        if let clicked = target as? PlanItemView, !selection.contains(clicked.item.id) {
            setSelection([clicked.item.id], primary: clicked.item.id)
            canvas.itemViews.forEach { $0.isSelected = selection.contains($0.item.id) }
        }
        if let event = target as? PlanItemView, event.item.kind == .event {
            menu.addItem(colorMenuItem(for: selection))
        } else if let card = target as? PlanItemView, card.item.kind == .card {
            let id = card.item.id
            // (The choice is not set here: a right click on a chosen card is about all the chosen ones, and the lines above chose this one if it was not.)
            menu.addItem(colorMenuItem(for: selection))
            menu.addItem(.separator())
            if card.item.lineIndex != nil {
                add(L("Make Floating")) { [weak self] in
                    guard let self else { return }
                    self.apply(drop: NSRect(x: self.canvas.layout.columnsRight + 60, y: card.frame.minY, width: PlanLayout.columnWidth, height: PlanLayout.cardHeight), of: card.item)
                }
            }
            for lane in store.visibleLines { if let lid = lane.id { add(L("Link to “{name}”", ["name": lane.name ?? ""])) { [weak self] in self?.link(card: id, toLine: lid) } } }
            menu.addItem(.separator())
            add(L("Delete Card")) { [weak self] in self?.selectedID = id; self?.deleteSelected() }
        } else if let header = target as? PlanLineHeaderView {
            return lineMenu(header.lineID)
        } else {
            add(L("New Card Here")) { [weak self] in self?.addCard(at: point) }
            add(L("New Line")) { [weak self] in self?.addLine() }
        }
        return menu
    }

    // MARK: Colours of the chosen cards and events

    /// "Color ▸" for the chosen cards and events: each colour with its swatch, ticked when all of them have it; "No Color" when an event is among them.
    func colorMenuItem(for ids: Set<String>) -> NSMenuItem {
        let item = NSMenuItem(title: L("Color"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let current = Set(ids.compactMap { id -> String?? in
            if let card = store.cards[id] { return .some(card.color ?? "indigo") }
            if store.events[id] != nil { return .some(store.eventColors[id]) }
            return nil
        })
        let common: String?? = current.count == 1 ? current.first : nil
        for (name, title) in PlanColors.palette {
            let entry = ClosureMenuItem(title: title) { [weak self] in self?.setColor(name, for: ids) }
            entry.image = PlanColors.swatch(name)
            if let common, common == name { entry.state = .on }
            sub.addItem(entry)
        }
        if ids.contains(where: { store.events[$0] != nil }) {
            sub.addItem(.separator())
            let none = ClosureMenuItem(title: L("No Color")) { [weak self] in self?.setColor(nil, for: ids) }
            none.image = PlanColors.swatch(nil)
            if let common, common == nil { none.state = .on }
            sub.addItem(none)
        }
        item.submenu = sub
        return item
    }

    /// Gives every chosen card and event the colour (nil takes an event's colour away; a card then has the usual one). One Undo takes it all back.
    func setColor(_ name: String?, for ids: Set<String>) {
        let targets = ids.filter { store.cards[$0] != nil || store.events[$0] != nil }
        guard !targets.isEmpty else { return }
        registerUndo(L("Color"))
        for id in targets {
            if store.cards[id] != nil { attempt { try store.updateCard(id) { $0.color = name } } }
            else { attempt { try store.setEventColor(id, to: name) } }
        }
        if targets.contains(where: { store.events[$0] != nil }) { onEventsChanged?() }
        reload()
    }

    /// Puts a card on a line at the end (after the last row).
    func link(card id: String, toLine line: String) {
        registerUndo(L("Link to Line"))
        let layout = PlanLayout.make(from: store, excluding: id, hidden: hidden)
        let start = (try? store.resolve(.between(layout.rows.last?.start, nil))) ?? PlanPositions.step
        attempt { try store.updateCard(id) { $0.place(onLine: line, start: start) } }
        reload()
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let closure: () -> Void
    init(title: String, action: @escaping () -> Void) {
        closure = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { closure() }
}
