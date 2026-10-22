import Foundation

/// The kinds of things the graph draws.
public enum GraphKind: String, CaseIterable, Sendable {
    case character, place, event, scene
}

public struct GraphNode: Equatable, Sendable {
    public var id: String
    public var kind: GraphKind
    public var title: String
    /// A character marked as a main one (drawn with a thick border).
    public var isMain = false
}

/// A line between two nodes. `a` and `b` are in no particular order (a link is stored once, on one side; the graph does not care which).
public struct GraphEdge: Equatable, Sendable {
    public enum Kind: String, Sendable { case relationship, takesPart, heldAt, inScene }
    public var a: String
    public var b: String
    public var kind: Kind
    /// A relationship's kind ("sisters"); empty for the others.
    public var label: String
    /// How much is behind the line: for a relationship, 1 plus the events the two share.
    public var weight: Int
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

    public init() {}
}

public struct BookGraph: Equatable, Sendable {
    public var nodes: [GraphNode] = []
    public var edges: [GraphEdge] = []

    public init(nodes: [GraphNode] = [], edges: [GraphEdge] = []) { self.nodes = nodes; self.edges = edges }

    public func node(_ id: String) -> GraphNode? { nodes.first { $0.id == id } }

    /// The ids of the nodes joined to `id` by a line.
    public func neighbours(of id: String) -> Set<String> {
        var out = Set<String>()
        for e in edges { if e.a == id { out.insert(e.b) } else if e.b == id { out.insert(e.a) } }
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
    public static func build(characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore, structure: BookStructure,
                             options: GraphOptions) -> BookGraph {
        let sceneTitles = Dictionary(structure.scenes.map { ($0.id, $0.node.title) }, uniquingKeysWith: { a, _ in a })
        var all: [String: GraphNode] = [:]
        var order: [String] = []
        func add(_ id: String?, _ kind: GraphKind, _ title: String?, main: Bool = false) {
            guard let id, all[id] == nil else { return }
            all[id] = GraphNode(id: id, kind: kind, title: title ?? "", isMain: main); order.append(id)
        }
        for c in characters.characters { add(c.id, .character, c.name, main: c.main) }
        for p in worlds.entries { add(p.id, .place, p.name) }
        for e in events.events { add(e.id, .event, e.title) }
        for s in structure.scenes { add(s.id, .scene, sceneTitles[s.id]) }

        var edges: [GraphEdge] = []
        func link(_ a: String, _ b: String, _ kind: GraphEdge.Kind, label: String = "", weight: Int = 1) {
            guard all[a] != nil, all[b] != nil, a != b else { return }
            edges.append(GraphEdge(a: a, b: b, kind: kind, label: label, weight: weight))
        }
        var eventsOf: [String: Set<String>] = [:]
        for c in characters.characters {
            guard let id = c.id else { continue }
            for key in c.links.keys.sorted() {
                if all[key]?.kind == .event { link(id, key, .takesPart); eventsOf[id, default: []].insert(key) }
                else if all[key]?.kind == .scene { link(id, key, .inScene) }
            }
            for scene in c.povScenes where c.links[scene] == nil { link(id, scene, .inScene) }
        }
        for e in events.events {
            guard let id = e.id else { continue }
            for key in e.places.keys.sorted() { link(id, key, .heldAt) }
            for key in e.links.keys.sorted() { link(id, key, .inScene) }
        }
        for p in worlds.entries {
            guard let id = p.id else { continue }
            for key in p.links.keys.sorted() { link(id, key, .inScene) }
        }
        // Relationships: one line for each pair of characters; the kinds of the relationships between the same two are put together.
        var pairs: [String: (a: String, b: String, labels: [String])] = [:]
        var pairOrder: [String] = []
        for r in relationships.relationships {
            let members = Array(NSOrderedSet(array: r.characters)) as? [String] ?? r.characters
            for i in 0..<members.count { for j in (i + 1)..<max(members.count, i + 1) {
                let (a, b) = members[i] < members[j] ? (members[i], members[j]) : (members[j], members[i])
                let key = a + "|" + b
                if pairs[key] == nil { pairs[key] = (a, b, []); pairOrder.append(key) }
                if let kind = r.kind, !kind.isEmpty, !pairs[key]!.labels.contains(kind) { pairs[key]!.labels.append(kind) }
            } }
        }
        for key in pairOrder {
            let p = pairs[key]!
            let shared = (eventsOf[p.a] ?? []).intersection(eventsOf[p.b] ?? []).count
            link(p.a, p.b, .relationship, label: p.labels.joined(separator: ", "), weight: 1 + shared)
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
