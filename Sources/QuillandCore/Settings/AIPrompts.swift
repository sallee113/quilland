import Foundation

/// The author's own wording of the instructions the AI actions send, and their temperatures: kept in `prompts.json` in the settings folder
/// (quilland-settings.md). A key that is absent means the built-in text. In a prompt, `{language}` stands for the name of the book's language.
public struct AIPromptSettings: Equatable, Sendable {
    public var prompts: [String: String] = [:]
    public var temperatures: [String: Double] = [:]
    public init() {}

    static func url(_ directory: URL) -> URL { directory.appendingPathComponent("prompts.json") }

    public static func load(directory: URL) -> AIPromptSettings {
        var s = AIPromptSettings()
        guard let data = try? Data(contentsOf: url(directory)), let o = try? JSONParser.parseObject(data) else { return s }
        s.prompts = (o.stringMap("prompts") ?? [:]).filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // Real numbers are kept as text in the file (the format's rule for numbers).
        for (k, v) in o.stringMap("temperatures") ?? [:] { if let d = Double(v), (0...2).contains(d) { s.temperatures[k] = d } }
        return s
    }

    public func save(directory: URL) throws {
        var o: JSONObject = (try? JSONParser.parseObject(Data(contentsOf: Self.url(directory)))) ?? [:]
        o["format"] = .int(1)
        o.setStringMap("prompts", prompts)
        o.setStringMap("temperatures", temperatures.mapValues { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.2f", $0) })
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(o), to: Self.url(directory))
    }
}

public enum AIPrompts {
    public struct Entry: Sendable {
        public var key: String
        public var title: String
        /// What the author should know when editing it.
        public var note: String
        public var temperature: Double?
    }

    /// The prompts the author may change, in the order of the Settings window.
    public static var entries: [Entry] {
        [
            Entry(key: "collect", title: L("Collect from the Book"), note: L("The instructions, the same for both readings of a passage (what is there, then what happens). What to look for is added after the passage by the app, for the kinds that were chosen."), temperature: 0.2),
            Entry(key: "consistency", title: L("Check Consistency"), note: L("Looks for contradictions between a passage and one source at a time."), temperature: 0.1),
            Entry(key: "consistency_judge", title: L("Check Consistency: the second look"), note: L("Decides whether a suspected contradiction is real. Must answer with the JSON shown."), temperature: nil),
            Entry(key: "continue", title: L("Continue Writing"), note: L("Writes the next paragraph after the cursor."), temperature: 0.8),
            Entry(key: "synopsis.scene", title: L("Synopsis of a scene"), note: L("Written from the scene's text."), temperature: 0.4),
            Entry(key: "synopsis.chapter", title: L("Synopsis of a chapter"), note: L("Written from the synopses of its scenes."), temperature: nil),
            Entry(key: "synopsis.part", title: L("Synopsis of a part"), note: L("Written from the synopses of its chapters."), temperature: nil),
            Entry(key: "chat", title: L("Chat"), note: L("The standing instructions of every conversation; the attached material is added after them."), temperature: 0.7),
            Entry(key: "grammar.ru", title: L("Grammar, Russian books"), note: L("The model returns the corrected passage; the app finds what changed."), temperature: 0.1),
            Entry(key: "grammar.en", title: L("Grammar, other languages"), note: L("The model returns the corrected passage; the app finds what changed."), temperature: nil),
        ]
    }

    /// The built-in wording of a prompt, with `{language}` where the language's name goes: what the Settings window shows when nothing was changed.
    public static func template(for key: String) -> String {
        let name = "{language}"
        switch key {
        case "collect": return CollectPrompt.intro(name)
        case "consistency": return ConsistencyPrompt.builtIn(name)
        case "consistency_judge": return ConsistencyJudge.builtInSystem
        case "continue": return ContinuePrompt.builtIn(name)
        case "synopsis.scene": return SynopsisPrompt.builtIn(kind: .scene, name: name)
        case "synopsis.chapter": return SynopsisPrompt.builtIn(kind: .chapter, name: name)
        case "synopsis.part": return SynopsisPrompt.builtIn(kind: .part, name: name)
        case "chat": return ChatPrompt.builtIn
        case "grammar.ru": return GrammarPrompt.builtIn(russian: true)
        case "grammar.en": return GrammarPrompt.builtIn(russian: false)
        default: return ""
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var settings = AIPromptSettings()

    public static var current: AIPromptSettings { lock.withLock { settings } }
    public static func use(_ new: AIPromptSettings) { lock.withLock { settings = new } }

    /// The author's wording when there is one (with the language's name put in), else the built-in text.
    static func resolve(_ key: String, language: String, builtIn: @autoclosure () -> String) -> String {
        if let own = current.prompts[key], !own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return own.replacingOccurrences(of: "{language}", with: CollectPrompt.languageName(language) ?? "the language of the text")
        }
        return builtIn()
    }

    public static func temperature(_ key: String, default value: Double) -> Double { current.temperatures[key] ?? value }
}
