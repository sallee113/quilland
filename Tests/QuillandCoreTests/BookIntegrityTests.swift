import Foundation
import Testing
@testable import QuillandCore

@Suite("What leaves the book takes every reference to it along")
struct BookIntegrityTests {
    struct Book {
        let parent: URL, book: URL
        let anna: String, lev: String, vera: String
        let manor: String, port: String, world: String, otherWorld: String
        let arrival: String, departure: String
        let sisters: String, friends: String, trio: String
        let doc: String, card: String, thing: URL
    }

    /// Three characters, two places in two worlds, two events, three relationships (one with three characters), a research document, a plan card and a thing of an
    /// own kind that all refer to some of them.
    static func book() throws -> Book {
        let parent = try NewBookTests.folder()
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let people = CharacterStore(book: book)
        let anna = try people.add(name: "Анна"), lev = try people.add(name: "Лев"), vera = try people.add(name: "Вера")
        let worlds = WorldStore(book: book)
        let world = try #require(worlds.worlds.first?.id)
        let otherWorld = try worlds.addWorld(name: "Другой")
        let manor = try worlds.addEntry(name: "Усадьба", world: world), port = try worlds.addEntry(name: "Порт", world: world)
        let inner = try worlds.addEntry(name: "Подвал", world: world, parent: manor)
        _ = inner
        try people.update(anna) { $0.worlds = [world, otherWorld] }
        let events = EventStore(book: book)
        let arrival = try events.add(title: "Приезд"), departure = try events.add(title: "Отъезд")
        let rels = RelationshipStore(book: book)
        let sisters = try rels.add(characters: [anna, lev], kind: "сёстры")
        let friends = try rels.add(characters: [anna, vera], kind: "друзья")
        let trio = try rels.add(characters: [anna, lev, vera], kind: "знакомые")
        let startID = try #require(events.startEvent?.id)
        try events.update(startID) { $0.relationships = [sisters: "starts", trio: "starts"] }
        try events.update(arrival) { r in
            r.characters = [anna: "выходит", lev: "встречает", vera: ""]
            r.places = [manor: "встреча"]
            r.relationships = [friends: "starts"]
            r.effects = [anna: .object(["profile": .string("Стала главной.")]), manor: .object(["description": .string("Сгорела.")]), friends: .object(["kind": .string("враги")])]
        }
        try events.update(departure) { r in
            r.characters = [anna: ""]
            r.places = [port: ""]
            r.relationships = [sisters: "ends"]
        }
        let research = ResearchStore(book: book)
        let doc = try research.add(title: "Заметка")
        try research.update(doc) { $0.links = [anna: "о ней", manor: "о доме", "other": "x"] }
        let card = try PlanStore(folder: book).addCard(title: "Идея")
        let cardURL = book.appendingPathComponent("plan/cards/\(card).json")
        var cardObject = try JSONParser.parseObject(Data(contentsOf: cardURL))
        cardObject.setStringMap("links", [anna: "", port: ""])
        try AtomicFile.write(JSONWriter.data(cardObject), to: cardURL)
        let thingDir = book.appendingPathComponent("bible/things/kind-1")
        try FileManager.default.createDirectory(at: thingDir, withIntermediateDirectories: true)
        let thing = thingDir.appendingPathComponent("t1.json")
        let thingObject: JSONObject = ["id": .string("t1"), "name": .string("Кольцо"), "fields": .object(["owner": .string(anna), "seen": .array([.string(arrival), .string(anna)])]), "links": .object([anna: .string("носит")])]
        try AtomicFile.write(JSONWriter.data(thingObject), to: thing)
        return Book(parent: parent, book: book, anna: anna, lev: lev, vera: vera, manor: manor, port: port, world: world, otherWorld: otherWorld, arrival: arrival, departure: departure,
                    sisters: sisters, friends: friends, trio: trio, doc: doc, card: card, thing: thing)
    }

    static func ends(_ book: URL) -> Int { LooseEnds(book: book).scan().count }

    @Test("a deleted character goes from every event, relationship, document, card and thing")
    func character() throws {
        let b = try Self.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        let report = try BookIntegrity.deleteCharacter(b.anna, book: b.book)
        #expect(report.snapshot != nil && report.relationshipsRemoved == 2 && report.eventsChanged >= 2, "\(report)")
        let events = EventStore(book: b.book), rels = RelationshipStore(book: b.book)
        #expect(events.event(b.arrival)?.characters.keys.sorted() == [b.lev, b.vera].sorted() && events.event(b.departure)?.characters.isEmpty == true, "the rows")
        #expect(events.event(b.arrival)?.effects[b.anna] == nil && events.event(b.arrival)?.effects[b.manor] != nil, "its effects go, others stay")
        #expect(rels.relationship(b.sisters) == nil && rels.relationship(b.friends) == nil, "a relationship with two characters goes with it")
        #expect(rels.relationship(b.trio)?.characters.sorted() == [b.lev, b.vera].sorted(), "one with three loses only the member")
        #expect(events.startEvent?.relationships == [b.trio: "starts"] && events.event(b.arrival)?.relationships.isEmpty == true && events.event(b.departure)?.relationships.isEmpty == true, "and the markers of the relationships that went")
        #expect(events.event(b.arrival)?.effects[b.friends] == nil, "and what an event changed in them")
        #expect(ResearchStore(book: b.book).document(b.doc)?.links.keys.sorted() == [b.manor, "other"].sorted(), "the research document")
        let card = try JSONParser.parseObject(Data(contentsOf: b.book.appendingPathComponent("plan/cards/\(b.card).json")))
        #expect(card.stringMap("links") == [b.port: ""], "the plan card")
        let thing = try JSONParser.parseObject(Data(contentsOf: b.thing))
        #expect(thing.object("fields")?["owner"] == nil && thing.object("fields")?.strings("seen") == nil || thing.object("fields")?.strings("seen") == [b.arrival], "the fields of a thing: \(String(describing: thing.object("fields")))")
        #expect(thing.stringMap("links") == nil || thing.stringMap("links")?.isEmpty == true, "the links of a thing")
        #expect(CharacterStore(book: b.book).character(b.anna) == nil && Self.ends(b.book) == 0, "no loose end is left")
    }

    @Test("a deleted place goes from every event, its children move up, and its other references go")
    func place() throws {
        let b = try Self.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        let report = try BookIntegrity.deletePlace(b.manor, book: b.book, snapshot: false)
        #expect(report.snapshot == nil, "no snapshot when the caller takes its own")
        let events = EventStore(book: b.book)
        #expect(events.event(b.arrival)?.places.isEmpty == true && events.event(b.arrival)?.effects[b.manor] == nil && events.event(b.arrival)?.effects[b.anna] != nil)
        #expect(ResearchStore(book: b.book).document(b.doc)?.links[b.manor] == nil)
        #expect(WorldStore(book: b.book).entry(b.manor) == nil && Self.ends(b.book) == 0)
    }

    @Test("a deleted world goes from the characters' lists, and a world that holds places is refused with nothing touched")
    func world() throws {
        let b = try Self.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        #expect(throws: (any Error).self) { try BookIntegrity.deleteWorld(b.world, book: b.book, snapshot: false) }
        #expect(CharacterStore(book: b.book).character(b.anna)?.worlds == [b.world, b.otherWorld], "refused: nothing was touched")
        try BookIntegrity.deleteWorld(b.otherWorld, book: b.book, snapshot: false)
        #expect(CharacterStore(book: b.book).character(b.anna)?.worlds == [b.world] && WorldStore(book: b.book).world(b.otherWorld) == nil && Self.ends(b.book) == 0)
    }

    @Test("a deleted relationship goes from the events that start, change or end it")
    func relationship() throws {
        let b = try Self.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        let report = try BookIntegrity.deleteRelationship(b.friends, book: b.book, snapshot: false)
        #expect(report.relationshipsRemoved == 1)
        let events = EventStore(book: b.book)
        #expect(events.event(b.arrival)?.relationships.isEmpty == true && events.event(b.arrival)?.effects[b.friends] == nil && RelationshipStore(book: b.book).relationship(b.friends) == nil)
        #expect(Self.ends(b.book) == 0)
    }

    @Test("a deleted event takes its effects; relationships that start in it are deleted or start in another event; the default event cannot be deleted")
    func event() throws {
        let b = try Self.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        let startID = try #require(EventStore(book: b.book).startEvent?.id)
        #expect(BookIntegrity.relationshipsStarting(in: b.arrival, book: b.book) == [b.friends])
        #expect(throws: (any Error).self) { try BookIntegrity.deleteEvent(startID, book: b.book, snapshot: false) }
        #expect(throws: (any Error).self) { try BookIntegrity.deleteEvent(b.arrival, book: b.book, started: .moveStart(to: "nothing"), snapshot: false) }
        #expect(EventStore(book: b.book).event(b.arrival) != nil, "a refused deletion changes nothing")
        // They start in another event.
        try BookIntegrity.deleteEvent(b.arrival, book: b.book, started: .moveStart(to: b.departure), snapshot: false)
        var events = EventStore(book: b.book)
        #expect(events.event(b.arrival) == nil && events.event(b.departure)?.relationships[b.friends] == "starts" && RelationshipStore(book: b.book).relationship(b.friends) != nil, "it starts in the other event")
        // An event where a relationship ends: the relationship is active again.
        try BookIntegrity.deleteEvent(b.departure, book: b.book, started: .deleteThem, snapshot: false)
        events = EventStore(book: b.book)
        #expect(events.event(b.departure) == nil && RelationshipStore(book: b.book).relationship(b.friends) == nil, "deleted with the event")
        #expect(RelationshipStore(book: b.book).relationship(b.sisters) != nil && events.startEvent?.relationships[b.sisters] == "starts", "one that ended there has no end any more")
        #expect(Self.ends(b.book) == 0)
    }

    @Test("with a snapshot, everything comes back")
    func snapshotBringsBack() throws {
        let b = try Self.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        let report = try BookIntegrity.deleteCharacter(b.anna, book: b.book)
        let info = try #require(SnapshotStore(bookFolder: b.book).list().first { $0.id == report.snapshot })
        _ = try SnapshotStore(bookFolder: b.book).restoreAll(from: info)
        #expect(CharacterStore(book: b.book).character(b.anna) != nil && EventStore(book: b.book).event(b.arrival)?.characters[b.anna] == "выходит")
        #expect(RelationshipStore(book: b.book).relationship(b.sisters) != nil && EventStore(book: b.book).startEvent?.relationships[b.sisters] == "starts")
        #expect(ResearchStore(book: b.book).document(b.doc)?.links[b.anna] == "о ней")
    }

    @Test("merging places carries what an event changes in them over to the kept one")
    func mergePlaces() throws {
        let b = try Self.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        _ = try WorldMerger.mergePlaces(b.manor, into: b.port, book: b.book)
        let arrival = EventStore(book: b.book).event(b.arrival)
        #expect(arrival?.places[b.port] != nil && arrival?.effects[b.port] != nil && arrival?.effects[b.manor] == nil, "\(String(describing: arrival?.effects.keys.sorted()))")
        #expect(ResearchStore(book: b.book).document(b.doc)?.links[b.port] == "о доме", "and so do the research links")
    }
}

@Suite("Loose ends in what events keep")
struct EventLooseEndsTests {
    @Test("a row, a relationship marker or an effect that points at something that is gone is found, and can be taken out")
    func found() throws {
        let b = try BookIntegrityTests.book(); defer { try? FileManager.default.removeItem(at: b.parent) }
        let events = EventStore(book: b.book)
        try events.update(b.arrival) { r in
            var c = r.characters; c["gone-character"] = ""; r.characters = c
            var m = r.relationships; m["gone-relationship"] = "starts"; r.relationships = m
            var e = r.effects; e["gone-target"] = .object(["profile": .string("x")]); r.effects = e
        }
        let ends = LooseEnds(book: b.book).scan()
        #expect(Set(ends.map(\.target)) == ["gone-character", "gone-relationship", "gone-target"], "\(ends.map(\.target))")
        for end in ends { try LooseEnds(book: b.book).remove(end) }
        #expect(LooseEnds(book: b.book).scan().isEmpty && EventStore(book: b.book).event(b.arrival)?.effects[b.anna] != nil, "what is real stays")
    }
}
