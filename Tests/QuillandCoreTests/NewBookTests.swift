import Foundation
import Testing
@testable import QuillandCore

@Suite("A new book, the settings, the local state")
struct NewBookTests {
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-newbook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a new book has what every book has, and the app reads it")
    func create() throws {
        let parent = try Self.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом на Сосновой", author: "Вадим Сульянов", language: "ru", parentFolder: parent))
        #expect(book.lastPathComponent == "Дом на Сосновой")
        let info = try JSONParser.parseObject(Data(contentsOf: book.appendingPathComponent("book.json")))
        #expect(info.string("title") == "Дом на Сосновой" && info.string("author") == "Вадим Сульянов" && info.string("language") == "ru" && info.int("format") == 1 && info.string("id") != nil)
        #expect(try String(contentsOf: book.appendingPathComponent(".gitignore"), encoding: .utf8) == ".quilland/\n")
        let structure = try BookStructure.load(folder: book)
        #expect(structure.problems.isEmpty && structure.scenes.count == 1)
        #expect(structure.scenes[0].node.title == "Сцена 1" && structure.scenes[0].chapterTitle == "Глава 1" && structure.scenes[0].node.status == "idea")
        #expect(try Data(contentsOf: structure.markdownURL(for: structure.scenes[0].node)).isEmpty, "the first scene is empty")
        // The default world and the starter kind.
        let worlds = try FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent("bible/worlds").path)
        #expect(worlds.count == 1)
        let kinds = try FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent("bible/kinds").path)
        #expect(kinds.count == 1)
        let kind = try JSONParser.parseObject(Data(contentsOf: book.appendingPathComponent("bible/kinds/\(kinds[0])")))
        #expect(kind.string("description")?.hasPrefix("Вещи:") == true && kind.object("name")?.string("one") == "Вещь")
        #expect((kind.objects("fields") ?? []).count == 3 && kind.bool("findable") == true)
        // Every file is in the canonical form (written by the strict writer).
        for path in ["book.json", "bible/kinds/\(kinds[0])", "manuscript/001-chapter/_chapter.json"] {
            let text = try String(contentsOf: book.appendingPathComponent(path), encoding: .utf8)
            #expect(JSONWriter.write(try JSONParser.parseObject(Data(text.utf8))) == text, "\(path)")
        }
    }

    @Test("English names, a taken folder name, a title with slashes, an empty title")
    func edges() throws {
        let parent = try Self.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let a = try BookCreator.create(NewBookRequest(title: "My: Book/One", language: "en", parentFolder: parent))
        let b = try BookCreator.create(NewBookRequest(title: "My: Book/One", language: "en", parentFolder: parent))
        #expect(a.lastPathComponent == "My- Book-One" && b.lastPathComponent == "My- Book-One 2")
        #expect(try BookStructure.load(folder: a).scenes[0].chapterTitle == "Chapter 1")
        #expect(throws: BookCreator.Failure.self) { try BookCreator.create(NewBookRequest(title: "   ", parentFolder: parent)) }
        let c = try BookCreator.create(NewBookRequest(title: "..hidden", parentFolder: parent))
        #expect(c.lastPathComponent == "hidden")
        #expect(try JSONParser.parseObject(Data(contentsOf: a.appendingPathComponent("book.json"))).string("author") == nil, "no author: the field is left out")
    }

    @Test("settings: recent books, in order, at most 10; a damaged file is kept aside")
    func settings() throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = AppSettings(directory: dir)
        #expect(s.knownBooks.isEmpty && s.lastOpened == nil)
        for i in 0..<12 { s.noteOpened(folder: URL(fileURLWithPath: "/books/b\(i)"), name: "Book \(i)") }
        #expect(s.knownBooks.count == 10 && s.knownBooks[0].name == "Book 11" && s.lastOpened == "/books/b11")
        s.noteOpened(folder: URL(fileURLWithPath: "/books/b5"), name: "Book 5")
        #expect(s.knownBooks[0].path == "/books/b5" && s.knownBooks.filter { $0.path == "/books/b5" }.count == 1)
        let again = AppSettings(directory: dir)
        #expect(again.knownBooks == s.knownBooks && again.lastOpened == "/books/b5")
        again.forget(path: "/books/b5")
        #expect(again.lastOpened == nil && !again.knownBooks.contains { $0.path == "/books/b5" })
        again.clearLastOpened()
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("settings.json"))
        let bad = AppSettings(directory: dir)
        #expect(bad.damaged && bad.knownBooks.isEmpty && FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json.bad").path))
        // Unknown keys survive.
        try JSONWriter.data(["format": .int(1), "x_other": .object(["a": .int(1)])]).write(to: dir.appendingPathComponent("settings.json"))
        let keep = AppSettings(directory: dir)
        keep.noteOpened(folder: URL(fileURLWithPath: "/b"), name: "B")
        #expect(try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8).contains("x_other"))
    }

    @Test("the local state remembers the scene, the place and the view, and keeps keys it does not know")
    func state() throws {
        let book = try Self.folder()
        defer { try? FileManager.default.removeItem(at: book) }
        #expect(LocalBookState.load(book: book) == LocalBookState())
        LocalBookState(scene: "s1", position: 1432, mode: "book", split: true).save(book: book)
        #expect(LocalBookState.load(book: book) == LocalBookState(scene: "s1", position: 1432, mode: "book", split: true))
        var memory = GraphViewMemory()
        memory.look = "neighbourhood"; memory.kinds = ["character", "scene"]; memory.showUnlinked = false; memory.section = "ch1"; memory.focus = "anna"; memory.depth = 2
        memory.zoom = 0.625; memory.centerX = -120; memory.centerY = 340
        LocalBookState(scene: "s1", mode: "graph", graph: memory).save(book: book)
        #expect(LocalBookState.load(book: book).graph == memory, "the Graph view's settings and place are kept")
        LocalBookState(scene: "s1", mode: "graph").save(book: book)
        #expect(LocalBookState.load(book: book).graph == nil, "and left out when there are none")
        let kept = ["events": ViewMemory(selected: "e7", scroll: 412, filter: "ссор", anchors: ["character:anna"]), "world": ViewMemory(selected: "w1", closed: ["a", "b"]), "research": ViewMemory()]
        LocalBookState(scene: "s1", mode: "events", views: kept).save(book: book)
        #expect(LocalBookState.load(book: book).views == ["events": kept["events"]!, "world": kept["world"]!], "each list view's chosen item, place, filters and open places are kept (an empty one is not)")
        LocalBookState(scene: "s1", mode: "events").save(book: book)
        #expect(LocalBookState.load(book: book).views.isEmpty, "and left out when there are none")
        let oldFile = #"{"format":1,"mode":"events","events":{"selected":"e9","scroll":30}}"#
        try Data(oldFile.utf8).write(to: book.appendingPathComponent(".quilland/state.json"))
        #expect(LocalBookState.load(book: book).views["events"] == ViewMemory(selected: "e9", scroll: 30), "the Events place kept in the earlier form is still read")
        var o = try JSONParser.parseObject(Data(contentsOf: book.appendingPathComponent(".quilland/state.json")))
        o["x_keep"] = .string("yes")
        try JSONWriter.data(o).write(to: book.appendingPathComponent(".quilland/state.json"))
        LocalBookState(scene: "s2", position: 3, mode: "plan").save(book: book)
        let text = try String(contentsOf: book.appendingPathComponent(".quilland/state.json"), encoding: .utf8)
        #expect(text.contains("x_keep") && LocalBookState.load(book: book).scene == "s2")
    }
}
