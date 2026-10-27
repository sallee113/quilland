import Foundation

/// The worlds and places of the book as a tree, a graph of its own: each world is a root, a place hangs from the place it is inside (or from its world), and the tree
/// runs from the left to the right with its places already worked out. A place shows what events change in it (Δ) and how many events are held there.
public enum PlaceTreeBuilder {
    /// `only`: one world's tree (nil: every world).
    public static func build(only world: String? = nil, characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore) -> ArcGraph {
        var out = ArcGraph()
        let columnGap = 230.0, rowGap = 62.0, nodeWidth = 170.0
        var nextY = 0.0
        var seen = Set<String>()

        let held = events.events.reduce(into: [String: Int]()) { counts, e in for p in e.places.keys { counts[p, default: 0] += 1 } }
        func title(_ s: String?) -> String { s ?? "" }
        func name(_ p: PlaceRecord) -> String { title(p.name) }

        func placeNode(_ p: PlaceRecord) -> GraphNode? {
            guard let id = p.id else { return nil }
            var n = GraphNode(id: id, kind: .place, title: name(p))
            for e in events.ordered(sceneOrder: []) where !e.effect(of: id).isEmpty {
                if let c = GraphBuilder.change(of: e, target: id, characters: characters, worlds: worlds, relationships: relationships) { n.changes.append(c) }
            }
            let text = worlds.text(id).trimmingCharacters(in: .whitespacesAndNewlines)
            var detail = text.count > 160 ? String(text.prefix(159)) + "…" : text
            if let k = held[id], k > 0 { detail += (detail.isEmpty ? "" : "\n") + Lp("{n} event here", "{n} events here", k) }
            n.detail = detail
            return n
        }

        func children(of parent: String?, in world: String) -> [PlaceRecord] {
            worlds.entries.filter { $0.world == world && $0.parent == parent }.sorted { name($0).localizedLowercase < name($1).localizedLowercase }
        }

        /// Places a node and everything inside it; returns the node's own row (the middle of its children).
        func lay(_ p: PlaceRecord, parent: String, depth: Int, world: String) -> Double? {
            guard let id = p.id, seen.insert(id).inserted, let node = placeNode(p) else { return nil }
            let kids = children(of: id, in: world).compactMap { lay($0, parent: id, depth: depth + 1, world: world) }
            let y: Double
            if kids.isEmpty { y = nextY; nextY += rowGap } else { y = (kids.first! + kids.last!) / 2 }
            out.graph.nodes.append(node)
            out.positions[id] = GraphPoint(x: Double(depth) * columnGap, y: y)
            out.graph.edges.append(GraphEdge(a: parent, b: id, kind: .contains, label: "", weight: 1))
            return y
        }

        // Each world with its places is a block of its own, laid out from the left to the right; the blocks are then set in rows on the canvas (in the order of the worlds),
        // a row at a time, so that the picture fills a wide window instead of making one tall column.
        struct Block {
            var nodes: [GraphNode] = []
            var edges: [GraphEdge] = []
            var points: [String: GraphPoint] = [:]
            var width = 0.0, height = 0.0
        }
        var blocks: [Block] = []
        for w in worlds.worlds where world == nil || w.id == world {
            guard let wid = w.id else { continue }
            let before = (nodes: out.graph.nodes.count, edges: out.graph.edges.count)
            let savedPositions = out.positions
            out.positions = [:]
            nextY = 0
            // A place whose parent is gone, or in another world, hangs from its world.
            let ids = Set(worlds.entries.filter { $0.world == wid }.compactMap(\.id))
            let roots = worlds.entries.filter { $0.world == wid && ($0.parent == nil || !ids.contains($0.parent ?? "")) }.sorted { name($0).localizedLowercase < name($1).localizedLowercase }
            let rows = roots.compactMap { lay($0, parent: wid, depth: 1, world: wid) }
            let y = rows.isEmpty ? { let v = nextY; nextY += rowGap; return v }() : (rows.first! + rows.last!) / 2
            var root = GraphNode(id: wid, kind: .world, title: title(w.name))
            root.anchored = true
            out.graph.nodes.append(root)
            out.positions[wid] = GraphPoint(x: 0, y: y)
            var block = Block()
            block.nodes = Array(out.graph.nodes[before.nodes...])
            block.edges = Array(out.graph.edges[before.edges...])
            block.points = out.positions
            let xs = block.points.values.map(\.x), ys = block.points.values.map(\.y)
            block.width = (xs.max() ?? 0) + nodeWidth
            block.height = (ys.max() ?? 0) - (ys.min() ?? 0) + rowGap
            blocks.append(block)
            out.graph.nodes.removeSubrange(before.nodes...)
            out.graph.edges.removeSubrange(before.edges...)
            out.positions = savedPositions
        }
        // The blocks stand in rows of about the square root of their number (rounded up), in the order of the worlds: two worlds are side by side, three or four make two
        // rows of two, five to nine three rows of three, so that the picture fills a wide window instead of making one tall column.
        let airX = 70.0, airY = 50.0
        let perRow = max(1, Int(Double(blocks.count).squareRoot().rounded(.up)))
        var x = 0.0, top = 0.0, rowHeight = 0.0
        for (n, block) in blocks.enumerated() {
            if n > 0, n % perRow == 0 { top += rowHeight + airY; x = 0; rowHeight = 0 }
            let low = block.points.values.map(\.y).min() ?? 0
            out.graph.nodes += block.nodes
            out.graph.edges += block.edges
            for (id, p) in block.points { out.positions[id] = GraphPoint(x: x + p.x, y: top + p.y - low) }
            x += block.width + airX
            rowHeight = max(rowHeight, block.height)
        }
        return out
    }
}
