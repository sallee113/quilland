import Foundation

/// Two events that are one: the second is taken out of the book and what it holds is added to the first (the same way a character or a place is merged).
/// The kept event gets the other's characters, places, scenes, relationship marks and effects (what the kept event already says is not overwritten), the links of other
/// things are pointed at it, and the other goes to the trash folder last.
public enum EventMerger {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    public struct Report: Equatable, Sendable {
        public var rowsAdded = 0
        public var marksMoved = 0
        public var effectsMoved = 0
        public var linksRepointed = 0
    }

    @discardableResult
    public static func merge(_ source: String, into target: String, book: URL) throws -> Report {
        guard source != target else { throw Failure(L("An event cannot be merged into itself.")) }
        let events = EventStore(book: book)
        guard let from = events.event(source), let into = events.event(target) else { throw Failure(L("No such event.")) }
        guard !from.start, !into.start else { throw Failure(L("“Book starts” cannot be merged.")) }
        var report = Report()

        try events.update(target) { r in
            report.rowsAdded += from.characters.keys.filter { r.characters[$0] == nil }.count + from.places.keys.filter { r.places[$0] == nil }.count
            r.characters = CharacterMerger.joined(r.characters, from.characters)
            r.places = CharacterMerger.joined(r.places, from.places)
            r.links = CharacterMerger.joined(r.links, from.links)
            var marks = r.relationships
            for (id, mark) in from.relationships {
                if marks[id] == nil { marks[id] = mark; report.marksMoved += 1 }
                else if (marks[id] ?? "").isEmpty, !mark.isEmpty { marks[id] = mark }
            }
            r.relationships = marks
            // What the kept event already says about a thing is not overwritten: the other's fields are added where it says nothing.
            var effects = r.effects
            for (thing, value) in from.effects {
                guard case .object(let theirs) = value else { continue }
                var mine: JSONObject = [:]
                if case .object(let o)? = effects[thing] { mine = o }
                let before = mine.count
                for (field, v) in theirs where mine[field] == nil { mine[field] = v }
                if mine.count > before || effects[thing] == nil { report.effectsMoved += 1 }
                effects[thing] = .object(mine)
            }
            r.effects = effects
            if r.date.isEmpty { r.date = from.date }
            if r.color == nil { r.color = from.color }
            r.notes = r.notes + from.notes.filter { !r.notes.contains($0) }
        }
        let extra = events.text(source).trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            let base = events.text(target).trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.contains(extra) { try events.setText(target, base.isEmpty ? extra : base + "\n\n" + extra) }
        }

        // Where the other stood on the plan: the kept event keeps its own place; with none, it takes the other's.
        if let plan = try? PlanStore(folder: book) {
            let theirs = plan.entry(forEvent: source)
            try? plan.removeEntry(forEvent: source)   // (first: the place it stood in must be free for the kept event to take)
            if plan.entry(forEvent: target) == nil, let lane = theirs?.lane, let start = theirs?.start { try? plan.placeEvent(target, onLine: lane, start: start) }
        }

        // The links of other things (a plan card realised by it, a research document, a place or character that mentions it) point at the kept event.
        let fm = FileManager.default
        for relative in ["bible/characters", "bible/places", "bible/relationships", "bible/things", "plan/cards", "research"] {
            let dir = book.appendingPathComponent(relative)
            for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where name.hasSuffix(".json") {
                let url = dir.appendingPathComponent(name)
                guard var object = try? JSONParser.parseObject(Data(contentsOf: url)) else { continue }
                var links = object.stringMap("links") ?? [:]
                guard let text = links.removeValue(forKey: source) else { continue }
                object.setStringMap("links", CharacterMerger.joined(links, [target: text]))
                try AtomicFile.write(JSONWriter.data(object), to: url)
                report.linksRepointed += 1
            }
        }

        // The other event: what it held has been moved, so deleting it takes no relationship or change with it.
        try events.update(source) { $0.relationships = [:]; $0.effects = [:] }
        try BookIntegrity.deleteEvent(source, book: book, started: .deleteThem, snapshot: false)
        return report
    }
}

/// Two relationships that are one (the same characters, the same bond written twice): the second is taken out and its notes, links, and where it starts, changes and ends
/// in the events are added to the first.
public enum RelationshipMerger {
    public struct Report: Equatable, Sendable {
        public var eventsChanged = 0
    }

    @discardableResult
    public static func merge(_ source: String, into target: String, book: URL) throws -> Report {
        guard source != target else { throw EventMerger.Failure(L("A relationship cannot be merged into itself.")) }
        let store = RelationshipStore(book: book)
        guard let from = store.relationship(source), let into = store.relationship(target) else { throw EventMerger.Failure(L("No such relationship.")) }
        guard Set(from.characters) == Set(into.characters) else { throw EventMerger.Failure(L("Only relationships between the same characters can be merged.")) }
        var report = Report()
        try store.update(target) { r in
            r.notes = r.notes + from.notes.filter { !r.notes.contains($0) }
            r.links = CharacterMerger.joined(r.links, from.links)
        }
        let extra = store.text(source).trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            let base = store.text(target).trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.contains(extra) { try store.setText(target, base.isEmpty ? extra : base + "\n\n" + extra) }
        }
        // In the events: where the other starts, changes and ends is where the kept one does.
        let events = EventStore(book: book)
        for e in events.allEvents {
            guard let id = e.id, e.relationships[source] != nil || e.effects[source] != nil else { continue }
            try events.update(id) { r in
                var marks = r.relationships
                if let mark = marks.removeValue(forKey: source) {
                    if marks[target] == nil || ((marks[target] ?? "").isEmpty && !mark.isEmpty) { marks[target] = mark }
                    r.relationships = marks
                }
                var effects = r.effects
                if let moved = effects.removeValue(forKey: source) {
                    if case .object(let theirs) = moved {
                        var mine: JSONObject = [:]
                        if case .object(let o)? = effects[target] { mine = o }
                        for (field, v) in theirs where mine[field] == nil { mine[field] = v }
                        effects[target] = .object(mine)
                    }
                    r.effects = effects
                }
            }
            report.eventsChanged += 1
        }
        try BookIntegrity.deleteRelationship(source, book: book, snapshot: false)
        return report
    }
}
