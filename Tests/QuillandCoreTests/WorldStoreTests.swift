import Foundation
import Testing
@testable import QuillandCore

@Suite("Worlds and their places")
struct WorldStoreTests {
    static func store() throws -> (URL, URL, WorldStore) {
        let (parent, book) = try BookEditorTests.book()
        return (parent, book, WorldStore(book: book))
    }

    @Test("a new book has a default world; places nest in it, and everything reads back")
    func basics() throws {
        let (parent, book, store) = try Self.store()
        defer { try? FileManager.default.removeItem(at: parent) }
        #expect(store.worlds.count == 1 && store.entries.isEmpty)
        let world = store.worlds[0].id!
        let germany = try store.addEntry(name: "Германия", world: world)
        let frankfurt = try store.addEntry(name: "Франкфурт", world: world, parent: germany)
        let thing = try store.addEntry(name: "Меч", world: world, type: "thing")
        let back = WorldStore(book: book)
        #expect(back.entries.count == 3 && back.problems.isEmpty)
        #expect(back.children(of: nil, in: world).compactMap(\.name) == ["Германия", "Меч"])
        #expect(back.children(of: germany, in: world).compactMap(\.id) == [frankfurt])
        #expect(back.entry(thing)?.type == "thing" && back.entry(germany)?.type == "place")
        #expect(back.path(of: frankfurt) == [store.worlds[0].name!, "Германия", "Франкфурт"])
        let names = ParadigmMatcher(entries: back.nameEntries).matches(in: "Он приехал во Франкфурт из Германии.")
        #expect(Set(names.map(\.entry)) == [frankfurt, germany])
    }

    @Test("moving an entry takes what is inside it along; a loop is refused; a world change reaches the children")
    func moving() throws {
        let (parent, book, store) = try Self.store()
        defer { try? FileManager.default.removeItem(at: parent) }
        let w1 = store.worlds[0].id!
        let w2 = try store.addWorld(name: "Другой мир")
        let a = try store.addEntry(name: "А", world: w1)
        let b = try store.addEntry(name: "Б", world: w1, parent: a)
        let c = try store.addEntry(name: "В", world: w1, parent: b)
        #expect(throws: (any Error).self) { try store.move(entry: a, toWorld: w1, parent: c) }
        #expect(throws: (any Error).self) { try store.move(entry: a, toWorld: w1, parent: a) }
        try store.move(entry: b, toWorld: w2, parent: nil)
        let back = WorldStore(book: book)
        #expect(back.entry(b)?.world == w2 && back.entry(b)?.parent == nil && back.entry(c)?.world == w2 && back.entry(c)?.parent == b)
        #expect(back.entry(a)?.world == w1 && back.problems.isEmpty)
    }

    @Test("deleting a place lifts what was inside; a world needs to be empty and is never the last")
    func deleting() throws {
        let (parent, book, store) = try Self.store()
        defer { try? FileManager.default.removeItem(at: parent) }
        let w = store.worlds[0].id!
        let a = try store.addEntry(name: "А", world: w)
        let b = try store.addEntry(name: "Б", world: w, parent: a)
        try store.setText(a, "Описание.")
        try store.deleteEntry(a)
        let back = WorldStore(book: book)
        #expect(back.entry(a) == nil && back.entry(b)?.parent == nil)
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent("bible/places/\(a).md").path))
        #expect(throws: (any Error).self) { try store.deleteWorld(w) }
        let w2 = try store.addWorld(name: "Второй")
        #expect(throws: (any Error).self) { try store.deleteWorld(w) }
        try store.deleteWorld(w2)
        #expect(WorldStore(book: book).worlds.count == 1)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent(".quilland/trash").path)) ?? []).count >= 1)
    }

    @Test("unknown fields are kept, a broken parent is reported, a world mismatch is reported")
    func problems() throws {
        let (parent, book, store) = try Self.store()
        defer { try? FileManager.default.removeItem(at: parent) }
        let w = store.worlds[0].id!
        let w2 = try store.addWorld(name: "Другой")
        let a = try store.addEntry(name: "А", world: w)
        let file = book.appendingPathComponent("bible/places/\(a).json")
        var raw = try JSONParser.parseObject(Data(contentsOf: file))
        raw["future"] = .string("kept")
        raw["parent"] = .string("no-such-place")
        try AtomicFile.write(JSONWriter.data(raw), to: file)
        let again = WorldStore(book: book)
        #expect(again.problems.contains { $0.contains("missing") })
        try again.updateEntry(a) { $0.aliases = ["А-ля"]; $0.parent = nil }
        #expect(try JSONParser.parseObject(Data(contentsOf: file)).string("future") == "kept")
        let b = try again.addEntry(name: "Б", world: w2)
        try again.updateEntry(a) { $0.parent = b }
        #expect(WorldStore(book: book).problems.contains { $0.contains("another world") })
    }
}
