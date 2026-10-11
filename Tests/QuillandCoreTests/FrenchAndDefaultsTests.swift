import Foundation
import Testing
@testable import QuillandCore

@Suite("French, and English as the default")
struct FrenchAndDefaultsTests {
    static let languages = LanguageCoverageTests.root.appendingPathComponent("Resources/Languages")

    @Test("the French file translates every text, keeps every {name}, and has both plural forms")
    func frenchIsComplete() throws {
        let template = try #require(Template.load(Self.languages.appendingPathComponent("template.json")))
        let loaded = Language.load(Self.languages.appendingPathComponent("fr.json"))
        let fr = try #require(loaded.language, "\(loaded.problem ?? "")")
        #expect(fr.code == "fr" && fr.rule == .fr && fr.name == "Français")
        for key in template.strings {
            let translation = fr.strings[key] ?? ""
            #expect(!translation.isEmpty, "no French for: \(key)")
            #expect(LanguageCoverageTests.tokens(key) == LanguageCoverageTests.tokens(translation), "the {names} differ in: \(key)")
        }
        for key in template.plurals {
            let forms = fr.plurals[key] ?? [:]
            for category in fr.rule.categories {
                let text = forms[category] ?? ""
                #expect(!text.isEmpty, "no \(category) form for: \(key)")
                let wanted = LanguageCoverageTests.tokens(key), got = LanguageCoverageTests.tokens(text)
                // The singular may leave the number out ("Chaque minute"), as English does.
                #expect(wanted == got || (category == "one" && got.isEmpty && wanted == ["{n}"]), "the {names} differ in the \(category) form of: \(key)")
            }
        }
        #expect(fr.translated(of: template) == template.total)
        #expect(Set(fr.strings.keys).isSubset(of: Set(template.strings)), "French has texts the code does not ask for")
    }

    @Test("with French on, 0 and 1 are singular and 2 or more plural, and the spaces before : ; ? ! and inside « » do not break")
    func frenchPlurals() throws {
        let l = Localizer()
        l.directories = [Self.languages]
        #expect(l.use(code: "fr"))
        #expect([0, 1, 2, 5].map { l.plural("{n} scene", "{n} scenes", $0) } == ["0 scène", "1 scène", "2 scènes", "5 scènes"])
        #expect(l.text("Recover “{title}”?", ["title": "Chapitre"]) == "Récupérer «\u{00A0}Chapitre\u{00A0}»\u{00A0}?")
        l.use(code: nil)
    }

    @Test("English is the default: the interface, a new book, a book without a language")
    func englishIsDefault() throws {
        #expect(Preferences().interfaceLanguage == "en")
        #expect(BookSettings().language == "en")
        #expect(NewBookRequest(title: "T", parentFolder: FileManager.default.temporaryDirectory).language == "en")
        #expect(TextImporter.self != nil && ImportOptions().language == "en")
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = try BookCreator.create(NewBookRequest(title: "Plain", parentFolder: parent))
        #expect(BookSettings.load(book: folder).language == "en")
        let french = try BookCreator.create(NewBookRequest(title: "Livre", language: "fr", parentFolder: parent))
        #expect(BookSettings.load(book: french).language == "fr")
        #expect(BookWords.contents("fr") == "Table des matières" && BookWords.contents("xx") == "Contents" && BookWords.contents("ru") == "Содержание")
        #expect(Autocorrect.quotes(style: "auto", language: "fr") == ("«", "»") && Autocorrect.quotes(style: "auto", language: "en") == ("“", "”"))
    }
}
