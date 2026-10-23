import Foundation
import Testing
@testable import QuillandCore

@Suite("Telling duplicates")
struct DuplicateFinderTests {
    static func event(_ title: String, scenes: [String] = ["s1"], people: [String] = ["Анна", "Лев"]) -> DupeFacet {
        DupeFacet(kind: .events, id: UUID().uuidString, names: [title], scenes: Set(scenes), people: people.map { [Names.normalize($0)] })
    }
    static func named(_ kind: CollectKind, _ names: [String], scenes: [String] = ["s1"]) -> DupeFacet { DupeFacet(kind: kind, id: UUID().uuidString, names: names, scenes: Set(scenes)) }

    @Test("an event under two wordings: the same when one title says all the words of the other in the same scene; probably when the titles share a word and the scene and the people are the same")
    func events() {
        func level(_ a: DupeFacet, _ b: DupeFacet) -> DupeLevel? { DuplicateFinder.compare(a, b)?.level }
        #expect(level(Self.event("Ссора на станции"), Self.event("Ссора на станции вечером")) == .same, "one title has all the words of the other, in the same scene")
        #expect(level(Self.event("Ссора на станции"), Self.event("ссора на станции")) == .same, "the same title")
        #expect(level(Self.event("Ссора на станции"), Self.event("Ссора на платформе")) == .probably, "a word shared, the same scene, the same people")
        #expect(level(Self.event("Приезд Анны", people: ["Анна"]), Self.event("Приезд Веры", people: ["Вера"])) == nil, "a word shared but another person")
        #expect(level(Self.event("Ссора на станции"), Self.event("Пожар в усадьбе")) == nil, "no word in common")
        #expect(level(Self.event("Ссора на станции", scenes: ["s1"]), Self.event("Ссора на станции вечером", scenes: ["s9"])) == .probably || level(Self.event("Ссора на станции", scenes: ["s1"]), Self.event("Ссора на станции вечером", scenes: ["s9"])) == nil, "another scene is never more than a guess")
        #expect(level(Self.event("Приезд Анны"), Self.event("Приезд Анны")) == .same && DuplicateFinder.compare(Self.event("Приезд Анны"), Self.event("Приезд Анны"))?.reason == "the same title")
        // Case forms of a word are the same word.
        #expect(level(Self.event("Спор о наследстве"), Self.event("Спор о наследстве дяди")) == .same && level(Self.event("Возвращение домой"), Self.event("Возвращения домой")) != nil, "case forms")
    }

    @Test("characters and places: shared names, a typo, a name that is a word of another")
    func named() {
        func level(_ a: DupeFacet, _ b: DupeFacet) -> DupeLevel? { DuplicateFinder.compare(a, b)?.level }
        #expect(level(Self.named(.characters, ["Лютик"]), Self.named(.characters, ["Лютик", "Люта"])) == .same, "they share a name")
        #expect(level(Self.named(.characters, ["Лютик"]), Self.named(.characters, ["Лютек"])) == .probably, "a letter wrong")
        #expect(level(Self.named(.characters, ["Вера"]), Self.named(.characters, ["Вера Павловна"])) == .same, "a character: a name that is a word of the other, in the same scene")
        #expect(level(Self.named(.places, ["Усадьба"]), Self.named(.places, ["Усадьба Берзиных"])) == .probably, "a place: only a guess")
        #expect(level(Self.named(.characters, ["Анна"]), Self.named(.characters, ["Лев"])) == nil)
        #expect(level(Self.named(.characters, ["Вера"]), Self.named(.places, ["Вера"])) == nil, "never across kinds")
    }

    @Test("relationships, changes and facts")
    func others() {
        func rel(_ a: String, _ b: String, _ kind: String) -> DupeFacet { DupeFacet(kind: .relationships, id: UUID().uuidString, names: [], people: [[Names.normalize(a)], [Names.normalize(b)]], text: kind) }
        func change(_ target: String, _ field: String, _ text: String) -> DupeFacet { DupeFacet(kind: .changes, id: UUID().uuidString, names: [target], text: text, field: field) }
        func fact(_ about: String, _ text: String) -> DupeFacet { DupeFacet(kind: .observations, id: UUID().uuidString, names: [about], text: text) }
        #expect(DuplicateFinder.compare(rel("Анна", "Лев", "сёстры"), rel("Лев", "Анна", "Сёстры"))?.level == .same, "the same two, in either order")
        #expect(DuplicateFinder.compare(rel("Анна", "Лев", "друзья"), rel("Анна", "Лев", "друзья детства"))?.level == .probably)
        #expect(DuplicateFinder.compare(rel("Анна", "Лев", "друзья"), rel("Анна", "Вера", "друзья")) == nil && DuplicateFinder.compare(rel("Анна", "Лев", "друзья"), rel("Анна", "Лев", "враги")) == nil, "another pair, or another kind")
        #expect(DuplicateFinder.compare(change("Анна", "profile", "Теперь капитан."), change("Анна", "profile", "теперь капитан"))?.level == .same)
        #expect(DuplicateFinder.compare(change("Анна", "profile", "Теперь она капитан корабля."), change("Анна", "profile", "Теперь капитан корабля."))?.level == .probably)
        #expect(DuplicateFinder.compare(change("Анна", "profile", "Капитан."), change("Анна", "description", "Капитан.")) == nil && DuplicateFinder.compare(change("Анна", "profile", "Капитан."), change("Лев", "profile", "Капитан.")) == nil, "another field or another thing")
        #expect(DuplicateFinder.compare(fact("Старик", "носит фуражку"), fact("старик", "Носит фуражку."))?.level == .same && DuplicateFinder.compare(fact("Старик", "носит фуражку"), fact("Старик", "хромает")) == nil)
    }

    @Test("findings that are the same thing under two wordings become one row with both quotes")
    func merging() {
        func event(_ title: String, scene: String, quote: String, at: Int = 0) -> CollectedItem {
            var i = CollectedItem(kind: .events, name: title)
            i.members = ["Анна", "Лев"]
            i.evidence = [CollectedEvidence(scene: scene, quote: quote, range: NSRange(location: at, length: 3), note: "")]
            return i
        }
        var set = CollectedSet()
        set.merge([event("Ссора на станции", scene: "s1", quote: "первая")])
        set.merge([event("Ссора на станции вечером", scene: "s1", quote: "вторая", at: 50), event("Прощание", scene: "s1", quote: "третья", at: 90)])
        #expect(set.items.count == 2, "\(set.items.map(\.name))")
        #expect(set.items[0].name == "Ссора на станции" && set.items[0].evidence.count == 2, "the first wording stays, with the quotes of both")
        set.merge([event("Ссора на платформе", scene: "s1", quote: "четвёртая", at: 130)])
        #expect(set.items.count == 3, "a guess is not merged: it stays as a row of its own")
    }

    @Test("the model is told the events it knows, so that it does not name one twice; the run's own finds are added as it goes")
    func prompts() async throws {
        let text = CollectPrompt.user(chunk: "ТЕКСТ", sceneTitle: "С", knownCharacters: [], knownPlaces: [], knownEvents: ["Ссора на станции", "Прощание"], kinds: [.events])
        #expect(text.contains("use exactly its title") && text.contains("- Ссора на станции\n- Прощание") && text.hasPrefix("Passage from the scene"), "the known events follow the passage")
        #expect(!CollectPrompt.user(chunk: "Т", sceneTitle: "С", knownCharacters: [], knownPlaces: [], kinds: [.events]).contains("already known"), "none known, nothing said")
        let long = CollectTests.passage + " " + String(repeating: "Они шли медленно и молчали. ", count: 12)
        let server = try CollectTests.answeringServer { user in
            if user.contains("Сцена two") { return "{\"events\": []}" }
            return "{\"events\": [{\"title\": \"Приезд Анны\", \"characters\": [\"Анна\"], \"note\": \"\", \"quote\": \"Анна стояла на платформе\"}]}"
        }
        var request = CollectRequest(kinds: [.events], scenes: [CollectTests.scene("one", long), CollectTests.scene("two", long)])
        request.context = 8192
        request.knownEvents = ["two": ["Старый разговор"]]
        _ = await CollectJob.run(request, client: LLMTests.client(server), progress: { _ in }, found: { _ in })
        let bodies = server.requests.map { String(decoding: $0.body, as: UTF8.self) }
        #expect(bodies.count == 2 && !bodies[0].contains("already known"), "the first scene: nothing known yet")
        #expect(bodies[1].contains("- Старый разговор") && bodies[1].contains("- Приезд Анны"), "the second is told the book's event of its scene and the one found in the first")
    }
}
