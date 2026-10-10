import Foundation
import Testing
@testable import QuillandCore

@Suite("The language of the interface")
struct LocalizationTests {
    static func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-lang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static let russian = """
        {"format":1,"code":"ru","name":"Русский","plural_rule":"ru",
         "strings":{"Open Book…":"Открыть книгу…","Delete “{title}”?":"Удалить «{title}»?","Empty":""},
         "plurals":{"{n} scenes":{"one":"{n} сцена","few":"{n} сцены","many":"{n} сцен","other":"{n} сцены"}}}
        """

    @Test("plural rules give the right category: Russian, Polish, Czech, French, Arabic, English")
    func rules() {
        func cats(_ rule: PluralRule, _ numbers: [Int]) -> [String] { numbers.map(rule.category) }
        #expect(cats(.ru, [0, 1, 2, 4, 5, 11, 12, 14, 19, 20, 21, 22, 25, 100, 101, 111, 112]) ==
                ["many", "one", "few", "few", "many", "many", "many", "many", "many", "many", "one", "few", "many", "many", "one", "many", "many"])
        #expect(cats(.pl, [1, 2, 5, 12, 22, 25]) == ["one", "few", "many", "many", "few", "many"])
        #expect(cats(.cs, [1, 3, 5]) == ["one", "few", "other"])
        #expect(cats(.fr, [0, 1, 2]) == ["one", "one", "other"])
        #expect(cats(.ar, [0, 1, 2, 5, 11, 100]) == ["zero", "one", "two", "few", "many", "other"])
        #expect(cats(.en, [0, 1, 2]) == ["other", "one", "other"] && cats(.none, [1, 5]) == ["other", "other"])
    }

    @Test("a text is found by its English words, filled with names, and falls back to English; plurals follow the language's rule")
    func lookup() throws {
        let dir = try Self.dir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(Self.russian.utf8).write(to: dir.appendingPathComponent("ru.json"))
        let l = Localizer()
        l.directories = [dir]
        #expect(l.text("Open Book…") == "Open Book…" && l.use(code: nil) == false)
        #expect(l.use(code: "ru"))
        #expect(l.text("Open Book…") == "Открыть книгу…")
        #expect(l.text("Delete “{title}”?", ["title": "Станция"]) == "Удалить «Станция»?")
        #expect(l.text("Not translated yet") == "Not translated yet", "no translation: English")
        #expect(l.text("Empty") == "Empty", "an empty translation counts as none")
        #expect(l.text("Hello {name}", ["name": "Анна"]) == "Hello Анна")
        #expect([1, 2, 5, 11, 21, 22].map { l.plural("{n} scene", "{n} scenes", $0) } == ["1 сцена", "2 сцены", "5 сцен", "11 сцен", "21 сцена", "22 сцены"])
        #expect(l.plural("{n} thing", "{n} things", 1) == "1 thing" && l.plural("{n} thing", "{n} things", 3) == "3 things", "a plural with no translation uses English")
        #expect(l.plural("{n} scene", "{n} scenes", 1234) == "1\u{00A0}234 сцены" || l.plural("{n} scene", "{n} scenes", 1234).hasSuffix("сцены"))
        #expect(l.use(code: "xx") == false && l.text("Open Book…") == "Open Book…", "an unknown code is English")
    }

    @Test("a language file is checked: what is wrong is said, nothing crashes")
    func loading() throws {
        let dir = try Self.dir()
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ name: String, _ text: String) throws -> URL { let u = dir.appendingPathComponent(name); try Data(text.utf8).write(to: u); return u }
        let good = Language.load(try write("a.json", Self.russian))
        #expect(good.language?.code == "ru" && good.language?.rule == .ru && good.problem == nil)
        #expect(Language.load(try write("b.json", "{ nope")).problem?.contains("not valid JSON") == true)
        #expect(Language.load(try write("c.json", "{\"name\":\"X\"}")).problem?.contains("code") == true)
        #expect(Language.load(try write("d.json", "{\"code\":\"x y\",\"name\":\"X\"}")).problem?.contains("code") == true)
        #expect(Language.load(try write("e.json", "{\"code\":\"uk\"}")).problem?.contains("name") == true)
        #expect(Language.load(dir.appendingPathComponent("missing.json")).problem != nil)
        // An unknown plural rule falls back to English's.
        #expect(Language.load(try write("f.json", "{\"code\":\"uk\",\"name\":\"Українська\",\"plural_rule\":\"klingon\"}")).language?.rule == .en)
    }

    @Test("languages from two folders are listed, the user's file replaces the bundled one with the same code, bad files are left out")
    func available() throws {
        let bundled = try Self.dir(), user = try Self.dir()
        defer { try? FileManager.default.removeItem(at: bundled); try? FileManager.default.removeItem(at: user) }
        try Data(Self.russian.utf8).write(to: bundled.appendingPathComponent("ru.json"))
        try Data("{\"code\":\"ru\",\"name\":\"Русский (мой)\",\"strings\":{\"Open Book…\":\"Книгу открыть…\"}}".utf8).write(to: user.appendingPathComponent("ru.json"))
        try Data("{\"code\":\"uk\",\"name\":\"Українська\",\"plural_rule\":\"ru\"}".utf8).write(to: user.appendingPathComponent("uk.json"))
        try Data("garbage".utf8).write(to: user.appendingPathComponent("bad.json"))
        try Data("{\"strings\":{}}".utf8).write(to: user.appendingPathComponent("template.json"))
        let l = Localizer()
        l.directories = [bundled, user]
        let list = l.available()
        #expect(list.map(\.code) == ["ru", "uk"] && list[0].name == "Русский (мой)" && !list[0].isBundled && !list[1].isBundled)
        #expect(l.use(code: "RU") && l.text("Open Book…") == "Книгу открыть…")
    }

    @Test("the system's language is used when installed; the template says how much of a language is done")
    func systemAndProgress() throws {
        let dir = try Self.dir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(Self.russian.utf8).write(to: dir.appendingPathComponent("ru.json"))
        let l = Localizer()
        l.directories = [dir]
        let code = l.systemCode()
        #expect(code == nil || code == "ru")
        let templateURL = dir.appendingPathComponent("template.json")
        try Data("""
            {"format":1,"strings":{"Open Book…":"","Delete “{title}”?":"","Empty":"","Third":""},"plurals":{"{n} scenes":{},"{n} chapters":{}}}
            """.utf8).write(to: templateURL)
        let template = try #require(Template.load(templateURL))
        #expect(template.total == 6)
        let ru = try #require(l.available().first)
        #expect(ru.translated(of: template) == 3, "two strings and the one plural that has every form")
    }
}
