import Foundation
import Testing
@testable import QuillandCore

@Suite("The events hold their links; Book starts; the migration of old books")
struct EventLinkMigrationTests {
    /// A book written the old way: a character's links to events are in the character's file, and the relationships start at no event.
    struct Old {
        let parent: URL
        let book: URL
        let anna: String, lev: String, arrival: String, departure: String, sister: String
    }

    static func old() throws -> Old {
        let parent = try NewBookTests.folder()
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let people = CharacterStore(book: book)
        let anna = try people.add(name: "Анна"), lev = try people.add(name: "Лев")
        let events = EventStore(book: book)
        let arrival = try events.add(title: "Приезд"), departure = try events.add(title: "Отъезд")
        // The old way: the links are in the characters' files, with a scene line beside them.
        try people.update(anna) { $0.links = [arrival: "выходит из вагона", departure: "", "scene-1": "в доме"] }
        try people.update(lev) { $0.links = [arrival: "встречает"] }
        let sister = try RelationshipStore(book: book).add(characters: [anna, lev], kind: "сёстры")
        return Old(parent: parent, book: book, anna: anna, lev: lev, arrival: arrival, departure: departure, sister: sister)
    }

    @Test("a new book has the default event, kept apart from the events of the story, first, and it cannot be deleted")
    func startEvent() throws {
        let parent = try NewBookTests.folder(); defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let events = EventStore(book: book)
        let start = try #require(events.startEvent)
        #expect(start.title == "Начало книги" && start.start && events.events.isEmpty, "apart from the events of the story")
        #expect(events.event(start.id!)?.start == true && events.allEvents.first?.id == start.id)
        #expect(throws: (any Error).self) { try events.delete(start.id!) }
        try events.update(start.id!) { $0.start = false; $0.title = "Пролог" }
        #expect(EventStore(book: book).startEvent?.title == "Пролог", "it can be renamed, and stays the default event")
        let english = try BookCreator.create(NewBookRequest(title: "House", language: "en", parentFolder: parent))
        #expect(EventStore(book: english).startEvent?.title == "Book starts")
        // Two that say they are the default: the first is, the other is an event of the story.
        let id = try EventStore(book: book).add(title: "Другое")
        try EventStore(book: book).update(id) { $0.start = true }
        let again = EventStore(book: book)
        #expect(again.startEvent != nil && again.events.count == 1 && again.allEvents.count == 2, "one of the two is the default event, the other an event of the story")
    }

    @Test("the plan counts what must move; a book with nothing to move needs no question")
    func plan() throws {
        let o = try Self.old(); defer { try? FileManager.default.removeItem(at: o.parent) }
        let plan = EventLinkMigration.plan(book: o.book)
        #expect(plan == EventLinkMigration.Plan(links: 3, characters: 2, relationships: 1) && plan.isNeeded, "\(plan)")
        let clean = try NewBookTests.folder(); defer { try? FileManager.default.removeItem(at: clean) }
        let fresh = try BookCreator.create(NewBookRequest(title: "Чистая", language: "en", parentFolder: clean))
        #expect(!EventLinkMigration.plan(book: fresh).isNeeded)
    }

    @Test("the migration moves the links into the events, starts the relationships at Book starts, takes a snapshot, and can be done again")
    func migrate() throws {
        let o = try Self.old(); defer { try? FileManager.default.removeItem(at: o.parent) }
        let report = try EventLinkMigration.run(book: o.book)
        #expect(report.links == 3 && report.characters == 2 && report.relationships == 1 && report.snapshot != nil, "\(report)")
        let events = EventStore(book: o.book), people = CharacterStore(book: o.book)
        #expect(events.event(o.arrival)?.characters == [o.anna: "выходит из вагона", o.lev: "встречает"])
        #expect(events.event(o.departure)?.characters == [o.anna: ""])
        #expect(people.character(o.anna)?.links == ["scene-1": "в доме"] && people.character(o.lev)?.links.isEmpty == true, "the characters keep only their lines in scenes")
        #expect(events.startEvent?.relationships == [o.sister: "starts"], "the relationship starts at Book starts")
        #expect(!SnapshotStore(bookFolder: o.book).list().isEmpty, "a snapshot was taken first")
        // Again: nothing to move, nothing changes.
        let before = try Data(contentsOf: o.book.appendingPathComponent("bible/events/\(o.arrival).json"))
        #expect(!EventLinkMigration.plan(book: o.book).isNeeded)
        let second = try EventLinkMigration.run(book: o.book)
        let after = try Data(contentsOf: o.book.appendingPathComponent("bible/events/\(o.arrival).json"))
        #expect(second == EventLinkMigration.Report() && after == before, "the second time changes nothing")
    }

    @Test("a book with no old links is not touched, and one that has no default event gets it without a question")
    func nothingToMove() throws {
        let parent = try NewBookTests.folder(); defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let startFile = try FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent("bible/events").path)
        for f in startFile { try FileManager.default.removeItem(at: book.appendingPathComponent("bible/events/\(f)")) }
        #expect(EventStore(book: book).startEvent == nil)
        #expect(!EventLinkMigration.plan(book: book).isNeeded)
        try EventLinkMigration.ensureStartEvent(book: book)
        #expect(EventStore(book: book).startEvent?.title == "Начало книги")
        let report = try EventLinkMigration.run(book: book)
        #expect(report == EventLinkMigration.Report(), "nothing was moved")
        #expect(SnapshotStore(bookFolder: book).list().isEmpty, "and no snapshot was taken")
    }

    @Test("merging two characters carries their rows and effects in the events over to the kept one")
    func mergeCarriesEventRows() throws {
        let o = try Self.old(); defer { try? FileManager.default.removeItem(at: o.parent) }
        try EventLinkMigration.run(book: o.book, snapshot: false)
        let events = EventStore(book: o.book)
        try events.update(o.arrival) { r in r.effects = [o.lev: .object(["profile": .string("Теперь он главный.")])] }
        _ = try CharacterMerger.merge(o.lev, into: o.anna, book: o.book)
        let after = EventStore(book: o.book).event(o.arrival)
        #expect(after?.characters.keys.contains(o.lev) == false && (after?.characters[o.anna] ?? "").contains("выходит из вагона"), "\(String(describing: after?.characters))")
        #expect(after?.effects[o.anna] != nil && after?.effects[o.lev] == nil, "the effect follows the kept character")
    }
}
