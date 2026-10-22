import Foundation
import Testing
@testable import QuillandCore

@Suite("The book graph")
struct BookGraphTests {
    struct Fixture {
        let parent: URL
        let characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore
        let structure: BookStructure
        let ids: [String: String]

        func graph(_ options: GraphOptions = GraphOptions()) -> BookGraph {
            GraphBuilder.build(characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure, options: options)
        }
    }

    static func fixture() throws -> Fixture {
        let parent = try NewBookTests.folder()
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        var structure = BookStructure(folder: book)
        func scene(_ id: String, _ title: String) -> BookStructure.Node { BookStructure.Node(id: id, kind: .scene, title: title, status: nil, base: id, children: []) }
        structure.scenes = [
            BookStructure.SceneEntry(node: scene("s1", "Сцена 1"), chapterID: "ch1", chapterTitle: "Глава 1", partID: nil, partTitle: nil),
            BookStructure.SceneEntry(node: scene("s2", "Сцена 2"), chapterID: "ch1", chapterTitle: "Глава 1", partID: nil, partTitle: nil),
        ]
        let people = CharacterStore(book: book)
        let anna = try people.add(name: "Анна"), lev = try people.add(name: "Лев"), vera = try people.add(name: "Вера"), lone = try people.add(name: "Одинокий")
        let worlds = WorldStore(book: book)
        let world = try #require(worlds.worlds.first?.id)
        let manor = try worlds.addEntry(name: "Усадьба", world: world), port = try worlds.addEntry(name: "Космопорт", world: world), nowhere = try worlds.addEntry(name: "Нигдевия", world: world)
        let events = EventStore(book: book)
        let arrival = try events.add(title: "Приезд"), departure = try events.add(title: "Отъезд")
        try events.update(arrival) { $0.links = ["s1": ""]; $0.places = [manor: ""] }
        try events.update(departure) { $0.links = ["s2": ""]; $0.places = [port: ""] }
        try events.update(arrival) { $0.characters = [anna: "", lev: ""] }
        try events.update(departure) { $0.characters = [anna: ""] }
        try people.update(anna) { $0.links = ["s1": "в доме"] }
        try people.update(lev) { $0.povScenes = ["s2"] }
        try worlds.updateEntry(manor) { $0.links = ["s1": "тут"] }
        let relationships = RelationshipStore(book: book)
        _ = try relationships.add(characters: [anna, lev], kind: "сёстры")
        _ = try relationships.add(characters: [lev, anna], kind: "соперники")
        _ = try relationships.add(characters: [anna, vera], kind: "подруги")
        return Fixture(parent: parent, characters: people, worlds: worlds, events: events, relationships: relationships, structure: structure,
                       ids: ["anna": anna, "lev": lev, "vera": vera, "lone": lone, "manor": manor, "port": port, "nowhere": nowhere, "arrival": arrival, "departure": departure])
    }

    @Test("the whole book: the kinds switched on, with the links between them")
    func whole() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let g = f.graph()
        #expect(Set(g.nodes.map(\.kind)) == [.character, .place, .event], "scenes are off by default")
        #expect(g.nodes.count == 4 + 3 + 2)
        func has(_ a: String, _ b: String, _ kind: GraphEdge.Kind) -> Bool { g.edges.contains { $0.kind == kind && Set([$0.a, $0.b]) == Set([a, b]) } }
        #expect(has(id["anna"]!, id["arrival"]!, .takesPart) && has(id["anna"]!, id["departure"]!, .takesPart) && has(id["lev"]!, id["arrival"]!, .takesPart))
        #expect(has(id["arrival"]!, id["manor"]!, .heldAt) && has(id["departure"]!, id["port"]!, .heldAt))
        #expect(!g.edges.contains { $0.kind == .inScene }, "a scene is not drawn, so its lines are not")
        var withScenes = GraphOptions(); withScenes.kinds = Set(GraphKind.allCases)
        let all = f.graph(withScenes)
        func hasAll(_ a: String, _ b: String) -> Bool { all.edges.contains { $0.kind == .inScene && Set([$0.a, $0.b]) == Set([a, b]) } }
        #expect(hasAll(id["arrival"]!, "s1") && hasAll(id["anna"]!, "s1") && hasAll(id["manor"]!, "s1") && hasAll(id["lev"]!, "s2"), "an event's scene, a character's line, a place's line, a point of view")
    }

    @Test("a character marked as a main one is marked in the graph, and only a character")
    func mainCharacters() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        try f.characters.update(f.ids["anna"]!) { $0.main = true }
        let g = f.graph()
        #expect(g.node(f.ids["anna"]!)?.isMain == true, "a main character")
        #expect(g.nodes.filter(\.isMain).map(\.id) == [f.ids["anna"]!], "and no one else, nor any place or event")
    }

    @Test("a relationship is one line between two characters, whatever order and however many are made")
    func relationships() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let rel = f.graph().edges.filter { $0.kind == .relationship }
        #expect(rel.count == 2, "\(rel)")
        let pair = rel.first { Set([$0.a, $0.b]) == Set([id["anna"]!, id["lev"]!]) }
        #expect(pair?.label == "сёстры, соперники", "the kinds between the same two are put together: \(String(describing: pair?.label))")
        #expect(pair?.weight == 2, "1 and the one event the two share")
    }

    @Test("the social graph is the characters and their relationships only")
    func social() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        var o = GraphOptions(); o.mode = .social
        let g = f.graph(o)
        #expect(g.nodes.allSatisfy { $0.kind == .character } && g.edges.allSatisfy { $0.kind == .relationship })
        #expect(g.nodes.contains { $0.id == f.ids["lone"] }, "unlinked ones are shown unless asked not to")
        o.showUnlinked = false
        let linked = f.graph(o)
        #expect(!linked.nodes.contains { $0.id == f.ids["lone"] } && linked.nodes.count == 3, "with unlinked off, a character with no relationship goes")
    }

    @Test("a neighbourhood is one thing and what is around it, a step or two out")
    func neighbourhood() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        var o = GraphOptions(); o.mode = .neighbourhood(id["manor"]!, depth: 1)
        #expect(Set(f.graph(o).nodes.map(\.id)) == [id["manor"]!, id["arrival"]!], "the place and its event")
        o.mode = .neighbourhood(id["manor"]!, depth: 2)
        #expect(Set(f.graph(o).nodes.map(\.id)) == [id["manor"]!, id["arrival"]!, id["anna"]!, id["lev"]!], "and the characters of the event")
        o.kinds = [.place]
        #expect(Set(f.graph(o).nodes.map(\.id)) == [id["manor"]!], "kinds switched off are left out, the focus stays")
        o.mode = .neighbourhood("nothing", depth: 1)
        #expect(f.graph(o).nodes.isEmpty, "a focus that is gone shows nothing")
    }

    @Test("a section limits what is shown, and unlinked things can be hidden")
    func filters() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        var o = GraphOptions(); o.allowed = [id["anna"]!, id["arrival"]!, id["manor"]!]
        let g = f.graph(o)
        #expect(Set(g.nodes.map(\.id)) == o.allowed && g.edges.count == 2)
        o = GraphOptions(); o.showUnlinked = false
        let ids = Set(f.graph(o).nodes.map(\.id))
        #expect(!ids.contains(id["lone"]!) && !ids.contains(id["nowhere"]!) && ids.contains(id["anna"]!), "a character with no event and a place no event uses are hidden")
    }

    @Test("the layout is the same every time, keeps what was moved where it was put, and does not pile nodes up")
    func layout() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let g = f.graph()
        let a = GraphLayout.layout(nodes: g.nodes, edges: g.edges), b = GraphLayout.layout(nodes: g.nodes, edges: g.edges)
        #expect(a == b && a.count == g.nodes.count, "deterministic")
        let anna = f.ids["anna"]!
        let moved = GraphLayout.layout(nodes: g.nodes, edges: g.edges, pinned: [anna: GraphPoint(x: 900, y: -400)])
        #expect(moved[anna] == GraphPoint(x: 900, y: -400), "a pinned node stays")
        let points = Array(a.values)
        var closest = Double.infinity
        for i in 0..<points.count { for j in (i + 1)..<points.count { closest = min(closest, hypot(points[i].x - points[j].x, points[i].y - points[j].y)) } }
        #expect(closest > 30, "no two nodes on top of each other: \(closest)")
        let linked = hypot(a[anna]!.x - a[f.ids["arrival"]!]!.x, a[anna]!.y - a[f.ids["arrival"]!]!.y)
        let apart = hypot(a[anna]!.x - a[f.ids["port"]!]!.x, a[anna]!.y - a[f.ids["port"]!]!.y)
        #expect(linked < GraphLayout.spacing * 2.5 && linked.isFinite && apart.isFinite, "linked ones are near: \(linked)")
        #expect(GraphLayout.layout(nodes: [], edges: []).isEmpty)
        let single = GraphLayout.layout(nodes: [GraphNode(id: "x", kind: .place, title: "x")], edges: [])
        #expect(single.count == 1)
    }

    @Test("things with no lines are packed together and do not drift away")
    func unlinked() {
        var nodes: [GraphNode] = [], edges: [GraphEdge] = []
        for i in 0..<12 { nodes.append(GraphNode(id: "c\(i)", kind: .character, title: "")) }
        for i in 1..<12 { edges.append(GraphEdge(a: "c\(i)", b: "c\(i / 2)", kind: .takesPart, label: "", weight: 1)) }
        for i in 0..<40 { nodes.append(GraphNode(id: "u\(i)", kind: .place, title: "")) }
        for (a, b) in [("p1", "p2"), ("p3", "p4")] { nodes.append(GraphNode(id: a, kind: .character, title: "")); nodes.append(GraphNode(id: b, kind: .character, title: "")); edges.append(GraphEdge(a: a, b: b, kind: .relationship, label: "x", weight: 1)) }
        let out = GraphLayout.layout(nodes: nodes, edges: edges)
        let xs = out.values.map(\.x), ys = out.values.map(\.y)
        let width = xs.max()! - xs.min()!, height = ys.max()! - ys.min()!
        #expect(width < 2500 && height < 2500, "\(width) x \(height)")
        let closest = out.values.enumerated().flatMap { i, a in out.values.dropFirst(i + 1).map { hypot(a.x - $0.x, a.y - $0.y) } }.min() ?? 0
        #expect(closest > 30, "\(closest)")
        let pinned = GraphLayout.layout(nodes: nodes, edges: edges, pinned: ["u3": GraphPoint(x: 5000, y: 5000)])
        #expect(pinned["u3"] == GraphPoint(x: 5000, y: 5000) && pinned.count == nodes.count, "a pinned single node stays; the rest are still arranged")
    }

    @Test("a big book is laid out in reasonable time")
    func big() {
        var nodes: [GraphNode] = [], edges: [GraphEdge] = []
        for i in 0..<600 { nodes.append(GraphNode(id: "n\(i)", kind: .character, title: "n\(i)")) }
        for i in 1..<600 { edges.append(GraphEdge(a: "n\(i)", b: "n\(i / 2)", kind: .takesPart, label: "", weight: 1)) }
        let start = Date()
        let out = GraphLayout.layout(nodes: nodes, edges: edges)
        #expect(out.count == 600 && Date().timeIntervalSince(start) < 5, "\(Date().timeIntervalSince(start)) s")
    }

    @Test("the places the author moved nodes to are kept in the book")
    func store() throws {
        let parent = try NewBookTests.folder(); defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let s = GraphStore(folder: book)
        #expect(s.positions.isEmpty)
        try s.pin("a", at: GraphPoint(x: 10.4, y: -20.6)); try s.pin("b", at: GraphPoint(x: 5, y: 5))
        let again = GraphStore(folder: book)
        #expect(again.positions["a"] == GraphPoint(x: 10, y: -21) && again.positions["b"] == GraphPoint(x: 5, y: 5), "saved, rounded to whole points")
        try again.release("a")
        #expect(GraphStore(folder: book).positions.keys.sorted() == ["b"])
        try again.releaseAll()
        #expect(GraphStore(folder: book).positions.isEmpty && !FileManager.default.fileExists(atPath: book.appendingPathComponent("plan/graph.json").path), "nothing left: no file")
    }
}
