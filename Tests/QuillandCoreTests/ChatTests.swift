import Foundation
import Testing
@testable import QuillandCore

@Suite("The Chat")
struct ChatTests {
    @Test("the request has the instructions with the attached material, the earlier turns that fit, and the question; a small context cuts the material, then the history")
    func building() {
        let scene = ChatAttachment(label: "Scene: Платформа", text: "Анна стояла на платформе. " + String(repeating: "Слова слова. ", count: 20))
        let card = ChatAttachment(label: "Character: Анна", text: "Серые глаза.")
        let history = [ChatTurn("user", "Кто такая Анна?"), ChatTurn("assistant", "Героиня книги.")]
        let (messages, usage) = ChatPrompt.build(history: history, question: "А что с её глазами?", attachments: [scene, card], language: "ru", context: 40960)
        #expect(messages.map(\.role) == ["system", "user", "assistant", "user"] && messages.last?.content == "А что с её глазами?")
        #expect(messages[0].content.contains("[Scene: Платформа]") && messages[0].content.contains("Серые глаза.") && messages[0].content.contains("You change nothing"))
        #expect(!usage.truncated && usage.context == 40960 && usage.perAttachment[scene.id]! > usage.perAttachment[card.id]! && usage.tokens < 1000)
        let huge = ChatAttachment(label: "Chapter: Длинная", text: String(repeating: "Очень длинный текст главы. ", count: 3000))
        let small = ChatPrompt.build(history: history, question: "Кратко?", attachments: [huge, card], language: "ru", context: 4096)
        #expect(small.usage.truncated && small.usage.tokens < 4096, "\(small.usage)")
        #expect(small.messages[0].content.contains("…") && small.messages[0].content.contains("Серые глаза"), "each attachment keeps its beginning")
        let longHistory = (1...200).flatMap { [ChatTurn("user", "Вопрос номер \($0) " + String(repeating: "слово ", count: 40)), ChatTurn("assistant", "Ответ номер \($0) " + String(repeating: "слово ", count: 40))] }
        let trimmed = ChatPrompt.build(history: longHistory, question: "Последний?", attachments: [], language: "en", context: 8192)
        #expect(trimmed.messages.count < longHistory.count && trimmed.messages.dropLast().last?.content.contains("Ответ номер 200") == true && trimmed.usage.truncated && trimmed.usage.tokens < 8192)
        #expect(ChatPrompt.usage(history: [], attachments: [card], language: "ru", context: 8192).tokens > 0)
    }

    @Test("the last five prompts are kept on this machine, newest last, a repeated one moves to the end")
    func prompts() {
        let book = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-chat-\(UUID().uuidString)")
        for i in 1...7 { ChatPrompts.remember("вопрос \(i)", book: book) }
        #expect(ChatPrompts.load(book: book) == ["вопрос 3", "вопрос 4", "вопрос 5", "вопрос 6", "вопрос 7"])
        ChatPrompts.remember("  вопрос 4 ", book: book); ChatPrompts.remember("   ", book: book)
        #expect(ChatPrompts.load(book: book) == ["вопрос 3", "вопрос 5", "вопрос 6", "вопрос 7", "вопрос 4"])
    }

    @Test("what @ can attach: the scene, the chapter, the cards found in the scene, the plan, the synopses, and a named thing")
    func mentions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-mention-\(UUID().uuidString)")
        try DemoBook.write(into: folder, scenes: 12, paragraphs: 4)
        let structure = try BookStructure.load(folder: folder)
        let book = ChatMentions.Book(structure: structure, characters: CharacterStore(book: folder), worlds: WorldStore(book: folder), events: EventStore(book: folder), relationships: RelationshipStore(book: folder),
                                     plan: try PlanStore(folder: folder), sceneText: { id in structure.scenes.first { $0.id == id }.flatMap { try? String(contentsOf: structure.markdownURL(for: $0.node), encoding: .utf8) } ?? "" })
        let scene = structure.scenes[4].id
        #expect(ChatMentions.scene(scene, in: book)?.label.hasPrefix("Scene:") == true && ChatMentions.scene(scene, in: book)?.text.isEmpty == false)
        let chapter = ChatMentions.chapter(of: scene, in: book)
        #expect(chapter != nil && chapter!.text.count > ChatMentions.scene(scene, in: book)!.text.count, "a chapter is longer than one of its scenes")
        #expect(ChatMentions.plan(in: book)?.text.contains("Анна и дом") == true && ChatMentions.cards(in: book)?.text.contains("Найти письмо") == true)
        #expect(ChatMentions.synopses(in: book)?.text.contains("Что происходит в сцене") == true)
        let anna = book.characters.characters.first { $0.name == "Анна" }!
        #expect(ChatMentions.item(.character(anna.id!), in: book)?.text.contains("Анна") == true && ChatMentions.item(.character("nope"), in: book) == nil)
        let place = book.worlds.entries.first!
        #expect(ChatMentions.item(.place(place.id!), in: book)?.label.hasPrefix("Place:") == true)
        #expect(ChatMentions.item(.event(book.events.events[0].id!), in: book) != nil)
        // The cards of a scene are the ones named in it or linked to it.
        let withText = structure.scenes.first { s in !(ChatMentions.characters(of: s.id, in: book)?.text ?? "").isEmpty }
        #expect(withText != nil)
    }
}
