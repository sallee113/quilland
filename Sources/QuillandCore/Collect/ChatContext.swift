import Foundation

/// A piece of the book attached to a chat message: shown as a chip with its size, and given to the model as reference material.
public struct ChatAttachment: Identifiable, Equatable, Sendable {
    public var id = UUID()
    /// What the chip says ("Scene: Платформа").
    public var label: String
    public var text: String
    /// For a general attachment (`scene`, `chapter`, `characters`…): what it is, so that a saved action can attach the same kind to another scene. Nil for one named thing.
    public var mention: String?
    public init(label: String, text: String, mention: String? = nil) { self.label = label; self.text = text; self.mention = mention }
    public var tokens: Int { ContinuePrompt.tokens(text.count) }
}

public struct ChatTurn: Equatable, Sendable {
    public var role: String   // "user" or "assistant"
    public var content: String
    public init(_ role: String, _ content: String) { self.role = role; self.content = content }
}

/// What a message would cost: for the line under the chips ("Context 6,200 / 40,960").
public struct ChatUsage: Equatable, Sendable {
    public var tokens: Int
    public var context: Int
    /// Tokens each attachment takes after cutting, by id.
    public var perAttachment: [UUID: Int]
    /// Some attachment was cut to fit, or the oldest turns were dropped.
    public var truncated: Bool
}

public enum ChatPrompt {
    public static func system(language: String) -> String { AIPrompts.resolve("chat", language: language, builtIn: builtIn) }

    static var builtIn: String {
        """
        You are a thoughtful reading and writing assistant for the author of a novel. You answer questions about the book and help with ideas, using the attached material when there is any.
        Answer in the language of the question. Be concrete and brief. If the attached material does not say something, say so instead of guessing, and keep what you know apart from what you suppose.
        You change nothing in the book: you only answer. Never claim to have saved or edited anything.
        """
    }

    /// The request for a message: the instructions with the attached material, the earlier turns that fit, and the question. The material is cut to fit the context
    /// (each attachment keeps its beginning); the oldest turns are dropped first.
    public static func build(history: [ChatTurn], question: String, attachments: [ChatAttachment], language: String, context: Int) -> (messages: [ChatMessage], usage: ChatUsage) {
        let reserve = 1400
        let availableChars = max(1200, Int(Double(max(2048, context) - reserve) * 2.4))
        let base = system(language: language).count + question.count + 60
        let shareForMaterial = max(0, Int(Double(availableChars - base) * 0.65))
        var truncated = false
        var cut: [(ChatAttachment, String)] = []
        let totalChars = attachments.reduce(0) { $0 + $1.text.count }
        for a in attachments {
            if totalChars <= shareForMaterial { cut.append((a, a.text)); continue }
            truncated = true
            let keep = max(200, shareForMaterial * a.text.count / max(1, totalChars))
            cut.append((a, String(a.text.prefix(keep)) + "…"))
        }
        let materialChars = cut.reduce(0) { $0 + $1.1.count + $1.0.label.count + 8 }
        let historyBudget = max(0, availableChars - base - materialChars)
        var kept: [ChatTurn] = []
        var used = 0
        for turn in history.reversed() {
            guard used + turn.content.count <= historyBudget else { truncated = truncated || kept.count < history.count; break }
            used += turn.content.count
            kept.insert(turn, at: 0)
        }
        var sys = system(language: language)
        if !cut.isEmpty {
            sys += "\n\nAttached material from the book:\n"
            for (a, text) in cut { sys += "\n[\(a.label)]\n\(text)\n" }
        }
        var messages = [ChatMessage("system", sys)]
        for t in kept { messages.append(ChatMessage(t.role, t.content)) }
        messages.append(ChatMessage("user", question))
        let tokens = ContinuePrompt.tokens(messages.reduce(0) { $0 + $1.content.count })
        var per: [UUID: Int] = [:]
        for (a, text) in cut { per[a.id] = ContinuePrompt.tokens(text.count) }
        return (messages, ChatUsage(tokens: tokens, context: context, perAttachment: per, truncated: truncated))
    }

    /// The size of what would be sent, without a question yet (for the chips).
    public static func usage(history: [ChatTurn], attachments: [ChatAttachment], language: String, context: Int) -> ChatUsage {
        build(history: history, question: "", attachments: attachments, language: language, context: context).usage
    }
}

/// The last prompts, for the up arrow: kept on this machine in `.quilland/chat-prompts.json`. The conversation itself is never kept.
public enum ChatPrompts {
    static func url(_ book: URL) -> URL { book.appendingPathComponent(".quilland/chat-prompts.json") }
    public static let limit = 5

    public static func load(book: URL) -> [String] {
        guard let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data) else { return [] }
        return o.strings("prompts") ?? []
    }

    /// Newest last; a prompt said again moves to the end.
    public static func remember(_ prompt: String, book: URL) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let all = Array((load(book: book).filter { $0 != text } + [text]).suffix(limit))
        var o: JSONObject = ["format": .int(1)]
        o["prompts"] = .array(all.map { .string($0) })
        try? FileManager.default.createDirectory(at: url(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: url(book))
    }
}

/// What can be attached with `@`: the current scene or chapter, the cards found in the scene, the whole plan, all synopses, or one named thing.
public enum ChatMentions {
    public enum Item: Equatable, Sendable { case character(String), place(String), event(String), scene(String) }

    public struct Book {
        public var structure: BookStructure
        public var characters: CharacterStore
        public var worlds: WorldStore
        public var events: EventStore
        public var relationships: RelationshipStore
        public var plan: PlanStore?
        public var sceneText: (String) -> String
        public init(structure: BookStructure, characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore, plan: PlanStore?, sceneText: @escaping (String) -> String) {
            self.structure = structure; self.characters = characters; self.worlds = worlds; self.events = events; self.relationships = relationships; self.plan = plan; self.sceneText = sceneText
        }
    }

    static func characterText(_ c: CharacterRecord, _ store: CharacterStore) -> String {
        var s = ""
        if !c.aliases.isEmpty { s += "Also called: " + c.aliases.joined(separator: ", ") + ". " }
        let profile = store.profile(c.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty { s += profile + " " }
        if !c.notes.isEmpty { s += "Notes: " + c.notes.joined(separator: " ") }
        return s
    }

    static func placeText(_ e: PlaceRecord, _ store: WorldStore) -> String {
        var s = store.text(e.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.notes.isEmpty { s += " Notes: " + e.notes.joined(separator: " ") }
        return s
    }

    static func eventText(_ e: EventRecord, _ store: EventStore) -> String {
        var s = e.date.isEmpty ? "" : "When: \(e.date). "
        s += store.text(e.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !e.notes.isEmpty { s += " Notes: " + e.notes.joined(separator: " ") }
        return s
    }

    public static func item(_ item: Item, in book: Book) -> ChatAttachment? {
        switch item {
        case .character(let id):
            guard let c = book.characters.character(id) else { return nil }
            return ChatAttachment(label: "\(L("Character")): \(c.name ?? "")", text: "\(c.name ?? ""). " + characterText(c, book.characters))
        case .place(let id):
            guard let e = book.worlds.entry(id) else { return nil }
            return ChatAttachment(label: "\(L("Place")): \(e.name ?? "")", text: "\(e.name ?? ""). " + placeText(e, book.worlds))
        case .event(let id):
            guard let e = book.events.event(id) else { return nil }
            return ChatAttachment(label: "\(L("Event")): \(e.title ?? "")", text: "\(e.title ?? ""). " + eventText(e, book.events))
        case .scene(let id):
            guard let s = book.structure.scenes.first(where: { $0.id == id }) else { return nil }
            return ChatAttachment(label: "\(L("Scene")): \(s.node.title)", text: book.sceneText(id), mention: "scene")
        }
    }

    public static func scene(_ id: String, in book: Book) -> ChatAttachment? { item(.scene(id), in: book) }

    /// The text of the whole chapter the scene is in.
    public static func chapter(of sceneID: String, in book: Book) -> ChatAttachment? {
        guard let entry = book.structure.scenes.first(where: { $0.id == sceneID }), let chapter = entry.chapterID else { return nil }
        let scenes = book.structure.scenes.filter { $0.chapterID == chapter }
        return ChatAttachment(label: "\(L("Chapter")): \(entry.chapterTitle ?? "")", text: scenes.map { "# \($0.node.title)\n" + book.sceneText($0.id) }.joined(separator: "\n\n"), mention: "chapter")
    }

    private static func found(in sceneID: String, _ book: Book) -> (characters: Set<String>, places: Set<String>) {
        let text = book.sceneText(sceneID)
        return (Set(ParadigmMatcher(entries: book.characters.entries).matches(in: text).map(\.entry)), Set(ParadigmMatcher(entries: book.worlds.nameEntries).matches(in: text).map(\.entry)))
    }

    /// The characters named in the scene or linked to it.
    public static func characters(of sceneID: String, in book: Book) -> ChatAttachment? {
        let named = found(in: sceneID, book).characters
        let list = book.characters.characters.filter { named.contains($0.id ?? "") || SceneLinks.has($0.links, scene: sceneID) }
        guard !list.isEmpty else { return nil }
        return ChatAttachment(label: L("Characters of the scene"), text: list.map { "\($0.name ?? ""): " + characterText($0, book.characters) }.joined(separator: "\n\n"), mention: "characters")
    }

    public static func places(of sceneID: String, in book: Book) -> ChatAttachment? {
        let named = found(in: sceneID, book).places
        let list = book.worlds.entries.filter { named.contains($0.id ?? "") || SceneLinks.has($0.links, scene: sceneID) }
        guard !list.isEmpty else { return nil }
        return ChatAttachment(label: L("Places of the scene"), text: list.map { "\($0.name ?? ""): " + placeText($0, book.worlds) }.joined(separator: "\n\n"), mention: "places")
    }

    public static func events(of sceneID: String, in book: Book) -> ChatAttachment? {
        let list = book.events.events.filter { SceneLinks.has($0.links, scene: sceneID) }
        guard !list.isEmpty else { return nil }
        return ChatAttachment(label: L("Events of the scene"), text: list.map { "\($0.title ?? ""): " + eventText($0, book.events) }.joined(separator: "\n\n"), mention: "events")
    }

    /// The plan: its lines, the events on them and the cards.
    public static func plan(in book: Book) -> ChatAttachment? {
        guard let plan = book.plan, !plan.lines.isEmpty || !plan.cards.isEmpty else { return nil }
        var s = ""
        for line in plan.lines {
            s += "Line “\(line.name ?? "")”" + (line.summary.map { ": \($0)" } ?? "") + "\n"
            for entry in plan.entries.filter({ $0.lane == line.id }).sorted(by: { ($0.start ?? 0) < ($1.start ?? 0) }) { s += "  event: " + (plan.events[entry.event ?? ""] ?? "") + "\n" }
            for card in plan.cards.values.filter({ $0.line == line.id }).sorted(by: { ($0.start ?? 0) < ($1.start ?? 0) }) { s += "  card: \(card.title ?? "") — \(card.text ?? "")\n" }
        }
        let loose = plan.cards.values.filter { $0.line == nil }
        if !loose.isEmpty { s += "Loose cards:\n" + loose.map { "  \($0.title ?? "") — \($0.text ?? "")" }.joined(separator: "\n") }
        return ChatAttachment(label: L("The plan"), text: s, mention: "plan")
    }

    public static func cards(in book: Book) -> ChatAttachment? {
        guard let plan = book.plan, !plan.cards.isEmpty else { return nil }
        let ordered = plan.cards.values.sorted { ($0.title ?? "") < ($1.title ?? "") }
        return ChatAttachment(label: L("Plan cards"), text: ordered.map { "\($0.title ?? "") — \($0.text ?? "")" }.joined(separator: "\n"), mention: "cards")
    }

    /// Every synopsis of the book, in order: a map of the whole story.
    public static func synopses(in book: Book) -> ChatAttachment? {
        let editor = BookEditor(structure: book.structure)
        var lines: [String] = []
        for s in book.structure.scenes {
            guard let text = editor.record(s.id)?.string("synopsis"), !text.isEmpty else { continue }
            lines.append("\([s.partTitle, s.chapterTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › ")) › \(s.node.title): \(text)")
        }
        guard !lines.isEmpty else { return nil }
        return ChatAttachment(label: L("All synopses"), text: lines.joined(separator: "\n"), mention: "synopses")
    }

    /// The general attachment of that name for a scene (or the whole book); nil when there is nothing of it.
    public static func attachment(for mention: String, scene: String?, in book: Book) -> ChatAttachment? {
        switch mention {
        case "scene": return scene.flatMap { self.scene($0, in: book) }
        case "chapter": return scene.flatMap { chapter(of: $0, in: book) }
        case "characters": return scene.flatMap { characters(of: $0, in: book) }
        case "places": return scene.flatMap { places(of: $0, in: book) }
        case "events": return scene.flatMap { events(of: $0, in: book) }
        case "plan": return plan(in: book)
        case "cards": return cards(in: book)
        case "synopses": return synopses(in: book)
        default: return nil
        }
    }
}
