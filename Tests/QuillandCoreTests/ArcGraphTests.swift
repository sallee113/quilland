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
