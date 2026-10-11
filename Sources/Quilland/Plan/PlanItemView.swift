import AppKit
import QuillandCore

/// What a card or an event on the canvas is, for drawing and dragging.
struct PlanItem: Equatable {
    enum Kind { case card, event }
    var kind: Kind
    var id: String
    var title: String
    var text: String
    var colorName: String?
    /// Index of the line it sits on, nil for a floating card.
    var lineIndex: Int?
    var start: Int?
    var floatingAt: NSPoint?
}

enum PlanColors {
    static func color(_ name: String?) -> NSColor {
        switch name {
        case "teal": return .systemTeal
        case "pink": return .systemPink
        case "amber", "orange": return .systemOrange
        case "green": return .systemGreen
        case "red": return .systemRed
        case "purple": return .systemPurple
        case "blue": return .systemBlue
        default: return .systemIndigo
        }
    }
}

protocol PlanItemViewDelegate: AnyObject {
    func itemClicked(_ view: PlanItemView)
    func itemDragged(_ view: PlanItemView)
    func itemDropped(_ view: PlanItemView)
    func itemDoubleClicked(_ view: PlanItemView)
}

/// A card or an event drawn on the canvas. The one in the upper layer can be dragged; the one below is shown grayed.
final class PlanItemView: NSView {
    var item: PlanItem
    /// The upper layer casts a shadow on the one below, so that the offset between the two layers reads as depth.
    var isTopLayer = true { didSet { needsDisplay = true; layer?.shadowOpacity = isTopLayer ? 0.35 : 0 } }
    var isSelected = false { didSet { needsDisplay = true } }
    /// The pointer is over it (only the upper layer reacts: it is the one that can be taken).
    private(set) var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    weak var delegate: PlanItemViewDelegate?
    private var dragOffset = NSPoint.zero
    private var didDrag = false
    private(set) var dragStartFrame = NSRect.zero

    init(item: PlanItem, frame: NSRect) {
        self.item = item
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = CGSize(width: 2, height: -3)
        layer?.shadowRadius = 5
        layer?.shadowOpacity = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: The pointer

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { isHovered = isTopLayer }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    /// The hand that can take it.
    override func resetCursorRects() { if isTopLayer { addCursorRect(bounds, cursor: .openHand) } }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let accent = PlanColors.color(item.colorName)
        let lit = isHovered && isTopLayer
        if item.kind == .card {
            (isTopLayer ? NSColor.controlBackgroundColor : NSColor.controlBackgroundColor.withAlphaComponent(0.55)).setFill()
            path.fill()
            if lit { NSColor.labelColor.withAlphaComponent(0.09).setFill(); path.fill() }
            (isTopLayer ? accent : NSColor.tertiaryLabelColor).setStroke()
            path.lineWidth = isSelected || lit ? 2 : 1
            path.stroke()
            accent.withAlphaComponent(isTopLayer ? 1 : 0.4).setFill()
            NSRect(x: 0, y: 14, width: 4, height: bounds.height - 28).fill()
        } else {
            (isTopLayer ? NSColor.controlBackgroundColor : NSColor.windowBackgroundColor.withAlphaComponent(0.7)).setFill()
            path.fill()
            if lit { NSColor.labelColor.withAlphaComponent(0.09).setFill(); path.fill() }
            (lit ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor).setStroke()
            path.lineWidth = isSelected || lit ? 2 : 1
            path.stroke()
        }
        if isTopLayer {
            let titleColor: NSColor = .labelColor
            let title = NSAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: titleColor])
            title.draw(with: NSRect(x: 12, y: 8, width: bounds.width - 20, height: 34), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            let label = item.kind == .event ? L("event · in the book") : item.text
            let body = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
            body.draw(with: NSRect(x: 12, y: 42, width: bounds.width - 20, height: bounds.height - 48), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        } else {
            // The layer below shows its title in the strip that peeks out from under the layer on top: the events are a little to the left and up of
            // the cards, so an event shows its title along its top edge and a card (below, in Events mode) along its bottom edge.
            let small = NSAttributedString(string: (item.kind == .event ? "◧ " : "") + item.title, attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor])
            let y: CGFloat = item.kind == .event ? 2 : bounds.height - 15
            small.draw(with: NSRect(x: item.kind == .event ? 8 : 26, y: y, width: bounds.width - 34, height: 13), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    // MARK: Dragging

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        dragStartFrame = frame
        let local = superview?.convert(event.locationInWindow, from: nil) ?? .zero
        dragOffset = NSPoint(x: local.x - frame.minX, y: local.y - frame.minY)
        delegate?.itemClicked(self)
        if event.clickCount == 2 { delegate?.itemDoubleClicked(self) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTopLayer, let superview else { return }
        let local = superview.convert(event.locationInWindow, from: nil)
        if !didDrag { didDrag = true; superview.addSubview(self, positioned: .above, relativeTo: nil) }
        frame.origin = NSPoint(x: local.x - dragOffset.x, y: local.y - dragOffset.y)
        delegate?.itemDragged(self)
        autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if didDrag { delegate?.itemDropped(self) }
        didDrag = false
    }
}

/// The name of a plot line, at the top of its column.
final class PlanLineHeaderView: NSView {
    let lineID: String
    private let label = NSTextField(labelWithString: "")
    private let colorName: String?
    private let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    var onToggle: (() -> Void)?
    var onEdit: (() -> Void)?
    /// The visible place (0 is the first column) the header was let go over.
    var onDrop: ((Int) -> Void)?
    var onMenu: (() -> NSMenu)?

    private let summaryLabel = NSTextField(labelWithString: "")

    init(lineID: String, name: String, summary: String?, colorName: String?, frame: NSRect) {
        self.lineID = lineID
        self.colorName = colorName
        super.init(frame: frame)
        label.stringValue = name
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        let hasSummary = !(summary ?? "").isEmpty
        label.frame = NSRect(x: 30, y: hasSummary ? 3 : (frame.height - 16) / 2, width: frame.width - 52, height: 16)
        if hasSummary {
            summaryLabel.stringValue = summary ?? ""
            summaryLabel.font = .systemFont(ofSize: 10)
            summaryLabel.textColor = .secondaryLabelColor
            summaryLabel.lineBreakMode = .byTruncatingTail
            summaryLabel.frame = NSRect(x: 30, y: 19, width: frame.width - 52, height: 12)
            addSubview(summaryLabel)
            toolTip = (name.isEmpty ? "" : name + "\n") + (summary ?? "")
        }
        addSubview(label)
        check.state = .on
        check.target = self; check.action = #selector(checkClicked)
        check.setAccessibilityLabel(L("Show or hide the line"))
        check.frame = NSRect(x: 8, y: (frame.height - 18) / 2, width: 20, height: 18)
        addSubview(check)
    }

    @objc private func checkClicked() { onToggle?() }

    private(set) var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    /// The hand that can take the header (sideways), and the pointing hand over the arrow that opens its menu.
    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 0, width: max(0, bounds.width - 28), height: bounds.height), cursor: .openHand)
        addCursorRect(NSRect(x: max(0, bounds.width - 28), y: 0, width: 28, height: bounds.height), cursor: .pointingHand)
    }

    // The checkbox takes its own click; the rest of the header is this view's: a double click edits the line, the arrow opens the menu,
    // and dragging sideways moves the line to another place among the others.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if check.frame.contains(p) { return check }
        return bounds.contains(p) ? self : nil
    }

    private var dragStartX: CGFloat = 0
    private var originX: CGFloat = 0
    private var dragging = false

    private func canvasX(_ event: NSEvent) -> CGFloat { superview?.convert(event.locationInWindow, from: nil).x ?? 0 }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 { onEdit?(); return }
        if p.x > bounds.width - 28, let menu = onMenu?() {
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.width - 20, y: bounds.height), in: self)
            return
        }
        dragStartX = canvasX(event); originX = frame.origin.x; dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let canvas = superview as? PlanCanvasView else { return }
        let dx = canvasX(event) - dragStartX
        if !dragging && abs(dx) < 4 { return }
        dragging = true
        alphaValue = 0.75
        frame.origin.x = max(0, originX + dx)
        autoscroll(with: event)
        canvas.dropHint = canvas.layout.lineIndex(atX: frame.midX).map { PlanCanvasView.DropHint(lineIndex: $0, rowRect: nil, gapY: nil) }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging, let canvas = superview as? PlanCanvasView else { return }
        dragging = false
        alphaValue = 1
        let target = canvas.layout.lineIndex(atX: frame.midX)
        canvas.dropHint = nil
        if let target, target != canvas.layout.lineIDs.firstIndex(of: lineID) { onDrop?(target) } else { frame.origin.x = originX }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let c = PlanColors.color(colorName)
        c.withAlphaComponent(isHovered ? 0.32 : 0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        NSAttributedString(string: "▾", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: c]).draw(at: NSPoint(x: bounds.width - 16, y: (bounds.height - 14) / 2))
    }
}
