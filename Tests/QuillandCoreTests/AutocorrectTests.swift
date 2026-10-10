import Foundation
import Testing
@testable import QuillandCore

@Suite("Typing corrections")
struct AutocorrectTests {
    let on = AutocorrectSettings()

    /// Types a string character by character the way the editor does, and returns the text.
    func typed(_ input: String, settings: AutocorrectSettings? = nil, language: String = "ru", start: String = "") -> String {
        var text = start
        for ch in input {
            let s = String(ch)
            if let e = Autocorrect.edit(typed: s, before: paragraphBefore(text), settings: settings ?? on, language: language) {
                text.removeLast(e.back)
                text += e.text
            } else { text += s }
        }
        return text
    }

    func paragraphBefore(_ text: String) -> String { String(text.split(separator: "\n", omittingEmptySubsequences: false).last ?? "") }

    @Test("Russian quotes open after a space or at the start and close after a word")
    func russianQuotes() {
        #expect(typed("Он сказал \"привет\" и ушёл.") == "Он сказал «привет» и ушёл.")
        #expect(typed("\"Да\", - ответила она.") == "«Да»,\u{00A0}— ответила она.")
        #expect(typed("(\"в скобках\")") == "(«в скобках»)")
        #expect(typed("а потом \"так\"") == "а потом «так»")
    }

    @Test("English quotes are curly; the style can be forced")
    func englishQuotes() {
        #expect(typed("He said \"hello\".", language: "en") == "He said “hello”.")
        var s = on; s.quoteStyle = "ru"
        #expect(typed("\"x\"", settings: s, language: "en") == "«x»")
        s.quoteStyle = "en"
        #expect(typed("\"x\"", settings: s, language: "ru") == "“x”")
    }

    @Test("a dash with a non-breaking space before it, a dialogue dash at the start, two hyphens")
    func dashes() {
        #expect(typed("слово - слово") == "слово\u{00A0}— слово")
        #expect(typed("- Привет! - сказал он.") == "— Привет!\u{00A0}— сказал он.")
        #expect(typed("a--b") == "a—b")
        #expect(typed("первая\n- вторая") == "первая\n— вторая")
        #expect(typed("кто-то") == "кто-то", "a hyphen inside a word is left alone")
        #expect(typed("a -b") == "a -b", "a hyphen with no space after it is not a dash")
    }

    @Test("the ellipsis stays three dots unless it is turned on")
    func ellipsis() {
        #expect(typed("Ну...") == "Ну...")
        var s = on; s.ellipsis = true
        #expect(typed("Ну...", settings: s) == "Ну…")
    }

    @Test("each correction can be turned off, and so can all of them")
    func switches() {
        var s = on; s.smartQuotes = false
        #expect(typed("\"x\"", settings: s) == "\"x\"")
        s = on; s.dashes = false
        #expect(typed("a - b", settings: s) == "a - b" && typed("a--b", settings: s) == "a--b")
        s = on; s.dialogueDash = false
        #expect(typed("- да", settings: s) == "- да")
        s = on; s.enabled = false
        #expect(typed("\"a\" - b -- c", settings: s) == "\"a\" - b -- c")
    }

    @Test("the settings are kept in autocorrect.json, a damaged file is kept aside, unknown keys stay")
    func file() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-ac-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(AutocorrectSettings.load(directory: dir).settings == AutocorrectSettings() && !AutocorrectSettings.load(directory: dir).damaged)
        var s = AutocorrectSettings()
        s.ellipsis = true; s.quoteStyle = "en"; s.dashes = false
        s.save(directory: dir)
        var raw = try JSONParser.parseObject(Data(contentsOf: dir.appendingPathComponent("autocorrect.json")))
        raw["replacements"] = .array([])
        try AtomicFile.write(JSONWriter.data(raw), to: dir.appendingPathComponent("autocorrect.json"))
        s.dialogueDash = false
        s.save(directory: dir)
        let back = AutocorrectSettings.load(directory: dir)
        #expect(back.settings == s && !back.damaged)
        #expect(try String(contentsOf: dir.appendingPathComponent("autocorrect.json"), encoding: .utf8).contains("\"replacements\""), "a key this version does not know is kept")
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("autocorrect.json"))
        let bad = AutocorrectSettings.load(directory: dir)
        #expect(bad.damaged && bad.settings == AutocorrectSettings() && FileManager.default.fileExists(atPath: dir.appendingPathComponent("autocorrect.json.bad").path))
    }
}
