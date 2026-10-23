import Foundation

/// The kinds of things the graph draws.
public enum GraphKind: String, CaseIterable, Sendable {
    case character, place, event, scene
    /// A card of the plan (it is joined to the events that realise it).
    case card
    /// A state of a character in its arc (the card's own text at the start, then what each event makes of it). Only in the arc graph.
    case stage
    /// A world (the root of a tree of places). Only in the place tree.
    case world
}

/// What an event does to one thing, for the marks and tooltips of the graph: the fields it fills in (a character's or a place's, or a relationship's kind), a
/// character's main flag, and, for a relationship, that it starts or ends there.
public struct GraphChange: Equatable, Sendable {
    public var target: String
    public var fields: [EffectField]
    public var main: Bool?
    /// `starts` or `ends` for a relationship.
    public var marker: String?
}

/// One relationship between two characters over the book: its kinds in order ("friends", then "enemies") and the events where it starts (nil: at the start of
/// the book) and ends (nil: it does not).
public struct GraphPeriod: Equatable, Sendable {
    public var kinds: [String]
    public var from: String?
    public var to: String?
}

public struct GraphNode: Equatable, Sendable {
    public var id: String
    public var kind: GraphKind
    public var title: String
    /// A character marked as a main one (drawn with a thick border).
    public var isMain = false
    /// For an event: what it changes (empty: nothing). Drawn as a small Δ.
    public var changes: [GraphChange] = []
    /// A card's colour on the plan (its name: `teal`, `pink`…; nil is the plan's default).
    public var color: String?
    /// As of a point in the book: it has not come yet (an event after the point, a character or place not met yet, a scene after it). Drawn faded.
    public var notYet = false
    /// The plot lines (ids, in the order of the plan) it belongs to: an event, its line on the plan; a card, its line; a character or place, the lines of the events it is linked to.
    public var lines: [String] = []
    /// An event that changes something but has no scene: it has no place in the book, so its changes do not apply (a warning).
    public var doesNotApply = false
    /// The full text of a node whose title is a cut-down line (a state in an arc).
    public var detail = ""
    /// For a node made for one scene's bush (the locations graph): the real place or character it stands for, and the scene it is in.
    public var ref: String?
    public var scene: String?
    /// A place that is only there as the parent of one that is linked (drawn smaller and lighter).
    public var isContext = false
}

/// A line between two nodes. `a` and `b` are in no particular order (a link is stored once, on one side; the graph does not care which).
public struct GraphEdge: Equatable, Sendable {
    public enum Kind: String, Sendable { case relationship, takesPart, heldAt, inScene, realises, arc, contains
        /// In the locations graph: who was at a place in a scene.
        case wasAt
    }
    public var a: String
    public var b: String
    public var kind: Kind
    /// A relationship's kind ("sisters"); empty for the others.
    public var label: String
    /// How much is behind the line: for a relationship, 1 plus the events the two share.
    public var weight: Int
    /// For a line from an event to a character or a place: what the event changes in it.
    public var changes: [GraphChange] = []
    /// For a relationship line: every relationship has ended (the line is dashed).
    public var ended = false
    /// For a relationship line: the relationships it stands for.
    public var periods: [GraphPeriod] = []
    /// As of a point in the book: no relationship between the pair has started yet.
    public var notYet = false
    /// Not drawn (it is there only to keep the layout where it was): a relationship not started yet, or ended with the ended ones switched off, as of a point.
    public var hidden = false
    /// For a line from or to an event: the plot line that event is on (nil: none).
    public var line: String?
    /// For a relationship line: what is out of order in the relationships it stands for (an end before its start, a change after the end, a mark in an event with no scene).
    public var problems: [RelationshipTimeline.Problem] = []
    /// For the spine of an arc: how many scenes lie between two events of the character with none of theirs.
    public var gap = 0
    /// The relationship changes its kind, ends, or starts at an event after the start of the book.
    public var turns: Bool { periods.contains { $0.kinds.count > 1 || $0.to != nil || $0.from != nil } }
}

/// What the Graph view shows.
public struct GraphOptions: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Everything of the kinds switched on.
        case whole
        /// Characters only, joined by their relationships.
        case social
        /// One thing and what is around it, `depth` steps out.
        case neighbourhood(String, depth: Int)
    }

    public var mode: Mode = .whole
    public var kinds: Set<GraphKind> = [.character, .place, .event]
    /// Show the things that have no line to anything shown (a place no event uses, a character with no events).
    public var showUnlinked = true
    /// When set, only these ids are shown (what is related to a section of the book); nil shows everything.
    public var allowed: Set<String>?
    /// Draw the relationships that have ended (dashed).
    public var showEnded = true
    /// Keep only the events that change something, with what they change: the turning points of the story.
    public var changesOnly = false
    /// A scene: the book as it is after it (relationships started, changed or ended by then, who has been met, who is a main character). The nodes and lines are all kept, so that
    /// the layout does not move; what is not there yet is flagged. nil: the whole book.
    public var asOf: String?
    /// One plot line of the plan: its events and cards, with the characters, places and scenes they are linked to.
    public var plotLine: String?

    public init() {}
}

public struct BookGraph: Equatable, Sendable {
    public var nodes: [GraphNode] = []
    public var edges: [GraphEdge] = []

    public init(nodes: [GraphNode] = [], edges: [GraphEdge] = []) { self.nodes = nodes; self.edges = edges }

    public func node(_ id: String) -> GraphNode? { nodes.first { $0.id == id } }

    /// How many things are marked with a warning (an event that does not apply, a relationship out of order).
    public var warningCount: Int { nodes.filter(\.doesNotApply).count + edges.filter { !$0.problems.isEmpty && !$0.hidden }.count }

    /// The ids of the nodes joined to `id` by a line.
    public func neighbours(of id: String) -> Set<String> {
        var out = Set<String>()
        for e in edges where !e.hidden { if e.a == id { out.insert(e.b) } else if e.b == id { out.insert(e.a) } }
        return out
    }

    /// How many lines each node has.
    public func degrees() -> [String: Int] {
        var out: [String: Int] = [:]
        for e in edges { out[e.a, default: 0] += 1; out[e.b, default: 0] += 1 }
        return out
    }
}

/// Builds the graph from the book's records. The links it follows are the ones the filters follow (quilland-format.md, section 5): a character's link to an
/// event or a scene, a character's point of view, an event's places and scenes, a place's scenes, and the relationships between characters. Who is named in a
/// scene's text is not followed: a scene is joined only by a link that was written down.
public enum GraphBuilder {
    /// What an event does to one character, place or relationship (nil: nothing, or the thing is gone).
    public static func change(of e: EventRecord, target: String, characters: CharacterStore, worlds: WorldStore, relationships: RelationshipStore) -> GraphChange? {
        func name(of target: String) -> String? {
            if let c = characters.character(target) { return c.name }
            if let p = worlds.entry(target) { return p.name }
            if let r = relationships.relationship(target) { return r.characters.compactMap { characters.character($0)?.name }.joined(separator: " — ") + ": " + (r.kind ?? "") }
            return nil
        }
        let effect = e.effect(of: target)
        let marker = e.relationships[target].flatMap { $0.isEmpty ? nil : $0 }
        guard !effect.isEmpty || marker != nil, let title = name(of: target) else { return nil }
        let known: [EffectField] = [.aliases, .main, .profile, .worlds, .description, .kind]
        return GraphChange(target: title, fields: known.filter { effect[$0.rawValue] != nil }, main: e.effectFlag(of: target), marker: marker)
    }

    /// Everything an event changes.
    public static func changes(of e: EventRecord, characters: CharacterStore, worlds: WorldStore, relationships: RelationshipStore) -> [GraphChange] {
        Set(e.effects.keys).union(e.relationships.keys).sorted().compactMap { change(of: e, target: $0, characters: characters, worlds: worlds, relationships: relationships) }
    }

    public static func build(characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore, structure: BookStructure,
                             options: GraphOptions, plan: PlanStore? = nil) -> BookGraph {
        let sceneTitles = Dictionary(structure.scenes.map { ($0.id, $0.node.title) }, uniquingKeysWith: { a, _ in a })
        var all: [String: GraphNode] = [:]
        var order: [String] = []
        func add(_ id: String?, _ kind: GraphKind, _ title: String?, main: Bool = false) {
            guard let id, all[id] == nil else { return }
            all[id] = GraphNode(id: id, kind: kind, title: title ?? "", isMain: main); order.append(id)
        }
        for c in characters.characters { add(c.id, .character, c.name, main: c.main) }
        for p in worlds.entries { add(p.id, .place, p.name) }
        let sceneOrder = structure.scenes.map(\.id)
        let scenePos = Dictionary(sceneOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let point: Int? = options.asOf.flatMap { scenePos[$0] }
        func eventPos(_ e: EventRecord) -> Int? { e.start ? -1 : e.links.keys.compactMap { scenePos[$0] }.min() }
        func applies(_ e: EventRecord) -> Bool { guard let p = point else { return true }; return eventPos(e).map { $0 <= p } ?? false }
        func appliesEvent(_ id: String?) -> Bool { id.flatMap { events.event($0) }.map(applies) ?? false }
        let timeline = RelationshipTimeline(events: events, sceneOrder: sceneOrder)
        func fields(_ e: EventRecord, _ target: String) -> GraphChange? { change(of: e, target: target, characters: characters, worlds: worlds, relationships: relationships) }
        for e in events.events {
            let changes = changes(of: e, characters: characters, worlds: worlds, relationships: relationships)
            guard let id = e.id, all[id] == nil else { continue }
            var node = GraphNode(id: id, kind: .event, title: e.title ?? "", changes: changes)
            node.doesNotApply = e.changesSomething && !e.start && timeline.order(of: id) == nil
            all[id] = node; order.append(id)
        }
        for s in structure.scenes { add(s.id, .scene, sceneTitles[s.id]) }
        for id in (plan?.cards.keys.sorted() ?? []) { if let card = plan?.cards[id], all[id] == nil { all[id] = GraphNode(id: id, kind: .card, title: card.title ?? "", color: card.color); order.append(id) } }

        var edges: [GraphEdge] = []
        func link(_ a: String, _ b: String, _ kind: GraphEdge.Kind, label: String = "", weight: Int = 1, changes: [GraphChange] = [], ended: Bool = false, periods: [GraphPeriod] = [], notYet: Bool = false, problems: [RelationshipTimeline.Problem] = []) {
            guard all[a] != nil, all[b] != nil, a != b else { return }
            var edge = GraphEdge(a: a, b: b, kind: kind, label: label, weight: weight, changes: changes, ended: ended, periods: periods)
            edge.problems = problems
            edge.notYet = notYet; edge.hidden = notYet || (point != nil && ended && !options.showEnded)
            edges.append(edge)
        }
        var eventsOf: [String: Set<String>] = [:]
        for c in characters.characters {
            guard let id = c.id else { continue }
            for key in c.links.keys.sorted() where all[key]?.kind == .scene { link(id, key, .inScene) }
            for scene in c.povScenes where c.links[scene] == nil { link(id, scene, .inScene) }
        }
        for e in events.events {
            guard let id = e.id else { continue }
            for cid in e.characters.keys.sorted() where all[cid]?.kind == .character {
                link(cid, id, .takesPart, changes: fields(e, cid).map { [$0] } ?? []); eventsOf[cid, default: []].insert(id)
            }
            for key in e.places.keys.sorted() { link(id, key, .heldAt, changes: fields(e, key).map { [$0] } ?? []) }
            for key in e.links.keys.sorted() { link(id, key, .inScene) }
        }
        for p in worlds.entries {
            guard let id = p.id else { continue }
            for key in p.links.keys.sorted() { link(id, key, .inScene) }
        }
        // A card is joined to the events that realise it.
        if let plan { for id in plan.cards.keys.sorted() { for event in plan.realisedBy(id) { link(id, event, .realises) } } }
        // Relationships: one line for each pair of characters; the kinds of the relationships between the same two are put together.
        var pairs: [String: (a: String, b: String, labels: [String], periods: [GraphPeriod], started: Bool, problems: [RelationshipTimeline.Problem])] = [:]
        var pairOrder: [String] = []
        for r in relationships.relationships {
            let members = Array(NSOrderedSet(array: r.characters)) as? [String] ?? r.characters
            for i in 0..<members.count { for j in (i + 1)..<max(members.count, i + 1) {
                let (a, b) = members[i] < members[j] ? (members[i], members[j]) : (members[j], members[i])
                let key = a + "|" + b
                if pairs[key] == nil { pairs[key] = (a, b, [], [], point == nil, []); pairOrder.append(key) }
                for p in r.id.map({ timeline.broken($0) }) ?? [] where !pairs[key]!.problems.contains(p) { pairs[key]!.problems.append(p) }
                // Its kinds in the order of the book ("friends → enemies"), and where it starts and ends.
                let marks = r.id.map { timeline.marks(of: $0) }
                // (As of a point, a relationship that has not started is left out of what the line says.)
                if point != nil, let start = marks?.start, events.startEvent?.id != start, !appliesEvent(start) { continue }
                pairs[key]!.started = true
                var kinds = [r.kind ?? ""]
                for ev in marks?.changes ?? [] where appliesEvent(ev) { if let k = events.event(ev)?.effect(of: r.id ?? "").string(EffectField.kind.rawValue), k != kinds.last { kinds.append(k) } }
                func title(_ id: String?) -> String? { id.flatMap { events.event($0) }.map { $0.title ?? "" } }
                let from = marks?.start.flatMap { events.startEvent?.id == $0 ? nil : title($0) }
                let period = GraphPeriod(kinds: kinds, from: from, to: appliesEvent(marks?.end) ? title(marks?.end) : nil)
                let label = kinds.filter { !$0.isEmpty }.joined(separator: " → ")
                if !label.isEmpty, !pairs[key]!.labels.contains(label) { pairs[key]!.labels.append(label) }
                pairs[key]!.periods.append(period)
            } }
        }
        for key in pairOrder {
            let p = pairs[key]!
            let shared = (eventsOf[p.a] ?? []).intersection(eventsOf[p.b] ?? []).count
            link(p.a, p.b, .relationship, label: p.labels.joined(separator: ", "), weight: 1 + shared, ended: p.started && p.periods.allSatisfy { $0.to != nil }, periods: p.periods, notYet: !p.started, problems: p.problems)
        }
        // The plot lines (of the plan): each event is on at most one; a character or place is on those of its events.
        let laneIDs = plan?.lines.compactMap(\.id) ?? []
        var laneOf: [String: String] = [:]
        for entry in plan?.entries ?? [] { if let event = entry.event, let lane = entry.lane, laneIDs.contains(lane) { laneOf[event] = lane } }
        if plan != nil {
            var linesOf: [String: Set<String>] = [:]
            for i in edges.indices {
                let eventEnd = all[edges[i].a]?.kind == .event ? edges[i].a : (all[edges[i].b]?.kind == .event ? edges[i].b : nil)
                guard let event = eventEnd, edges[i].kind != .relationship else { continue }
                edges[i].line = laneOf[event]
                if edges[i].kind == .takesPart || edges[i].kind == .heldAt, let lane = laneOf[event] { linesOf[edges[i].a == event ? edges[i].b : edges[i].a, default: []].insert(lane) }
            }
            for id in order {
                guard var n = all[id] else { continue }
                switch n.kind {
                case .event: n.lines = laneOf[id].map { [$0] } ?? []
                case .card: n.lines = plan?.cards[id]?.line.flatMap { laneIDs.contains($0) ? [$0] : nil } ?? []
                case .character, .place: n.lines = laneIDs.filter { linesOf[id]?.contains($0) == true }
                case .scene, .stage, .world: break
                }
                all[id] = n
            }
        }
        if !options.showEnded, point == nil { edges.removeAll { $0.kind == .relationship && $0.ended } }

        // Only the turning points: the events that change something, what they change, and the relationships that turn.
        var keep: Set<String>?
        if options.changesOnly {
            var kept = Set(order.filter { all[$0]?.kind == .event && !(all[$0]?.changes.isEmpty ?? true) })
            edges = edges.filter { e in
                switch e.kind {
                case .takesPart, .heldAt: return !e.changes.isEmpty
                case .relationship: return e.turns
                case .inScene: return false
                case .realises: return false
                case .arc, .contains, .wasAt: return false
                }
            }
            for e in edges { kept.insert(e.a); kept.insert(e.b) }
            if options.kinds.contains(.scene) {
                for e in events.events where e.id.map(kept.contains) == true {
                    for key in e.links.keys where all[key]?.kind == .scene { kept.insert(key); link(e.id!, key, .inScene) }
                }
            }
            keep = kept
        }
        if let line = options.plotLine, plan != nil {
            var kept = Set(order.filter { all[$0]?.kind == .card ? plan?.cards[$0]?.line == line : (all[$0]?.kind == .event && laneOf[$0] == line) })
            // What the events of the line are linked to (a card brings nothing but itself).
            for e in edges where e.kind != .relationship && e.kind != .realises {
                if kept.contains(e.a), all[e.a]?.kind == .event { kept.insert(e.b) }
                if kept.contains(e.b), all[e.b]?.kind == .event { kept.insert(e.a) }
            }
            keep = keep.map { $0.intersection(kept) } ?? kept
        }

        // As of a point: what has not come yet is flagged, and a character is a main one as the events up to the point say.
        if let point {
            var first: [String: Int] = [:]
            func see(_ id: String?, _ pos: Int?) { guard let id, let pos else { return }; first[id] = min(first[id] ?? Int.max, pos) }
            for c in characters.characters { for k in c.links.keys { see(c.id, scenePos[k]) }; for k in c.povScenes { see(c.id, scenePos[k]) } }
            for p in worlds.entries { for k in p.links.keys { see(p.id, scenePos[k]) } }
            for e in events.events {
                let pos = eventPos(e)
                for cid in e.characters.keys { see(cid, pos) }
                for pid in e.places.keys { see(pid, pos) }
                see(e.id, pos)
            }
            for (scene, i) in scenePos { see(scene, i) }
            var mainNow: [String: Bool] = [:]
            for e in events.ordered(sceneOrder: sceneOrder) where applies(e) { for c in characters.characters { if let id = c.id, let flag = e.effectFlag(of: id) { mainNow[id] = flag } } }
            for id in order {
                guard var n = all[id] else { continue }
                switch n.kind {
                case .event: n.notYet = events.event(id).map { !applies($0) } ?? false
                case .character, .place, .scene: n.notYet = first[id].map { $0 > point } ?? false
                case .card, .stage, .world: break
                }
                if n.kind == .character, let flag = mainNow[id] { n.isMain = flag }
                all[id] = n
            }
        }

        // What is shown.
        var kinds = options.kinds
        var relationshipsOnly = false
        switch options.mode {
        case .social: kinds = [.character]; relationshipsOnly = true
        case .neighbourhood(let focus, _): if let k = all[focus]?.kind { kinds.insert(k) }
        case .whole: break
        }
        func shown(_ id: String) -> Bool {
            guard let node = all[id], kinds.contains(node.kind) else { return false }
            if let keep, !keep.contains(id) { return false }
            if let allowed = options.allowed, !allowed.contains(id) { return false }
            return true
        }
        var visible = Set(order.filter(shown))
        var lines = edges.filter { visible.contains($0.a) && visible.contains($0.b) && (!relationshipsOnly || $0.kind == .relationship) }

        if case .neighbourhood(let focus, let depth) = options.mode, visible.contains(focus) {
            var reached: Set<String> = [focus]
            var frontier: Set<String> = [focus]
            for _ in 0..<max(1, depth) {
                var next = Set<String>()
                for e in lines {
                    if frontier.contains(e.a), !reached.contains(e.b) { next.insert(e.b) }
                    if frontier.contains(e.b), !reached.contains(e.a) { next.insert(e.a) }
                }
                reached.formUnion(next); frontier = next
            }
            visible = reached
            lines = lines.filter { visible.contains($0.a) && visible.contains($0.b) }
        } else if case .neighbourhood = options.mode {
            visible = []; lines = []
        }

        var graph = BookGraph(nodes: order.filter { visible.contains($0) }.compactMap { all[$0] }, edges: lines)
        if !options.showUnlinked {
            // (A neighbourhood is made of what is linked to the focus, which is itself shown even when it has nothing around it.)
            if case .neighbourhood = options.mode {} else {
                let linked = graph.degrees()
                graph.nodes = graph.nodes.filter { linked[$0.id] != nil }
            }
        }
        return graph
    }
}
