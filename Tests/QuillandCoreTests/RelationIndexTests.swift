import Foundation
import Testing
@testable import QuillandCore

@Suite("Relations in both directions")
struct RelationIndexTests {
    /// A book of two chapters with three scenes, some characters, places and events, and the texts of the scenes.
    struct Fixture {
        let parent: URL
        let index: RelationIndex
        let ids: [String: String]
    }

    static func fixture() throws -> Fixture {
        let parent = try NewBookTests.folder()
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        var structure = BookStructure(folder: book)
        func scene(_ id: String, _ title: String) -> BookStructure.Node { BookStructure.Node(id: id, kind: .scene, title: title, status: nil, base: id, children: []) }
        let ch1 = BookStructure.Node(id: "ch1", kind: .chapter, title: "Глава 1", status: nil, base: "ch1", children: [scene("s1", "Сцена 1"), scene("s2", "Сцена 2")])
        let ch2 = BookStructure.Node(id: "ch2", kind: .chapter, title: "Глава 2", status: nil, base: "ch2", children: [scene("s3", "Сцена 3")])
        let part = BookStructure.Node(id: "p1", kind: .part, title: "Часть 1", status: nil, base: "p1", children: [ch1, ch2])
        structure.roots = [part]
        structure.scenes = [
            BookStructure.SceneEntry(node: scene("s1", "Сцена 1"), chapterID: "ch1", chapterTitle: "Глава 1", partID: "p1", partTitle: "Часть 1"),
            BookStructure.SceneEntry(node: scene("s2", "Сцена 2"), chapterID: "ch1", chapterTitle: "Глава 1", partID: "p1", partTitle: "Часть 1"),
            BookStructure.SceneEntry(node: scene("s3", "Сцена 3"), chapterID: "ch2", chapterTitle: "Глава 2", partID: "p1", partTitle: "Часть 1"),
        ]
        let people = CharacterStore(book: book)
        let anna = try people.add(name: "Анна"), lev = try people.add(name: "Лев"), narrator = try people.add(name: "Герой")
        let worlds = WorldStore(book: book)
        let world = try #require(worlds.worlds.first?.id)
        let manor = try worlds.addEntry(name: "Усадьба", world: world), port = try worlds.addEntry(name: "Космопорт", world: world)
        let events = EventStore(book: book)
        let arrival = try events.add(title: "Приезд"), departure = try events.add(title: "Отъезд")
        try events.update(arrival) { $0.links = ["s1": ""]; $0.places = [manor: "встреча"] }
        try events.update(departure) { $0.links = ["s3": ""]; $0.places = [port: ""] }
        // The links that live on the character: Lev takes part in the departure; the narrator is in scene 1 by a line only.
        try people.update(lev) { $0.links = [departure: "улетает"] }
        try people.update(narrator) { $0.links = ["s1": "едет"] }
        let texts = ["s1": "Анна приехала в усадьбу.", "s2": "Лев смотрел на Анну.", "s3": "Лев ждал в космопорте."]
        let index = RelationIndex(characters: people, worlds: worlds, events: events, structure: structure, sceneText: { texts[$0] ?? "" })
        return Fixture(parent: parent, index: index, ids: ["anna": anna, "lev": lev, "narrator": narrator, "manor": manor, "port": port, "arrival": arrival, "departure": departure])
    }

    @Test("by a section: a scene, a chapter or a part gives who and what is in its scenes")
    func bySection() throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.parent) }
        let i = f.index, id = f.ids
        #expect(i.scenes(inSection: "ch1") == ["s1", "s2"] && i.scenes(inSection: "p1") == ["s1", "s2", "s3"] && i.scenes(inSection: "s3") == ["s3"])
        #expect(i.matching(.character, anchors: [.section("s1")]) == [id["anna"]!, id["narrator"]!], "the name in the text, and a line for the scene")
        #expect(i.matching(.character, anchors: [.section("ch1")]) == [id["anna"]!, id["lev"]!, id["narrator"]!])
        #expect(i.matching(.character, anchors: [.section("ch2")]) == [id["lev"]!])
        #expect(i.matching(.place, anchors: [.section("s1")]) == [id["manor"]!])
        #expect(i.matching(.place, anchors: [.section("p1")]) == [id["manor"]!, id["port"]!])
        #expect(i.matching(.event, anchors: [.section("ch1")]) == [id["arrival"]!], "an event is in the scenes it is linked to")
        #expect(i.matching(.event, anchors: [.section("p1")]) == [id["arrival"]!, id["departure"]!])
        #expect(i.matching(.event, anchors: [.section("s2")]) == [])
    }

    @Test("by an event, a character or a place: the link is read from the side that stores it, and answered from either")
    func byLinks() throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.parent) }
        let i = f.index, id = f.ids
        // The character's file holds the link to the event: characters of an event, and events of a character.
        #expect(i.matching(.character, anchors: [.event(id["departure"]!)]) == [id["lev"]!])
        #expect(i.matching(.event, anchors: [.character(id["lev"]!)]) == [id["departure"]!])
        #expect(i.matching(.event, anchors: [.character(id["anna"]!)]) == [], "no link to an event")
        // The event's file holds its places: places of an event, and events at a place.
        #expect(i.matching(.place, anchors: [.event(id["arrival"]!)]) == [id["manor"]!])
        #expect(i.matching(.event, anchors: [.place(id["port"]!)]) == [id["departure"]!])
        // A character and a place go together by the scenes they share.
        #expect(i.matching(.place, anchors: [.character(id["anna"]!)]) == [id["manor"]!])
        #expect(i.matching(.place, anchors: [.character(id["lev"]!)]) == [id["port"]!])
        #expect(i.matching(.character, anchors: [.place(id["manor"]!)]) == [id["anna"]!, id["narrator"]!])
        #expect(i.matching(.character, anchors: [.place(id["port"]!)]) == [id["lev"]!])
    }

    @Test("several anchors must all match; an anchor of the kind asked for does nothing; none means no filter")
    func combining() throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.parent) }
        let i = f.index, id = f.ids
        #expect(i.matching(.character, anchors: []) == nil)
        #expect(i.matching(.character, anchors: [.section("ch1"), .event(id["departure"]!)]) == [id["lev"]!], "in chapter 1 AND in the departure")
        #expect(i.matching(.character, anchors: [.section("ch2"), .place(id["manor"]!)]) == [], "nobody is in chapter 2 and at the manor")
        #expect(i.matching(.character, anchors: [.character(id["anna"]!)]) == nil, "a character is not filtered by a character")
        #expect(i.matching(.character, anchors: [.character(id["anna"]!), .section("s1")]) == [id["anna"]!, id["narrator"]!], "the useless anchor is left out")
        #expect(i.matching(.event, anchors: [.section("p1"), .place(id["manor"]!), .character(id["lev"]!)]) == [], "the arrival is not Lev's, the departure is not at the manor")
    }
}
