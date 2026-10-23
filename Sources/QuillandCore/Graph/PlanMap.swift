import Foundation

/// The plan as a map of its own, like a subway map: each plot line is a strand in its own colour, running from the top left to the bottom right, with its cards and
/// its events in the order of the plan. What is at the same moment on different lines is level across the strands. An orange line joins a card to the events that
/// realised it; a card that no event has realised is hollow. Cards on no line, and events that realise a card without being on the plan, are on a last strand.
public enum PlanMapBuilder {
    public static let looseStrand = "plan:loose"

    public static func build(plan: PlanStore, events: EventStore) -> ArcGraph {
        var out = ArcGraph()
        let step = (x: 175.0, y: 110.0)
        let normal = (x: -0.54, y: 0.84)
        let strandGap = 215.0

        struct Item { var id: String; var isCard: Bool; var start: Int?; var title: String }
        var strands: [(id: String, name: String, color: String?, items: [Item])] = []
        for lane in plan.lines {
            guard let id = lane.id else { continue }
            var items: [Item] = []
            for (cid, card) in plan.cards where card.line == id { items.append(Item(id: cid, isCard: true, start: card.start, title: card.title ?? "")) }
            for entry in plan.entries where entry.lane == id { if let e = entry.event, plan.events[e] != nil { items.append(Item(id: e, isCard: false, start: entry.start, title: plan.events[e] ?? "")) } }
            strands.append((id, lane.name ?? "", lane.color, items))
        }
        // The last strand: cards on no line, and the events that realise a card without being on the plan.
        let placed = Set(plan.entries.compactMap { $0.event })
        var loose: [Item] = plan.cards.filter { $0.value.line == nil }.map { Item(id: $0.key, isCard: true, start: nil, title: $0.value.title ?? "") }
        var seen = Set(loose.map(\.id))
        for (cid, _) in plan.cards { for e in plan.realisedBy(cid) where !placed.contains(e) && seen.insert(e).inserted { loose.append(Item(id: e, isCard: false, start: nil, title: plan.events[e] ?? "")) } }
        if !loose.isEmpty { strands.append((looseStrand, L("Not on a line"), nil, loose.sorted { ($0.isCard ? 0 : 1, $0.title.localizedLowercase) < ($1.isCard ? 0 : 1, $1.title.localizedLowercase) })) }
        strands = strands.filter { !$0.items.isEmpty }
        guard !strands.isEmpty else { return out }

        // The rows: the moments (`start`) of the plan, in order; a strand with no moments of its own (the last one) goes one item to a row.
        let moments = Array(Set(strands.flatMap { $0.items.compactMap(\.start) })).sorted()
        let rowOf = Dictionary(moments.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func point(row: Double, strand: Int, shift: Double) -> GraphPoint {
            let across = Double(strands.count - 1 - strand) * strandGap + shift
            return GraphPoint(x: 80 + step.x * (row + 1) + normal.x * across, y: 80 + step.y * (row + 1) + normal.y * across)
        }
        func realised(_ card: String) -> Bool { !plan.realisedBy(card).isEmpty }
        var drawn = Set<String>()

        for (k, strand) in strands.enumerated() {
            // The head of the strand: its name, in its colour.
            var head = GraphNode(id: "plan:line:\(strand.id)", kind: .stage, title: strand.name)
            head.color = strand.color ?? "gray"
            out.graph.nodes.append(head); out.positions[head.id] = point(row: -1, strand: k, shift: 0)
            var previous = head.id
            // Items in order of their moment; at one moment a card is on the lower-left of the strand and an event on the upper-right.
            var sequence = 0
            let ordered = strand.items.sorted { a, b in
                switch (a.start, b.start) {
                case let (x?, y?): return x != y ? x < y : (a.isCard ? 0 : 1, a.title) < (b.isCard ? 0 : 1, b.title)
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return (a.isCard ? 0 : 1, a.title.localizedLowercase) < (b.isCard ? 0 : 1, b.title.localizedLowercase)
                }
            }
            let sharing = Dictionary(grouping: ordered.compactMap { $0.start }, by: { $0 }).mapValues(\.count)
            for item in ordered {
                guard drawn.insert(item.id).inserted else { continue }
                let row: Double
                if let s = item.start, let r = rowOf[s] { row = Double(r) } else { row = Double(sequence); sequence += 1 }   // (what has no moment of its own, one to a row from the top)
                let both = item.start.map { (sharing[$0] ?? 0) > 1 } ?? false
                let shift = both ? (item.isCard ? -45.0 : 45.0) : 0
                var n: GraphNode
                if item.isCard, let card = plan.cards[item.id] {
                    n = GraphNode(id: item.id, kind: .card, title: item.title, color: card.color)
                    n.detail = [card.text ?? "", realised(item.id) ? "" : L("Not realised by any event yet")].filter { !$0.isEmpty }.joined(separator: "\n")
                    n.hollow = !realised(item.id)
                } else {
                    n = GraphNode(id: item.id, kind: .event, title: item.title)
                }
                out.graph.nodes.append(n); out.positions[item.id] = point(row: row, strand: k, shift: shift)
                var line = GraphEdge(a: previous, b: item.id, kind: .arc, label: "", weight: 3)
                line.color = strand.color ?? "gray"
                out.graph.edges.append(line)
                previous = item.id
            }
        }
        // A card is joined to the events that realised it (wherever they stand).
        for (cid, _) in plan.cards.sorted(by: { $0.key < $1.key }) {
            for e in plan.realisedBy(cid) where out.positions[e] != nil && out.positions[cid] != nil { out.graph.edges.append(GraphEdge(a: cid, b: e, kind: .realises, label: "", weight: 1)) }
        }
        return out
    }
}
