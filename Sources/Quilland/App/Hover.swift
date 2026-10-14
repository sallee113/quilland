import AppKit

/// Reactions of what can be clicked: a row of a list is lit softly when the pointer is over it, and a borderless button gets a soft background and the pointing hand.
enum Hover {
    nonisolated(unsafe) private static var key = 0

    /// A list lights the row under the pointer (a row that cannot be chosen, such as a heading, is left alone).
    @discardableResult
    static func rows<T: NSTableView>(_ table: T) -> T {
        objc_setAssociatedObject(table, &key, RowHover(table), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return table
    }

    static func isAttached(_ view: NSView) -> Bool { objc_getAssociatedObject(view, &key) != nil }

    /// Shows a button as if the pointer were on it. For the automatic checks.
    static func simulateHover(_ view: NSView, _ inside: Bool) { (objc_getAssociatedObject(view, &key) as? ButtonHover)?.simulate(inside) }

    /// Lights a row as if the pointer were over it (-1: none). For the automatic checks.
    static func setHoveredRow(_ table: NSTableView, _ row: Int) { (objc_getAssociatedObject(table, &key) as? RowHover)?.hover(row) }

    /// A borderless button (or any small control that acts when clicked).
    @discardableResult
    static func button<T: NSView>(_ view: T, radius: CGFloat? = nil) -> T {
        objc_setAssociatedObject(view, &key, ButtonHover(view, radius: radius), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return view
    }

    /// The tint of what is under the pointer: the text's own colour, faintly, so it suits the light and the dark appearance.
    static func tint(for view: NSView) -> CGColor {
        var color = NSColor.clear.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor.withAlphaComponent(0.14).cgColor }
        return color
    }

    /// The soft light over a row: a view of its own inside the row (under the row's cells), so that the row's own drawing, above all its selection, is never touched.
    private final class RowLight: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
    }

    private final class RowHover: NSObject {
        weak var table: NSTableView?
        private var hovered = -1
        private let light = RowLight()
        private var observers: [NSObjectProtocol] = []
        private var scrollObserver: NSObjectProtocol?

        init(_ table: NSTableView) {
            self.table = table
            super.init()
            light.autoresizingMask = [.width, .height]
            table.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
            // A row that gets chosen is not lit any more (its own selection look is what shows).
            // (An outline view posts its own notification for it, a table view the table's.)
            for name in [NSTableView.selectionDidChangeNotification, NSOutlineView.selectionDidChangeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: table, queue: .main) { [weak self] _ in
                    guard let self else { return }
                    let row = self.hovered
                    self.hovered = -2
                    self.set(row)
                })
            }
        }

        deinit { (observers + (scrollObserver.map { [$0] } ?? [])).forEach { NotificationCenter.default.removeObserver($0) } }

        private func canLight(_ row: Int) -> Bool {
            guard let table, row >= 0, row < table.numberOfRows, !table.selectedRowIndexes.contains(row) else { return false }
            if table.delegate?.tableView?(table, isGroupRow: row) == true { return false }
            return table.delegate?.tableView?(table, shouldSelectRow: row) ?? true
        }

        private func set(_ row: Int) {
            guard let table, row != hovered else { return }
            light.removeFromSuperview()
            hovered = -1
            guard canLight(row), let view = table.rowView(atRow: row, makeIfNecessary: false) else { return }
            hovered = row
            light.frame = view.bounds
            view.addSubview(light, positioned: .below, relativeTo: view.subviews.first)
            light.needsDisplay = true
        }

        func hover(_ row: Int) { set(row) }

        // The system sends every message the tracking area's options ask for to the owner, and a message the owner does not answer is an exception (which ends a
        // modal dialog that is open at the time): the owner answers all three.
        @objc(mouseMoved:) func mouseMoved(with event: NSEvent) { track(event) }
        @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { track(event) }
        private func track(_ event: NSEvent) {
            guard let table else { return }
            watchScrolling()
            set(table.row(at: table.convert(event.locationInWindow, from: nil)))
        }

        /// The list scrolls under a pointer that does not move (the wheel): the row under it is another one, and the light follows.
        private func watchScrolling() {
            guard scrollObserver == nil, let clip = table?.enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                guard let self, let table = self.table, let window = table.window, self.hovered >= 0 else { return }
                let point = table.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                self.set(table.bounds.contains(point) ? table.row(at: point) : -1)
            }
        }
        @objc(mouseExited:) func mouseExited(with event: NSEvent) { set(-1) }
    }

    /// What is drawn over a button when the pointer is on it: a view of its own (laid over the button, letting every click through), so that the button's
    /// own drawing cannot wipe it.
    private final class HoverOverlay: NSView {
        var ring = false
        var radius: CGFloat = 6
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let rect = bounds.insetBy(dx: ring ? 0.75 : 0, dy: ring ? 0.75 : 0)
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.labelColor.withAlphaComponent(ring ? 0.12 : 0.16).setFill()
            path.fill()
            if ring {
                NSColor.labelColor.withAlphaComponent(0.6).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    private final class ButtonHover: NSObject {
        weak var view: NSView?
        private var observation: NSKeyValueObservation?
        private let radius: CGFloat?
        private let overlay = HoverOverlay()

        init(_ view: NSView, radius: CGFloat?) {
            self.view = view
            self.radius = radius
            super.init()
            overlay.frame = view.bounds
            overlay.autoresizingMask = [.width, .height]
            overlay.isHidden = true
            view.addSubview(overlay)
            view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
            // A control that is off is faded, so that it can be told from one that works.
            if let control = view as? NSControl {
                dim(control)
                observation = control.observe(\.isEnabled, options: [.new]) { [weak self] control, _ in self?.dim(control) }
            }
        }

        private func dim(_ control: NSControl) {
            control.alphaValue = control.isEnabled ? 1 : 0.4
            if !control.isEnabled { overlay.isHidden = true }
        }

        private var enabled: Bool { (view as? NSControl)?.isEnabled ?? true }

        /// For the automatic checks: as if the pointer came (or left).
        func simulate(_ inside: Bool) { inside ? show() : hide() }

        private func show() {
            guard let view, enabled else { return }
            overlay.frame = view.bounds
            overlay.radius = radius ?? min(view.bounds.height / 2, 9)
            // A button with a bezel gets a ring and a faint fill; a borderless one only the fill.
            if let button = view as? NSButton, button.isBordered, button.bezelStyle != .regularSquare || button is NSPopUpButton { overlay.ring = true } else { overlay.ring = false }
            overlay.isHidden = false
            overlay.needsDisplay = true
            view.needsDisplay = true
        }
        private func hide() { overlay.isHidden = true; view?.needsDisplay = true }

        @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { show() }
        @objc(mouseExited:) func mouseExited(with event: NSEvent) { hide() }
        @objc(cursorUpdate:) func cursorUpdate(with event: NSEvent) { if enabled { NSCursor.pointingHand.set() } }
    }

    // MARK: Tab strips

    /// A strip of segments (tabs) lights the segment under the pointer, unless it is the chosen one or is off.
    @discardableResult
    static func segments<T: NSSegmentedControl>(_ control: T) -> T {
        objc_setAssociatedObject(control, &key, SegmentHover(control), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return control
    }

    /// Where each segment is, in the control's own coordinates. The control gives no frames, but it is made of accessibility elements that know theirs; failing that,
    /// the segments with no width of their own share what is left.
    static func segmentFrames(of control: NSSegmentedControl) -> [NSRect] {
        let count = control.segmentCount
        guard count > 0, control.bounds.width > 0 else { return [] }
        // The control's one accessibility child is its cell, and the cell's children are the segments, each knowing its frame (on the screen).
        if let window = control.window, let cell = control.accessibilityChildren()?.first as? NSObject,
           let children = cell.value(forKey: "accessibilityChildren") as? [NSObject] {
            let frames = children.compactMap { child -> NSRect? in
                guard let screen = (child.value(forKey: "accessibilityFrame") as? NSValue)?.rectValue else { return nil }
                return control.convert(window.convertFromScreen(screen), from: nil)
            }.sorted { $0.minX < $1.minX }
            if frames.count == count { return frames }
        }
        let fixed = (0..<count).reduce(CGFloat(0)) { $0 + control.width(forSegment: $1) }
        let flexible = (0..<count).filter { control.width(forSegment: $0) == 0 }.count
        let share = flexible > 0 ? max(0, control.bounds.width - fixed) / CGFloat(flexible) : 0
        var x: CGFloat = 0
        return (0..<count).map { i in
            let w = control.width(forSegment: i) == 0 ? share : control.width(forSegment: i)
            defer { x += w }
            return NSRect(x: x, y: 0, width: w, height: control.bounds.height)
        }
    }

    /// For the automatic checks: lights a segment as if the pointer were over it (-1: none).
    static func setHoveredSegment(_ control: NSSegmentedControl, _ index: Int) { (objc_getAssociatedObject(control, &key) as? SegmentHover)?.set(index) }

    private final class SegmentOverlay: NSView {
        var rect: NSRect?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {
            guard let rect else { return }
            NSColor.labelColor.withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).fill()
        }
    }

    private final class SegmentHover: NSObject {
        weak var control: NSSegmentedControl?
        private let overlay = SegmentOverlay()
        private var hovered = -1

        init(_ control: NSSegmentedControl) {
            self.control = control
            super.init()
            overlay.frame = control.bounds
            overlay.autoresizingMask = [.width, .height]
            overlay.isHidden = true
            control.addSubview(overlay)
            control.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
        }

        func set(_ index: Int) {
            guard let control else { return }
            var index = index
            let frames = Hover.segmentFrames(of: control)
            if index < 0 || index >= frames.count || index == control.selectedSegment || !control.isEnabled || !control.isEnabled(forSegment: index) { index = -1 }
            hovered = index
            overlay.frame = control.bounds
            overlay.rect = index >= 0 ? frames[index] : nil
            overlay.isHidden = index < 0
            overlay.needsDisplay = true
        }

        private func segment(at event: NSEvent) -> Int {
            guard let control else { return -1 }
            let point = control.convert(event.locationInWindow, from: nil)
            return Hover.segmentFrames(of: control).firstIndex { $0.contains(point) } ?? -1
        }

        @objc(mouseMoved:) func mouseMoved(with event: NSEvent) { set(segment(at: event)) }
        @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { set(segment(at: event)) }
        @objc(mouseExited:) func mouseExited(with event: NSEvent) { set(-1) }
        @objc(cursorUpdate:) func cursorUpdate(with event: NSEvent) { if control?.isEnabled == true { NSCursor.pointingHand.set() } }
    }

    // MARK: Every button

    nonisolated(unsafe) private static var installed = false

    /// Every button that does something reacts to the pointer and shows when it is off (a button of the application's own windows: the system's panels keep theirs).
    static func installForAllButtons() {
        guard !installed else { return }
        installed = true
        guard let original = class_getInstanceMethod(NSButton.self, #selector(NSView.viewDidMoveToWindow)),
              let replacement = class_getInstanceMethod(NSButton.self, #selector(NSButton.hover_viewDidMoveToWindow)) else { return }
        method_exchangeImplementations(original, replacement)
    }

    static func attachIfNeeded(_ button: NSButton) {
        guard button.window != nil, !(button.window is NSPanel), button.action != nil, objc_getAssociatedObject(button, &key) == nil else { return }
        button.layer?.masksToBounds = false
        objc_setAssociatedObject(button, &key, ButtonHover(button, radius: nil), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension NSButton {
    @objc func hover_viewDidMoveToWindow() {
        hover_viewDidMoveToWindow()   // the original (the two were exchanged)
        Hover.attachIfNeeded(self)
    }
}
