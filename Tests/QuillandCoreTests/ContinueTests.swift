import Foundation
import Testing
@testable import QuillandCore

@Suite("Continue Writing")
struct ContinueTests {
    @Test("the request has the text up to the cursor (the oldest part cut), the reference material, the direction, and a summary")
    func prompt() {
        let before = (1...400).map { "Абзац номер \($0) рассказывает о том, как Анна шла по платформе." }.joined(separator: "\n")
        let sources = [ConsistencySource(label: "C1", kind: .character, ref: "a", title: "Анна", text: "Серые глаза."), ConsistencySource(label: "S1", kind: .scene, ref: "s", title: "Платформа", text: "Анна приехала.")]
        let (messages, summary) = ContinuePrompt.messages(before: before, after: "Потом пришёл старик.", language: "ru", synopsis: "Анна ждёт.", note: "", sources: sources,
                                                           planCards: [("Встреча", "Анна встречает тётю.")], direction: "они ссорятся", context: 8192)
        #expect(messages.count == 2 && messages[0].role == "system" && messages[1].role == "user")
        let user = messages[1].content
        #expect(user.contains("[Анна] Серые глаза.") && user.contains("Earlier scenes: “Платформа”") && user.contains("Plan for this part: Встреча") && user.contains("they") == false)
        #expect(user.contains("Direction for the continuation: они ссорятся") && user.contains("Потом пришёл старик.") && user.contains("This scene, in short: Анна ждёт."))
        #expect(user.contains("Абзац номер 400") && !user.contains("Абзац номер 1 "), "the oldest part is cut")
        #expect(summary.cards == 1 && summary.hasPlan && summary.hasDirection && summary.tokens < 8192 && summary.textCharacters < before.count)
        #expect(messages[0].content.contains("Russian") && messages[0].content.contains("ONE paragraph"))
        let small = ContinuePrompt.messages(before: before, after: "", language: "ru", synopsis: "", note: "", sources: [], planCards: [], direction: nil, context: 4096)
        #expect(small.summary.tokens < 4096 - 300, "a small context gets a smaller prompt: \(small.summary.tokens)")
        let none = ContinuePrompt.messages(before: "Начало.", after: "", language: "en", synopsis: "", note: "", sources: [], planCards: [], direction: nil, context: 40960)
        #expect(!none.messages[1].content.contains("Reference material") && !none.messages[1].content.contains("Direction") && none.messages[0].content.contains("English"))
    }

    @Test("the continuation is cleaned as it streams: no leading blank, a paragraph ends at its line break, no emphasis marks, a space when it goes on in the same line")
    func filter() {
        var f = ContinuationFilter(before: "Она вышла.")
        let a = f.feed("\n\nТоро"), b = f.feed("пливо *шла* дальше.\n\n"), c = f.feed("Новый абзац.")
        #expect(a + b + c == " Торопливо шла дальше." && f.isFinished, "one paragraph: the first line break after text ends it")
        var g = ContinuationFilter(before: "Она вышла.\n")
        #expect(g.feed("  Утро.") == "Утро.", "after a newline no space is added")
        var h = ContinuationFilter(before: "")
        #expect(h.feed("Начало") == "Начало")
        var split = ContinuationFilter(before: "Конец,")
        #expect(split.feed("") + split.feed(" и дальше") == " и дальше", "a space of its own is not doubled")
    }
}
