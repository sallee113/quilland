import Foundation
import Testing
@testable import QuillandCore

@Suite("Grammar by the model", .serialized)
struct GrammarTests {
    func apply(_ hunks: [TextHunk], to text: String) -> String {
        var s = text as NSString
        for h in hunks.sorted(by: { $0.range.location > $1.range.location }) { s = s.replacingCharacters(in: h.range, with: h.after) as NSString }
        return s as String
    }

    @Test("what changed between a text and its corrected version, word by word: a comma, a misspelled word, a doubled word; spacing alone is not a change")
    func diff() {
        let original = "Он сказал что пришол поздно. Мальчик который жил рядом тоже тоже пришёл."
        let corrected = "Он сказал, что пришёл поздно. Мальчик, который жил рядом, тоже пришёл."
        let hunks = TextDiff.hunks(from: original, to: corrected)
        #expect(hunks.map(\.before) == ["сказал", "пришол", "Мальчик", "рядом", " тоже"], "\(hunks.map(\.before))")
        #expect(hunks.map(\.after) == ["сказал,", "пришёл", "Мальчик,", "рядом,", ""], "\(hunks.map(\.after))")
        #expect(apply(hunks, to: original) == corrected, "applying every hunk gives the corrected text")
        #expect(hunks.allSatisfy { (original as NSString).substring(with: $0.range) == $0.before }, "the ranges are the original's own")
        #expect(TextDiff.hunks(from: "Он  пришёл.", to: "Он пришёл.").isEmpty && TextDiff.hunks(from: "Тот же текст.", to: "Тот же текст.").isEmpty)
        #expect(TextDiff.hunks(from: "", to: "").isEmpty)
        let start = TextDiff.hunks(from: "и пошёл дальше", to: "И пошёл дальше")
        #expect(start.count == 1 && start[0].before == "и" && start[0].after == "И")
    }

    @Test("the reply is cleaned of fences and wrappers")
    func extracting() {
        #expect(GrammarPrompt.extract("```\nТекст.\n```") == "Текст.")
        #expect(GrammarPrompt.extract("\"\"\"\nТекст.\n\"\"\"") == "Текст.")
        #expect(GrammarPrompt.extract("  Текст.\n ") == "Текст.")
        #expect(GrammarPrompt.system(language: "ru").contains("Russian rules") && !GrammarPrompt.system(language: "en").contains("Russian rules"))
    }

    static let text = "Он сказал что пришол поздно, и все молчали. " + String(repeating: "Они долго сидели у окна и смотрели на дорогу. ", count: 5)

    @Test("the job reads piece after piece, turns the model's corrections into findings with the scene's own offsets, and leaves out a rewrite")
    func job() async throws {
        let server = try FakeLMServer()
        server.handler = { request, responder in
            let body = String(decoding: request.body, as: UTF8.self)
            let reply: String
            if body.contains("REWRITE") { reply = "Совсем другой текст, который не имеет ничего общего с исходным и гораздо короче." }
            else { reply = Self.text.replacingOccurrences(of: "сказал что пришол", with: "сказал, что пришёл") }
            responder.json(["choices": [["message": ["content": reply]]]])
        }
        let client = LLMTests.client(server)
        let scenes = [GrammarScene(id: "a", title: "A", text: Self.text), GrammarScene(id: "b", title: "B", text: "REWRITE " + Self.text), GrammarScene(id: "c", title: "C", text: "Коротко.")]
        let got = CollectTests.Gathered()
        let box = FindingsBox()
        let summary = await GrammarJob.run(scenes: scenes, language: "ru", client: client, progress: { got.add($0) }, found: { id, list in box.add(id, list) })
        #expect(summary.found == 2 && summary.rewritten == 1 && summary.failedPieces == 0 && !summary.stopped, "\(summary)")
        let findings = box.byScene["a"] ?? []
        #expect(findings.map(\.before) == ["сказал", "пришол"] && findings.map(\.after) == ["сказал,", "пришёл"] && findings.allSatisfy { $0.rule == .grammar })
        #expect(findings.allSatisfy { (Self.text as NSString).substring(with: $0.range) == $0.before } && box.byScene["b"] == nil)
        let body = String(decoding: server.requests.first!.body, as: UTF8.self)
        #expect(body.contains("proofreader") && body.contains("Russian rules") && body.contains("no_think"))
    }
}

final class FindingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _byScene: [String: [TypographyFinding]] = [:]
    func add(_ id: String, _ list: [TypographyFinding]) { lock.withLock { _byScene[id, default: []] += list } }
    var byScene: [String: [TypographyFinding]] { lock.withLock { _byScene } }
}
