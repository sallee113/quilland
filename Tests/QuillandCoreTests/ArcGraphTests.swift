import Foundation
import Testing
@testable import QuillandCore

@Suite("The arc of a character as a graph")
struct ArcGraphTests {
    static func arc(_ c: BookGraphChangeTests.Changed, structure: BookStructure? = nil) -> ArcGraph {
        let f = c.f
        return ArcBuilder.build(character: f.ids["anna"]!, characters: f.characters, worlds: f.worlds, events: f.events, relationships: f.relationships, structure: structure ?? f.structure)
    }

    @Test("the spine, the states, the relationships and the places, each where it belongs")
    func shape() throws {
        let c = try BookGraphChangeTests.changed(); defer { try? FileManager.default.removeItem(at: c.f.parent) }
        let id = c.f.ids
        try c.f.characters.setProfile(id["anna"]!, "Тихая девочка.")
        let a = Self.arc(c), g = a.graph
        func at(_ id: String) -> GraphPoint { a.positions[id]! }
        let anna = id["anna"]!, arrival = id["arrival"]!, departure = id["departure"]!
        #expect(Set(g.nodes.map(\.id)) == [anna, arrival, departure, ArcBuilder.stateID(nil), ArcBuilder.stateID(arrival), id["lev"]!, id["vera"]!, id["manor"]!, id["port"]!], "the character, their events, two states, the others they are tied to, the places")
        func has(_ x: String, _ y: String, _ kind: GraphEdge.Kind) -> Bool { g.edges.contains { $0.kind == kind && Set([$0.a, $0.b]) == Set([x, y]) } }
        #expect(has(anna, arrival, .arc) && has(arrival, departure, .arc), "the spine joins the character to the events, in the order of the book")
        #expect(at(anna).x < at(arrival).x && at(arrival).x < at(departure).x && at(anna).y < at(arrival).y && at(arrival).y < at(departure).y, "and runs from the top left to the bottom right")
        let start = g.node(ArcBuilder.stateID(nil))!, made = g.node(ArcBuilder.stateID(arrival))!
        #expect(start.title == "Тихая девочка." && !start.isMain && made.title.contains("Стала старше.") && made.title.contains("becomes a main character") && made.isMain, "the states: the card as it is, then what the arrival makes of it")
        #expect(at(made.id).x > at(arrival).x && at(made.id).y < at(arrival).y && at(start.id).y < at(anna).y, "they hang on the upper right")
        #expect(has(start.id, made.id, .arc) && has(arrival, made.id, .arc) && has(anna, start.id, .arc), "joined in a line of their own and to their events")
        #expect(at(id["lev"]!).x < at(anna).x && at(id["lev"]!).y > at(anna).y && at(id["manor"]!).x < at(arrival).x && at(id["manor"]!).y > at(arrival).y, "the relationships and the places on the lower left")
        let lev = g.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([id["lev"]!, anna]) }, vera = g.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([id["vera"]!, anna]) }
        #expect(lev?.label == "сёстры → враги, соперники" && lev?.ended == false, "a relationship with its kinds in order: \(String(describing: lev?.label))")
        #expect(vera?.ended == true && vera?.periods.first?.to == "Отъезд", "one that has ended says where")
        #expect(has(arrival, id["manor"]!, .heldAt) && has(departure, id["port"]!, .heldAt))
        #expect(g.node(arrival)?.changes.isEmpty == false, "the Δ of an event that changes something")
        #expect(Self.arc(c) .positions == a.positions, "the same every time")
        #expect(g.node(anna)?.anchored == true && g.node(arrival)?.anchored == true && g.node(departure)?.anchored == true, "the spine cannot be moved")
        #expect(g.nodes.filter { !$0.anchored }.count == 6 && g.node(id["lev"]!)?.anchored == false && g.node(made.id)?.anchored == false && g.node(id["manor"]!)?.anchored == false, "what hangs on it can: the states, the others, the places")
    }

    @Test("a long absence shows on the spine, and an event with no scene comes last and does not apply")
    func gaps() throws {
        let c = try BookGraphChangeTests.changed(); defer { try? FileManager.default.removeItem(at: c.f.parent) }
        let id = c.f.ids
        var st = c.f.structure
        func scene(_ n: Int) -> BookStructure.SceneEntry {
            BookStructure.SceneEntry(node: BookStructure.Node(id: "s\(n)", kind: .scene, title: "Сцена \(n)", status: nil, base: "s\(n)", children: []), chapterID: "ch1", chapterTitle: "Глава 1", partID: nil, partTitle: nil)
        }
        st.scenes = (1...8).map(scene)
        try c.f.events.update(id["departure"]!) { $0.links = ["s8": ""] }
        let loose = try c.f.events.add(title: "Без сцены")
        try c.f.events.update(loose) { $0.setEffect(.profile, of: id["anna"]!, text: "Где-то.") }
        let a = Self.arc(c, structure: st), g = a.graph
        let spine = g.edges.first { $0.kind == .arc && Set([$0.a, $0.b]) == Set([id["arrival"]!, id["departure"]!]) }
        #expect(spine?.gap == 6 && spine?.label == "6 scenes without them", "six scenes between: the line says so")
        #expect(a.positions[id["departure"]!]!.x - a.positions[id["arrival"]!]!.x > 175 * 1.5, "and the absence is distance too: the step is longer than the usual one")
        #expect(g.node(loose)?.doesNotApply == true && g.node(loose)?.notYet == true && a.positions[loose]!.x > a.positions[id["departure"]!]!.x, "an event with no scene is last, faded and warned")
    }
}

@Suite("The place tree")
struct PlaceTreeTests {
    @Test("a world is the root, a place hangs from the place it is in; the tree runs left to right with parents in the middle of their children")
    func tree() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let world = try #require(f.worlds.worlds.first?.id)
        let germany = try f.worlds.addEntry(name: "Германия", world: world)
        let frankfurt = try f.worlds.addEntry(name: "Франкфурт", world: world, parent: germany), berlin = try f.worlds.addEntry(name: "Берлин", world: world, parent: germany)
        let station = try f.worlds.addEntry(name: "Вокзал", world: world, parent: frankfurt)
        let other = try f.worlds.addWorld(name: "Флора"), flora = try f.worlds.addEntry(name: "Столица", world: other)
        try f.events.update(id["arrival"]!) { $0.places[station] = ""; $0.setEffect(.description, of: station, text: "Сгорел.") }
        func tree(_ only: String? = nil) -> ArcGraph { PlaceTreeBuilder.build(only: only, characters: f.characters, worlds: f.worlds, events: f.events, relationships: f.relationships) }
        let t = tree(), g = t.graph
        func at(_ id: String) -> GraphPoint { t.positions[id]! }
        func has(_ a: String, _ b: String) -> Bool { g.edges.contains { $0.kind == .contains && $0.a == a && $0.b == b } }
        #expect(g.node(world)?.kind == .world && g.node(other)?.kind == .world && g.node(germany)?.kind == .place)
        #expect(has(world, germany) && has(germany, frankfurt) && has(germany, berlin) && has(frankfurt, station) && has(other, flora), "each is joined to what it is inside")
        #expect(at(world).x == 0 && at(germany).x < at(frankfurt).x && at(frankfurt).x < at(station).x && at(berlin).x == at(frankfurt).x, "the tree runs from the left to the right, one column for each depth")
        #expect(at(berlin).y < at(frankfurt).y, "the children are in order of their names (Берлин before Франкфурт)")
        let mid = (at(berlin).y + at(frankfurt).y) / 2
        #expect(at(germany).y == mid, "a parent is in the middle of its children")
        #expect(g.node(station)?.changes.isEmpty == false && g.node(station)?.detail.contains("1 event here") == true, "what events change in a place (Δ), and how many events are held there")
        #expect(Set(g.nodes.map(\.id)).isSuperset(of: [id["manor"]!, id["port"]!, id["nowhere"]!]), "the fixture's flat places are children of their world")
        #expect(Set(tree(other).graph.nodes.map(\.id)) == [other, flora], "one world alone")
        #expect(tree().positions == t.positions, "the same every time")
        #expect(g.node(world)?.anchored == true && g.node(other)?.anchored == true && g.node(germany)?.anchored == false && g.node(station)?.anchored == false, "the worlds stay where they are, the places can be moved")
    }
}

@Suite("Locations along the book")
struct LocationsTests {
    static func build(_ f: BookGraphTests.Fixture, only: String? = nil) -> ArcGraph {
        LocationsBuilder.build(only: only, characters: f.characters, worlds: f.worlds, events: f.events, structure: f.structure)
    }

    @Test("each scene is a bush of its own: a scene with one place is that place on the spine, and each place has its characters")
    func bushes() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let a = Self.build(f), g = a.graph
        func at(_ id: String) -> GraphPoint { a.positions[id]! }
        let first = "bush:s1|\(id["manor"]!)", second = "bush:s2|\(id["port"]!)"
        #expect(Set(g.nodes.map(\.id)) == [first, second, first + "|" + id["anna"]!, first + "|" + id["lev"]!, second + "|" + id["anna"]!], "a scene with one place has no node of its own, and characters are per place and scene: \(g.nodes.map(\.id))")
        #expect(g.node(first)?.kind == .place && g.node(first)?.ref == id["manor"]! && g.node(first)?.scene == "s1" && g.node(first)?.detail == "Сцена 1", "the place stands for the scene; the scene's title is its detail")
        #expect(g.edges.contains { $0.kind == .arc && $0.a == first && $0.b == second }, "the spine joins the scenes in the order of the book")
        #expect(at(first).x < at(second).x && at(first).y < at(second).y, "from the top left to the bottom right")
        #expect(at(first + "|" + id["lev"]!).y > at(first).y && at(first + "|" + id["lev"]!).x < at(first).x, "the characters hang on the lower left of their place")
        #expect(g.edges.contains { $0.kind == .wasAt && $0.a == first && $0.b == first + "|" + id["anna"]! })
        #expect(g.node(first)?.anchored == true && g.node(second)?.anchored == true && g.node(first + "|" + id["lev"]!)?.anchored == false, "a place that stands for its scene is on the spine; the characters of a bush can be moved")
        // A scene with two places: the scene has its node, the places hang from it, and a place that comes back is a new node.
        try f.events.update(id["arrival"]!) { $0.places = [id["manor"]!: "", id["port"]!: ""] }
        let b = Self.build(f).graph
        #expect(b.node("s1")?.kind == .scene && b.node("s1")?.title == "Сцена 1", "several places: the scene is a node")
        #expect(b.node("s1")?.anchored == true && b.node("bush:s1|\(id["manor"]!)")?.anchored == false, "the scene is on the spine, its places are not")
        #expect(b.nodes.filter { $0.ref == id["port"]! }.count == 2 && b.edges.contains { $0.kind == .heldAt && $0.a == "s1" && $0.b == "bush:s1|\(id["port"]!)" }, "the same place in two scenes is two nodes, joined to its own scene")
        // One character: the scenes where they are at a place, and only they in the bushes.
        let lev = Self.build(f, only: id["lev"]!).graph
        #expect(Set(lev.nodes.filter { $0.kind == .character }.map(\.ref)) == [id["lev"]!] && !lev.nodes.contains { $0.scene == "s2" }, "only the scenes where Лев is at a place")
        #expect(Self.build(f).positions == Self.build(f).positions, "the same every time")
    }

    @Test("a place inside another is a chain: the scene, the parent place (not the world), the place, and its characters; a parent shared by two places of a scene is one node")
    func chains() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let world = try #require(f.worlds.worlds.first?.id)
        let planet = try f.worlds.addEntry(name: "Флора 9", world: world)
        try f.worlds.updateEntry(id["manor"]!) { $0.parent = planet }
        let g = Self.build(f).graph
        let chain = "bush:s1|\(planet)", manor = "bush:s1|\(id["manor"]!)"
        #expect(g.node("s1")?.kind == .scene, "a place with a parent: the scene has its node again")
        #expect(g.node(chain)?.title == "Флора 9" && g.node(chain)?.isContext == true && g.node(manor)?.isContext == false, "the parent is a node, lighter than the place that is linked")
        #expect(g.edges.contains { $0.kind == .heldAt && $0.a == "s1" && $0.b == chain } && g.edges.contains { $0.kind == .contains && $0.a == chain && $0.b == manor } && g.edges.contains { $0.kind == .wasAt && $0.a == manor && $0.b == manor + "|" + id["anna"]! }, "scene → parent → place → characters")
        #expect(!g.nodes.contains { $0.title == world || $0.ref == world }, "the world is not in the chain")
        // Two places of the scene inside the same parent share it; a deeper chain goes all the way up.
        let inner = try f.worlds.addEntry(name: "Комната", world: world, parent: id["manor"]!)
        try f.events.update(id["arrival"]!) { $0.places = [id["manor"]!: "", inner: "", id["port"]!: ""] }
        try f.worlds.updateEntry(id["port"]!) { $0.parent = planet }
        let h = Self.build(f).graph
        #expect(h.nodes.filter { $0.ref == planet && $0.scene == "s1" }.count == 1, "the parent is one node for both places")
        #expect(h.edges.contains { $0.kind == .contains && $0.a == manor && $0.b == "bush:s1|\(inner)" }, "a place inside a place inside a place is a longer chain")
        #expect(h.nodes.filter { $0.ref == planet }.count == 2, "and in the second scene it is a node of that scene's bush")
    }
}

@Suite("The plan map")
struct PlanMapTests {
    @Test("a strand for each plot line, side by side from the top left to the bottom right, cards and events in the order of the plan; a card no event has realised is hollow")
    func strands() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let plan = try PlanStore(folder: f.structure.folder)
        let one = try plan.addLine(name: "Усадьба", color: "teal"), two = try plan.addLine(name: "Дорога", color: "amber")
        try plan.placeEvent(id["arrival"]!, onLine: one, start: 100); try plan.placeEvent(id["departure"]!, onLine: two, start: 200)
        let idea = try plan.addCard(title: "Идея", line: one, start: 100, color: "pink"), written = try plan.addCard(title: "Написано", line: two, start: 300, color: "green")
        let floating = try plan.addCard(title: "Плавающая", x: 10, y: 10)
        try plan.setRealised(card: written, by: id["departure"]!, true)
        let a = PlanMapBuilder.build(plan: plan, events: f.events), g = a.graph
        func at(_ id: String) -> GraphPoint { a.positions[id]! }
        let headOne = "plan:line:\(one)", headTwo = "plan:line:\(two)"
        #expect(g.node(headOne)?.title == "Усадьба" && g.node(headOne)?.color == "teal" && g.node(headTwo)?.color == "amber" && g.node(PlanMapBuilder.looseStrand.isEmpty ? "" : "plan:line:" + PlanMapBuilder.looseStrand)?.title == "Not on a line", "a head for each strand, in the colour of its line, and one for what is on no line")
        #expect(g.node(id["arrival"]!)?.kind == .event && g.node(idea)?.kind == .card && g.node(idea)?.color == "pink", "events and cards, a card in its own colour")
        #expect(g.edges.contains { $0.kind == .arc && $0.a == headOne && $0.color == "teal" } && g.edges.contains { $0.kind == .arc && $0.b == written && $0.color == "amber" }, "each strand is a line in its colour")
        #expect(g.edges.contains { $0.kind == .realises && $0.a == written && $0.b == id["departure"]! }, "a card is joined to the event that realised it, across strands")
        #expect(g.node(idea)?.hollow == true && g.node(written)?.hollow == false && g.node(floating)?.hollow == true && g.node(idea)?.detail.contains("Not realised") == true, "a card nobody has realised is hollow")
        func along(_ p: GraphPoint) -> Double { p.x * 0.84 + p.y * 0.54 }   // how far down the diagonal
        #expect(along(at(id["arrival"]!)) < along(at(id["departure"]!)) && along(at(id["departure"]!)) < along(at(written)), "the plan's moments run along the diagonal from the top left to the bottom right, whatever the strand")
        // Two strands side by side: the same moment is level across them; at one moment a card and an event of a strand are apart.
        #expect(at(headOne).x != at(headTwo).x && at(headOne).y != at(headTwo).y, "the strands are side by side")
        #expect(at(idea) != at(id["arrival"]!), "a card and an event at one moment are not on top of each other")
        #expect(PlanMapBuilder.build(plan: plan, events: f.events).positions == a.positions, "the same every time")
        #expect(g.nodes.allSatisfy { $0.anchored }, "the strands are the plan itself: nothing there moves")
        #expect(PlanMapBuilder.build(plan: try PlanStore(folder: try PlanTests.folder()), events: f.events).graph.nodes.isEmpty, "an empty plan is an empty map")
    }

    @Test("the bushes stand on both sides of the spine, and the main line can run another way")
    func sidesAndDirections() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let world = try #require(f.worlds.worlds.first?.id)
        let hall = try f.worlds.addEntry(name: "Зал", world: world)
        try f.events.update(id["arrival"]!) { $0.places = [id["manor"]!: "", id["port"]!: ""] }
        try f.events.update(id["departure"]!) { $0.places = [id["port"]!: "", hall: ""] }
        let a = LocationsTests.build(f)
        func at(_ id: String) -> GraphPoint { a.positions[id]! }
        // Which side of the spine a place stands on: along the normal of the spine (lower left is positive).
        func side(_ scene: String, _ place: String) -> Double {
            let p = at("bush:\(scene)|\(place)"), o = at(scene)
            return (p.x - o.x) * -0.54 + (p.y - o.y) * 0.84
        }
        #expect(side("s1", id["manor"]!) > 0 && side("s2", id["port"]!) < 0, "the first bush hangs on the lower left, the next on the upper right")
        // The spine is shorter than when every bush had to make room for the one before it.
        #expect(at("s2").x - at("s1").x < 190, "neighbouring scenes on opposite sides stand close on the spine: \(at("s2").x - at("s1").x)")

        // The directions: the same picture, turned.
        let spine = ["s1", "s2"]
        let horizontal = a.rotated(.horizontal), vertical = a.rotated(.vertical)
        let h1 = horizontal.positions[spine[0]]!, h2 = horizontal.positions[spine[1]]!, v1 = vertical.positions[spine[0]]!, v2 = vertical.positions[spine[1]]!
        #expect(abs(h1.y - h2.y) < 0.01 && h1.x < h2.x, "left to right: the spine is level")
        #expect(abs(v1.x - v2.x) < 0.01 && v1.y < v2.y, "top to bottom: the spine is upright")
        #expect(a.rotated(.diagonal).positions == a.positions, "diagonal is as it was")
        func distance(_ g: ArcGraph, _ x: String, _ y: String) -> Double { let p = g.positions[x]!, q = g.positions[y]!; return ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot() }
        let pair = ("s1", "bush:s1|\(id["manor"]!)")
        let before = distance(a, pair.0, pair.1), h = distance(horizontal, pair.0, pair.1), v = distance(vertical, pair.0, pair.1)
        #expect(abs(before - h) < 0.01, "distances do not change when turned left to right")
        #expect(abs(before - v) < 0.01, "or top to bottom")
        #expect(horizontal.graph.nodes.count == a.graph.nodes.count && horizontal.graph.edges.count == a.graph.edges.count, "nothing is added or lost")
    }

    @Test("the plan map and the arc turn with the main line too")
    func otherLooks() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let arc = ArcBuilder.build(character: f.ids["anna"]!, characters: f.characters, worlds: f.worlds, events: f.events, relationships: f.relationships, structure: f.structure)
        let spine = arc.graph.nodes.filter { $0.anchored }.map(\.id)
        #expect(spine.count >= 2)
        let h = arc.rotated(.horizontal), v = arc.rotated(.vertical)
        let ys = Set(spine.map { (h.positions[$0]!.y * 100).rounded() }), xs = Set(spine.map { (v.positions[$0]!.x * 100).rounded() })
        #expect(ys.count == 1 && xs.count == 1, "the arc's spine is level, or upright")
    }
}

@Suite("The place tree in blocks")
struct PlaceTreeBlocksTests {
    @Test("each world with its places is a block; two blocks stand side by side, the third begins a new row, and none overlap")
    func blocks() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let first = try #require(f.worlds.worlds.first?.id)
        var ids: [[String]] = [[first] + f.worlds.entries.filter { $0.world == first }.compactMap(\.id)]
        for name in ["Второй мир", "Третий мир"] {
            let w = try f.worlds.addWorld(name: name)
            let one = try f.worlds.addEntry(name: name + " А", world: w), two = try f.worlds.addEntry(name: name + " Б", world: w), inner = try f.worlds.addEntry(name: name + " В", world: w, parent: one)
            ids.append([w, one, two, inner])
        }
        let firstIDs = ids[0]
        func tree() -> ArcGraph { PlaceTreeBuilder.build(characters: f.characters, worlds: f.worlds, events: f.events, relationships: f.relationships) }
        let g = tree()
        func box(_ ids: [String]) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
            let ps = ids.compactMap { g.positions[$0] }
            return ((ps.map(\.x).min()!)...(ps.map(\.x).max()!), (ps.map(\.y).min()!)...(ps.map(\.y).max()!))
        }
        // (In the order of the worlds in the book.)
        let order = f.worlds.worlds.compactMap(\.id)
        ids.sort { (order.firstIndex(of: $0[0]) ?? 0) < (order.firstIndex(of: $1[0]) ?? 0) }
        let boxes = ids.map(box)
        for i in 0..<boxes.count { for j in (i + 1)..<boxes.count { #expect(!(boxes[i].x.overlaps(boxes[j].x) && boxes[i].y.overlaps(boxes[j].y)), "the worlds \(i) and \(j) do not overlap") } }
        #expect(boxes[0].y.overlaps(boxes[1].y) && boxes[1].x.lowerBound > boxes[0].x.upperBound, "the second world stands next to the first")
        #expect(boxes[2].y.lowerBound > boxes[0].y.upperBound, "the third begins a new row")
        #expect(Set(g.graph.nodes.map(\.id)) == Set(ids.flatMap { $0 }), "every world and place is there once")
        let one = PlaceTreeBuilder.build(only: first, characters: f.characters, worlds: f.worlds, events: f.events, relationships: f.relationships)
        #expect(Set(one.graph.nodes.map(\.id)) == Set(firstIDs) && one.positions.values.map(\.x).min() == 0, "one world alone")
    }
}
