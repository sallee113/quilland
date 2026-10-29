import Foundation
import Testing
@testable import QuillandCore

@Suite("Finding and merging duplicates in the book")
struct DuplicateMergeTests {
    @Test("an event written twice: the other's characters, places, scenes, marks, effects, plan place and links go to the kept one, which keeps what it says; the other is gone")
    func eventMerge() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let book = f.structure.folder
        let rel = try #require(f.relationships.relationships.first?.id)
        let keep = try f.events.add(title: "Ссора на станции"), other = try f.events.add(title: "Ссора на платформе")
        try f.events.update(keep) { $0.links = ["s1": "кричат"]; $0.characters = [id["anna"]!: "злится"]; $0.places = [id["manor"]!: ""]; $0.setEffect(.profile, of: id["anna"]!, text: "Злая.") }
        try f.events.update(other) { $0.links = ["s1": "", "s2": "потом"]; $0.characters = [id["anna"]!: "ругается", id["lev"]!: "молчит"]; $0.places = [id["port"]!: ""]; $0.relationships = [rel: "ends"]
            $0.setEffect(.profile, of: id["anna"]!, text: "Другая."); $0.setEffectFlag(of: id["anna"]!, true); $0.date = "осень" }
        try f.events.setText(other, "Они поссорились.")
        let plan = try PlanStore(folder: book)
        let line = try plan.addLine(name: "Линия")
        try plan.placeEvent(other, onLine: line, start: 100)
        let card = try plan.addCard(title: "Идея")
        try plan.setRealised(card: card, by: other, true)

        let report = try EventMerger.merge(other, into: keep, book: book)
        let events = EventStore(book: book)
        let kept = try #require(events.event(keep))
        #expect(events.event(other) == nil && !FileManager.default.fileExists(atPath: book.appendingPathComponent("bible/events/\(other).json").path), "the other is gone")
        #expect(kept.characters == [id["anna"]!: "злится ругается", id["lev"]!: "молчит"], "a character in both has both descriptions, the others are added: \(kept.characters)")
        #expect(kept.places.keys.contains(id["port"]!) && kept.places.keys.contains(id["manor"]!) && kept.links == ["s1": "кричат", "s2": "потом"], "places and scenes joined")
        #expect(kept.relationships[rel] == "ends", "where a relationship ends goes with it")
        #expect(kept.effectText(.profile, of: id["anna"]!) == "Злая." && kept.effectFlag(of: id["anna"]!) == true, "what the kept event already says is kept, and what it did not say is added")
        #expect(kept.date == "осень" && events.text(keep) == "Они поссорились.", "its date and its text")
        let after = try PlanStore(folder: book)
        #expect(after.entry(forEvent: keep)?.lane == line && after.entry(forEvent: keep)?.start == 100 && after.entry(forEvent: other) == nil, "the kept event takes the other's place on the plan")
        #expect(after.realisedBy(card) == [keep], "a card realised by the other is realised by the kept one")
        #expect(report.marksMoved == 1 && report.linksRepointed >= 1)
        #expect(throws: EventMerger.Failure.self) { try EventMerger.merge(keep, into: keep, book: book) }
        let start = try #require(events.startEvent?.id)
        #expect(throws: EventMerger.Failure.self) { try EventMerger.merge(start, into: keep, book: book) }
    }

    @Test("a relationship written twice: where it starts, changes and ends in the events moves to the kept one; only the same characters can be merged")
    func relationshipMerge() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let book = f.structure.folder
        let one = try f.relationships.add(characters: [id["anna"]!, id["vera"]!], kind: "подруги по школе"), two = try f.relationships.add(characters: [id["vera"]!, id["anna"]!], kind: "подруги детства")
        let start = try #require(f.events.startEvent?.id)
        try f.events.update(start) { $0.relationships = [two: "starts"] }
        try f.events.update(id["departure"]!) { var m = $0.relationships; m[two] = "ends"; $0.relationships = m; $0.setEffect(.kind, of: two, text: "бывшие") }
        try f.relationships.update(two) { $0.notes = ["Вместе учились."] }
        try RelationshipMerger.merge(two, into: one, book: book)
        let events = EventStore(book: book), rels = RelationshipStore(book: book)
        #expect(rels.relationship(two) == nil && rels.relationship(one)?.notes == ["Вместе учились."], "the other is gone, its notes are kept")
        #expect(events.startEvent?.relationships[one] == "starts" && events.startEvent?.relationships[two] == nil, "where it starts")
        #expect(events.event(id["departure"]!)?.relationships[one] == "ends" && events.event(id["departure"]!)?.effectText(.kind, of: one) == "бывшие" && events.event(id["departure"]!)?.effects[two] == nil, "where it ends, and what it changes")
        let other = try #require(rels.relationships.first { $0.characters.contains(id["lev"]!) }?.id)
        #expect(throws: EventMerger.Failure.self) { try RelationshipMerger.merge(other, into: one, book: book) }
    }

    @Test("the book is searched for cards that look like one; places of one name in two places are two; 'Not the same' is remembered")
    func finding() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let id = f.ids
        let book = f.structure.folder
        let world = try #require(f.worlds.worlds.first?.id)
        let a = try f.events.add(title: "Встреча у озера"), b = try f.events.add(title: "Встреча у озера вечером"), c = try f.events.add(title: "Пожар")
        for e in [a, b] { try f.events.update(e) { $0.links = ["s1": ""]; $0.characters = [id["anna"]!: "", id["lev"]!: ""] } }
        try f.events.update(c) { $0.links = ["s2": ""] }
        let frankfurt = try f.worlds.addEntry(name: "Франкфурт", world: world), berlin = try f.worlds.addEntry(name: "Берлин", world: world)
        let hall1 = try f.worlds.addEntry(name: "Вокзал", world: world, parent: frankfurt), hall2 = try f.worlds.addEntry(name: "Вокзал", world: world, parent: berlin)
        let vera2 = try f.characters.add(name: "Вера Павловна")
        try f.characters.update(vera2) { $0.links = ["s1": ""] }
        try f.characters.update(id["vera"]!) { $0.links = ["s1": ""] }
        func find(_ dismissed: Set<String> = []) -> [DuplicateGroup] { BookDuplicates.find(characters: CharacterStore(book: book), worlds: WorldStore(book: book), events: EventStore(book: book), relationships: RelationshipStore(book: book), dismissed: dismissed) }
        let groups = find()
        #expect(groups.contains { $0.kind == .events && Set($0.members.map(\.id)) == [a, b] && $0.level == .same }, "two events that say the same")
        #expect(!groups.contains { $0.kind == .events && $0.members.contains { $0.id == c } }, "an event that is another is not in a group")
        #expect(groups.contains { $0.kind == .characters && Set($0.members.map(\.id)) == [id["vera"]!, vera2] }, "Вера and Вера Павловна, in one scene")
        #expect(!groups.contains { $0.kind == .places && Set($0.members.map(\.id)) == [hall1, hall2] }, "the same place name inside two different places is two places")
        let group = try #require(groups.first { $0.kind == .events && Set($0.members.map(\.id)) == [a, b] })
        #expect(group.reasons.isEmpty == false && ["Встреча у озера", "Встреча у озера вечером"].contains(group.existing.title), "a reason, and one that is there already")
        BookDuplicates.dismiss([group.key], book: book)
        #expect(!find(BookDuplicates.dismissed(book: book)).contains { $0.key == group.key } && find(BookDuplicates.dismissed(book: book)).count == groups.count - 1, "Not the Same is remembered")
        BookDuplicates.forgetDismissed(book: book)
        #expect(BookDuplicates.dismissed(book: book).isEmpty)
    }

    @Test("the card made first is the one that is there; cards with no time noted come first, the heavier one first; a card gets its time once")
    func existingAndNew() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let book = f.structure.folder
        let world = try #require(f.worlds.worlds.first?.id)
        func find() -> [DuplicateGroup] { BookDuplicates.find(characters: CharacterStore(book: book), worlds: WorldStore(book: book), events: EventStore(book: book), relationships: RelationshipStore(book: book), ages: CardAges.ages(book: book)) }
        // Three events that say the same, made one after another: the first is the existing one, the others are new.
        let a = try f.events.add(title: "Встреча у озера"), b = try f.events.add(title: "Встреча у озера вечером"), c = try f.events.add(title: "Встреча у озера ночью")
        for e in [a, b, c] { try f.events.update(e) { $0.links = ["s1": ""]; $0.characters = [f.ids["anna"]!: "", f.ids["lev"]!: ""] } }
        let ages = CardAges.ages(book: book)
        #expect(ages[a] != nil && ages[b] != nil && ages[c] != nil && ages[a]! <= ages[b]! && ages[b]! <= ages[c]!, "each card made by the app has its time noted")
        let group = try #require(find().first { $0.kind == .events && Set($0.members.map(\.id)) == [a, b, c] })
        #expect(group.existing.id == a && group.newer.map(\.id) == [b, c], "the first made is the existing one")
        // A card keeps the time it was first noted.
        CardAges.stamp(a, book: book, at: Date().addingTimeInterval(3600))
        #expect(CardAges.ages(book: book)[a] == ages[a], "a time noted is not changed")
        // Places and relationships are noted too.
        let p = try f.worlds.addEntry(name: "Усадьба", world: world), r = try f.relationships.add(characters: [f.ids["anna"]!, f.ids["lev"]!], kind: "друзья")
        let person = try f.characters.add(name: "Новый")
        let more = CardAges.ages(book: book)
        #expect(more[p] != nil && more[r] != nil && more[person] != nil, "places, relationships and characters get their time as well")
        // Cards with no time noted (made before the records) are older than any noted; the one holding more is the existing one.
        try? FileManager.default.removeItem(at: book.appendingPathComponent(".quilland/card-ages.json"))
        CardAges.stamp(c, book: book)
        let mixed = try #require(find().first { $0.kind == .events && Set($0.members.map(\.id)) == [a, b, c] })
        #expect(mixed.existing.id == a && mixed.members.map(\.id) == [a, b, c], "the cards with no time are older, the one with a time comes last (the newest)")
    }

    @Test("the cards are put oldest first: those with no time noted keep the order given, then the others by their time")
    func oldestFirst() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let book = f.structure.folder
        let a = "legacy-a", b = "legacy-b", early = "early", late = "late"
        CardAges.stamp(late, book: book, at: Date(timeIntervalSince1970: 2_000))
        CardAges.stamp(early, book: book, at: Date(timeIntervalSince1970: 1_000))
        #expect(CardAges.oldestFirst([late, b, early, a], book: book) == [b, a, early, late], "unrecorded cards first in the order given, then by time")
        #expect(CardAges.oldestFirst([], book: book).isEmpty)
    }
}
