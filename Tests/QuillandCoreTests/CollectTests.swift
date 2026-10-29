import Foundation
import Testing
@testable import QuillandCore

@Suite("Collecting from the book", .serialized)
struct CollectTests {
    // MARK: Quotes

    @Test("a quote is looked for in the text ignoring case, ё, quotation marks and spacing, and the range is the text's own")
    func quotes() {
        let text = "Утром Анна вышла на платформу.  «Поезд ушёл», — сказал старик."
        let r1 = QuoteVerifier.find("анна ВЫШЛА на платформу", in: text)!
        #expect((text as NSString).substring(with: r1) == "Анна вышла на платформу")
        let r2 = QuoteVerifier.find("Поезд ушел сказал старик", in: text)
        #expect(r2 != nil, "ё and е, a dash and quotes do not matter")
        let r3 = QuoteVerifier.find("Анна вышла на платформу и закурила", in: text)!
        #expect((text as NSString).substring(with: r3) == "Анна вышла на платформу", "a quote that goes on past the text still finds its beginning")
        #expect(QuoteVerifier.find("Анна вернулась домой поздно", in: text) == nil)
        #expect(QuoteVerifier.find("Старик", in: text) != nil && QuoteVerifier.find("Старуха", in: text) == nil, "a short quote must be there whole")
        #expect(QuoteVerifier.find("", in: text) == nil)
    }

    // MARK: The answer

    static let passage = "Анна стояла на платформе. Старик в фуражке спросил, к кому она приехала. Она ответила: к тёте Вере. Они пошли к дому у озера."

    @Test("a JSON answer, even in a fence and with talk around it, becomes findings; those without a true quote are dropped")
    func parsing() {
        let reply = """
        Here you go:
        ```json
        {"characters": [
          {"name": "Анна", "aliases": ["Аня"], "description": "Приезжает к тёте.", "note": "стоит на платформе", "quote": "Анна стояла на платформе"},
          {"name": "Лев", "description": "Выдуманный", "note": "", "quote": "Лев вошёл в комнату"}],
         "places": [{"name": "Озеро", "type": "place", "parent": "", "description": "Рядом с домом.", "note": "", "quote": "к дому у озера"},
                    {"name": "Дом", "type": "weird", "description": "", "note": "", "quote": "Они пошли к дому"}],
         "events": [{"title": "Приезд Анны", "date": "", "places": ["Станция"], "characters": ["Анна", "Старик"], "note": "Её встречает старик", "quote": "Старик в фуражке спросил"}],
         "relationships": [{"characters": ["Анна", "Вера"], "kind": "племянница и тётя", "note": "", "quote": "к тёте Вере"}, {"characters": ["Анна"], "kind": "x", "note": "", "quote": "Анна стояла"}],
         "observations": [{"about": "Старик", "note": "носит фуражку", "quote": "Старик в фуражке"}]}
        ```
        Hope it helps.
        """
        let kinds = Set(CollectKind.allCases)
        let result = CollectParser.parse(reply, kinds: kinds, scene: "s1", chunk: Self.passage, chunkOffset: 1000)
        #expect(!result.malformed && result.dropped == 1 && result.items.count == 6, "\(result.dropped) \(result.items.map(\.title))")
        let anna = result.items.first { $0.name == "Анна" }!
        #expect(anna.aliases == ["Аня"] && anna.evidence[0].quote == "Анна стояла на платформе" && anna.evidence[0].range.location == 1000 && anna.evidence[0].note == "стоит на платформе")
        #expect(result.items.first { $0.name == "Дом" }?.type == "place", "an unknown type becomes a place")
        #expect(result.items.contains { $0.kind == .relationships && $0.members == ["Анна", "Вера"] } && !result.items.contains { $0.members == ["Анна"] }, "a relationship needs two different names")
        #expect(result.items.first { $0.kind == .observations }?.about == "Старик")
        #expect(result.items.first { $0.kind == .events }?.members == ["Анна", "Старик"], "an event has the characters who take part")
        #expect(CollectPrompt.system(kinds: [.events]).contains("who take part"), "the model is asked for them")
        let only = CollectParser.parse(reply, kinds: [.events], scene: "s1", chunk: Self.passage, chunkOffset: 0)
        #expect(only.items.count == 1 && only.items[0].kind == .events, "only the kinds asked for")
        #expect(CollectParser.parse("I could not do it.", kinds: kinds, scene: "s", chunk: "x", chunkOffset: 0).malformed)
        #expect(CollectParser.parse("{\"characters\": []}", kinds: kinds, scene: "s", chunk: "x", chunkOffset: 0).items.isEmpty)
    }

    // MARK: The second pass: what happens

    @Test("changes and when a relationship begins are read; what an event cannot change is never taken, whatever the model says")
    func changes() {
        let reply = """
        {"changes": [
          {"about": "Анна", "field": "profile", "value": "Теперь она капитан.", "event": "Приезд Анны", "quote": "Анна стояла на платформе"},
          {"about": "Старик", "field": "aliases", "aliases": ["Дед"], "quote": "Старик в фуражке"},
          {"about": "Анна", "field": "main", "value": "true", "quote": "Анна стояла"},
          {"about": "Анна", "field": "notes", "value": "x", "quote": "Анна стояла"},
          {"about": "Озеро", "field": "description", "value": "Пересохло.", "quote": "к дому у озера"},
          {"about": "Анна", "field": "profile", "value": "Выдумка.", "quote": "Анна вошла в замок"},
          {"about": "Анна", "field": "profile", "value": "", "quote": "Анна стояла"}],
         "relationships": [{"characters": ["Анна", "Вера"], "kind": "тётя и племянница", "when": "starts", "quote": "к тёте Вере"},
                           {"characters": ["Анна", "Вера"], "kind": "родные", "when": "whenever", "quote": "к тёте Вере"}]}
        """
        let r = CollectParser.parse(reply, kinds: [.changes, .relationships], scene: "s1", chunk: Self.passage, chunkOffset: 0)
        let changes = r.items.filter { $0.kind == .changes }
        #expect(changes.map(\.field) == ["profile", "aliases", "description"], "the main flag, the notes and an empty value are not changes: \(changes.map(\.field))")
        #expect(changes[0].eventTitle == "Приезд Анны" && changes[0].detail == "Теперь она капитан." && changes[1].aliases == ["Дед"] && changes[0].title == "Анна — profile")
        #expect(r.dropped == 1, "a change whose quote is not in the text is dropped")
        let rels = r.items.filter { $0.kind == .relationships }
        #expect(rels.map(\.when) == ["starts", "stated"], "an unknown moment is just stated")
        #expect(rels[0].key != rels[1].key, "the same pair at another moment is another finding")
        var set = CollectedSet()
        set.merge(changes + changes)
        #expect(set.items.count == 3, "two changes of one thing are not merged as names are")
    }

    @Test("the kind of a relationship is asked for in the book's language, with no English example to copy")
    func relationshipKindLanguage() {
        let ru = CollectPrompt.task(kinds: [.relationships], language: "ru"), none = CollectPrompt.task(kinds: [.relationships])
        #expect(ru.contains("written in Russian") && ru.contains("in Russian\"") && !ru.contains("sisters"), "the kind is in Russian, and the schema shows no English word to copy")
        #expect(none.contains("the language of the passage") && !none.contains("sisters"))
        #expect(CollectPrompt.user(chunk: "Т", sceneTitle: "С", knownCharacters: [], knownPlaces: [], kinds: [.relationships], language: "ru").contains("in Russian"), "the request carries it")
    }

    @Test("the two passes ask for different things, and the second is told the cards the passage names")
    func passes() {
        #expect(CollectKind.characters.pass == .facts && CollectKind.observations.pass == .facts && CollectKind.events.pass == .story && CollectKind.changes.pass == .story && CollectKind.relationships.pass == .story)
        let facts = CollectPrompt.task(kinds: [.characters, .places, .observations]), story = CollectPrompt.task(kinds: [.events, .changes, .relationships])
        #expect(facts.contains("\"observations\"") && !facts.contains("\"changes\"") && !facts.contains("\"events\""))
        #expect(story.contains("\"changes\"") && story.contains("\"when\"") && !story.contains("\"characters\": people") && story.contains("never the name, the notes or whether someone is a main character"))
        #expect(!story.contains("\"main\":") && !story.contains("field\": \"main"), "the model is never offered the main flag")
        let cards = [CollectCard(name: "Анна", aliases: ["Аня"], text: "Тихая девочка", relations: ["Вера: тётя"]), CollectCard(name: "Лев", text: "Капитан."), CollectCard(name: "Платформа", text: "Большая.", isPlace: true)]
        let known = CollectPrompt.known(cards: cards, in: Self.passage, budget: 1000)
        #expect(known.contains("Анна (also Аня): Тихая девочка | Relationships: Вера: тётя") && known.contains("Платформа") && !known.contains("Лев"), "only the cards the passage names: [\(known)]")
        #expect(CollectPrompt.known(cards: cards, in: Self.passage, budget: 40).split(separator: "\n").count == 0, "within the budget")
        let a = CollectPrompt.user(chunk: "ТЕКСТ", sceneTitle: "С", knownCharacters: [], knownPlaces: [], kinds: [.characters]), b = CollectPrompt.user(chunk: "ТЕКСТ", sceneTitle: "С", knownCharacters: [], knownPlaces: [], known: known, kinds: [.events])
        #expect(a.hasPrefix("Passage from the scene “С”:") && b.hasPrefix(String(a.prefix(40))), "both passes begin with the same passage")
    }

    // MARK: Merging

    @Test("the same thing found in several scenes is one item, with all the evidence; another name of it joins")
    func merging() {
        func character(_ name: String, aliases: [String] = [], scene: String, at: Int, detail: String = "") -> CollectedItem {
            var c = CollectedItem(kind: .characters, name: name)
            c.aliases = aliases; c.detail = detail
            c.evidence = [CollectedEvidence(scene: scene, quote: "q", range: NSRange(location: at, length: 1), note: "в \(scene)")]
            return c
        }
        var set = CollectedSet()
        set.merge([character("Анна", scene: "a", at: 1, detail: "Коротко.")])
        set.merge([character("анна", scene: "b", at: 5, detail: "Подробнее и длиннее."), character("Аня", aliases: ["Анна"], scene: "c", at: 9)])
        #expect(set.items.count == 1 && set.items[0].evidence.map(\.scene) == ["a", "b", "c"], "\(set.items.map(\.name))")
        #expect(set.items[0].detail == "Подробнее и длиннее." && set.items[0].aliases == ["Аня"])
        set.merge([character("Анна", scene: "a", at: 1)])
        #expect(set.items[0].evidence.count == 3, "the same place in the same scene is not counted twice")
        var r1 = CollectedItem(kind: .relationships, name: ""); r1.members = ["Анна", "Вера"]; r1.type = "тётя"
        var r2 = CollectedItem(kind: .relationships, name: ""); r2.members = ["вера", "анна"]; r2.type = "Тётя"
        set.merge([r1, r2])
        #expect(set.items.filter { $0.kind == .relationships }.count == 1, "a relationship is the same whichever way it is written")
        var e1 = CollectedItem(kind: .events, name: "Приезд"); e1.members = ["Анна"]
        var e2 = CollectedItem(kind: .events, name: "приезд"); e2.members = ["анна", "Вера"]
        set.merge([e1, e2])
        #expect(set.items.filter { $0.kind == .events }.count == 1 && set.items.first { $0.kind == .events }?.members == ["Анна", "Вера"], "the participants of one event found twice are joined")
    }

    @Test("a long scene is cut at paragraph ends, and the offsets add up")
    func chunking() {
        let paragraph = String(repeating: "слово ", count: 100) + "\n"
        let text = String(repeating: paragraph, count: 10)
        let chunks = CollectChunker.chunks(text, maxCharacters: 1500)
        #expect(chunks.count >= 3 && chunks.allSatisfy { $0.text.count <= 1500 + 600 })
        #expect(chunks.map(\.text).joined() == text, "nothing lost")
        var at = 0
        for c in chunks { #expect(c.offset == at); at += (c.text as NSString).length }
        #expect(CollectChunker.chunks("short", maxCharacters: 1500).count == 1 && CollectChunker.chunks("", maxCharacters: 1500).isEmpty)
        #expect(CollectJob.pieceSize(context: 40960) == 8000 && CollectJob.pieceSize(context: 4096) == 1500)
    }

    // MARK: The job

    final class Gathered: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [CollectedItem] = []
        private var _progress: [CollectProgress] = []
        func add(_ i: [CollectedItem]) { lock.withLock { _items += i } }
        func add(_ p: CollectProgress) { lock.withLock { _progress.append(p) } }
        var items: [CollectedItem] { lock.withLock { _items } }
        var progress: [CollectProgress] { lock.withLock { _progress } }
    }

    static func scene(_ id: String, _ text: String) -> CollectScene { CollectScene(id: id, title: "Сцена \(id)", text: text) }

    static func answeringServer(_ answer: @escaping @Sendable (String) -> String) throws -> FakeLMServer {
        let server = try FakeLMServer()
        server.handler = { request, responder in
            let messages = (request.json?["messages"] as? [[String: Any]]) ?? []
            let user = (messages.last?["content"] as? String) ?? ""
            responder.json(["choices": [["message": ["content": answer(user)]]]])
        }
        return server
    }

    @Test("the job reads scene after scene, reports, skips short and unchanged scenes, and keeps what it found")
    func job() async throws {
        let long = Self.passage + " " + String(repeating: "Они шли медленно и молчали. ", count: 12)
        let server = try Self.answeringServer { user in
            if user.contains("Сцена two") { return "not json at all" }
            return "{\"characters\": [{\"name\": \"Анна\", \"description\": \"d\", \"note\": \"n\", \"quote\": \"Анна стояла на платформе\"}]}"
        }
        let client = LLMTests.client(server)
        var request = CollectRequest(kinds: [.characters], scenes: [Self.scene("one", long), Self.scene("two", long), Self.scene("tiny", "Коротко."), Self.scene("three", long)])
        request.context = 8192
        let gathered = Gathered()
        let summary = await CollectJob.run(request, client: client, progress: { gathered.add($0) }, found: { gathered.add($0) })
        #expect(summary.scenesDone == 3 && summary.scenesTooShort == 1 && summary.failedPieces == 1 && !summary.stopped && summary.error == nil)
        let scenesReported = gathered.progress.map(\.scene).reduce(into: [Int]()) { if $1 != $0.last { $0.append($1) } }
        #expect(gathered.items.count == 2 && scenesReported == [1, 2, 4], "scene two's answer was not JSON: \(scenesReported)")
        // The bar and the count are live: a report after every request, the steps done never going back, the findings counted as they come, and the last step is the total.
        let steps = gathered.progress
        #expect(steps.count == 3 + 3 && steps.allSatisfy { $0.pieces == 3 }, "each of the three scenes read reports when it starts and when its request is done: \(steps.map { "\($0.scene):\($0.piece)/\($0.pieces)" })")
        #expect(steps.map(\.piece) == steps.map(\.piece).sorted() && steps.last?.piece == 3 && steps.map(\.found) == steps.map(\.found).sorted() && steps.last?.found == 2, "steps and findings only grow, ending at the true totals")
        #expect(steps.first { $0.scene == 2 && $0.piece == 1 }?.found == 1, "the status line is told what was found so far, not what was found before the scene")
        #expect(Set(summary.analysed.keys) == ["one", "three"], "a scene whose answer failed is not remembered as read")
        // Again with the memory: the scenes read before are skipped; Re-analyse reads them all.
        var again = request
        again.analysed = summary.analysed
        let second = await CollectJob.run(again, client: client, progress: { _ in }, found: { _ in })
        #expect(second.scenesSkipped == 2 && second.scenesDone == 1)
        again.reanalyse = true
        let third = await CollectJob.run(again, client: client, progress: { _ in }, found: { _ in })
        #expect(third.scenesSkipped == 0 && third.scenesDone == 3)
        // A different ask is a different fingerprint.
        #expect(CollectJob.fingerprint(long, kinds: [.characters]) != CollectJob.fingerprint(long, kinds: [.characters, .places]))
        // The request carries the instructions, the known names and the passage.
        let body = String(decoding: server.requests.last!.body, as: UTF8.self)
        #expect(body.contains("EXACTLY") && body.contains("Анна стояла") && body.contains("no_think"))
    }

    @Test("two passes over each piece: what is known, then what happens; the second is told the known cards and is left out where no one is")
    func twoPasses() async throws {
        let long = Self.passage + " " + String(repeating: "Они шли медленно и молчали. ", count: 12)
        let nobody = "Шёл дождь. " + String(repeating: "Капли стучали по крыше. ", count: 20)
        let server = try Self.answeringServer { user in
            if user.contains("\"changes\"") { return "{\"changes\": [{\"about\": \"Анна\", \"field\": \"profile\", \"value\": \"Устала.\", \"quote\": \"Анна стояла на платформе\"}]}" }
            if user.contains("Шёл дождь") { return "{\"characters\": []}" }
            return "{\"characters\": [{\"name\": \"Анна\", \"description\": \"d\", \"note\": \"n\", \"quote\": \"Анна стояла на платформе\"}]}"
        }
        let client = LLMTests.client(server)
        var request = CollectRequest(kinds: [.characters, .changes], scenes: [Self.scene("one", long), Self.scene("rain", nobody)])
        request.context = 8192
        request.cards = [CollectCard(name: "Анна", text: "Тихая девочка.")]
        let gathered = Gathered()
        let summary = await CollectJob.run(request, client: client, progress: { gathered.add($0) }, found: { gathered.add($0) })
        #expect(summary.scenesDone == 2 && summary.failedPieces == 0)
        #expect(gathered.progress.allSatisfy { $0.pieces == 4 } && gathered.progress.last?.piece == 4, "four steps in all (two passes over two scenes), and the one left out for the rain still counts: \(gathered.progress.map { "\($0.piece)/\($0.pieces)" })")
        #expect(gathered.items.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.changes, .characters], "one scene gave a character and a change")
        let bodies = server.requests.map { String(decoding: $0.body, as: UTF8.self) }
        #expect(bodies.count == 3, "two requests for the scene with someone in it, one for the rain: \(bodies.count)")
        let second = bodies.first { $0.contains("\\\"changes\\\"") }
        #expect(second?.contains("Тихая девочка.") == true && second?.contains("Known cards") == true, "the second pass is told what the card says")
        #expect(!bodies.contains { $0.contains("Шёл дождь") && $0.contains("\\\"changes\\\"") }, "no one is in the rain: nothing happens to anyone")
        // Only the story: the passage is read once, with no first pass.
        var story = request
        story.kinds = [.events]
        let before = server.requests.count
        _ = await CollectJob.run(story, client: client, progress: { _ in }, found: { _ in })
        #expect(server.requests.count - before == 2, "one request for each scene when only the story is asked for")
    }

    @Test("Stop keeps what was found; a server that does not answer ends the run with the reason")
    func stopping() async throws {
        let long = Self.passage + " " + String(repeating: "Они шли медленно и молчали. ", count: 12)
        let server = try Self.answeringServer { _ in "{\"characters\": [{\"name\": \"Анна\", \"description\": \"\", \"note\": \"\", \"quote\": \"Анна стояла на платформе\"}]}" }
        let client = LLMTests.client(server)
        let request = CollectRequest(kinds: [.characters], scenes: (1...20).map { Self.scene("s\($0)", long) })
        let gathered = Gathered()
        let task = Task { await CollectJob.run(request, client: client, progress: { gathered.add($0) }, found: { gathered.add($0) }) }
        while gathered.items.count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        task.cancel()
        let summary = await task.value
        #expect(summary.stopped && summary.scenesDone < 20 && gathered.items.count >= 2)
        var closed: FakeLMServer? = try FakeLMServer()
        let dead = LLMTests.client(closed!)
        closed = nil
        let failed = await CollectJob.run(request, client: dead, progress: { _ in }, found: { _ in })
        #expect(failed.error?.contains("LM Studio") == true && failed.scenesDone == 0)
    }

    @Test("a name the model made up is replaced by a card's name, in one finding or in all, by the kind the name can be; findings that become the same join")
    func replacingNames() {
        func ev(_ scene: String) -> [CollectedEvidence] { [CollectedEvidence(scene: scene, quote: "q", range: NSRange(location: 0, length: 1), note: "")] }
        func rel(_ a: String, _ b: String, _ kind: String, scene: String) -> CollectedItem {
            var r = CollectedItem(kind: .relationships, name: ""); r.members = [a, b]; r.type = kind; r.when = "stated"; r.evidence = ev(scene); return r
        }
        var set = CollectedSet()
        let r1 = rel("Герой", "Элли", "дружба", scene: "s1"), r2 = rel("Герой (рассказчик)", "Элли", "дружба", scene: "s2"), r3 = rel("Герой", "Губер", "ученик", scene: "s1")
        var event = CollectedItem(kind: .events, name: "Встреча"); event.members = ["Герой", "Лилит"]; event.places = ["Герой"]; event.evidence = ev("s1")
        var place = CollectedItem(kind: .places, name: "Герой"); place.parent = "Дом"; place.evidence = ev("s1")
        var fact = CollectedItem(kind: .observations, name: ""); fact.about = "Герой"; fact.detail = "Хромает."; fact.evidence = ev("s1")
        set.merge([r1, r2, r3, event, place, fact])
        #expect(r1.nameSlots == [NameSlot(role: .character, name: "Герой"), NameSlot(role: .character, name: "Элли")] && fact.nameSlots == [NameSlot(role: .either, name: "Герой")], "the names of a finding, with what each can be")
        #expect(event.nameSlots.map(\.role) == [.character, .character, .place] && place.nameSlots.map(\.name) == ["Герой", "Дом"])

        // One finding alone.
        var one = set
        #expect(one.replaceName("Герой", role: .character, with: "Вилли", only: r3.id) == 1)
        #expect(one.items.first { $0.id == r3.id }?.members == ["Вилли", "Губер"] && one.items.first { $0.id == r1.id }?.members == ["Герой", "Элли"], "only that finding changes")

        // All: by the kind the name is. The character «Герой» changes in relationships, the event's people and a fact (a name of either kind); the place called «Герой» and the
        // event's place of that name keep it.
        let changed = set.replaceName("Герой", role: .character, with: "Вилли")
        #expect(changed == 4, "the relationships, the event and the fact: \(changed)")
        let items = set.items
        #expect(items.first { $0.kind == .events }?.members == ["Вилли", "Лилит"] && items.first { $0.kind == .events }?.places == ["Герой"], "an event's people change, its places (another kind) do not")
        #expect(items.first { $0.kind == .places }?.name == "Герой", "a place with the same text is not touched")
        #expect(items.first { $0.kind == .observations }?.about == "Вилли", "a name that can be either kind follows")
        // (Another way the model wrote the same name is a name of its own: it is replaced in its turn, and then the two findings are one.)
        #expect(set.replaceName("Герой (рассказчик)", role: .character, with: "Вилли") == 1)
        let friends = set.items.filter { $0.kind == .relationships && Set($0.members) == ["Вилли", "Элли"] }
        #expect(friends.count == 1 && friends[0].evidence.count == 2, "two findings that are now the same relationship are one, with the quotes of both")

        // A place name; the replaced name does not become another name of the card.
        var more = CollectedSet(); var c = CollectedItem(kind: .characters, name: "Герой"); c.aliases = ["Вилли"]; c.evidence = ev("s1"); more.merge([c])
        more.replaceName("Герой", role: .character, with: "Вилли")
        #expect(more.items[0].name == "Вилли" && more.items[0].aliases.isEmpty, "the new name is the name, and is not also an alias")
        var parents = CollectedSet(); parents.merge([place])
        parents.replaceName("Дом", role: .place, with: "Усадьба")
        #expect(parents.items[0].parent == "Усадьба", "a place's parent is a place name")
        #expect(parents.replaceName("Нет такого", role: .place, with: "X") == 0, "nothing to replace changes nothing")
    }
}
