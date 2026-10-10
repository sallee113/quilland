import Foundation
import Testing
@testable import QuillandCore

@Suite("The AI prompts the author may change", .serialized)
struct AIPromptsTests {
    init() { AIPrompts.use(AIPromptSettings()) }

    @Test("every prompt has a built-in text with the language's place marked, and the actions use the author's wording when there is one")
    func overrides() {
        for e in AIPrompts.entries { #expect(!AIPrompts.template(for: e.key).isEmpty, "no text for \(e.key)") }
        #expect(AIPrompts.template(for: "continue").contains("{language}") && AIPrompts.template(for: "synopsis.scene").contains("{language}") && AIPrompts.template(for: "collect").contains("{language}"))
        #expect(ContinuePrompt.system(language: "ru").contains("Russian"), "the built-in text names the book's language")
        var s = AIPromptSettings()
        s.prompts["continue"] = "Пиши в духе автора. Язык: {language}."
        s.prompts["chat"] = "   "
        AIPrompts.use(s)
        #expect(ContinuePrompt.system(language: "ru") == "Пиши в духе автора. Язык: Russian.", "the author's text, with the language put in")
        #expect(ChatPrompt.system(language: "ru").contains("thoughtful reading"), "an empty one means the built-in text")
        s.prompts["grammar.ru"] = "Исправь ошибки."; s.prompts["synopsis.chapter"] = "Кратко о главе."; s.prompts["collect"] = "Ищи персонажей."; s.prompts["consistency_judge"] = "Судья."
        AIPrompts.use(s)
        #expect(GrammarPrompt.system(language: "ru") == "Исправь ошибки." && GrammarPrompt.system(language: "en").contains("careful proofreader"), "grammar has one for Russian books and one for the others")
        #expect(SynopsisPrompt.system(kind: .chapter, language: "ru") == "Кратко о главе." && SynopsisPrompt.system(kind: .scene, language: "ru").contains("Two to four sentences"))
        #expect(CollectPrompt.system(kinds: [.characters], language: "ru").hasPrefix("Ищи персонажей.") && CollectPrompt.system(kinds: [.characters], language: "ru").contains("\"characters\""), "what to look for is still added after")
        #expect(ConsistencyJudge.system == "Судья.")
        AIPrompts.use(AIPromptSettings())
        #expect(ContinuePrompt.system(language: "en").contains("English") && ConsistencyJudge.system.contains("CONTRADICT"))
    }

    @Test("temperatures: the author's, else the action's own")
    func temperatures() {
        #expect(AIPrompts.temperature("continue", default: 0.8) == 0.8)
        var s = AIPromptSettings()
        s.temperatures["continue"] = 1.1
        AIPrompts.use(s)
        #expect(AIPrompts.temperature("continue", default: 0.8) == 1.1 && AIPrompts.temperature("chat", default: 0.7) == 0.7)
        AIPrompts.use(AIPromptSettings())
    }

    @Test("prompts.json keeps only what was changed, and what it does not know")
    func file() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-prompts-\(UUID().uuidString)")
        #expect(AIPromptSettings.load(directory: dir) == AIPromptSettings())
        var s = AIPromptSettings()
        s.prompts = ["continue": "Свой текст.", "chat": "  "]
        s.temperatures = ["continue": 1.1, "collect": 0.25]
        try s.save(directory: dir)
        let again = AIPromptSettings.load(directory: dir)
        #expect(again.prompts == ["continue": "Свой текст."] && again.temperatures == ["continue": 1.1, "collect": 0.25], "an empty prompt is not kept")
        // A key this version does not know stays in the file.
        var raw = try JSONParser.parseObject(Data(contentsOf: dir.appendingPathComponent("prompts.json")))
        raw["x_future"] = .string("keep")
        try AtomicFile.write(JSONWriter.data(raw), to: dir.appendingPathComponent("prompts.json"))
        try again.save(directory: dir)
        #expect(try JSONParser.parseObject(Data(contentsOf: dir.appendingPathComponent("prompts.json"))).string("x_future") == "keep")
        // A temperature out of range is ignored when read.
        raw["temperatures"] = .object(["continue": .string("7"), "chat": .string("0.5")])
        try AtomicFile.write(JSONWriter.data(raw), to: dir.appendingPathComponent("prompts.json"))
        #expect(AIPromptSettings.load(directory: dir).temperatures == ["chat": 0.5])
    }
}

@Suite("Saved AI actions")
struct AIActionsTests {
    @Test("actions are kept in actions.json: a name, the prompt and what to attach; a damaged entry is skipped")
    func file() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-actions-\(UUID().uuidString)")
        #expect(AIActions.load(directory: dir).isEmpty)
        let a = AIAction(name: "Что не так в сцене", prompt: "Найди слабые места в этой сцене.", attach: ["scene", "characters"])
        let b = AIAction(name: "Кратко о плане", prompt: "Перескажи план.", attach: [])
        try AIActions.save([a, b], directory: dir)
        #expect(AIActions.load(directory: dir) == [a, b])
        var raw = try JSONParser.parseObject(Data(contentsOf: dir.appendingPathComponent("actions.json")))
        raw["actions"] = .array((raw.objects("actions") ?? []).map { .object($0) } + [.object(["id": .string("x"), "name": .string("")])])
        try AtomicFile.write(JSONWriter.data(raw), to: dir.appendingPathComponent("actions.json"))
        #expect(AIActions.load(directory: dir) == [a, b], "an entry without a name or a prompt is skipped")
    }

    @Test("a general attachment can be made again for another scene by its name")
    func mentions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-act-\(UUID().uuidString)")
        try DemoBook.write(into: folder, scenes: 12, paragraphs: 3)
        let structure = try BookStructure.load(folder: folder)
        let book = ChatMentions.Book(structure: structure, characters: CharacterStore(book: folder), worlds: WorldStore(book: folder), events: EventStore(book: folder), relationships: RelationshipStore(book: folder),
                                     plan: try PlanStore(folder: folder), sceneText: { id in structure.scenes.first { $0.id == id }.flatMap { try? String(contentsOf: structure.markdownURL(for: $0.node), encoding: .utf8) } ?? "" })
        let scene = structure.scenes[2].id
        for key in ["scene", "chapter", "plan", "cards", "synopses"] {
            let a = ChatMentions.attachment(for: key, scene: scene, in: book)
            #expect(a?.mention == key, "\(key)")
        }
        #expect(ChatMentions.attachment(for: "nonsense", scene: scene, in: book) == nil && ChatMentions.attachment(for: "scene", scene: nil, in: book) == nil)
        #expect(ChatMentions.item(.character(book.characters.characters[0].id!), in: book)?.mention == nil, "one named thing is not a general attachment")
    }
}
