import Foundation

/// The places the author has moved nodes to (`plan/graph.json`, quilland-format.md, section 21): the others are arranged by the layout each time.
public final class GraphStore {
    public let folder: URL
    public private(set) var positions: [String: GraphPoint] = [:]

    public init(folder: URL) {
        self.folder = folder
        reload()
    }

    private var url: URL { folder.appendingPathComponent("plan/graph.json") }

    public func reload() {
        positions = [:]
        guard let data = try? Data(contentsOf: url), let o = try? JSONParser.parseObject(data), let list = o.object("positions") else { return }
        for (id, value) in list {
            if case .object(let p) = value, let x = p.int("x"), let y = p.int("y") { positions[id] = GraphPoint(x: Double(x), y: Double(y)) }
        }
    }

    /// Keeps a node where the author put it.
    public func pin(_ id: String, at point: GraphPoint) throws {
        positions[id] = GraphPoint(x: point.x.rounded(), y: point.y.rounded())
        try save()
    }

    /// Lets the layout place a node again.
    public func release(_ id: String) throws {
        guard positions.removeValue(forKey: id) != nil else { return }
        try save()
    }

    public func releaseAll() throws {
        guard !positions.isEmpty else { return }
        positions = [:]
        try save()
    }

    private func save() throws {
        if positions.isEmpty { try? FileManager.default.removeItem(at: url); return }
        var list: JSONObject = [:]
        for (id, p) in positions { list[id] = .object(["x": .int(Int(p.x)), "y": .int(Int(p.y))]) }
        let o: JSONObject = ["format": .int(1), "positions": .object(list)]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(o), to: url)
    }
}
