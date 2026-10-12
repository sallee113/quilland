import Foundation
import Testing
@testable import QuillandCore

@Suite("Import speed")
struct ImportSpeedTests {
    @Test("a long Markdown book is analysed and planned quickly")
    func longBook() {
        var text = "# Моя книга\n\n"
        for c in 1...40 {
            text += "## Глава \(c)\n\n"
            for s in 1...12 {
                if s > 1 { text += "* * *\n\n" }
                for p in 1...12 { text += "Это абзац номер \(p) сцены \(s) главы \(c). Он длинный, как и положено абзацу, в нём много слов, запятых и тире — вот так. Анна сказала: «Хорошо». И пошла дальше по дороге, которая не кончалась.\n\n" }
            }
        }
        let start = Date()
        let analysis = TextImporter.analyze(text, source: .markdown, joinWrappedLines: false)
        let analysed = Date().timeIntervalSince(start)
        let plan = TextImporter.plan(text, source: .markdown, options: ImportOptions())
        let planned = Date().timeIntervalSince(start) - analysed
        print("IMPORT-SPEED chars=\(text.count) analyse=\(analysed) plan=\(planned) chapters=\(plan.chapterCount) scenes=\(plan.sceneCount) kinds=\(analysis.kinds.count)")
        #expect(analysed < 4 && planned < 4, "analyse \(analysed) s, plan \(planned) s")
    }
}
