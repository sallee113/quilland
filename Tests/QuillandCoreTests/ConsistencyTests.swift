import Foundation
import Testing
@testable import QuillandCore

@Suite("Consistency Check", .serialized)
struct ConsistencyTests {
    static let sources = [
        ConsistencySource(label: "C1", kind: .character, ref: "anna", title: "Анна", text: "Серые глаза, высокая, приехала из города."),
        ConsistencySource(label: "S1", kind: .scene, ref: "s0", title: "Платформа", text: "Анна приезжает на станцию осенью."),
    ]
    static let passage = "Анна подняла голубые глаза и посмотрела на старика. Было жаркое лето, и станция пустовала."

    @Test("a finding is kept only when its label, its passage words and its source words are all true")
    func parsing() {
        let reply = """
        {"findings": [
          {"source": "C1", "problem": "Цвет глаз не совпадает с карточкой.", "passage_quote": "подняла голубые глаза", "source_quote": "Серые глаза"},
          {"source": "S1", "problem": "Сезон другой.", "passage_quote": "Было жаркое лето", "source_quote": "приезжает на станцию осенью"},
          {"source": "C9", "problem": "Нет такого источника.", "passage_quote": "подняла голубые глаза", "source_quote": "Серые глаза"},
          {"source": "C1", "problem": "Цитата выдумана.", "passage_quote": "она рассмеялась в голос", "source_quote": "Серые глаза"},
          {"source": "C1", "problem": "Слова источника выдуманы.", "passage_quote": "подняла голубые глаза", "source_quote": "рост два метра"}]}
        """
        let result = ConsistencyParser.parse(reply, scene: "s1", passage: Self.passage, offset: 500, sources: Self.sources)
        #expect(result.findings.count == 2 && result.dropped == 3 && !result.malformed)
        let eyes = result.findings[0]
        #expect(eyes.source.label == "C1" && eyes.quote == "подняла голубые глаза" && eyes.sourceQuote == "Серые глаза" && eyes.range.location == 500 + 5)
        #expect(ConsistencyParser.parse("nothing here", scene: "s", passage: "x", offset: 0, sources: []).malformed)
        #expect(ConsistencyParser.parse("{\"findings\": []}", scene: "s", passage: "x", offset: 0, sources: []).findings.isEmpty)
        #expect(eyes.key == ConsistencyParser.parse(reply, scene: "other", passage: Self.passage, offset: 0, sources: Self.sources).findings[0].key, "the same finding has the same key wherever it is")
    }

    @Test("the sources are the cards named in the passage or linked to the scene, the scene's events, and the earlier scenes, within a budget")
    func gathering() throws {
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-cons-\(UUID().uuidString)")
        try DemoBook.write(into: book, scenes: 12, paragraphs: 3)
        let structure = try BookStructure.load(folder: book)
        let characters = CharacterStore(book: book), worlds = WorldStore(book: book), events = EventStore(book: book), relationships = RelationshipStore(book: book)
        let scene = structure.scenes[5].id
        let anna = characters.characters.first { $0.name == "Анна" }!
        try characters.update(anna.id!) { $0.notes = ["Глаза серые."] }
        let passage = "Анна и Вера Павловна сидели в доме. Анна молчала."
        let all = ConsistencySources.gather(sceneID: scene, passage: passage, characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure, budget: 20000)
        #expect(all.contains { $0.kind == .character && $0.title == "Анна" && $0.text.contains("Глаза серые") } && all.contains { $0.kind == .character && $0.title == "Вера Павловна" })
        #expect(all.contains { $0.kind == .relationship }, "the relationship between two characters named in the passage")
        #expect(all.contains { $0.kind == .place && $0.title.hasPrefix("Дом") }, "a place named in it")
        #expect(Set(all.map(\.label)).count == all.count && all.allSatisfy { $0.label.count >= 2 }, "every source has its own label")
        let scenes = all.filter { $0.kind == .scene }
        #expect(scenes.count <= 6 && scenes.allSatisfy { s in structure.scenes.firstIndex { $0.id == s.ref }! < 5 }, "only scenes before this one")
        let small = ConsistencySources.gather(sceneID: scene, passage: passage, characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure, budget: 300)
        #expect(small.count < all.count && small.map(\.text.count).reduce(0, +) < 400, "cut to the budget")
    }

    @Test("the job checks scene after scene, keeps findings when stopped, and tells the model what it needs to")
    func job() async throws {
        let server = try FakeLMServer()
        server.handler = { request, responder in
            let body = String(decoding: request.body, as: UTF8.self)
            let answer = body.contains("compare two statements") ? "{\"contradiction\": true}" : "{\"findings\": [{\"source\": \"C1\", \"problem\": \"Цвет глаз.\", \"passage_quote\": \"подняла голубые глаза\", \"source_quote\": \"Серые глаза\"}]}"
            responder.json(["choices": [["message": ["content": answer]]]])
        }
        let client = LLMTests.client(server)
        let scenes = [ConsistencyScene(id: "a", title: "A", text: Self.passage, sources: Self.sources), ConsistencyScene(id: "b", title: "B", text: "Коротко.", sources: Self.sources),
                      ConsistencyScene(id: "c", title: "C", text: Self.passage, within: NSRange(location: 0, length: 51), sources: Self.sources)]
        let got = CollectTests.Gathered()
        let summary = await ConsistencyJob.run(scenes: scenes, language: "ru", context: 8192, client: client, progress: { got.add($0) }, found: { found in got.add(found.map { _ in CollectedItem(kind: .characters, name: "f") }) })
        #expect(summary.scenesDone == 2 && summary.scenesTooShort == 1 && summary.found == 2 && summary.error == nil)
        let body = String(decoding: server.requests.first!.body, as: UTF8.self)
        #expect(body.contains("CONTRADICTIONS") && body.contains("[C1] Анна") && body.contains("Russian") && body.contains("no_think"))
        let last = String(decoding: server.requests.last!.body, as: UTF8.self)
        #expect(last.contains("подняла голубые глаза") && !last.contains("Было жаркое лето"), "a selection sends only the selected words")
    }

    @Test("a dismissed finding is remembered on this machine, by its words")
    func dismissals() {
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-dis-\(UUID().uuidString)")
        let f = ConsistencyFinding(scene: "s", problem: "Цвет глаз.", quote: "голубые глаза", range: NSRange(location: 0, length: 3), source: Self.sources[0], sourceQuote: "Серые глаза")
        AIDismissals.add([f.key], book: book)
        #expect(AIDismissals.load(book: book).contains(f.key))
        AIDismissals.forgetAll(book: book)
        #expect(AIDismissals.load(book: book).isEmpty)
    }

    @Test("a candidate the second look does not confirm, or a repeated sentence, is left out")
    func judging() async throws {
        let server = try FakeLMServer()
        server.handler = { request, responder in
            let body = String(decoding: request.body, as: UTF8.self)
            let answer = body.contains("compare two statements") ? "{\"contradiction\": false}" : "{\"findings\": [{\"source\": \"C1\", \"problem\": \"Цвет глаз.\", \"passage_quote\": \"подняла голубые глаза\", \"source_quote\": \"Серые глаза\"}]}"
            responder.json(["choices": [["message": ["content": answer]]]])
        }
        let scene = ConsistencyScene(id: "a", title: "A", text: Self.passage, sources: [Self.sources[0]])
        let summary = await ConsistencyJob.run(scenes: [scene], language: "ru", context: 8192, client: LLMTests.client(server), progress: { _ in }, found: { _ in })
        #expect(summary.found == 0 && summary.droppedByJudge == 1, "\(summary)")
        let same = ConsistencyFinding(scene: "s", problem: "p", quote: "Пахло смолой, дымом и чем-то ещё", range: NSRange(location: 0, length: 3), source: Self.sources[1], sourceQuote: "пахло смолой дымом и чем-то еще")
        #expect(ConsistencyJudge.isRepetition(same))
        #expect(ConsistencyJudge.verdict("{\"contradiction\": true}") == true && ConsistencyJudge.verdict("maybe") == nil)
    }
}
