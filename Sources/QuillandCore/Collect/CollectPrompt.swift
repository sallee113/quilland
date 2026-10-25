import Foundation

/// The words the model is given for collecting from the book. Only what the passage says counts; every finding must carry a quote, which is checked afterwards.
public enum CollectPrompt {
    /// The language to write the descriptions in, from the book's language code (`ru`, `en`…).
    static func languageName(_ code: String) -> String? {
        let names = ["ru": "Russian", "en": "English", "uk": "Ukrainian", "de": "German", "fr": "French", "es": "Spanish", "it": "Italian", "pl": "Polish", "pt": "Portuguese", "cs": "Czech"]
        return names[String(code.lowercased().prefix(2))]
    }

    /// The instructions before the list of what to look for. They are the same for both passes over a passage (so that the model's server can keep what it has read of
    /// the passage between them); what to look for follows the passage.
    static func intro(_ name: String) -> String {
        """
        You read a passage of a novel and list what the author may want to put on the book's reference cards.
        Answer with ONE JSON object and nothing else (no comments, no markdown). Use only what the passage says; never invent anything.
        Every entry needs "quote": a short piece of the passage (4 to 12 words) copied EXACTLY, letter for letter, that shows the entry.
        Names are in their base form (nominative, singular), spelled as the text spells them, with a capital letter for a name of a person or a place.
        Descriptions, notes, event titles and relationship kinds are one or two short sentences or a few words, written in \(name) (not in English unless the passage is English).
        Be selective: a few good entries are better than many trivial ones. Never list the same thing twice, and never use two names for one person when the text shows they are the same.
        If the passage has nothing for a list, give an empty list. The keys to answer with come after the passage.
        """
    }

    /// The instructions (the author's own wording when there is one).
    public static func shared(language: String = "") -> String {
        AIPrompts.resolve("collect", language: language, builtIn: intro(languageName(language) ?? "the language of the passage"))
    }

    /// What to look for, for the kinds of one pass.
    public static func task(kinds: Set<CollectKind>, language: String = "") -> String {
        let name = languageName(language) ?? "the language of the passage"
        var s = "Answer with ONE JSON object with these keys (leave out any other):"
        if kinds.contains(.characters) {
            s += "\n\"characters\": people or beings who act, speak or are named in the passage: [{\"name\": \"\", \"aliases\": [], \"description\": \"who this is, as far as the passage says\", \"note\": \"what this character does in the passage\", \"quote\": \"\"}]"
        }
        if kinds.contains(.places) {
            s += "\n\"places\": named places only (a town, a building, a region, a planet), never a people, an object or an invented term: [{\"name\": \"\", \"parent\": \"the larger place it is in, if the passage says\", \"description\": \"\", \"note\": \"what happens there in the passage\", \"quote\": \"\"}]"
        }
        if kinds.contains(.observations) {
            s += "\n\"observations\": a stable fact about a character or a place that was true all along and is worth keeping on its card (looks, age, habits, past, a secret), as a short sentence; not what merely happens in this passage and not a change: [{\"about\": \"the name\", \"note\": \"the fact\", \"quote\": \"\"}]"
        }
        if kinds.contains(.events) {
            s += "\n\"events\": important happenings that move the story or change a character's situation (an arrival, a quarrel, a discovery, a decision, a death); not descriptions, thoughts or small actions; each with a short title: [{\"title\": \"\", \"date\": \"only if the passage says when\", \"places\": [\"place names\"], \"characters\": [\"names of those who take part in it\"], \"note\": \"what happens\", \"quote\": \"\"}]"
        }
        if kinds.contains(.changes) {
            s += "\n\"changes\": how a character or a place CHANGES in this passage, from now on (a character gets a new name, learns the truth, is crippled, changes their way of life; a place burns down or is rebuilt). Not a fact that was true all along, and never the name, the notes or whether someone is a main character. Give only what is NEW compared with the known card: [{\"about\": \"the name of the character or place\", \"field\": \"profile (a character) | description (a place) | aliases (new names of a character)\", \"value\": \"the NEW state in one or two short sentences (not for aliases)\", \"aliases\": [\"new names, for aliases only\"], \"event\": \"the title of the event above, or of a known event, that it belongs to, or empty\", \"note\": \"\", \"quote\": \"\"}]"
        }
        if kinds.contains(.relationships) {
            s += "\n\"relationships\": a LASTING bond between two named characters that the passage states or clearly shows (a family tie, friendship, enmity, work, love); never a mere meeting of strangers. The kind of bond is a word or two written in \(name), never in English unless the passage is English. \"when\": \"stated\" if it is simply so (it was so before the passage), \"starts\" if it begins in this passage, \"changes\" if it becomes another kind (friends become enemies), \"ends\" if it ends (a break, a death): [{\"characters\": [\"A\", \"B\"], \"kind\": \"the kind of bond, in \(name)\", \"when\": \"stated\", \"note\": \"how it shows here\", \"quote\": \"\"}]"
        }
        return s
    }

    /// The instructions and what to look for in one text (the instructions are sent first, then the passage, then what to look for: see `user`).
    public static func system(kinds: Set<CollectKind>, language: String = "") -> String { shared(language: language) + "\n" + task(kinds: kinds, language: language) }

    /// The cards of the book that the passage names, as what is known now, so that the model can tell a new fact from one already written down: each with its text
    /// (cut short) and its relationships, until `budget` characters are used.
    public static func known(cards: [CollectCard], in chunk: String, budget: Int) -> String { CollectKnown(cards: cards).text(in: chunk, budget: budget) }
}

/// Finds which cards a passage names (in any case form of the name, as the text matching does) and tells what they say.
public struct CollectKnown {
    private let cards: [CollectCard]
    private let matcher: ParadigmMatcher

    public init(cards: [CollectCard]) {
        self.cards = cards
        matcher = ParadigmMatcher(entries: cards.enumerated().map { NameEntry(id: String($0.offset), name: $0.element.name, aliases: $0.element.aliases, ignoresCapitals: $0.element.isPlace) })
    }

    public func text(in chunk: String, budget: Int) -> String {
        guard !cards.isEmpty else { return "" }
        let named = Set(matcher.matches(in: chunk).map(\.entry))
        var out = "", used = 0
        for (i, card) in cards.enumerated() where named.contains(String(i)) {
            var line = "- " + card.name + (card.aliases.isEmpty ? "" : " (also " + card.aliases.joined(separator: ", ") + ")")
            if !card.text.isEmpty { line += ": " + String(card.text.prefix(300)).replacingOccurrences(of: "\n", with: " ") }
            if !card.relations.isEmpty { line += (card.text.isEmpty ? ": " : " | ") + "Relationships: " + card.relations.joined(separator: "; ") }
            if used + line.count > budget { break }
            out += line + "\n"; used += line.count + 1
        }
        return out
    }
}

extension CollectPrompt {

    public static func user(chunk: String, sceneTitle: String, knownCharacters: [String], knownPlaces: [String], known: String = "", knownEvents: [String] = [], kinds: Set<CollectKind>, language: String = "") -> String {
        // The passage first: both passes begin with the same words, so that the model's server need not read it twice.
        var s = "Passage from the scene “\(sceneTitle)”:\n\"\"\"\n\(chunk)\n\"\"\"\n"
        if !knownCharacters.isEmpty { s += "Characters already on cards (use exactly these names when the same person is meant): " + knownCharacters.joined(separator: ", ") + "\n" }
        if !knownPlaces.isEmpty { s += "Places already on cards (same rule): " + knownPlaces.joined(separator: ", ") + "\n" }
        if !known.isEmpty { s += "Known cards (what is written on them now):\n" + known }
        // So that the same event is not proposed twice under two titles (the book's own events of this scene, and those found earlier in the run).
        if !knownEvents.isEmpty { s += "Events already known for this scene or found earlier (if the passage shows one of them, use exactly its title for it, never a new one):\n" + knownEvents.map { "- " + $0 }.joined(separator: "\n") + "\n" }
        s += task(kinds: kinds, language: language)
        return s
    }
}

/// Cuts a scene into pieces for the model, at paragraph ends.
public enum CollectChunker {
    public static func chunks(_ text: String, maxCharacters: Int) -> [(offset: Int, text: String)] {
        let ns = text as NSString
        guard ns.length > maxCharacters else { return ns.length == 0 ? [] : [(0, text)] }
        var out: [(Int, String)] = []
        var start = 0
        var i = 0
        var lastBreak: Int?
        while i < ns.length {
            if ns.character(at: i) == 0x0A { lastBreak = i + 1 }
            if i - start >= maxCharacters {
                let end = lastBreak.flatMap { $0 > start ? $0 : nil } ?? i
                out.append((start, ns.substring(with: NSRange(location: start, length: end - start))))
                start = end; lastBreak = nil; i = end
                continue
            }
            i += 1
        }
        if start < ns.length { out.append((start, ns.substring(from: start))) }
        return out
    }
}

/// Reads what the model answered. A finding whose quote is not in the passage is dropped (and counted): it is never shown.
public enum CollectParser {
    public struct Result: Equatable, Sendable {
        public var items: [CollectedItem] = []
        public var dropped = 0
        /// The answer could not be read as the expected JSON.
        public var malformed = false
    }

    /// The first complete JSON object in the reply (models wrap it in fences or talk before it).
    static func extractObject(_ reply: String) -> [String: Any]? {
        let chars = Array(reply)
        guard let start = chars.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        for i in start..<chars.count {
            let c = chars[i]
            if inString { if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }; continue }
            if c == "\"" { inString = true } else if c == "{" { depth += 1 } else if c == "}" {
                depth -= 1
                if depth == 0 { return (try? JSONSerialization.jsonObject(with: Data(String(chars[start...i]).utf8))) as? [String: Any] }
            }
        }
        return nil
    }

    public static func parse(_ reply: String, kinds: Set<CollectKind>, scene: String, chunk: String, chunkOffset: Int) -> Result {
        guard let object = extractObject(reply) else { return Result(malformed: true) }
        var result = Result()
        func str(_ d: [String: Any], _ key: String) -> String { (d[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        func list(_ d: [String: Any], _ key: String) -> [String] { ((d[key] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
        func evidence(_ d: [String: Any], note: String) -> CollectedEvidence? {
            let quote = str(d, "quote")
            guard !quote.isEmpty, let r = QuoteVerifier.find(quote, in: chunk) else { result.dropped += 1; return nil }
            let range = NSRange(location: r.location + chunkOffset, length: r.length)
            // The quote is the text's own, without its markup marks, for showing.
            let shown = (chunk as NSString).substring(with: r).replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "^[", with: "[")
            return CollectedEvidence(scene: scene, quote: shown, range: range, note: note)
        }
        func entries(_ key: String) -> [[String: Any]] { (object[key] as? [Any])?.compactMap { $0 as? [String: Any] } ?? [] }

        if kinds.contains(.characters) {
            for d in entries("characters") {
                let name = str(d, "name"); guard !name.isEmpty, let ev = evidence(d, note: str(d, "note")) else { continue }
                var item = CollectedItem(kind: .characters, name: name)
                item.aliases = list(d, "aliases"); item.detail = str(d, "description"); item.evidence = [ev]
                result.items.append(item)
            }
        }
        if kinds.contains(.places) {
            for d in entries("places") {
                let name = str(d, "name"); guard !name.isEmpty, let ev = evidence(d, note: str(d, "note")) else { continue }
                var item = CollectedItem(kind: .places, name: name)
                item.type = "place"   // (a place is a place: things and peoples are not kept among them)
                item.parent = str(d, "parent"); item.detail = str(d, "description"); item.aliases = list(d, "aliases"); item.evidence = [ev]
                result.items.append(item)
            }
        }
        if kinds.contains(.events) {
            for d in entries("events") {
                let title = str(d, "title"); guard !title.isEmpty, let ev = evidence(d, note: str(d, "note")) else { continue }
                var item = CollectedItem(kind: .events, name: title)
                item.date = str(d, "date"); item.places = list(d, "places"); item.members = list(d, "characters"); item.detail = str(d, "note"); item.evidence = [ev]
                result.items.append(item)
            }
        }
        if kinds.contains(.relationships) {
            for d in entries("relationships") {
                let members = list(d, "characters")
                guard Set(members.map(Names.normalize)).count >= 2, !str(d, "kind").isEmpty, let ev = evidence(d, note: str(d, "note")) else { continue }
                var item = CollectedItem(kind: .relationships, name: "")
                let when = str(d, "when").lowercased()
                item.members = members; item.type = str(d, "kind"); item.evidence = [ev]
                item.when = ["stated", "starts", "changes", "ends"].contains(when) ? when : "stated"
                result.items.append(item)
            }
        }
        if kinds.contains(.changes) {
            // Only what an event can change on a card (never the name, the notes or the main-character flag, whatever the model says).
            for d in entries("changes") {
                let about = str(d, "about"), field = str(d, "field").lowercased()
                guard !about.isEmpty, ["profile", "description", "aliases"].contains(field) else { continue }
                var item = CollectedItem(kind: .changes, name: about)
                item.field = field; item.eventTitle = str(d, "event")
                if field == "aliases" {
                    item.aliases = list(d, "aliases").isEmpty ? str(d, "value").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : list(d, "aliases")
                    guard !item.aliases.isEmpty else { continue }
                } else {
                    item.detail = str(d, "value")
                    guard !item.detail.isEmpty else { continue }
                }
                guard let ev = evidence(d, note: str(d, "note").isEmpty ? (item.detail.isEmpty ? item.aliases.joined(separator: ", ") : item.detail) : str(d, "note")) else { continue }
                item.evidence = [ev]
                result.items.append(item)
            }
        }
        if kinds.contains(.observations) {
            for d in entries("observations") {
                let about = str(d, "about"), note = str(d, "note")
                guard !about.isEmpty, !note.isEmpty, let ev = evidence(d, note: note) else { continue }
                var item = CollectedItem(kind: .observations, name: "")
                item.about = about; item.detail = note; item.evidence = [ev]
                result.items.append(item)
            }
        }
        return result
    }
}
