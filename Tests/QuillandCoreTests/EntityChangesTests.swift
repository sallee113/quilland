import Foundation
import Testing
@testable import QuillandCore

@Suite("The changes events make in an entity, for the cards")
struct EntityChangesTests {
    @Test("the changes are in the order of the book, those of events with no scene last, and names given by events are found in the text")
    func changes() throws {
        let parent = try NewBookTests.folder(); defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let events = EventStore(book: book), people = CharacterStore(book: book)
        let anna = try people.add(name: "Анна")
        let late = try events.add(title: "Позже"), early = try events.add(title: "Раньше"), loose = try events.add(title: "Без сцены")
        try events.update(late) { $0.links = ["s2": ""]; $0.setEffect(.profile, of: anna, text: "Вторая."); $0.setEffect(.aliases, of: anna, list: ["Вильгельм"]) }
        try events.update(early) { $0.links = ["s1": ""]; $0.setEffect(.profile, of: anna, text: "Первая."); $0.setEffect(.aliases, of: anna, list: ["Вилли", "вильгельм"]) }
        try events.update(loose) { $0.setEffect(.profile, of: anna, text: "Нигде.") }
        let list = events.changes(of: anna, sceneOrder: ["s1", "s2"])
        #expect(list.map(\.eventTitle) == ["Раньше", "Позже", "Без сцены"], "\(list.map(\.eventTitle))")
        #expect(list.map(\.applies) == [true, true, false] && list[0].scene == "s1" && list[0].text(.profile) == "Первая." && list[2].scene == nil)
        #expect(events.changes(of: "nobody", sceneOrder: ["s1"]).isEmpty)
        #expect(events.addedAliases(of: anna).sorted() == ["Вилли", "Вильгельм"], "the names, once each, whatever the case: \(events.addedAliases(of: anna))")
        #expect(people.entries.first?.aliases == [], "without the application's help the card's own names")
        people.extraAliases = { events.addedAliases(of: $0) }
        #expect(Set(people.entries.first?.aliases ?? []) == ["Вилли", "Вильгельм"], "with it the matcher knows the added names")
        let text = "Вилли пришёл. Анна ждала."
        #expect(ParadigmMatcher(entries: people.entries).matches(in: text).count == 2, "the added name is found in the text")
    }
}
