import Foundation
import Testing
@testable import QuillandCore

@Suite("Reminders")
struct RemindersStoreTests {
    @Test("reminders are added in order, marked done and undone, and read again")
    func roundTrip() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let store = RemindersStore(book: book)
        #expect(store.reminders.isEmpty && !FileManager.default.fileExists(atPath: book.appendingPathComponent("reminders.json").path))
        #expect(try store.add("   ") == nil)
        let a = try #require(try store.add("  Проверить год основания школы "))
        let b = try #require(try store.add("Позвонить редактору"))
        #expect(store.open.map(\.text) == ["Проверить год основания школы", "Позвонить редактору"])
        try store.setDone(a, true)
        let again = RemindersStore(book: book)
        #expect(again.open.map(\.id) == [b] && again.done.map(\.id) == [a] && again.done[0].doneAt != nil && again.problems.isEmpty)
        try again.setDone(a, false)
        #expect(again.open.count == 2 && again.reminders.first { $0.id == a }?.doneAt == nil)
        try again.setText(b, "Позвонить редактору в пятницу")
        #expect(RemindersStore(book: book).reminders.last?.text == "Позвонить редактору в пятницу")
    }

    @Test("a deleted reminder can be put back where it was; unknown fields stay in the file")
    func deleteAndUndo() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let store = RemindersStore(book: book)
        let ids = try ["один", "два", "три"].map { try #require(try store.add($0)) }
        try store.delete(ids[1])
        #expect(store.reminders.map(\.text) == ["один", "три"])
        #expect(try store.undoDelete() && store.reminders.map(\.text) == ["один", "два", "три"])
        #expect(try !store.undoDelete())
        // A field this version does not know survives a write.
        let url = book.appendingPathComponent("reminders.json")
        var o = try JSONParser.parseObject(Data(contentsOf: url))
        o["future"] = .string("kept")
        try AtomicFile.write(JSONWriter.data(o), to: url)
        let other = RemindersStore(book: book)
        try other.add("четыре")
        #expect(try JSONParser.parseObject(Data(contentsOf: url)).string("future") == "kept")
    }

    @Test("a reminder may have several lines; they come back as they were, trimmed only at the ends")
    func severalLines() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let store = RemindersStore(book: book)
        let id = try #require(try store.add("\n Проверить:\n- год основания\n\n- имя директора  \n"))
        #expect(RemindersStore(book: book).reminders.first?.text == "Проверить:\n- год основания\n\n- имя директора")
        try store.setText(id, "Одна строка\nвторая")
        #expect(RemindersStore(book: book).reminders.first?.text == "Одна строка\nвторая")
    }

    @Test("a damaged file is reported, not guessed")
    func damaged() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        try Data("{ not json".utf8).write(to: book.appendingPathComponent("reminders.json"))
        let store = RemindersStore(book: book)
        #expect(store.reminders.isEmpty && store.problems.count == 1)
    }

    @Test("Loose Ends does not call reminders.json a stray file")
    func looseEnds() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let before = LooseEnds(book: book).scan().count
        try RemindersStore(book: book).add("x")
        #expect(LooseEnds(book: book).scan().count == before)
    }
}
