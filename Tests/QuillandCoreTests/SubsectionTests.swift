import Foundation
import Testing
@testable import QuillandCore

@Suite("Subsections of a scene")
struct SubsectionTests {
    static let a = "11111111-1111-4111-8111-111111111111", b = "22222222-2222-4222-8222-222222222222", c = "33333333-3333-4333-8333-333333333333"

    @Test("the markers in a scene's text make its subsections; a title typed wins, else the heading, else the first words")
    func parsing() {
        let text = "<!-- fragment: \(Self.a) -->\n\nПервая часть сцены, в которой герой входит в дом и садится.\n\n<!-- fragment: \(Self.b) -->\n\n## Ночью\n\nВторая часть.\n\n<!-- fragment: \(Self.c) -->\n\nТретья."
        let subs = Subsections.parse(scene: "s1", markdown: text, titles: [Self.c: "Утро"])
        #expect(subs.map(\.id) == [Self.a, Self.b, Self.c] && subs.map(\.index) == [0, 1, 2] && subs.allSatisfy { $0.scene == "s1" && $0.isMarked })
        #expect(subs[0].derivedTitle == "Первая часть сцены, в которой герой…", "the first words, up to six: \(subs[0].derivedTitle)")
        #expect(subs[1].derivedTitle == "Ночью" && subs[1].shownTitle == "Ночью", "a heading as the first line is the title")
        #expect(subs[2].title == "Утро" && subs[2].shownTitle == "Утро", "a typed title wins")
        #expect(subs[1].characters == "Ночью".count + "Вторая часть.".count, "the size is the text of the part, with no marker")
        #expect(Subsections.parse(scene: "s1", markdown: "Просто текст.").isEmpty, "a scene with no markers has none")
    }

    @Test("text before the first marker is a part under the scene's own id; a marker at the very top leaves none")
    func leadingPart() {
        let text = "Начало без метки.\n\n<!-- fragment: \(Self.a) -->\n\nПродолжение."
        let subs = Subsections.parse(scene: "s9", markdown: text)
        #expect(subs.count == 2 && subs[0].id == "s9" && !subs[0].isMarked && subs[1].id == Self.a && subs[1].isMarked)
        let top = Subsections.parse(scene: "s9", markdown: "<!-- fragment: \(Self.a) -->\n\nТолько часть.")
        #expect(top.count == 1 && top[0].isMarked)
    }

    @Test("first words are cut at six words or 48 characters")
    func words() {
        #expect(Subsections.firstWords("раз два три") == "раз два три")
        #expect(Subsections.firstWords("один два три четыре пять шесть семь восемь") == "один два три четыре пять шесть…")
        #expect(Subsections.firstWords(String(repeating: "я", count: 60)) == String(repeating: "я", count: 48) + "…")
    }

    @Test("the structure of a book knows the subsections, with the titles typed, and a link to one resolves to its scene")
    func inTheBook() throws {
        let parent = try NewBookTests.folder(); defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        var structure = try BookStructure.load(folder: book)
        let scene = try #require(structure.scenes.first)
        let base = book.appendingPathComponent(scene.node.base)
        try "<!-- fragment: \(Self.a) -->\n\nПервая.\n\n<!-- fragment: \(Self.b) -->\n\nВторая.".write(to: base.appendingPathExtension("md"), atomically: true, encoding: .utf8)
        var record = SceneRecord(object: try JSONParser.parseObject(Data(contentsOf: base.appendingPathExtension("json"))))
        record.fragmentTitles = [Self.b: "Вечер"]
        try AtomicFile.write(JSONWriter.data(record.object), to: base.appendingPathExtension("json"))
        structure = try BookStructure.load(folder: book)
        let subs = try #require(structure.subsections[scene.node.id])
        #expect(subs.map(\.shownTitle) == ["Первая.", "Вечер"], "\(subs.map(\.shownTitle))")
        #expect(SceneLinks.scene(of: Self.a) == scene.node.id && SceneLinks.scene(of: scene.node.id) == scene.node.id && SceneLinks.isSubsection(Self.b) && !SceneLinks.isSubsection(scene.node.id), "a link to a subsection stands for its scene")
        #expect(SceneLinks.has([Self.b: "что-то"], scene: scene.node.id) && !SceneLinks.has([Self.b: ""], scene: "another") && SceneLinks.scenes(of: [Self.a: "", "x": ""]) == [scene.node.id, "x"])
        #expect(Set(SceneLinks.subsections(of: scene.node.id)) == [Self.a, Self.b])
        // Loose Ends: the id of a subsection is not an id that points to nothing (an id that is nobody's is).
        let people = CharacterStore(book: book)
        let anna = try people.add(name: "Анна")
        try people.update(anna) { $0.links = [Self.a: "здесь", "99999999-9999-4999-8999-999999999999": "нигде"] }
        let ends = LooseEnds(book: book).scan().filter { $0.owner == "Анна" }.map(\.target)
        #expect(ends == ["99999999-9999-4999-8999-999999999999"], "a link to a subsection is not a loose end, a link to nothing still is: \(ends)")
        // Titles typed are dropped with the empty ones, and the key is left out when there are none.
        record.fragmentTitles = [:]
        #expect(record.object["fragment_titles"] == nil)
    }

    @Test("a link to a subsection counts for its scene: members, the graph, the order of events, and Loose Ends")
    func linksResolve() throws {
        let f = try BookGraphTests.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let book = f.structure.folder
        let frag = "44444444-4444-4444-8444-444444444444"   // (ids are unique in the real world; the tests that run together must not share one)
        SceneLinks.set([frag: "s1"], forBook: book)
        defer { SceneLinks.set([:], forBook: book) }
        let vera = f.ids["vera"]!, lone = f.ids["lone"]!, manor = f.ids["manor"]!
        try f.characters.update(vera) { $0.links = [frag: "в начале"] }
        try f.worlds.updateEntry(manor) { $0.links = [frag: ""] }
        #expect(SceneMembers.linkedCharacters(inScene: "s1", store: f.characters).contains(vera) && !SceneMembers.linkedCharacters(inScene: "s2", store: f.characters).contains(vera), "a character linked to a subsection is in its scene")
        #expect(SceneMembers.linkedPlaces(inScene: "s1", store: f.worlds).contains(manor), "so is a place")
        // The graph draws the line to the scene.
        let graph = f.graph()
        _ = graph
        var withScenes = GraphOptions(); withScenes.kinds = Set(GraphKind.allCases)
        let all = f.graph(withScenes)
        #expect(all.edges.contains { $0.kind == .inScene && Set([$0.a, $0.b]) == Set([vera, "s1"]) }, "the graph links the character to the scene, not to a node that is not there")
        // An event linked to a subsection stands where its scene does.
        let late = try f.events.add(title: "Поздно")
        try f.events.update(late) { $0.links = [frag: ""] }
        let order = f.structure.scenes.map(\.id)
        let timeline = RelationshipTimeline(events: f.events, sceneOrder: order)
        #expect(timeline.order(of: late) != nil, "an event linked only to a subsection has a place in the book")
        let groups = f.events.groups(sceneOrder: order)
        #expect(groups.first { $0.events.contains { $0.id == late } }?.scene == "s1", "and is grouped with its scene")
        _ = lone
    }

    @Test("Collect reads a divided scene in its parts, each with its own narrators (the scene's where it has none), and never across a boundary")
    func collectParts() {
        let marker = "\u{FFFC}"
        let text = marker + "\nПервая часть, где «я» входит в дом.\n" + marker + "\nВторая часть, где «я» уходит.\n"
        let ns = text as NSString
        let second = ns.range(of: marker, options: [], range: NSRange(location: 1, length: ns.length - 1)).location
        let scene = CollectScene(id: "s1", title: "С", text: text, narrators: ["Вилли"], parts: [CollectPart(start: 0, end: second, narrators: ["Вилли"]), CollectPart(start: second, end: ns.length, narrators: ["Лилит"])])
        let pieces = CollectJob.pieces(of: scene, maxCharacters: 10_000)
        #expect(pieces.count == 2 && pieces[0].narrators == ["Вилли"] && pieces[1].narrators == ["Лилит"], "one piece for each subsection, with its narrators")
        #expect(pieces[0].text.contains("входит") && !pieces[0].text.contains("уходит") && pieces[1].text.contains("уходит"), "a piece never crosses a boundary")
        #expect(!pieces.contains { $0.text.contains(marker) } && pieces[1].offset == second, "the markers are blanked and the places in the scene stay the same")
        #expect((text as NSString).substring(with: NSRange(location: pieces[1].offset + 3, length: 6)) == (pieces[1].text as NSString).substring(with: NSRange(location: 3, length: 6)), "a place in a piece is a place in the scene")
        // A scene with no parts is read as it was, with the scene's narrators.
        let plain = CollectScene(id: "s2", title: "С", text: "Просто текст сцены.", narrators: ["Вилли"])
        let whole = CollectJob.pieces(of: plain, maxCharacters: 10_000)
        #expect(whole.count == 1 && whole[0].narrators == ["Вилли"] && whole[0].offset == 0)
        // A long part is cut into pieces of its own.
        let long = CollectScene(id: "s3", title: "С", text: String(repeating: "Слово. ", count: 400), narrators: [], parts: [CollectPart(start: 0, end: 2800, narrators: ["Анна"])])
        #expect(CollectJob.pieces(of: long, maxCharacters: 1000).allSatisfy { $0.narrators == ["Анна"] } && CollectJob.pieces(of: long, maxCharacters: 1000).count >= 2)
    }
}
