import Foundation
import Testing
@testable import QuillandCore

/// The list of texts to translate must be the texts the code has, and the Russian file must have every one of them.
@Suite("Languages are complete")
struct LanguageCoverageTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t").replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// The texts the code asks for with L("…") and Lp("…", "…", n).
    static func textsInCode() throws -> (strings: Set<String>, plurals: Set<String>) {
        let skip: Set<String> = ["AppSelfTest.swift", "LabWindowController.swift", "LabBookGenerator.swift", "LabPlanGenerator.swift", "LabSelfTest.swift", "main.swift"]
        let literal = "\"((?:[^\"\\\\\\n]|\\\\.)*)\""
        let single = try NSRegularExpression(pattern: "(?<![A-Za-z_])L\\(\\s*" + literal)
        let plural = try NSRegularExpression(pattern: "(?<![A-Za-z_])Lp\\(\\s*" + literal + "\\s*,\\s*" + literal)
        var strings = Set<String>(), plurals = Set<String>()
        for folder in ["Sources/Quilland", "Sources/QuillandCore"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" && !skip.contains(url.lastPathComponent) {
                let text = try String(contentsOf: url, encoding: .utf8)
                let ns = text as NSString
                for m in plural.matches(in: text, range: NSRange(location: 0, length: ns.length)) { plurals.insert(unescape(ns.substring(with: m.range(at: 2)))) }
                for m in single.matches(in: text, range: NSRange(location: 0, length: ns.length)) { strings.insert(unescape(ns.substring(with: m.range(at: 1)))) }
            }
        }
        return (strings, plurals)
    }

    static func tokens(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: "\\{[a-z]+\\}")
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }.sorted()
    }

    @Test("template.json lists exactly the texts that are in the code (run make-languages.py when this fails)")
    func templateMatchesCode() throws {
        let code = try Self.textsInCode()
        let template = try #require(Template.load(Self.root.appendingPathComponent("Resources/Languages/template.json")))
        #expect(Set(template.strings) == code.strings, "missing from the template: \(code.strings.subtracting(template.strings).sorted()); not in the code any more: \(Set(template.strings).subtracting(code.strings).sorted())")
        #expect(Set(template.plurals) == code.plurals, "plurals: \(code.plurals.symmetricDifference(template.plurals).sorted())")
        #expect(code.strings.count > 400)
    }

    @Test("the Russian file translates every text, keeps every {name}, and has every plural form")
    func russianIsComplete() throws {
        let template = try #require(Template.load(Self.root.appendingPathComponent("Resources/Languages/template.json")))
        let loaded = Language.load(Self.root.appendingPathComponent("Resources/Languages/ru.json"))
        let ru = try #require(loaded.language, "\(loaded.problem ?? "")")
        #expect(ru.code == "ru" && ru.rule == .ru && ru.name == "Русский")
        for key in template.strings {
            let translation = ru.strings[key] ?? ""
            #expect(!translation.isEmpty, "no Russian for: \(key)")
            #expect(Self.tokens(key) == Self.tokens(translation), "the {names} differ in: \(key)")
        }
        for key in template.plurals {
            let forms = ru.plurals[key] ?? [:]
            for category in ru.rule.categories {
                let text = forms[category] ?? ""
                #expect(!text.isEmpty, "no \(category) form for: \(key)")
                #expect(Self.tokens(key) == Self.tokens(text), "the {names} differ in the \(category) form of: \(key)")
            }
        }
        #expect(ru.translated(of: template) == template.total)
        #expect(Set(ru.strings.keys).isSubset(of: Set(template.strings)), "Russian has texts the code does not ask for")
    }

    @Test("with Russian on, a plural reads right for 1, 2, 5, 11, 21, and a context key shows plain English without it")
    func russianPlurals() throws {
        let l = Localizer()
        l.directories = [Self.root.appendingPathComponent("Resources/Languages")]
        #expect(l.use(code: "ru"))
        #expect([1, 2, 5, 11, 21, 22, 25].map { l.plural("{n} scene", "{n} scenes", $0) } == ["1 сцена", "2 сцены", "5 сцен", "11 сцен", "21 сцена", "22 сцены", "25 сцен"])
        #expect(l.plural("{n} character||text", "{n} characters||text", 3) == "3 символа" && l.plural("{n} character", "{n} characters", 3) == "3 персонажа")
        l.use(code: nil)
        #expect(l.plural("{n} character||text", "{n} characters||text", 3) == "3 characters", "English shows only the text before ||")
        #expect(l.text("characters||text") == "characters")
    }

    @Test("a language template for a new language is written with the fields that name it, and an installed file is listed")
    func newLanguage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-newlang-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("my.json")
        try LanguageFiles.writeTemplate(from: Self.root.appendingPathComponent("Resources/Languages/template.json"), to: file, code: "uk", name: "Українська", rule: .ru)
        let loaded = Language.load(file)
        let language = try #require(loaded.language)
        #expect(language.code == "uk" && language.rule == .ru && language.strings.count > 400)
        #expect(language.translated(of: try #require(Template.load(file))) == 0, "nothing is translated yet")
        let userFolder = dir.appendingPathComponent("user")
        let installed = try LanguageFiles.install(file, into: userFolder)
        #expect(installed.code == "uk" && FileManager.default.fileExists(atPath: userFolder.appendingPathComponent("uk.json").path))
        #expect(throws: (any Error).self) { try LanguageFiles.install(dir.appendingPathComponent("missing.json"), into: userFolder) }
        let l = Localizer()
        l.directories = [userFolder]
        #expect(l.available().map(\.code) == ["uk"])
    }
}
