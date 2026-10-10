import Foundation
import Testing
@testable import QuillandCore

@Suite("Write Synopsis")
struct SynopsisTests {
    @Test("each level has its own instructions, in the book's language, and a section's input lists its children in order")
    func prompts() {
        let scene = SynopsisPrompt.system(kind: .scene, language: "ru"), chapter = SynopsisPrompt.system(kind: .chapter, language: "en"), part = SynopsisPrompt.system(kind: .part, language: "ru")
        #expect(scene.contains("Two to four sentences") && scene.contains("Russian") && chapter.contains("synopses of its scenes") && chapter.contains("English") && part.contains("synopses of its chapters"))
        let input = SynopsisPrompt.userForSection(kind: .chapter, title: "Станция", children: [("Платформа", "Анна приезжает."), ("Письмо", "")])
        #expect(input.contains("1. “Платформа”: Анна приезжает.") && input.contains("2. “Письмо”: (no synopsis)") && input.hasPrefix("Chapter “Станция”"))
        #expect(SynopsisPrompt.userForSection(kind: .part, title: "Дорога", children: [("Глава 1", "x")]).hasPrefix("Part “Дорога”. Chapters"))
        #expect(SynopsisPrompt.userForScene(title: "Платформа", text: "Текст.").contains("Текст."))
    }
}
