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

@Suite("The book graph: what events change")
struct BookGraphChangeTests {
    /// The fixture, with Анна's profile and main flag changed at the arrival, the sisters becoming enemies at the departure, and Анна–Вера (friends) ending there.
    struct Changed {
        let f: BookGraphTests.Fixture
        let sisters: String, rivals: String, friends: String, start: String
    }

    static func changed() throws -> Changed {
        let f = try BookGraphTests.fixture()
        let id = f.ids
        let start = try #require(f.events.startEvent?.id)
        let rels = f.relationships.relationships
        let sisters = try #require(rels.first { $0.kind == "сёстры" }?.id), rivals = try #require(rels.first { $0.kind == "соперники" }?.id), friends = try #require(rels.first { $0.kind == "подруги" }?.id)
        try f.events.update(start) { $0.relationships = [sisters: "starts", rivals: "starts", friends: "starts"] }
        try f.events.update(id["arrival"]!) { $0.setEffect(.profile, of: id["anna"]!, text: "Стала старше."); $0.setEffectFlag(of: id["anna"]!, true) }
        try f.events.update(id["departure"]!) { $0.relationships = [friends: "ends", sisters: ""]; $0.setEffect(.kind, of: sisters, text: "враги") }
        return Changed(f: f, sisters: sisters, rivals: rivals, friends: friends, start: start)
    }

    @Test("an event that changes something is marked, and so is the line that carries the change")
    func marks() throws {
        let c = try Self.changed(); defer { try? FileManager.default.removeItem(at: c.f.parent) }
        let id = c.f.ids
        let g = c.f.graph()
        #expect(g.node(id["arrival"]!)?.changes.first?.fields == [.main, .profile] && g.node(id["arrival"]!)?.changes.first?.main == true, "the arrival changes a character")
        #expect(g.node(id["departure"]!)?.changes.contains { $0.marker == "ends" } == true && g.node(id["departure"]!)?.changes.contains { $0.fields == [.kind] } == true, "the departure ends a relationship and changes a kind")
        let line = g.edges.first { $0.kind == .takesPart && Set([$0.a, $0.b]) == Set([id["anna"]!, id["arrival"]!]) }
        #expect(line?.changes.map(\.fields) == [[.main, .profile]], "the line from the event to the character carries it")
        #expect(g.edges.first { $0.kind == .takesPart && Set([$0.a, $0.b]) == Set([id["lev"]!, id["arrival"]!]) }?.changes.isEmpty == true, "and no other line does")
        #expect(g.node(c.start) == nil && !g.nodes.contains { $0.title == "Начало книги" }, "Book starts is not drawn")
    }

    @Test("a relationship that has ended is dashed; the kinds that change are shown in order; the switch hides the ended ones")
    func ended() throws {
        let c = try Self.changed(); defer { try? FileManager.default.removeItem(at: c.f.parent) }
        let id = c.f.ids
        let g = c.f.graph()
        func pair(_ a: String, _ b: String) -> GraphEdge? { g.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([a, b]) } }
        let annaVera = pair(id["anna"]!, id["vera"]!)
        #expect(annaVera?.ended == true && annaVera?.periods.first?.to == "Отъезд" && annaVera?.periods.first?.from == nil, "friends ended at the departure, and started with the book")
        let annaLev = pair(id["anna"]!, id["lev"]!)
        #expect(annaLev?.ended == false && annaLev?.label == "сёстры → враги, соперники", "a pair is dashed only when every relationship in it has ended; the kinds are in order: \(String(describing: annaLev?.label))")
        var o = GraphOptions(); o.showEnded = false
        let hidden = c.f.graph(o)
        #expect(!hidden.edges.contains { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([id["anna"]!, id["vera"]!]) } && hidden.edges.contains { $0.kind == .relationship }, "with the switch off the ended one is not drawn, the others are")
    }

    @Test("warnings: a relationship out of order, and an event that changes something but has no scene")
    func warnings() throws {
        let c = try Self.changed(); defer { try? FileManager.default.removeItem(at: c.f.parent) }
        let id = c.f.ids
        let g0 = c.f.graph()
        #expect(g0.warningCount == 0 && g0.edges.allSatisfy { $0.problems.isEmpty } && g0.nodes.allSatisfy { !$0.doesNotApply }, "a sound book has none")
        // Лев and Вера are neighbours from the departure (second scene) to the arrival (first): the end comes before the start.
        let neighbours = try c.f.relationships.add(characters: [id["lev"]!, id["vera"]!], kind: "соседи")
        try c.f.events.update(id["departure"]!) { var m = $0.relationships; m[neighbours] = "starts"; $0.relationships = m }
        try c.f.events.update(id["arrival"]!) { var m = $0.relationships; m[neighbours] = "ends"; $0.relationships = m }
        // An event with no scene that changes a card.
        let loose = try c.f.events.add(title: "Без сцены")
        try c.f.events.update(loose) { $0.setEffect(.profile, of: id["anna"]!, text: "Где-то.") }
        let quiet = try c.f.events.add(title: "Тихое без сцены")
        let g = c.f.graph()
        let edge = g.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([id["lev"]!, id["vera"]!]) }
        #expect(edge?.problems == [.endsBeforeStart(eventTitle: "Приезд")], "the neighbours end before they start: \(String(describing: edge?.problems))")
        #expect(g.edges.filter { $0.kind == .relationship && !$0.problems.isEmpty }.count == 1, "no other line is marked")
        #expect(g.node(loose)?.doesNotApply == true && g.node(quiet)?.doesNotApply == false && g.node(id["arrival"]!)?.doesNotApply == false, "an event with changes and no scene does not apply; one that changes nothing, or has a scene, is fine")
        #expect(g.warningCount == 2)
    }

    @Test("as of a scene: what has not come yet is flagged and kept in place; relationships are as they were; a main character is one by then")
    func asOf() throws {
        let c = try Self.changed(); defer { try? FileManager.default.removeItem(at: c.f.parent) }
        let id = c.f.ids
        // Вера is met only at the departure; Лев and Вера become neighbours there.
        let neighbours = try c.f.relationships.add(characters: [id["lev"]!, id["vera"]!], kind: "соседи")
        try c.f.events.update(id["departure"]!) { var m = $0.relationships; m[neighbours] = "starts"; $0.relationships = m; var l = $0.characters; l[id["vera"]!] = ""; $0.characters = l }
        func graph(_ scene: String?, showEnded: Bool = true) -> BookGraph { var o = GraphOptions(); o.asOf = scene; o.showEnded = showEnded; return c.f.graph(o) }
        func pair(_ g: BookGraph, _ a: String, _ b: String) -> GraphEdge? { g.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([a, b]) } }

        let whole = graph(nil)
        #expect(whole.nodes.allSatisfy { !$0.notYet } && whole.edges.allSatisfy { !$0.notYet && !$0.hidden } && whole.node(id["anna"]!)?.isMain == false, "no point: the book as it is, the base cards")
        let first = graph("s1")
        #expect(first.node(id["departure"]!)?.notYet == true && first.node(id["arrival"]!)?.notYet == false, "an event after the point has not come")
        #expect(first.node(id["vera"]!)?.notYet == true && first.node(id["anna"]!)?.notYet == false && first.node(id["port"]!)?.notYet == true && first.node(id["manor"]!)?.notYet == false, "nor a character or a place that is met later")
        #expect(first.node(id["anna"]!)?.isMain == true, "a main character by the events up to the point (the arrival makes Анна one)")
        let friends = pair(first, id["anna"]!, id["vera"]!)
        #expect(friends?.ended == false && friends?.hidden == false && friends?.label == "подруги", "friends have not ended yet")
        #expect(pair(first, id["anna"]!, id["lev"]!)?.label == "сёстры, соперники", "the sisters have not become enemies yet")
        let neighbour = pair(first, id["lev"]!, id["vera"]!)
        #expect(neighbour != nil && neighbour?.notYet == true && neighbour?.hidden == true && neighbour?.label == "", "a relationship that starts later is there (so that the layout does not move) but not drawn")
        let second = graph("s2")
        #expect(pair(second, id["anna"]!, id["vera"]!)?.ended == true && pair(second, id["anna"]!, id["lev"]!)?.label == "сёстры → враги, соперники", "later: friends have ended, the sisters have become enemies")
        #expect(pair(second, id["lev"]!, id["vera"]!)?.notYet == false && second.node(id["departure"]!)?.notYet == false && second.node(id["vera"]!)?.notYet == false)
        #expect(first.nodes.map(\.id) == whole.nodes.map(\.id) && first.edges.map { $0.a + $0.b } == whole.edges.map { $0.a + $0.b }, "the same nodes and lines at every point")
        let hiddenEnded = graph("s2", showEnded: false)
        #expect(pair(hiddenEnded, id["anna"]!, id["vera"]!)?.hidden == true && pair(graph(nil, showEnded: false), id["anna"]!, id["vera"]!) == nil, "with the ended ones off they are hidden as of a point (kept for the layout), and removed with no point")
        #expect(graph("no-such-scene").nodes.allSatisfy { !$0.notYet }, "a scene that is gone is no point")
    }

    @Test("Changes only keeps the events that change something, what they change and the relationships that turn")
    func changesOnly() throws {
        let c = try Self.changed(); defer { try? FileManager.default.removeItem(at: c.f.parent) }
        let id = c.f.ids
        var o = GraphOptions(); o.changesOnly = true
        let g = c.f.graph(o)
        #expect(Set(g.nodes.map(\.id)) == [id["arrival"]!, id["departure"]!, id["anna"]!, id["lev"]!, id["vera"]!], "\(g.nodes.map(\.title))")
        #expect(g.edges.filter { $0.kind == .takesPart }.count == 1 && g.edges.filter { $0.kind == .relationship }.count == 2, "only the lines that carry a change or turn")
        try c.f.events.update(id["departure"]!) { $0.relationships = [:]; $0.effects = [:] }
        try c.f.events.update(c.start) { $0.relationships = [:] }
        let few = c.f.graph(o)
        #expect(Set(few.nodes.map(\.id)) == [id["arrival"]!, id["anna"]!], "an event that changes nothing is gone")
    }
}

@Suite("Cards realised by events")
struct CardRealisedTests {
    @Test("a card is realised by several events, the link is the card's own, and it goes when the event does")
    func links() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let plan = try PlanStore(folder: f.structure.folder)
        let card = try plan.addCard(title: "Приезд в усадьбу", color: "teal"), other = try plan.addCard(title: "Побег")
        try plan.setRealised(card: card, by: id["arrival"]!, true)
        try plan.setRealised(card: card, by: id["departure"]!, true)
        try plan.setRealised(card: card, by: id["arrival"]!, true)
        try plan.setRealised(card: card, by: "no-such-event", true)
        #expect(Set(plan.realisedBy(card)) == [id["arrival"]!, id["departure"]!] && plan.realisedBy(other).isEmpty, "several events; one that does not exist is not a link")
        #expect(plan.plannedBy(event: id["arrival"]!) == [card] && plan.plannedBy(event: id["port"]!).isEmpty, "the event knows which cards planned it")
        #expect((try PlanStore(folder: f.structure.folder)).realisedBy(card).count == 2, "kept in the card's file")
        try plan.setRealised(card: card, by: id["departure"]!, false)
        #expect(plan.realisedBy(card) == [id["arrival"]!])
        try BookIntegrity.deleteEvent(id["arrival"]!, book: f.structure.folder, started: .deleteThem, snapshot: false)
        #expect(try PlanStore(folder: f.structure.folder).realisedBy(card).isEmpty, "deleting the event takes the link away from the card")
    }

    @Test("the graph shows cards as a kind of its own, joined to the events that realise them; an unrealised card is alone")
    func graph() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let plan = try PlanStore(folder: f.structure.folder)
        let card = try plan.addCard(title: "Приезд в усадьбу", color: "teal"), idle = try plan.addCard(title: "Не написано")
        try plan.setRealised(card: card, by: id["arrival"]!, true)
        try plan.setRealised(card: card, by: id["departure"]!, true)
        func graph(_ o: GraphOptions) -> BookGraph { GraphBuilder.build(characters: f.characters, worlds: f.worlds, events: f.events, relationships: f.relationships, structure: f.structure, options: o, plan: plan) }
        #expect(!graph(GraphOptions()).nodes.contains { $0.kind == .card }, "cards are off until asked for")
        var o = GraphOptions(); o.kinds = [.character, .place, .event, .card]
        let g = graph(o)
        #expect(g.node(card)?.kind == .card && g.node(card)?.color == "teal" && g.node(card)?.title == "Приезд в усадьбу")
        #expect(g.edges.filter { $0.kind == .realises && $0.a == card }.map(\.b).sorted() == [id["arrival"]!, id["departure"]!].sorted(), "a line to each event that realises it")
        #expect(g.node(idle) != nil && !g.edges.contains { $0.a == idle || $0.b == idle }, "an idea that was never written has no line")
        o.showUnlinked = false
        #expect(graph(o).node(idle) == nil && graph(o).node(card) != nil, "and shows only with unlinked on")
        o = GraphOptions(); o.kinds = [.character, .place, .event, .card]; o.mode = .neighbourhood(id["arrival"]!, depth: 1)
        #expect(graph(o).node(card) != nil, "the neighbourhood of an event has the card that planned it")
    }
}

@Suite("The graph and the plot lines")
struct GraphPlotLineTests {
    /// The fixture's two events on two lines of the plan; Анна is in both, Лев only in the arrival; a card on the second line.
    static func lined() throws -> (f: BookGraphTests.Fixture, plan: PlanStore, one: String, two: String, card: String) {
        let f = try BookGraphTests.fixture()
        let plan = try PlanStore(folder: f.structure.folder)
        let one = try plan.addLine(name: "Усадьба", color: "teal"), two = try plan.addLine(name: "Дорога", color: "amber")
        try plan.placeEvent(f.ids["arrival"]!, onLine: one, start: 100)
        try plan.placeEvent(f.ids["departure"]!, onLine: two, start: 200)
        let card = try plan.addCard(title: "Побег", line: two, start: 300)
        try plan.setRealised(card: card, by: f.ids["departure"]!, true)
        return (f, plan, one, two, card)
    }

    @Test("a node knows the plot lines it is on: an event its own, a character or place those of its events")
    func lines() throws {
        let t = try Self.lined(); defer { try? FileManager.default.removeItem(at: t.f.parent) }
        let id = t.f.ids
        var o = GraphOptions(); o.kinds = [.character, .place, .event, .card]
        let g = GraphBuilder.build(characters: t.f.characters, worlds: t.f.worlds, events: t.f.events, relationships: t.f.relationships, structure: t.f.structure, options: o, plan: t.plan)
        #expect(g.node(id["arrival"]!)?.lines == [t.one] && g.node(id["departure"]!)?.lines == [t.two] && g.node(t.card)?.lines == [t.two])
        #expect(g.node(id["anna"]!)?.lines == [t.one, t.two], "Анна is in both events, so on both lines, in the order of the plan")
        #expect(g.node(id["lev"]!)?.lines == [t.one] && g.node(id["manor"]!)?.lines == [t.one] && g.node(id["port"]!)?.lines == [t.two])
        #expect(g.node(id["lone"]!)?.lines.isEmpty == true && g.node(id["vera"]!)?.lines.isEmpty == true, "one in no event is on no line")
        #expect(g.edges.first { $0.kind == .takesPart && Set([$0.a, $0.b]) == Set([id["lev"]!, id["arrival"]!]) }?.line == t.one && g.edges.first { $0.kind == .realises }?.line == t.two, "a line from an event carries the event's line")
        #expect(g.edges.first { $0.kind == .relationship }?.line == nil)
        let without = BookGraph(nodes: [], edges: [])
        #expect(without.nodes.isEmpty)
        let none = GraphBuilder.build(characters: t.f.characters, worlds: t.f.worlds, events: t.f.events, relationships: t.f.relationships, structure: t.f.structure, options: GraphOptions())
        #expect(none.nodes.allSatisfy { $0.lines.isEmpty }, "with no plan there are no lines")
    }

    @Test("one plot line: its events and cards with what they are linked to, and nothing of the other line")
    func filter() throws {
        let t = try Self.lined(); defer { try? FileManager.default.removeItem(at: t.f.parent) }
        let id = t.f.ids
        func build(_ line: String?) -> BookGraph {
            var o = GraphOptions(); o.kinds = [.character, .place, .event, .card]; o.plotLine = line
            return GraphBuilder.build(characters: t.f.characters, worlds: t.f.worlds, events: t.f.events, relationships: t.f.relationships, structure: t.f.structure, options: o, plan: t.plan)
        }
        #expect(Set(build(t.one).nodes.map(\.id)) == [id["arrival"]!, id["anna"]!, id["lev"]!, id["manor"]!], "the first line: its event, who is in it and where it is")
        #expect(Set(build(t.two).nodes.map(\.id)) == [id["departure"]!, id["anna"]!, id["port"]!, t.card], "the second: its event and its card, who is in it and where it is")
        #expect(build(nil).nodes.count == GraphBuilder.build(characters: t.f.characters, worlds: t.f.worlds, events: t.f.events, relationships: t.f.relationships, structure: t.f.structure, options: { var o = GraphOptions(); o.kinds = [.character, .place, .event, .card]; return o }(), plan: t.plan).nodes.count)
        var o = GraphOptions(); o.kinds = [.character, .place, .event, .card]; o.plotLine = t.two; o.mode = .social
        #expect(!GraphBuilder.build(characters: t.f.characters, worlds: t.f.worlds, events: t.f.events, relationships: t.f.relationships, structure: t.f.structure, options: o, plan: t.plan).nodes.contains { $0.id == id["lev"]! }, "it combines with the other filters")
    }
}
