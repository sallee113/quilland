import Foundation

/// Two cards that are one person: the second character is taken out of the book and what is known of them is added to the first (`Merge Into…`).
/// The writes go in an order in which a stop half way loses nothing: the kept character first, then the links of the others, the relationships, and the removed
/// character (to the trash folder) last; doing it again from the start gives the same result.
public enum CharacterMerger {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    public struct Report: Equatable, Sendable {
        /// The names the kept character has gained (the other one's name and aliases).
        public var aliasesAdded: [String] = []
        /// Files of other things (events, places, plan cards…) whose links were pointed at the kept character.
        public var linksRepointed = 0
        public var relationshipsChanged = 0
        /// Relationships between the two themselves, which would have been a character related to themselves.
        public var relationshipsRemoved = 0
    }

    /// Descriptions that go with the same target are joined; one that is already inside the other is not added twice.
    static func joined(_ first: [String: String], _ second: [String: String]) -> [String: String] {
        var out = first
        for (key, text) in second {
            let existing = out[key] ?? ""
            if existing.isEmpty { out[key] = text }
            else if !text.isEmpty, !existing.contains(text) { out[key] = existing + " " + text }
        }
        return out
    }

    private static func union(_ first: [String], _ second: [String]) -> [String] {
        var out = first
        for item in second where !out.contains(item) { out.append(item) }
        return out
    }

    @discardableResult
    public static func merge(_ source: String, into target: String, book: URL) throws -> Report {
        guard source != target else { throw Failure(L("A character cannot be merged into itself.")) }
        let characters = CharacterStore(book: book)
        guard let from = characters.character(source), let into = characters.character(target) else { throw Failure(L("No such character.")) }
        var report = Report()
        let fromName = (from.name ?? "").trimmingCharacters(in: .whitespaces)

        // The kept character: the names, the notes, the links and what else the other one had.
        var aliases = into.aliases
        let keptName = (into.name ?? "").lowercased()
        for name in [fromName] + from.aliases {
            let t = name.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.lowercased() != keptName, !aliases.contains(where: { $0.lowercased() == t.lowercased() }) else { continue }
            aliases.append(t)
            report.aliasesAdded.append(t)
        }
        try characters.update(target) { r in
            r.aliases = aliases
            r.main = r.main || from.main
            r.notes = union(r.notes, from.notes)
            r.povScenes = union(r.povScenes, from.povScenes)
            r.worlds = union(r.worlds, from.worlds)
            r.links = joined(r.links, from.links)
            var images = r.images
            for (key, value) in from.images where images[key] == nil { images[key] = value }
            r.images = images
        }
        let extra = characters.profile(source)
        if !extra.isEmpty {
            let base = characters.profile(target)
            try characters.setProfile(target, base.isEmpty ? extra : base + "\n\n**" + fromName + "**\n\n" + extra)
        }

        // Everything else that is linked to the removed character is linked to the kept one.
        let fm = FileManager.default
        for relative in ["bible/characters", "bible/places", "bible/events", "bible/things", "plan/cards"] {
            let dir = book.appendingPathComponent(relative)
            for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where name.hasSuffix(".json") {
                if relative == "bible/characters", name == source + ".json" || name == target + ".json" { continue }
                let url = dir.appendingPathComponent(name)
                guard var object = try? JSONParser.parseObject(Data(contentsOf: url)) else { continue }
                var touched = false
                var links = object.stringMap("links") ?? [:]
                if let text = links.removeValue(forKey: source) {
                    links = joined(links, [target: text])
                    object.setStringMap("links", links)
                    touched = true
                }
                if relative == "bible/events" {
                    // An event holds its characters, and what it changes in them, itself.
                    var characters = object.stringMap("characters") ?? [:]
                    if let text = characters.removeValue(forKey: source) {
                        characters = joined(characters, [target: text])
                        object.setStringMap("characters", characters)
                        touched = true
                    }
                    var effects = object.object("effects") ?? [:]
                    if let moved = effects.removeValue(forKey: source) {
                        if effects[target] == nil { effects[target] = moved }
                        if effects.isEmpty { object.removeValue(forKey: "effects") } else { object["effects"] = .object(effects) }
                        touched = true
                    }
                }
                guard touched else { continue }
                try AtomicFile.write(JSONWriter.data(object), to: url)
                report.linksRepointed += 1
            }
        }

        // The relationships: the kept character takes the other one's place; one between the two of them has no meaning any more.
        let relationships = RelationshipStore(book: book)
        for r in relationships.relationships(of: source) {
            guard let id = r.id else { continue }
            var members: [String] = []
            for c in r.characters.map({ $0 == source ? target : $0 }) where !members.contains(c) { members.append(c) }
            if members.count >= 2 { try relationships.update(id) { $0.characters = members }; report.relationshipsChanged += 1 }
            else { try relationships.delete(id); report.relationshipsRemoved += 1 }
        }

        // The other character goes to the trash folder (the card and its profile).
        try characters.delete(source)
        return report
    }
}
