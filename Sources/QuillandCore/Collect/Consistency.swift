import Foundation

/// A piece of the book's reference material that the model checks a passage against: a character's card, a place, an event, a relationship, or what an
/// earlier scene says. Each has a label (C1, P2, E1, R1, S3) that the model quotes, so that a finding can be traced back.
public struct ConsistencySource: Equatable, Sendable {
    public enum Kind: String, Sendable { case character, place, event, relationship, scene }
    public var label: String
    public var kind: Kind
    /// The id of the card or the scene.
    public var ref: String
    public var title: String
    public var text: String
    public init(label: String, kind: Kind, ref: String, title: String, text: String) { self.label = label; self.kind = kind; self.ref = ref; self.title = title; self.text = text }
}

/// A contradiction between a passage and a source. A finding says what conflicts; it never changes anything.
public struct ConsistencyFinding: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var scene: String
    public var problem: String
    /// The words of the passage that conflict, as the text has them, and where they are in the scene (UTF-16 units).
    public var quote: String
    public var range: NSRange
    public var source: ConsistencySource
    /// The words of the source that conflict, as the source has them.
    public var sourceQuote: String
    public init(scene: String, problem: String, quote: String, range: NSRange, source: ConsistencySource, sourceQuote: String) {
        self.scene = scene; self.problem = problem; self.quote = quote; self.range = range; self.source = source; self.sourceQuote = sourceQuote
    }

    /// What a dismissal is remembered by: the problem and the passage's words, not the place.
    public var key: String { "consistency|" + Names.normalize(quote) + "|" + source.label.prefix(1) + "|" + Names.normalize(problem).prefix(60) }
}

public enum ConsistencySources {
    /// The sources worth showing the model for one passage, most relevant first, cut to `budget` characters:
    /// the cards of the characters and places named in it or linked to the scene, the events of the scene, the relationships between the characters in it,
    /// and what the scenes before it say (their synopses).
    public static func gather(sceneID: String, passage: String, characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore,
                              structure: BookStructure, budget: Int) -> [ConsistencySource] {
        var out: [ConsistencySource] = []
        var used = 0
        func add(_ kind: ConsistencySource.Kind, _ ref: String, _ title: String, _ text: String, prefix: String) {
            let clipped = text.count > 900 ? String(text.prefix(900)) + "…" : text
            guard !clipped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, used + clipped.count + title.count < budget else { return }
            used += clipped.count + title.count + 12
            out.append(ConsistencySource(label: prefix + String(out.filter { $0.kind == kind }.count + 1), kind: kind, ref: ref, title: title, text: clipped))
        }
        let namedCharacters = Set(ParadigmMatcher(entries: characters.entries).matches(in: passage).map(\.entry))
        let namedPlaces = Set(ParadigmMatcher(entries: worlds.nameEntries).matches(in: passage).map(\.entry))
        let linkedEvents = events.events.filter { $0.links.keys.contains(sceneID) }

        for c in characters.characters {
            guard let id = c.id, namedCharacters.contains(id) || c.links.keys.contains(sceneID) else { continue }
            var text = ""
            if !c.aliases.isEmpty { text += "Also called: " + c.aliases.joined(separator: ", ") + ". " }
            let profile = characters.profile(id).trimmingCharacters(in: .whitespacesAndNewlines)
            if !profile.isEmpty { text += profile + " " }
            if !c.notes.isEmpty { text += "Notes: " + c.notes.joined(separator: " ") }
            add(.character, id, c.name ?? "", text, prefix: "C")
        }
        for e in worlds.entries {
            guard let id = e.id, namedPlaces.contains(id) || e.links.keys.contains(sceneID) else { continue }
            var text = worlds.text(id).trimmingCharacters(in: .whitespacesAndNewlines)
            if !e.notes.isEmpty { text += " Notes: " + e.notes.joined(separator: " ") }
            add(.place, id, e.name ?? "", text, prefix: "P")
        }
        for ev in linkedEvents {
            guard let id = ev.id else { continue }
            var text = ""
            if !ev.date.isEmpty { text += "When: " + ev.date + ". " }
            let body = events.text(id).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { text += body + " " }
            if !ev.notes.isEmpty { text += "Notes: " + ev.notes.joined(separator: " ") }
            if let line = ev.links[sceneID], !line.isEmpty { text += " Here: " + line }
            add(.event, id, ev.title ?? "", text, prefix: "E")
        }
        for r in relationships.relationships where r.characters.filter(namedCharacters.contains).count >= 2 {
            guard let id = r.id else { continue }
            let names = r.characters.compactMap { characters.character($0)?.name }.joined(separator: ", ")
            add(.relationship, id, "\(names): \(r.kind ?? "")", r.notes.joined(separator: " ") + " " + relationships.text(id), prefix: "R")
        }
        // What the scenes before this one say, the nearest first.
        let editor = BookEditor(structure: structure)
        if let index = structure.scenes.firstIndex(where: { $0.id == sceneID }) {
            for entry in structure.scenes[..<index].reversed().prefix(6) {
                let synopsis = editor.record(entry.id)?.string("synopsis") ?? ""
                add(.scene, entry.id, entry.node.title, synopsis, prefix: "S")
            }
        }
        return out
    }
}

public enum ConsistencyPrompt {
    public static func system(language: String) -> String {
        AIPrompts.resolve("consistency", language: language, builtIn: builtIn(CollectPrompt.languageName(language) ?? "the language of the passage"))
    }

    static func builtIn(_ name: String) -> String {
        """
        You check a passage of a novel against reference material for CONTRADICTIONS. The material is one or more labelled sources (C = character card, P = place, E = event, R = relationship, S = what an earlier scene says).
        Work in two steps.
        Step 1: list the checkable facts of the source: age, looks (eyes, hair, height), family and relations, origin, home, job, dates and seasons, places, names, who is alive, what someone knows.
        Step 2: for each fact, look in the passage for anything about the same thing. If the passage says something that cannot be true together with the fact (a different age or number, another colour, another place, another name, a different time), that is a contradiction.
        Compare numbers and words carefully: "twenty-eight" and "thirty-five" differ. A fact the passage does not mention is NOT a contradiction. Do not report style, repetition or missing information. Report every real contradiction, and only real ones.
        Answer with ONE JSON object and nothing else: {"facts": ["fact of the source", "..."], "findings": [{"source": "C1", "problem": "one sentence: what conflicts", "passage_quote": "words copied EXACTLY from the passage", "source_quote": "words copied EXACTLY from that source"}]}
        Quotes are 3 to 12 words. Write "problem" in \(name). If there are no contradictions, "findings" is an empty list.
        """
    }

    public static func user(passage: String, sceneTitle: String, sources: [ConsistencySource]) -> String {
        var s = "Sources:\n"
        if sources.isEmpty { s += "(none)\n" }
        for src in sources { s += "[\(src.label)] \(src.title): \(src.text)\n" }
        s += "\nPassage from the scene “\(sceneTitle)”:\n\"\"\"\n\(passage)\n\"\"\""
        return s
    }
}

public enum ConsistencyJudge {
    public static var system: String { AIPrompts.resolve("consistency_judge", language: "", builtIn: builtInSystem) }

    static let builtInSystem = """
    You compare two statements taken from a novel and its reference material. Decide whether they CONTRADICT each other: they cannot both be true at the same time about the same person, place, thing or moment.
    NOT a contradiction: different subjects, one statement saying more or less than the other, a person or thing missing from one of them, the same words repeated, a change over time that the text explains.
    Answer with ONE JSON object and nothing else: {"contradiction": true} or {"contradiction": false}.
    """

    public static func user(_ f: ConsistencyFinding) -> String {
        "Statement A, from the reference material (\(f.source.title)): «\(f.sourceQuote)»\nStatement B, from the passage: «\(f.quote)»\nDo A and B contradict each other?"
    }

    /// True when the statements are the same words (a repeated sentence is not a contradiction), without asking the model.
    public static func isRepetition(_ f: ConsistencyFinding) -> Bool { Names.normalize(f.sourceQuote) == Names.normalize(f.quote) || Names.normalize(f.sourceQuote).contains(Names.normalize(f.quote)) && f.quote.count > 25 }

    /// The model's verdict; nil when its answer cannot be read.
    public static func verdict(_ reply: String) -> Bool? { (CollectParser.extractObject(reply)?["contradiction"] as? Bool) }
}

public enum ConsistencyParser {
    public struct Result: Equatable, Sendable {
        public var findings: [ConsistencyFinding] = []
        public var dropped = 0
        public var malformed = false
    }

    /// A finding is kept only when its label names a source, its passage words are in the passage and its source words are in that source.
    public static func parse(_ reply: String, scene: String, passage: String, offset: Int, sources: [ConsistencySource]) -> Result {
        guard let object = CollectParser.extractObject(reply) else { return Result(malformed: true) }
        var result = Result()
        for d in (object["findings"] as? [Any])?.compactMap({ $0 as? [String: Any] }) ?? [] {
            func str(_ k: String) -> String { (d[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            let label = str("source").uppercased()
            guard let source = sources.first(where: { $0.label == label }), !str("problem").isEmpty,
                  let r = QuoteVerifier.find(str("passage_quote"), in: passage), let sr = QuoteVerifier.find(str("source_quote"), in: source.text) else { result.dropped += 1; continue }
            let range = NSRange(location: r.location + offset, length: r.length)
            let shown = { (text: String, r: NSRange) in (text as NSString).substring(with: r).replacingOccurrences(of: "*", with: "") }
            result.findings.append(ConsistencyFinding(scene: scene, problem: str("problem"), quote: shown(passage, r), range: range, source: source, sourceQuote: shown(source.text, sr)))
        }
        return result
    }
}

public struct ConsistencyScene: Sendable {
    public var id: String
    public var title: String
    public var text: String
    /// Only this part of the text is checked (a selection), as UTF-16 units; nil: all of it.
    public var within: NSRange?
    /// The sources for this scene, made by the caller (they depend on the book's cards).
    public var sources: [ConsistencySource]
    public init(id: String, title: String, text: String, within: NSRange? = nil, sources: [ConsistencySource]) { self.id = id; self.title = title; self.text = text; self.within = within; self.sources = sources }
}

public struct ConsistencySummary: Equatable, Sendable {
    public var scenesDone = 0
    public var scenesTooShort = 0
    public var found = 0
    public var droppedUnverified = 0
    /// Candidates the second look found not to be contradictions.
    public var droppedByJudge = 0
    public var failedPieces = 0
    public var stopped = false
    public var error: String?
}

public enum ConsistencyJob {
    /// Checks the scenes one after another (long ones in pieces). `found` gets each piece's findings as they come; stopping keeps them.
    public static func run(scenes: [ConsistencyScene], language: String, context: Int, client: LMStudioClient, progress: @Sendable (CollectProgress) -> Void,
                           found: @Sendable ([ConsistencyFinding]) -> Void) async -> ConsistencySummary {
        var summary = ConsistencySummary()
        let system = ConsistencyPrompt.system(language: language)
        let size = min(6000, max(1500, (context - 5000) * 2))
        // How many requests the run will make (one for each card and one for the earlier scenes, for each piece of each scene it will read).
        func groups(of scene: ConsistencyScene) -> [[ConsistencySource]] {
            let cards = scene.sources.filter { $0.kind != .scene }.map { [$0] }
            let earlier = scene.sources.filter { $0.kind == .scene }
            return cards + (earlier.isEmpty ? [] : [earlier])
        }
        var totalSteps = 0
        for scene in scenes {
            let ns = scene.text as NSString
            let text = ns.substring(with: scene.within ?? NSRange(location: 0, length: ns.length))
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < (scene.within == nil ? 80 : 15) { continue }
            totalSteps += CollectChunker.chunks(text, maxCharacters: size).count * groups(of: scene).count
        }
        var stepsDone = 0
        for (index, scene) in scenes.enumerated() {
            if Task.isCancelled { summary.stopped = true; break }
            let ns = scene.text as NSString
            let base = scene.within ?? NSRange(location: 0, length: ns.length)
            let text = ns.substring(with: base)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < (scene.within == nil ? 80 : 15) { summary.scenesTooShort += 1; continue }
            progress(CollectProgress(scene: index + 1, of: scenes.count, title: scene.title, found: summary.found, piece: stepsDone, pieces: totalSteps))
            // One request for each card, and one for what the earlier scenes say: a model checks a single source against a passage far more
            // carefully than ten at once.
            let groups = groups(of: scene)
            pieces: for piece in CollectChunker.chunks(text, maxCharacters: size) {
                for group in groups {
                    defer { stepsDone += 1; progress(CollectProgress(scene: index + 1, of: scenes.count, title: scene.title, found: summary.found, piece: min(stepsDone, totalSteps), pieces: totalSteps)) }
                    if Task.isCancelled { summary.stopped = true; break pieces }
                    let messages = [ChatMessage("system", system), ChatMessage("user", ConsistencyPrompt.user(passage: piece.text, sceneTitle: scene.title, sources: group))]
                    do {
                        let reply = try await client.chat(messages, think: false, temperature: AIPrompts.temperature("consistency", default: 0.1), maxTokens: 1500)
                        let result = ConsistencyParser.parse(reply, scene: scene.id, passage: piece.text, offset: base.location + piece.offset, sources: group)
                        summary.droppedUnverified += result.dropped
                        if result.malformed { summary.failedPieces += 1 }
                        // A second, strict look at each candidate: only a pair that cannot both be true stays.
                        var confirmed: [ConsistencyFinding] = []
                        for f in result.findings {
                            if Task.isCancelled { summary.stopped = true; break pieces }
                            if ConsistencyJudge.isRepetition(f) { summary.droppedByJudge += 1; continue }
                            let judged = try? await client.chat([ChatMessage("system", ConsistencyJudge.system), ChatMessage("user", ConsistencyJudge.user(f))], think: false, temperature: 0, maxTokens: 40)
                            if let judged, ConsistencyJudge.verdict(judged) == true { confirmed.append(f) } else { summary.droppedByJudge += 1 }
                        }
                        if !confirmed.isEmpty { summary.found += confirmed.count; found(confirmed) }
                    } catch {
                        if Task.isCancelled || error is CancellationError { summary.stopped = true; break pieces }
                        if let e = error as? LLMError, e == .unreachable || e.description.contains("not found") { summary.error = e.description; return summary }
                        summary.failedPieces += 1
                    }
                }
            }
            if summary.stopped { break }
            summary.scenesDone += 1
        }
        return summary
    }
}

/// The findings the author dismissed, kept on this machine in `.quilland/ai-dismissed.json`.
public enum AIDismissals {
    static func url(_ book: URL) -> URL { book.appendingPathComponent(".quilland/ai-dismissed.json") }

    public static func load(book: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data) else { return [] }
        return Set(o.strings("dismissed") ?? [])
    }

    public static func add(_ keys: [String], book: URL) {
        var all = load(book: book)
        all.formUnion(keys)
        var o: JSONObject = ["format": .int(1)]
        o["dismissed"] = .array(all.sorted().map { .string($0) })
        try? FileManager.default.createDirectory(at: url(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: url(book))
    }

    public static func forgetAll(book: URL) { try? FileManager.default.removeItem(at: url(book)) }
}
