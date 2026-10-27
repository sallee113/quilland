import Foundation

/// The arc of one character as a graph of its own (quilland-change-events.md, the graph): the events that concern them in the order of the book, as a **spine** that
/// runs from the top left to the bottom right; the **states** the character passes through hang on the upper right of the events that make them; the characters they
/// are in relationship with, and the places of the events, hang on the lower left. The nodes have their places already: the picture is the same every time.
public struct ArcGraph: Sendable {
    public var graph = BookGraph()
    public var positions: [String: GraphPoint] = [:]

    /// The layout with its main line in the direction asked for. The builders draw the line from the top left to the bottom right; the whole picture is turned about its
    /// start, so its shape stays the same.
    public func rotated(_ direction: GraphDirection) -> ArcGraph {
        guard direction != .diagonal else { return self }
        // The main line runs along (175, 110); a quarter turn more makes it vertical.
        let line = atan2(GraphDirection.step.y, GraphDirection.step.x)
        let angle = direction == .horizontal ? -line : Double.pi / 2 - line
        let c = cos(angle), s = sin(angle)
        let origin = GraphDirection.origin
        var out = self
        out.positions = positions.mapValues { p in
            let dx = p.x - origin.x, dy = p.y - origin.y
            return GraphPoint(x: origin.x + dx * c - dy * s, y: origin.y + dx * s + dy * c)
        }
        return out
    }
}

/// Which way the main line of a computed view (the arc, the locations, the plan map) runs.
public enum GraphDirection: String, CaseIterable, Sendable {
    /// From the top left to the bottom right.
    case diagonal
    case horizontal
    case vertical

    static let origin = GraphPoint(x: 80, y: 80)
    static let step = GraphPoint(x: 175, y: 110)
}

public enum ArcBuilder {
    /// A state node's id: `state:start` for the card as it is, `state:<event id>` for what an event makes of it.
    public static func stateID(_ event: String?) -> String { "state:" + (event ?? "start") }
    public static func event(ofState id: String) -> String? { id.hasPrefix("state:") && id != "state:start" ? String(id.dropFirst(6)) : nil }

    /// A gap shows on the spine when more scenes than this lie between two events of the character.
    public static let gapScenes = 3

    public static func build(character id: String, characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore, structure: BookStructure) -> ArcGraph {
        guard let card = characters.character(id) else { return ArcGraph() }
        let sceneOrder = structure.scenes.map(\.id)
        let scenePos = Dictionary(sceneOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let timeline = RelationshipTimeline(events: events, sceneOrder: sceneOrder)
        let startID = events.startEvent?.id
        func scene(_ e: EventRecord) -> Int? { e.links.keys.compactMap { scenePos[$0] }.min() }

        // The events that concern the character: they take part, the event changes them, or it starts, changes or ends one of their relationships.
        let mine = relationships.relationships(of: id)
        var wanted = Set<String>()
        for e in events.events { if let eid = e.id, e.characters[id] != nil || !e.effect(of: id).isEmpty { wanted.insert(eid) } }
        for r in mine { if let rid = r.id { let m = timeline.marks(of: rid); for e in [m.start, m.end].compactMap({ $0 }) + m.changes where e != startID { wanted.insert(e) } } }
        let spine = events.ordered(sceneOrder: sceneOrder).filter { $0.id.map(wanted.contains) == true }

        var graph = BookGraph()
        var pos: [String: GraphPoint] = [:]
        func node(_ n: GraphNode, at p: GraphPoint) { guard pos[n.id] == nil else { return }; graph.nodes.append(n); pos[n.id] = p }
        func edge(_ a: String, _ b: String, _ kind: GraphEdge.Kind, label: String = "", weight: Int = 1) -> GraphEdge { GraphEdge(a: a, b: b, kind: kind, label: label, weight: weight) }

        // The spine runs down and to the right; a gap of scenes stretches it a little (up to a limit), so that an absence shows as distance too.
        let step = (x: 175.0, y: 110.0)
        var along: [String: Double] = [id: 0]
        var cumulative = 0.0
        var previousScene: Int?
        var previous = id
        var gaps: [String: Int] = [:]
        for e in spine {
            guard let eid = e.id else { continue }
            let here = scene(e)
            var factor = 1.0
            var gap = 0
            if let h = here {
                if let p = previousScene { gap = h - p - 1 } else { gap = h }   // (the first event: the scenes before it, with none of theirs)
                if gap > Self.gapScenes { factor += min(1.5, Double(gap) / 6) } else { gap = 0 }
                previousScene = h
            } else { factor = 1.3 }
            cumulative += factor
            along[eid] = cumulative
            gaps[eid] = gap
        }
        func spinePoint(_ s: Double) -> GraphPoint { GraphPoint(x: 80 + step.x * s, y: 80 + step.y * s) }

        var me = GraphNode(id: id, kind: .character, title: card.name ?? "", isMain: card.main)
        me.anchored = true
        node(me, at: spinePoint(0))

        // The spine.
        var eventNodes: [String: EventRecord] = [:]
        for e in spine {
            guard let eid = e.id else { continue }
            var n = GraphNode(id: eid, kind: .event, title: e.title ?? "", changes: GraphBuilder.changes(of: e, characters: characters, worlds: worlds, relationships: relationships))
            let applies = scene(e) != nil
            n.doesNotApply = e.changesSomething && !applies
            n.notYet = !applies
            n.anchored = true
            node(n, at: spinePoint(along[eid] ?? cumulative))
            var line = edge(previous, eid, .arc, weight: 4)
            if let g = gaps[eid], g > 0 { line.gap = g; line.label = Lp("{n} scene without them", "{n} scenes without them", g) }
            graph.edges.append(line)
            previous = eid
            eventNodes[eid] = e
        }

        // The states, in a second line above the spine: the card as it is, then what each event makes of it.
        func snippet(_ text: String) -> String { let one = text.replacingOccurrences(of: "\n", with: " "); return one.count > 60 ? String(one.prefix(59)) + "…" : one }
        let base = characters.profile(id).trimmingCharacters(in: .whitespacesAndNewlines)
        var running = (profile: base, main: card.main)
        func stateNode(_ event: String?, title: String, detail: String, main: Bool, changes: [GraphChange], at spineAt: Double) {
            var s = GraphNode(id: Self.stateID(event), kind: .stage, title: title, isMain: main)
            s.detail = detail; s.changes = changes
            let p = spinePoint(spineAt)
            node(s, at: GraphPoint(x: p.x + 85, y: p.y - 125))
        }
        stateNode(nil, title: base.isEmpty ? L("no profile yet") : snippet(base), detail: base, main: running.main, changes: [], at: 0)
        var lastState = Self.stateID(nil)
        graph.edges.append(edge(id, lastState, .arc))
        for e in spine {
            guard let eid = e.id, scene(e) != nil || !e.effect(of: id).isEmpty else { continue }
            let effect = e.effect(of: id)
            guard !effect.isEmpty else { continue }
            var parts: [String] = []
            if let text = e.effectText(.profile, of: id) { running.profile = text; parts.append(text) }
            let names = e.effectList(.aliases, of: id)
            if !names.isEmpty { parts.append(L("also called {names}", ["names": names.joined(separator: ", ")])) }
            if let flag = e.effectFlag(of: id) { running.main = flag; parts.append(flag ? L("becomes a main character") : L("stops being a main character")) }
            guard !parts.isEmpty else { continue }
            let change = GraphBuilder.change(of: e, target: id, characters: characters, worlds: worlds, relationships: relationships)
            stateNode(eid, title: snippet(parts.joined(separator: " · ")), detail: parts.joined(separator: "\n"), main: running.main, changes: change.map { [$0] } ?? [], at: along[eid] ?? cumulative)
            let s = Self.stateID(eid)
            graph.edges.append(edge(lastState, s, .arc, weight: 2))
            graph.edges.append(edge(eid, s, .arc))
            lastState = s
        }

        // The relationships, below the spine: the other character is joined to the event where the relationship starts (to the character itself when it starts with the book).
        var below: [String: Int] = [:]
        var partnerEdges: [String: GraphEdge] = [:]
        var partnerOrder: [String] = []
        for r in mine {
            guard let rid = r.id else { continue }
            let marks = timeline.marks(of: rid)
            let anchor = marks.start.flatMap { $0 == startID || eventNodes[$0] == nil ? nil : $0 } ?? id
            for other in r.characters where other != id {
                guard let partner = characters.character(other), let pid = partner.id else { continue }
                let slot = below[anchor, default: 0]
                if pos[pid] == nil { below[anchor] = slot + 1 }
                let p = spinePoint(along[anchor] ?? 0)
                node(GraphNode(id: pid, kind: .character, title: partner.name ?? "", isMain: partner.main), at: GraphPoint(x: p.x - 95 - 95 * Double(slot), y: p.y + 95 + 25 * Double(slot)))
                var kinds = [r.kind ?? ""]
                for ev in marks.changes { if let k = events.event(ev)?.effect(of: rid).string(EffectField.kind.rawValue), k != kinds.last { kinds.append(k) } }
                func title(_ e: String?) -> String? { e.flatMap { events.event($0) }.map { $0.title ?? "" } }
                let period = GraphPeriod(kinds: kinds, from: marks.start.flatMap { $0 == startID ? nil : title($0) }, to: title(marks.end))
                let key = pid + "|" + anchor
                var e = partnerEdges[key] ?? edge(pid, anchor, .relationship)
                let label = kinds.filter { !$0.isEmpty }.joined(separator: " → ")
                if !label.isEmpty { e.label = e.label.isEmpty ? label : e.label + ", " + label }
                e.periods.append(period)
                e.ended = e.periods.allSatisfy { $0.to != nil }
                e.problems = (e.problems + timeline.broken(rid)).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
                if partnerEdges[key] == nil { partnerOrder.append(key) }
                partnerEdges[key] = e
            }
        }
        for key in partnerOrder { if let e = partnerEdges[key] { graph.edges.append(e) } }

        // The places of the events, further down.
        var placeSlot: [String: Int] = [:]
        for e in spine {
            guard let eid = e.id else { continue }
            for pid in e.places.keys.sorted() {
                guard let place = worlds.entry(pid) else { continue }
                let slot = placeSlot[eid, default: 0]
                if pos[pid] == nil { placeSlot[eid] = slot + 1 }
                let p = spinePoint(along[eid] ?? cumulative)
                node(GraphNode(id: pid, kind: .place, title: place.name ?? ""), at: GraphPoint(x: p.x - 170 - 80 * Double(slot), y: p.y + 190 + 30 * Double(slot)))
                graph.edges.append(edge(eid, pid, .heldAt))
            }
        }
        return ArcGraph(graph: graph, positions: pos)
    }
}
