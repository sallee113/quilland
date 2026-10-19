import Foundation
import Testing
@testable import QuillandCore

@Suite("Who is in a scene")
struct SceneMembersTests {
    @Test("a character is in a scene by its name, by a line for the scene, or as the point of view; a place by its name or a line")
    func rule() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let people = CharacterStore(book: book)
        let anna = try people.add(name: "Анна")
        let narrator = try people.add(name: "Герой")
        let pov = try people.add(name: "Лев")
        let other = try people.add(name: "Мира")
        try people.update(narrator) { $0.aliases = ["Рассказчик"]; $0.links = ["day-1": "едет в усадьбу"] }
        try people.update(pov) { $0.povScenes = ["day-1"] }
        try people.update(other) { $0.links = ["day-9": "в другой сцене"] }
        let text = "Анне стало холодно. Я смотрел в окно."
        let inScene = SceneMembers.characters(inScene: "day-1", text: text, store: people)
        #expect(inScene == [anna, narrator, pov])
        #expect(SceneMembers.named(entries: people.entries, in: text) == [anna])
        #expect(SceneMembers.linkedCharacters(inScene: "day-1", store: people) == [narrator, pov])
        #expect(SceneMembers.characters(inScene: "day-2", text: "", store: people).isEmpty)

        let worlds = WorldStore(book: book)
        let world = try #require(worlds.worlds.first?.id)
        let manor = try worlds.addEntry(name: "Усадьба", world: world)
        let port = try worlds.addEntry(name: "Космопорт", world: world)
        let elsewhere = try worlds.addEntry(name: "Город", world: world)
        try worlds.updateEntry(port) { $0.links = ["day-1": "улетает"] }
        let places = SceneMembers.places(inScene: "day-1", text: "Мы приехали в усадьбу.", store: worlds)
        #expect(places.contains(manor) && places.contains(port) && !places.contains(elsewhere))
    }
}
