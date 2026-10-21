import Foundation

public struct GraphPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Puts the nodes of a graph on a plane: linked ones near each other, the others apart. The result depends only on the input (no random numbers), so the
/// same graph always looks the same, and the nodes the author has moved (`pinned`) stay where they were put, with the others arranged around them.
///
/// Each group of nodes that are joined to each other is arranged by itself (a force-directed layout), and the groups are then packed side by side in rows,
/// the big ones first and the single nodes last, so that a node with no lines does not drift away and make everything else small.
public enum GraphLayout {
    /// The distance a line "wants" to be, in points.
    public static let spacing = 110.0
    private static let gap = 90.0

    public static func layout(nodes: [GraphNode], edges: [GraphEdge], pinned: [String: GraphPoint] = [:]) -> [String: GraphPoint] {
        let ids = nodes.map(\.id).sorted()
        guard !ids.isEmpty else { return [:] }
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let links: [(Int, Int, Double)] = edges.compactMap { e in
            guard let a = index[e.a], let b = index[e.b], a != b else { return nil }
            return (a, b, 1 + 0.25 * Double(max(0, e.weight - 1)))
        }
        // The groups of joined nodes.
        var parent = Array(0..<ids.count)
        func find(_ x: Int) -> Int { var r = x; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        for (a, b, _) in links { let (ra, rb) = (find(a), find(b)); if ra != rb { parent[max(ra, rb)] = min(ra, rb) } }
        var groups: [Int: [Int]] = [:]
        for i in 0..<ids.count { groups[find(i), default: []].append(i) }
        let ordered = groups.values.sorted { ($0.count, $1[0]) > ($1.count, $0[0]) }.map { $0.sorted() }

        var out: [String: GraphPoint] = [:]
        var free: [(members: [Int], points: [GraphPoint], width: Double, height: Double)] = []
        var anchorBottom = -Double.infinity, anchorLeft = Double.infinity
        for members in ordered {
            let fixed = members.map { pinned[ids[$0]] }
            let local = Dictionary(uniqueKeysWithValues: members.enumerated().map { ($1, $0) })
            let inner = links.compactMap { l -> (Int, Int, Double)? in
                guard let a = local[l.0], let b = local[l.1] else { return nil }
                return (a, b, l.2)
            }
            let pts = arrange(count: members.count, links: inner, fixed: fixed)
            if fixed.contains(where: { $0 != nil }) {
                // A group with a node the author moved keeps its place (the rest of it is arranged around that node).
                for (k, m) in members.enumerated() { out[ids[m]] = pts[k] }
                anchorBottom = max(anchorBottom, pts.map(\.y).max() ?? 0)
                anchorLeft = min(anchorLeft, pts.map(\.x).min() ?? 0)
            } else {
                let minX = pts.map(\.x).min() ?? 0, maxX = pts.map(\.x).max() ?? 0, minY = pts.map(\.y).min() ?? 0, maxY = pts.map(\.y).max() ?? 0
                free.append((members, pts.map { GraphPoint(x: $0.x - minX, y: $0.y - minY) }, maxX - minX, maxY - minY))
            }
        }
        // Packing: rows as wide as a square of the same total area would be.
        let area = free.reduce(0.0) { $0 + ($1.width + gap) * ($1.height + gap) }
        let rowWidth = max(900, area.squareRoot() * 1.3)
        var x = anchorLeft.isFinite ? anchorLeft : 0
        let startX = x
        var y = anchorBottom.isFinite ? anchorBottom + gap * 1.5 : 0
        var rowHeight = 0.0
        for g in free {
            if x > startX, x - startX + g.width > rowWidth { x = startX; y += rowHeight + gap; rowHeight = 0 }
            for (k, m) in g.members.enumerated() { out[ids[m]] = GraphPoint(x: (g.points[k].x + x).rounded(), y: (g.points[k].y + y).rounded()) }
            x += g.width + gap
            rowHeight = max(rowHeight, g.height)
        }
        return out
    }

    /// One group by itself: a force-directed arrangement; the nodes in `fixed` do not move.
    private static func arrange(count n: Int, links: [(Int, Int, Double)], fixed: [GraphPoint?]) -> [GraphPoint] {
        if n == 1 { return [fixed[0] ?? GraphPoint(x: 0, y: 0)] }
        var px = [Double](repeating: 0, count: n), py = [Double](repeating: 0, count: n)
        for i in 0..<n {
            if let p = fixed[i] { px[i] = p.x; py[i] = p.y; continue }
            // Start on a spiral, so that no two nodes begin on the same spot.
            let radius = spacing * 0.6 * Double(i + 1).squareRoot()
            let angle = Double(i) * 2.399963
            px[i] = radius * cos(angle); py[i] = radius * sin(angle)
        }
        let k = spacing
        let rounds = max(60, min(300, 250_000 / max(1, n * n / 4)))
        var temperature = k * 2
        var dx = [Double](repeating: 0, count: n), dy = [Double](repeating: 0, count: n)
        for _ in 0..<rounds {
            for i in 0..<n { dx[i] = 0; dy[i] = 0 }
            for i in 0..<n { for j in (i + 1)..<max(n, i + 1) {
                var ex = px[i] - px[j], ey = py[i] - py[j]
                var d2 = ex * ex + ey * ey
                if d2 < 0.01 { ex = Double(i - j); ey = 1; d2 = ex * ex + ey * ey }
                let force = k * k / d2
                dx[i] += ex * force; dy[i] += ey * force
                dx[j] -= ex * force; dy[j] -= ey * force
            } }
            for (a, b, w) in links {
                let ex = px[a] - px[b], ey = py[a] - py[b]
                let d = max(0.1, (ex * ex + ey * ey).squareRoot())
                let force = d / k * w
                dx[a] -= ex * force; dy[a] -= ey * force
                dx[b] += ex * force; dy[b] += ey * force
            }
            for i in 0..<n where fixed[i] == nil {
                dx[i] -= px[i] * 0.03; dy[i] -= py[i] * 0.03
                let len = max(0.01, (dx[i] * dx[i] + dy[i] * dy[i]).squareRoot())
                let step = min(len, temperature)
                px[i] += dx[i] / len * step; py[i] += dy[i] / len * step
            }
            temperature = max(1, temperature * 0.97)
        }
        return (0..<n).map { fixed[$0] ?? GraphPoint(x: px[$0].rounded(), y: py[$0].rounded()) }
    }
}
