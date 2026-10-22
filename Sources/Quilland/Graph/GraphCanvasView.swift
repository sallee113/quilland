import AppKit
import QuillandCore

/// The canvas of the Graph view: the lines, the nodes and their names, drawn by the view itself (a book can have hundreds of nodes, which is too many views).
/// A node can be dragged (and stays where it was put), clicked (it and what is joined to it are lit) or double-clicked (its card opens).
final class GraphCanvasView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private(set) var graph = BookGraph()
    /// Where each node is, in the canvas's own coordinates.
    private(set) var points: [String: CGPoint] = [:]
    /// The nodes the author has put somewhere (a ring marks them).
    var pinned: Set<String> = [] { didSet { needsDisplay = true } }
    private(set) var selected: String? { didSet { needsDisplay = true } }
    var onSelect: ((String?) -> Void)?
    /// A drag has ended: the node and where it is now.
    var onMoved: ((String, CGPoint) -> Void)?
    var onOpen: ((GraphNode) -> Void)?
    /// The right-click menu for a node (nil: the canvas itself).
    var menuProvider: ((GraphNode?) -> NSMenu?)?
    private var byID: [String: GraphNode] = [:]
    private var neighbours: Set<String> = []
    private var dragging: (id: String, grab: CGSize, moved: Bool)?

    func set(graph: BookGraph, points: [String: CGPoint]) {
        self.graph = graph
        self.points = points
        byID = Dictionary(graph.nodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        if let s = selected, byID[s] == nil { selected = nil; onSelect?(nil) }
        refreshNeighbours()
        needsDisplay = true
    }

    func select(_ id: String?) {
        guard id != selected else { return }
        selected = id
        refreshNeighbours()
        onSelect?(id)
    }

    private func refreshNeighbours() { neighbours = selected.map { graph.neighbours(of: $0) } ?? [] }

    // MARK: Looks

    static func color(_ kind: GraphKind) -> NSColor {
        switch kind {
        case .character: return .systemBlue
        case .place: return .systemGreen
        case .event: return .systemOrange
        case .scene: return .systemGray
        }
    }

    static func radius(_ kind: GraphKind) -> CGFloat { kind == .scene ? 6 : 14 }

    private func shape(_ kind: GraphKind, at c: CGPoint, grow: CGFloat = 0) -> NSBezierPath {
        let r = Self.radius(kind) + grow
        switch kind {
        case .character, .scene: return NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case .place: return NSBezierPath(roundedRect: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), xRadius: 5, yRadius: 5)
        case .event:
            let d = NSBezierPath()
            d.move(to: CGPoint(x: c.x, y: c.y - r - 3)); d.line(to: CGPoint(x: c.x + r + 3, y: c.y)); d.line(to: CGPoint(x: c.x, y: c.y + r + 3)); d.line(to: CGPoint(x: c.x - r - 3, y: c.y))
            d.close()
            return d
        }
    }

    private static func lineColor(_ kind: GraphEdge.Kind) -> NSColor {
        switch kind {
        case .relationship: return .systemPurple
        case .takesPart: return .secondaryLabelColor
        case .heldAt: return .systemGreen
        case .inScene: return .tertiaryLabelColor
        }
    }

    private func isLit(_ id: String) -> Bool { selected == nil || id == selected || neighbours.contains(id) }

    override func draw(_ dirtyRect: NSRect) {
        let labelFont = NSFont.systemFont(ofSize: 11)
        for e in graph.edges {
            guard let a = points[e.a], let b = points[e.b] else { continue }
            if !dirtyRect.insetBy(dx: -40, dy: -40).intersects(NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -1, dy: -1)) { continue }
            let lit = selected == nil || e.a == selected || e.b == selected
            let path = NSBezierPath()
            path.move(to: a); path.line(to: b)
            path.lineWidth = min(1 + CGFloat(e.weight - 1) * 0.8, 5)
            if e.kind == .inScene { path.setLineDash([3, 3], count: 2, phase: 0) }
            Self.lineColor(e.kind).withAlphaComponent(lit ? 0.9 : 0.15).setStroke()
            path.stroke()
            if e.kind == .relationship, !e.label.isEmpty, lit {
                let text = NSAttributedString(string: e.label, attributes: [.font: labelFont, .foregroundColor: NSColor.systemPurple, .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.85)])
                let size = text.size()
                text.draw(at: CGPoint(x: (a.x + b.x) / 2 - size.width / 2, y: (a.y + b.y) / 2 - size.height / 2))
            }
        }
        for n in graph.nodes {
            guard let c = points[n.id], dirtyRect.insetBy(dx: -120, dy: -40).contains(c) else { continue }
            let lit = isLit(n.id)
            let path = shape(n.kind, at: c)
            // (An opaque ground first, so that the lines under a node do not show through it.)
            NSColor.textBackgroundColor.setFill()
            path.fill()
            Self.color(n.kind).withAlphaComponent(lit ? 1 : 0.2).setFill()
            path.fill()
            // A main character has a thick border. The chosen node has a ring of the accent colour round it, so that it shows on any colour (and on a main
            // character's thick border).
            if n.id == selected {
                NSColor.labelColor.setStroke(); path.lineWidth = n.isMain ? 4 : 3; path.stroke()
                let ring = shape(n.kind, at: c, grow: n.isMain ? 7 : 6)
                NSColor.controlAccentColor.setStroke(); ring.lineWidth = 2.5; ring.stroke()
            } else if n.isMain { NSColor.labelColor.withAlphaComponent(lit ? 0.95 : 0.25).setStroke(); path.lineWidth = 4; path.stroke() }
            else if pinned.contains(n.id) { NSColor.labelColor.withAlphaComponent(lit ? 0.7 : 0.2).setStroke(); path.lineWidth = 1.5; path.stroke() }
            let title = n.title.count > 24 ? String(n.title.prefix(23)) + "…" : n.title
            let text = NSAttributedString(string: title, attributes: [.font: labelFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(lit ? 1 : 0.3), .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(lit ? 0.6 : 0)])
            let size = text.size()
            text.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y + Self.radius(n.kind) + 4))
        }
    }

    // MARK: Pointing

    /// The node under a point (the topmost, which is the last drawn).
    func node(at point: CGPoint) -> GraphNode? {
        for n in graph.nodes.reversed() {
            guard let c = points[n.id] else { continue }
            let r = Self.radius(n.kind) + 4
            if hypot(c.x - point.x, c.y - point.y) <= r { return n }
        }
        return nil
    }

    func center(of id: String) -> CGPoint? { points[id] }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        guard let n = node(at: p), let c = points[n.id] else { select(nil); return }
        select(n.id)
        if event.clickCount >= 2 { onOpen?(n); return }
        dragging = (n.id, CGSize(width: c.x - p.x, height: c.y - p.y), false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var d = dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        d.moved = true
        dragging = d
        move(d.id, to: CGPoint(x: p.x + d.grab.width, y: p.y + d.grab.height))
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragging = nil }
        guard let d = dragging, d.moved, let c = points[d.id] else { return }
        onMoved?(d.id, c)
    }

    /// Puts a node somewhere (kept inside the canvas), for the drag and for the checks.
    func move(_ id: String, to point: CGPoint) {
        guard points[id] != nil else { return }
        points[id] = CGPoint(x: min(max(20, point.x), bounds.width - 20), y: min(max(20, point.y), bounds.height - 20))
        needsDisplay = true
    }

    /// For the checks: a drag of one node, ended.
    func drag(_ id: String, to point: CGPoint) { move(id, to: point); if let c = points[id] { onMoved?(id, c) } }

    override func menu(for event: NSEvent) -> NSMenu? {
        let n = node(at: convert(event.locationInWindow, from: nil))
        if let n { select(n.id) }
        return menuProvider?(n)
    }
}
