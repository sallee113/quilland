import Foundation
import Testing
@testable import QuillandCore

@Suite("Merging two characters")
struct CharacterMergeTests {
    static func book() throws -> (URL, URL) {
        let parent = try NewBookTests.folder()
        let folder = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        return (parent, folder)
    }

    @Test("the other one's names, notes, links, profile and relationships go to the kept character, and the card goes to the trash")
    func merge() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = CharacterStore(book: book)
        let kept = try store.add(name: "Вера Павловна")
        let other = try store.add(name: "тётя Вера")
        let third = try store.add(name: "Анна")
        try store.update(kept) { $0.aliases = ["Вера"]; $0.notes = ["Хозяйка дома."]; $0.links = ["scene-a": "ждёт у окна"] }
        try store.update(other) { $0.aliases = ["Верочка", "вера"]; $0.notes = ["Хозяйка дома.", "Любит чай."]; $0.links = ["scene-a": "курит", "scene-b": "встречает гостей"]; $0.povScenes = ["scene-b"]; $0.main = true }
        try store.setProfile(kept, "Высокая, строгая.")
        try store.setProfile(other, "Говорит тихо.")
        let rels = RelationshipStore(book: book)
        let sisters = try rels.add(characters: [other, third], kind: "тётя и племянница")
        let same = try rels.add(characters: [kept, other], kind: "ошибочная связь")
        // Other things that point at the character: a plan card and an event.
        let cardDir = book.appendingPathComponent("plan/cards"), eventDir = book.appendingPathComponent("bible/events")
        try FileManager.default.createDirectory(at: cardDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: eventDir, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(["id": .string("card1"), "title": .string("Приезд"), "links": .object([other: .string("встречает")])]), to: cardDir.appendingPathComponent("card1.json"))
        try AtomicFile.write(JSONWriter.data(["id": .string("ev1"), "title": .string("Ужин"), "links": .object([other: .string("накрывает"), kept: .string("садится")])]), to: eventDir.appendingPathComponent("ev1.json"))

        let report = try CharacterMerger.merge(other, into: kept, book: book)

        let after = CharacterStore(book: book)
        let now = try #require(after.character(kept))
        #expect(after.character(other) == nil && after.character(third) != nil)
        #expect(now.aliases == ["Вера", "тётя Вера", "Верочка"], "its name and aliases, none twice, none like the kept name: \(now.aliases)")
        #expect(report.aliasesAdded == ["тётя Вера", "Верочка"])
        #expect(now.notes == ["Хозяйка дома.", "Любит чай."] && now.main && now.povScenes == ["scene-b"])
        #expect(now.links == ["scene-a": "ждёт у окна курит", "scene-b": "встречает гостей"], "the descriptions of one target are joined: \(now.links)")
        #expect(after.profile(kept) == "Высокая, строгая.\n\n**тётя Вера**\n\nГоворит тихо.")
        // The relationships.
        let relsAfter = RelationshipStore(book: book)
        #expect(relsAfter.relationship(sisters)?.characters == [kept, third] && relsAfter.relationship(same) == nil)
        #expect(report.relationshipsChanged == 1 && report.relationshipsRemoved == 1)
        // The other things.
        let card = try JSONParser.parseObject(Data(contentsOf: cardDir.appendingPathComponent("card1.json")))
        #expect(card.stringMap("links") == [kept: "встречает"])
        let event = try JSONParser.parseObject(Data(contentsOf: eventDir.appendingPathComponent("ev1.json")))
        #expect(event.stringMap("links") == [kept: "садится накрывает"] || event.stringMap("links") == [kept: "садится"] || event.stringMap("links")?[kept]?.contains("накрывает") == true, "\(String(describing: event.stringMap("links")))")
        #expect(report.linksRepointed == 2)
        // The removed card is in the trash folder, not gone.
        let trash = book.appendingPathComponent(".quilland/trash")
        let trashed = (try? FileManager.default.subpathsOfDirectory(atPath: trash.path)) ?? []
        #expect(trashed.contains { $0.hasSuffix("\(other).json") } && trashed.contains { $0.hasSuffix("\(other).md") })
    }

    @Test("a character cannot be merged into itself or into one that is not there")
    func refused() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = CharacterStore(book: book)
        let a = try store.add(name: "Анна")
        #expect(throws: (any Error).self) { try CharacterMerger.merge(a, into: a, book: book) }
        #expect(throws: (any Error).self) { try CharacterMerger.merge(a, into: "missing", book: book) }
        #expect(CharacterStore(book: book).character(a) != nil, "nothing was removed")
    }

    @Test("joining descriptions never repeats what is already there")
    func joining() {
        #expect(CharacterMerger.joined(["a": "курит"], ["a": "курит", "b": "спит"]) == ["a": "курит", "b": "спит"])
        #expect(CharacterMerger.joined(["a": ""], ["a": "курит"]) == ["a": "курит"])
        #expect(CharacterMerger.joined(["a": "курит"], ["a": ""]) == ["a": "курит"])
    }
}
