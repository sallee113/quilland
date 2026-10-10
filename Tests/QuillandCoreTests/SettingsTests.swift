import Foundation
import Testing
@testable import QuillandCore

@Suite("Settings of the person and of the book")
struct SettingsTests {
    static func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("preferences have the design's defaults, are kept in settings.json beside the library, and survive a restart")
    func preferences() throws {
        let dir = try Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = AppSettings(directory: dir)
        let d = settings.preferences
        #expect(d == Preferences() && d.defaultMode == "panels" && d.recentLimit == 10 && d.snapshotMinutes == 15 && d.followDelay == 1.5 && d.reopenLastBook && d.autoSnapshots)
        var p = d
        p.defaultMode = "book"; p.recentLimit = 5; p.fontName = "Palatino"; p.fontSize = 19; p.lineSpacing = 1.45; p.readingWidth = 700
        p.appearance = "dark"; p.panelTabs = ["section"]; p.followDelay = 2.5; p.snapshotMinutes = 30; p.autoSnapshots = false; p.newBookFolder = "/tmp/books"
        settings.preferences = p
        settings.noteOpened(folder: URL(fileURLWithPath: "/tmp/B"), name: "B")   // the library is in the same file and is not disturbed
        let again = AppSettings(directory: dir)
        #expect(again.preferences == p && again.knownBooks.map(\.name) == ["B"] && again.lastOpened == "/tmp/B")
    }

    @Test("a hand-edited file cannot hold nonsense: values are brought into range, unknown keys stay")
    func clamping() throws {
        let dir = try Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let raw: JSONObject = ["format": .int(1), "future": .string("kept"), "preferences": .object([
            "recent_limit": .int(5000), "snapshot_minutes": .int(0), "font_size": .string("900"), "default_mode": .string("nonsense"),
            "appearance": .string("purple"), "panel_tabs": .array([.string("section")]),
        ])]
        try AtomicFile.write(JSONWriter.data(raw), to: dir.appendingPathComponent("settings.json"))
        let settings = AppSettings(directory: dir)
        let p = settings.preferences
        #expect(p.recentLimit == 30 && p.snapshotMinutes == 1 && p.fontSize == 36 && p.defaultMode == "panels" && p.appearance == "system")
        settings.preferences = p
        #expect(try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8).contains("\"future\""))
    }

    @Test("the recent list keeps as many books as the setting says")
    func recentCap() throws {
        let dir = try Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let settings = AppSettings(directory: dir)
        settings.recentCap = 3
        for i in 1...5 { settings.noteOpened(folder: URL(fileURLWithPath: "/tmp/book\(i)"), name: "B\(i)") }
        #expect(settings.knownBooks.map(\.name) == ["B5", "B4", "B3"])
    }

    @Test("book settings are read from and written to book.json, keeping what it has besides")
    func bookSettings() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", author: "А. Автор", language: "ru", parentFolder: parent))
        var s = BookSettings.load(book: book)
        #expect(s.title == "Дом" && s.author == "А. Автор" && s.language == "ru" && s.targetCharacters == nil && s.copyright == "")
        s.title = "Дом на Сосновой"; s.copyright = "© 2026"; s.language = "en"; s.targetCharacters = 400_000
        try s.save(book: book)
        #expect(BookSettings.load(book: book) == s)
        let info = try JSONParser.parseObject(Data(contentsOf: book.appendingPathComponent("book.json")))
        #expect(info.string("id") != nil && info.int("format") == 1, "the book's id and format are untouched")
        s.author = ""; s.targetCharacters = nil
        try s.save(book: book)
        let after = try JSONParser.parseObject(Data(contentsOf: book.appendingPathComponent("book.json")))
        #expect(after.string("author") == nil && after.int("target_characters") == nil, "an empty optional field is left out")
        // A cover is copied into assets.
        let image = parent.appendingPathComponent("my cover.PNG")
        try Data([0x89, 0x50]).write(to: image)
        let name = try BookSettings.addCover(from: image, to: book)
        #expect(name == "cover.png" && FileManager.default.fileExists(atPath: book.appendingPathComponent("assets/cover.png").path))
        #expect(try BookSettings.addCover(from: image, to: book) == "cover-2.png")
    }

    @Test("the dictionary keeps lowercase, sorted, unique words without spaces")
    func dictionary() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "B", parentFolder: parent))
        #expect(BookDictionary.load(book: book).isEmpty)
        try BookDictionary.save(["Аврора", "кемпинг", "АВРОРА", " Флора ", "two words", ""], book: book)
        #expect(BookDictionary.load(book: book) == ["аврора", "кемпинг", "флора"])
        let raw = try JSONParser.parseObject(Data(contentsOf: book.appendingPathComponent("dictionary.json")))
        #expect(raw.strings("words") == ["аврора", "кемпинг", "флора"])
    }
}
