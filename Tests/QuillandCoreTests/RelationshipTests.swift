import Foundation
import Testing
@testable import QuillandCore

@Suite("Relationships between characters")
struct RelationshipTests {
    @Test("a relationship is a file of its own; the characters' files do not mention it")
    func store() throws {
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-rel-\(UUID().uuidString)")
        let characters = CharacterStore(book: book)
        let a = try characters.add(name: "Анна"), b = try characters.add(name: "Мира"), c = try characters.add(name: "Лев")
        let store = RelationshipStore(book: book)
        let id = try store.add(characters: [a, b], kind: "сёстры")
        try store.update(id) { $0.links = ["scene-1": "ссорятся"]; $0.notes = ["давняя обида"] }
        try store.setText(id, "Подробнее об обиде.")
        let again = RelationshipStore(book: book)
        #expect(again.relationships.count == 1 && again.relationship(id)?.kind == "сёстры" && again.relationship(id)?.links == ["scene-1": "ссорятся"])
        #expect(again.text(id) == "Подробнее об обиде." && again.relationships(of: a).count == 1 && again.relationships(of: c).isEmpty)
        #expect(!(try String(contentsOf: book.appendingPathComponent("bible/characters/\(a).json"), encoding: .utf8)).contains(id), "layer 2 links to layer 1, never back")
        try again.update(id) { $0.characters = [a] }
        #expect(again.relationship(id)?.characters == [a, b], "fewer than two characters is refused")
        try again.update(id) { $0.kind = "" }
        #expect(again.relationship(id)?.kind == "сёстры", "and so is an empty kind")
    }

    @Test("a deleted character leaves its relationships; one that would be left alone goes to the trash")
    func characterDeleted() throws {
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-rel-\(UUID().uuidString)")
        let characters = CharacterStore(book: book)
        let a = try characters.add(name: "А"), b = try characters.add(name: "Б"), c = try characters.add(name: "В")
        let store = RelationshipStore(book: book)
        let pair = try store.add(characters: [a, b], kind: "друзья")
        let group = try store.add(characters: [a, b, c], kind: "команда")
        #expect(try store.characterDeleted(a) == 1)
        #expect(store.relationship(pair) == nil && store.relationship(group)?.characters == [b, c])
        #expect(RelationshipStore(book: book).relationships.count == 1)
    }

    @Test("a relationship that names a character who is gone is a loose end")
    func looseEnd() throws {
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-rel-\(UUID().uuidString)")
        try DemoBook.write(into: book, scenes: 8, paragraphs: 2)
        let characters = CharacterStore(book: book)
        try characters.delete(characters.characters[0].id!)
        let found = LooseEnds(book: book).scan()
        #expect(found.contains { $0.field == "characters" && $0.file.hasPrefix("bible/relationships/") })
    }
}
