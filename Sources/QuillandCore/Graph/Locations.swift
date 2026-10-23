import Foundation

/// How the places change along the book, as a graph of its own: the scenes that places are linked to (a place has a line in them, or an event held at it is in them)
/// are a spine that runs from the top left to the bottom right, and each scene is a **bush** of its own: its places, and for each place the characters who took part in an
/// event held there in that scene. Nothing is shared between scenes (a place that comes back is a new node each time), and a scene with a single place has no node of its
/// own: the place stands in its place on the spine. The places of the nodes are worked out.
public enum LocationsBuilder {
    /// `only`: follow one character (the scenes where they are at a place, and only they in the bushes); nil: everyone.
    public static func build(only character: String? = nil, characters: CharacterStore, worlds: WorldStore, events: EventStore, structure: BookStructure) -> ArcGraph {
        let sceneOrder = structure.scenes.map(\.id)
        let scenePos = Dictionary(sceneOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let titles = Dictionary(structure.scenes.map { ($0.id, $0.node.title) }, uniquingKeysWith: { a, _ in a })

        // For each scene: its places, and the characters at each.
        var atPlace: [String: [String: [String]]] = [:]
        func add(_ scene: String, _ place: String, _ who: String?) {
            var m = atPlace[scene] ?? [:]
            var list = m[place] ?? []
            if let who, !list.contains(who) { list.append(who) }
            m[place] = list
            atPlace[scene] = m
        }
        for p in worlds.entries { guard let id = p.id else { continue }; for s in p.links.keys where scenePos[s] != nil { add(s, id, nil) } }
        for e in events.ordered(sceneOrder: sceneOrder) {
            let scenes = e.links.keys.filter { scenePos[$0] != nil }
            for s in scenes {
                for pid in e.places.keys.sorted() where worlds.entry(pid) != nil {
                    add(s, pid, nil)
                    for cid in e.characters.keys.sorted() where characters.character(cid) != nil { add(s, pid, cid) }
                }
            }
        }
        if let character {
            for (s, places) in atPlace { atPlace[s] = places.filter { $0.value.contains(character) }.mapValues { _ in [character] } }
        }
        let scenes = atPlace.filter { !$0.value.isEmpty }.keys.sorted { (scenePos[$0] ?? 0) < (scenePos[$1] ?? 0) }

        var out = ArcGraph()
        func node(_ n: GraphNode, at p: GraphPoint) { guard out.positions[n.id] == nil else { return }; out.graph.nodes.append(n); out.positions[n.id] = p }
        func name(_ placeID: String) -> String { worlds.entry(placeID)?.name ?? "" }
        func placesOf(_ scene: String) -> [String] { (atPlace[scene] ?? [:]).keys.sorted { name($0).localizedLowercase < name($1).localizedLowercase } }

        // Each scene's bush is a small tree: the scene, then the places linked to it with the parent places above them (not the world), then the characters of each place.
        // Nothing is shared between scenes; within a scene a parent shared by two places is one node.
        let step = (x: 175.0, y: 110.0)
        let tangent = (x: 0.84, y: 0.54), normal = (x: -0.54, y: 0.84)
        let unit = 95.0, level = 100.0, perRow = 4

        struct Bush {
            var nodes: Set<String> = []            // place ids in the bush (linked here, and their parents)
            var children: [String: [String]] = [:]
            var roots: [String] = []
            var linked: Set<String> = []
        }
        func parents(of place: String) -> [String] {
            var out: [String] = [], seen: Set<String> = [place], current = worlds.entry(place)?.parent
            while let p = current, seen.insert(p).inserted, worlds.entry(p) != nil { out.append(p); current = worlds.entry(p)?.parent }
            return out   // nearest first
        }
        func bush(_ scene: String) -> Bush {
            var b = Bush()
            for p in placesOf(scene) { b.linked.insert(p); b.nodes.insert(p); for a in parents(of: p) { b.nodes.insert(a) } }
            for p in b.nodes.sorted(by: { name($0).localizedLowercase < name($1).localizedLowercase }) {
                if let parent = worlds.entry(p)?.parent, b.nodes.contains(parent) { b.children[parent, default: []].append(p) } else { b.roots.append(p) }
            }
            return b
        }
        let bushes = Dictionary(scenes.map { ($0, bush($0)) }, uniquingKeysWith: { a, _ in a })
        func who(_ scene: String, _ place: String) -> [String] { atPlace[scene]?[place] ?? [] }
        func width(_ b: Bush, _ scene: String, _ p: String) -> Double {
            let kids = (b.children[p] ?? []).reduce(0.0) { $0 + width(b, scene, $1) }
            return max(unit, kids + Double(min(perRow, who(scene, p).count)) * unit)
        }
        func total(_ scene: String) -> Double { guard let b = bushes[scene] else { return unit }; return max(unit, b.roots.reduce(0.0) { $0 + width(b, scene, $1) }) }

        var along: [String: Double] = [:]
        var cumulative = 0.0
        var previous: (scene: String, pos: Int)?
        var gaps: [String: Int] = [:]
        for s in scenes {
            let pos = scenePos[s] ?? 0
            var factor = 1.0
            var gap = 0
            if let p = previous {
                gap = pos - p.pos - 1
                if gap > ArcBuilder.gapScenes { factor += min(1.5, Double(gap) / 6) } else { gap = 0 }
                // (Room for the bushes of the two scenes side by side.)
                factor = max(factor, (total(p.scene) / 2 + total(s) / 2 + 40) / (step.x * tangent.x + step.y * tangent.y))
            }
            if previous != nil { cumulative += factor }
            along[s] = cumulative
            gaps[s] = gap
            previous = (s, pos)
        }
        func spinePoint(_ s: Double) -> GraphPoint { GraphPoint(x: 80 + step.x * s, y: 80 + step.y * s) }

        var before: String?
        for s in scenes {
            guard let b = bushes[s] else { continue }
            let origin = spinePoint(along[s] ?? 0)
            func at(_ offset: Double, _ depth: Double) -> GraphPoint { GraphPoint(x: origin.x + tangent.x * offset + normal.x * depth, y: origin.y + tangent.y * offset + normal.y * depth) }
            // A scene with one place and no parent has no node of its own: the place stands on the spine.
            let merged = b.nodes.count == 1 && b.roots.count == 1
            let spineID: String
            if merged, let only = b.roots.first {
                spineID = "bush:\(s)|\(only)"
            } else {
                spineID = s
                var n = GraphNode(id: s, kind: .scene, title: titles[s] ?? "")
                n.ref = s; n.scene = s
                n.anchored = true
                node(n, at: origin)
            }
            if let prev = before {
                var line = GraphEdge(a: prev, b: spineID, kind: .arc, label: "", weight: 4)
                if let g = gaps[s], g > 0 { line.gap = g; line.label = Lp("{n} scene without a place", "{n} scenes without a place", g) }
                out.graph.edges.append(line)
            }
            before = spineID

            // The tree: a place sits in the middle of its children (the places inside it, then its characters).
            @discardableResult
            func lay(_ p: String, depth: Int, left: Double, parent: String?) -> Double {
                let id = "bush:\(s)|\(p)"
                let kids = b.children[p] ?? []
                var x = left
                var centres: [Double] = []
                for k in kids { let w = width(b, s, k); centres.append(lay(k, depth: depth + 1, left: x, parent: p)); x += w }
                let people = who(s, p).filter { characters.character($0) != nil }
                let cols = min(perRow, people.count)
                if !people.isEmpty { centres.append(x + Double(cols) * unit / 2) }
                let centre = centres.isEmpty ? left + unit / 2 : (centres.first! + centres.last!) / 2
                let place = at(centre - total(s) / 2, level * Double(depth))
                var n = GraphNode(id: id, kind: .place, title: name(p))
                n.ref = p; n.scene = s
                n.isContext = !b.linked.contains(p)
                if merged { n.detail = titles[s] ?? ""; n.anchored = true }
                node(n, at: merged ? origin : place)
                if let parent { out.graph.edges.append(GraphEdge(a: "bush:\(s)|\(parent)", b: id, kind: .contains, label: "", weight: 1)) }
                else if !merged { out.graph.edges.append(GraphEdge(a: s, b: id, kind: .heldAt, label: "", weight: 1)) }
                for (j, cid) in people.enumerated() {
                    guard let c = characters.character(cid) else { continue }
                    let row = j / perRow, col = j % perRow
                    let inRow = min(perRow, people.count - row * perRow)
                    let blockCentre = x + Double(cols) * unit / 2
                    let off = blockCentre + (Double(col) - Double(inRow - 1) / 2) * unit - total(s) / 2
                    var cn = GraphNode(id: "bush:\(s)|\(p)|\(cid)", kind: .character, title: c.name ?? "", isMain: c.main)
                    cn.ref = cid; cn.scene = s
                    node(cn, at: at(off, level * Double(depth) + 85 + 70 * Double(row)))
                    out.graph.edges.append(GraphEdge(a: id, b: cn.id, kind: .wasAt, label: "", weight: 1))
                }
                return centre
            }
            var x = 0.0
            for r in b.roots { let w = width(b, s, r); lay(r, depth: merged ? 0 : 1, left: x, parent: nil); x += w }
        }
        return out
    }
}
