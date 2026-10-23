import AppKit
import QuillandCore

/// The canvas of the Graph view: the lines, the nodes and their names, drawn by the view itself (a book can have hundreds of nodes, which is too many views).
/// A node can be dragged (and stays where it was put), clicked (it and what is joined to it are lit) or double-clicked (its card opens).
final class GraphCanvasView: NSView, NSViewToolTipOwner {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private(set) var graph = BookGraph()
    /// Where each node is, in the canvas's own coordinates.
    private(set) var points: [String: CGPoint] = [:]
    /// The nodes the author has put somewhere (a ring marks them).
    /// Colour the nodes by the plot line they are on (the plan's lines, with their colours and names), not by their kind.
    var colourByLine = false { didSet { needsDisplay = true; rebuildToolTips() } }
    var lineStyles: [String: (name: String, color: String?)] = [:] { didSet { needsDisplay = true } }
    /// Nodes can be moved (not in the arc, whose places are worked out).
    var allowsDragging = true
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
        rebuildToolTips()
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
        case .card: return .systemIndigo
        case .stage: return .systemTeal
        case .world: return .systemBrown
        }
    }

    /// A card is drawn in its colour on the plan; the others in the colour of their kind.
    static func color(of node: GraphNode) -> NSColor { node.kind == .card || (node.kind == .stage && node.color != nil) ? PlanColors.color(node.color) : color(node.kind) }

    private func lineColour(_ id: String) -> NSColor { PlanColors.color(lineStyles[id]?.color) }

    /// What a node is filled with: by plot line, an event, a card, or a character or place on one line has that line's colour; one on several keeps its own (with dots, see
    /// `dotLines`), and one on none is grey.
    func fill(of n: GraphNode) -> NSColor {
        guard colourByLine, n.kind != .scene else { return Self.color(of: n) }
        if n.lines.count == 1 { return lineColour(n.lines[0]) }
        return n.lines.isEmpty ? .systemGray : Self.color(of: n)
    }

    /// The lines a node is marked with by dots (on several lines).
    func dotLines(of n: GraphNode) -> [String] { colourByLine && (n.kind == .character || n.kind == .place) && n.lines.count > 1 ? n.lines : [] }

    static func radius(_ kind: GraphKind) -> CGFloat { kind == .scene ? 6 : (kind == .card ? 11 : (kind == .stage ? 12 : (kind == .world ? 16 : 14))) }

    private func shape(_ kind: GraphKind, at c: CGPoint, grow: CGFloat = 0) -> NSBezierPath {
        let r = Self.radius(kind) + grow
        switch kind {
        case .character, .scene: return NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case .card: return NSBezierPath(roundedRect: NSRect(x: c.x - r * 1.4, y: c.y - r, width: 2 * r * 1.4, height: 2 * r), xRadius: 3, yRadius: 3)
        case .stage: return NSBezierPath(roundedRect: NSRect(x: c.x - r * 2.2, y: c.y - r, width: 2 * r * 2.2, height: 2 * r), xRadius: 8, yRadius: 8)
        case .world: return NSBezierPath(roundedRect: NSRect(x: c.x - r * 1.6, y: c.y - r, width: 2 * r * 1.6, height: 2 * r), xRadius: 7, yRadius: 7)
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
        case .realises: return .systemOrange
        case .arc: return .controlAccentColor
        case .contains: return .systemGreen
        case .wasAt: return .systemTeal
        }
    }

    private func isLit(_ id: String) -> Bool { selected == nil || id == selected || neighbours.contains(id) }

    override func draw(_ dirtyRect: NSRect) {
        let labelFont = NSFont.systemFont(ofSize: 11)
        for e in graph.edges where !e.hidden {
            guard let a = points[e.a], let b = points[e.b] else { continue }
            if !dirtyRect.insetBy(dx: -40, dy: -40).intersects(NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -1, dy: -1)) { continue }
            let lit = (selected == nil || e.a == selected || e.b == selected) && byID[e.a]?.notYet != true && byID[e.b]?.notYet != true
            let path = NSBezierPath()
            path.move(to: a); path.line(to: b)
            path.lineWidth = min(1 + CGFloat(e.weight - 1) * 0.8, 5)
            if e.kind == .inScene { path.setLineDash([3, 3], count: 2, phase: 0) }
            if e.kind == .relationship, e.ended { path.setLineDash([7, 5], count: 2, phase: 0) }
            if e.kind == .arc, e.gap > 0 { path.setLineDash([9, 6], count: 2, phase: 0) }
            if e.kind == .wasAt { path.setLineDash([2, 4], count: 2, phase: 0) }
            (e.color.map(PlanColors.color) ?? (colourByLine && e.kind != .relationship ? e.line.map(lineColour) : nil) ?? Self.lineColor(e.kind)).withAlphaComponent(lit ? 0.9 : 0.15).setStroke()
            path.stroke()
            if !e.changes.isEmpty { drawDelta(at: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), lit: lit) }
            if !e.problems.isEmpty { drawWarning(at: warningPoint(e, a, b), lit: lit) }
            if (e.kind == .relationship || e.kind == .arc), !e.label.isEmpty, lit {
                let text = NSAttributedString(string: e.label, attributes: [.font: labelFont, .foregroundColor: e.kind == .arc ? NSColor.secondaryLabelColor : NSColor.systemPurple, .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(0.85)])
                let size = text.size()
                text.draw(at: CGPoint(x: (a.x + b.x) / 2 - size.width / 2, y: (a.y + b.y) / 2 - size.height / 2))
            }
        }
        for n in graph.nodes {
            guard let c = points[n.id], dirtyRect.insetBy(dx: -120, dy: -40).contains(c) else { continue }
            let lit = isLit(n.id) && !n.notYet
            let path = shape(n.kind, at: c, grow: n.isContext ? -4 : 0)
            // (An opaque ground first, so that the lines under a node do not show through it.)
            NSColor.textBackgroundColor.setFill()
            path.fill()
            if n.hollow {
                // A card nobody has realised: hollow, with a dashed outline in its colour.
                NSColor.textBackgroundColor.setFill(); path.fill()
                fill(of: n).withAlphaComponent(lit ? 1 : 0.3).setStroke(); path.lineWidth = 2; path.setLineDash([4, 3], count: 2, phase: 0); path.stroke(); path.setLineDash([], count: 0, phase: 0)
            } else {
                fill(of: n).withAlphaComponent(lit ? (n.isContext ? 0.6 : 1) : 0.2).setFill()
                path.fill()
            }
            // A main character has a thick border. The chosen node has a ring of the accent colour round it, so that it shows on any colour (and on a main
            // character's thick border).
            if n.id == selected {
                NSColor.labelColor.setStroke(); path.lineWidth = n.isMain ? 4 : 3; path.stroke()
                let ring = shape(n.kind, at: c, grow: n.isMain ? 7 : 6)
                NSColor.controlAccentColor.setStroke(); ring.lineWidth = 2.5; ring.stroke()
            } else if n.isMain { NSColor.labelColor.withAlphaComponent(lit ? 0.95 : 0.25).setStroke(); path.lineWidth = 4; path.stroke() }
            else if pinned.contains(n.id) { NSColor.labelColor.withAlphaComponent(lit ? 0.7 : 0.2).setStroke(); path.lineWidth = 1.5; path.stroke() }
            if !n.changes.isEmpty { drawDeltaOnNode(at: c, lit: lit) }
            if n.doesNotApply { drawWarning(at: CGPoint(x: c.x + Self.radius(n.kind) + 2, y: c.y - Self.radius(n.kind) - 2), lit: lit) }
            let dots = dotLines(of: n)
            for (i, line) in dots.prefix(8).enumerated() {
                // Small dots in the colours of the lines, along the upper edge (the name is below).
                let a = Double.pi + Double.pi * Double(i + 1) / Double(min(dots.count, 8) + 1), r = Self.radius(n.kind) + 5
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                let dot = NSBezierPath(ovalIn: NSRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
                lineColour(line).withAlphaComponent(lit ? 1 : 0.25).setFill(); dot.fill()
                NSColor.textBackgroundColor.setStroke(); dot.lineWidth = 1; dot.stroke()
            }
            let limit = n.kind == .stage ? 44 : 24
            let title = n.title.count > limit ? String(n.title.prefix(limit - 1)) + "…" : n.title
            let text = NSAttributedString(string: title, attributes: [.font: labelFont, .foregroundColor: NSColor.labelColor.withAlphaComponent(lit ? 1 : 0.3), .backgroundColor: NSColor.textBackgroundColor.withAlphaComponent(lit ? 0.6 : 0)])
            let size = text.size()
            text.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y + Self.radius(n.kind) + 4))
        }
    }


    /// The small Δ in the middle of a line that carries a change (the same sign as in the events list), on a ground of its own so that the line does not cross it.
    private func drawDelta(at p: CGPoint, lit: Bool) {
        let r: CGFloat = 8
        let ground = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        NSColor.textBackgroundColor.setFill(); ground.fill()
        NSColor.controlAccentColor.withAlphaComponent(lit ? 1 : 0.25).setStroke(); ground.lineWidth = 1; ground.stroke()
        let t = NSAttributedString(string: "Δ", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.controlAccentColor.withAlphaComponent(lit ? 1 : 0.25)])
        let s = t.size()
        t.draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2))
    }

    /// A small warning triangle (an event that does not apply, a relationship out of order).
    private func drawWarning(at p: CGPoint, lit: Bool) {
        let t = NSBezierPath()
        t.move(to: CGPoint(x: p.x, y: p.y - 7)); t.line(to: CGPoint(x: p.x + 7, y: p.y + 5)); t.line(to: CGPoint(x: p.x - 7, y: p.y + 5)); t.close()
        NSColor.systemRed.withAlphaComponent(lit ? 1 : 0.3).setFill(); t.fill()
        let mark = NSAttributedString(string: "!", attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .heavy), .foregroundColor: NSColor.white.withAlphaComponent(lit ? 1 : 0.5)])
        let s = mark.size()
        mark.draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2 + 1))
    }

    private func warningPoint(_ e: GraphEdge, _ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2 + 16, y: (a.y + b.y) / 2 - 14) }

    /// The Δ in the middle of an event's diamond.
    private func drawDeltaOnNode(at c: CGPoint, lit: Bool) {
        let t = NSAttributedString(string: "Δ", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .heavy), .foregroundColor: NSColor.black.withAlphaComponent(lit ? 0.75 : 0.2)])
        let s = t.size()
        t.draw(at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2))
    }

    // MARK: Tooltips

    private var tipTexts: [String] = []
    private var tipRects: [NSRect] = []

    /// What an event changes, what a line carries and how a relationship went, as tooltips on rectangles (the canvas draws everything itself, so there are no views to
    /// give tooltips). Made again whenever the nodes are placed or moved.
    private func rebuildToolTips() {
        removeAllToolTips()
        tipTexts = []; tipRects = []
        func add(_ rect: NSRect, _ text: String) {
            guard !text.isEmpty else { return }
            tipTexts.append(text); tipRects.append(rect)
            addToolTip(rect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: tipTexts.count))
        }
        for e in graph.edges where !e.hidden {
            guard let a = points[e.a], let b = points[e.b] else { continue }
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            if !e.problems.isEmpty { let w = warningPoint(e, a, b); add(NSRect(x: w.x - 9, y: w.y - 9, width: 18, height: 18), GraphTexts.eventWarningLines(e.problems)) }
            if !e.changes.isEmpty { add(NSRect(x: mid.x - 9, y: mid.y - 9, width: 18, height: 18), GraphTexts.summary(e.changes)) }
            else if e.kind == .relationship { add(NSRect(x: mid.x - 40, y: mid.y - 10, width: 80, height: 20), GraphTexts.periods(e.periods)) }
        }
        for n in graph.nodes {
            guard let c = points[n.id] else { continue }
            var parts: [String] = []
            if !n.detail.isEmpty { parts.append(n.detail) }
            if !n.changes.isEmpty { parts.append(GraphTexts.summary(n.changes)) }
            if n.doesNotApply { parts.append("⚠ " + GraphTexts.eventWarning) }
            if colourByLine, !n.lines.isEmpty, n.kind != .scene { parts.append(L("Plot lines: {names}", ["names": n.lines.map { lineStyles[$0]?.name ?? "" }.joined(separator: ", ")])) }
            guard !parts.isEmpty else { continue }
            let r = Self.radius(n.kind) + 4
            add(NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), n.title + "\n" + parts.joined(separator: "\n"))
        }
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        let i = Int(bitPattern: data) - 1
        return tipTexts.indices.contains(i) ? tipTexts[i] : ""
    }

    /// For the checks: the tooltips there are (text and where).
    var toolTips: [(text: String, rect: NSRect)] { zip(tipTexts, tipRects).map { ($0, $1) } }

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
        guard allowsDragging else { return }
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
        rebuildToolTips()
    }

    /// For the checks: a drag of one node, ended.
    func drag(_ id: String, to point: CGPoint) { move(id, to: point); if let c = points[id] { onMoved?(id, c) } }

    override func menu(for event: NSEvent) -> NSMenu? {
        let n = node(at: convert(event.locationInWindow, from: nil))
        if let n { select(n.id) }
        return menuProvider?(n)
    }
}
