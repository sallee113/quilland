import Foundation
import Testing
@testable import QuillandCore

@Suite("Proofreading: the typography rules")
struct TypographyTests {
    func fixed(_ text: String, _ language: String = "ru", rules: Set<TypographyFinding.Rule> = Set(TypographyFinding.Rule.allCases)) -> String {
        var s = text as NSString
        for f in Typography.check(text, language: language, rules: rules).sorted(by: { $0.range.location > $1.range.location }) {
            s = s.replacingCharacters(in: f.range, with: f.after) as NSString
        }
        return s as String
    }

    @Test("a hyphen between words becomes a dash with a non-breaking space before it")
    func dash() {
        #expect(fixed("Он пришёл - и ушёл.", rules: [.dash]) == "Он пришёл\u{00A0}— и ушёл.")
        #expect(fixed("Он пришёл\u{00A0}— и ушёл.", rules: [.dash]) == "Он пришёл\u{00A0}— и ушёл.", "already right: nothing to do")
        #expect(fixed("Он пришёл — и ушёл.", rules: [.dash]) == "Он пришёл\u{00A0}— и ушёл.")
        #expect(fixed("кто-то и что-нибудь", rules: [.dash]) == "кто-то и что-нибудь", "a hyphen inside a word stays")
        #expect(fixed("He came - and left.", "en", rules: [.dash]) == "He came\u{2014}and left.")
    }

    @Test("a dash that opens a line of dialogue")
    func dialogue() {
        #expect(fixed("- Привет!\n– Здравствуй.\n—Что?\n— Уже так.", rules: [.dialogue]) == "— Привет!\n— Здравствуй.\n— Что?\n— Уже так.")
        #expect(fixed("- Hello", "en", rules: [.dialogue]) == "- Hello", "only for Russian")
        #expect(fixed("— — —", rules: [.dialogue]) == "— — —", "a row of dashes is left alone")
    }

    @Test("straight quotes become the language's own, opening and closing")
    func quotes() {
        #expect(fixed("Он сказал \"привет\" и (\"ушёл\").", rules: [.quotes]) == "Он сказал «привет» и («ушёл»).")
        #expect(fixed("\"Да\", — ответил он.", rules: [.quotes]) == "«Да», — ответил он.")
        #expect(fixed("He said \"hi\".", "en", rules: [.quotes]) == "He said \u{201C}hi\u{201D}.")
    }

    @Test("three dots, doubled spaces and spaces before punctuation")
    func spaces() {
        #expect(fixed("Ну... ладно", rules: [.ellipsis]) == "Ну… ладно")
        #expect(fixed("Ну.... ладно", rules: [.ellipsis]) == "Ну.... ладно", "four dots are not an ellipsis")
        #expect(fixed("Один  два   три", rules: [.spaces]) == "Один два три")
        #expect(fixed("Привет , мир !", rules: [.spaces]) == "Привет, мир!")
        #expect(fixed("  Отступ в начале\nстроки", rules: [.spaces]) == "  Отступ в начале\nстроки", "a leading indent is not touched")
    }

    @Test("a non-breaking space after a short word, Russian only")
    func nbsp() {
        #expect(fixed("Он жил в доме у реки.", rules: [.nbsp]) == "Он жил в\u{00A0}доме у\u{00A0}реки.")
        #expect(fixed("Вне дома", rules: [.nbsp]) == "Вне дома", "the end of a longer word is not a short word")
        #expect(fixed("He lived in a house.", "en", rules: [.nbsp]) == "He lived in a house.")
    }

    @Test("findings carry their context, and a dismissal is remembered by it, not by the place")
    func dismissals() throws {
        let findings = Typography.check("Первая фраза. Ну... ладно. Потом... ещё.", language: "ru", rules: [.ellipsis])
        #expect(findings.count == 2 && findings[0].contextAfter.hasPrefix(" ладно"))
        var d = ProofreadingDismissals()
        d.dismiss(findings[0])
        let moved = Typography.check("Вставка. Первая фраза. Ну... ладно. Потом... ещё.", language: "ru", rules: [.ellipsis])
        #expect(d.isDismissed(moved[0]) && !d.isDismissed(moved[1]), "the same words around: still dismissed, though the place changed")
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-proof-\(UUID().uuidString)")
        d.save(book: book)
        #expect(ProofreadingDismissals.load(book: book) == d)
    }

    @Test("the non-breaking space rule is off at first; the choice is kept per book")
    func rulesOff() {
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-rules-\(UUID().uuidString)")
        var d = ProofreadingDismissals.load(book: book)
        #expect(!d.rules.contains(.nbsp) && d.rules.contains(.dash))
        d.rulesOff = ["quotes"]
        d.save(book: book)
        let again = ProofreadingDismissals.load(book: book)
        #expect(again.rules.contains(.nbsp) && !again.rules.contains(.quotes))
    }
}
