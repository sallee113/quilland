import Foundation

/// The links between characters and events used to be kept in the characters' files (`links[event]`); the event keeps them now (`characters`, quilland-format.md,
/// section 12), and every relationship starts at some event (`relationships`), the ones that had none at the default event "Book starts".
///
/// `plan` says what a book needs; the application asks the author before `run` (a snapshot is taken first). `run` can be done again: it finds nothing the second time.
public enum EventLinkMigration {
    public struct Plan: Equatable, Sendable {
        /// Links from characters to events that move into the events, and the characters that have them.
        public var links = 0
        public var characters = 0
        /// Relationships that start at "Book starts" (they start at no event yet).
        public var relationships = 0
        /// Is there something to move, so that the author must be asked?
        public var isNeeded: Bool { links > 0 || relationships > 0 }

        public init(links: Int = 0, characters: Int = 0, relationships: Int = 0) { self.links = links; self.characters = characters; self.relationships = relationships }
    }

    public struct Report: Equatable, Sendable {
        public var links = 0
        public var characters = 0
        public var relationships = 0
        /// The name of the snapshot taken first.
        public var snapshot: String?

        public init() {}
    }

    /// The title of the default event, in the language of the book.
    public static func startTitle(language: String) -> String {
        switch language {
        case "ru": return "Начало книги"
        case "uk": return "Початок книги"
        case "fr": return "Début du livre"
        case "de": return "Beginn des Buches"
        case "es": return "Inicio del libro"
        case "it": return "Inizio del libro"
        case "pl": return "Początek książki"
        default: return "Book starts"
        }
    }

    public static func plan(book: URL) -> Plan {
        let characters = CharacterStore(book: book)
        let events = EventStore(book: book)
        let relationships = RelationshipStore(book: book)
        let eventIDs = Set(events.allEvents.compactMap(\.id))
        var plan = Plan()
        for c in characters.characters {
            let n = c.links.keys.filter(eventIDs.contains).count
            if n > 0 { plan.links += n; plan.characters += 1 }
        }
        let started = Set(events.allEvents.flatMap { $0.relationships.keys })
        plan.relationships = relationships.relationships.filter { $0.id.map { !started.contains($0) } ?? false }.count
        return plan
    }

    /// Makes the default event when the book has none (nothing to ask the author: no data moves).
    public static func ensureStartEvent(book: URL, language: String? = nil) throws {
        let events = EventStore(book: book)
        guard events.startEvent == nil else { return }
        try events.ensureStartEvent(title: startTitle(language: language ?? BookSettings.load(book: book).language))
    }

    /// Moves the links and starts the relationships that start at no event. With `snapshot`, the book is kept first.
    @discardableResult
    public static func run(book: URL, language: String? = nil, snapshot: Bool = true) throws -> Report {
        var report = Report()
        let needed = plan(book: book)
        guard needed.isNeeded else { try ensureStartEvent(book: book, language: language); return report }
        if snapshot {
            report.snapshot = try SnapshotStore(bookFolder: book).take(.beforeOperation, reason: L("Moving the links between characters and events into the events")).id
        }
        let events = EventStore(book: book)
        let startID = try events.ensureStartEvent(title: startTitle(language: language ?? BookSettings.load(book: book).language))
        let characters = CharacterStore(book: book)
        let relationships = RelationshipStore(book: book)

        // The characters' links to events go into the events.
        let eventIDs = Set(events.allEvents.compactMap(\.id))
        var moved: [String: [String: String]] = [:]   // event → character → text
        for c in characters.characters {
            guard let id = c.id else { continue }
            let mine = c.links.filter { eventIDs.contains($0.key) }
            guard !mine.isEmpty else { continue }
            for (event, text) in mine { moved[event, default: [:]][id] = text }
            report.links += mine.count
            report.characters += 1
        }
        for (event, who) in moved {
            try events.update(event) { r in
                var list = r.characters
                for (character, text) in who where (list[character] ?? "").isEmpty { list[character] = text }
                r.characters = list
            }
        }
        for c in characters.characters {
            guard let id = c.id, c.links.keys.contains(where: eventIDs.contains) else { continue }
            try characters.update(id) { r in r.links = r.links.filter { !eventIDs.contains($0.key) } }
        }

        // Every relationship that starts at no event starts at "Book starts".
        let started = Set(events.allEvents.flatMap { $0.relationships.keys })
        let loose = relationships.relationships.compactMap(\.id).filter { !started.contains($0) }
        if !loose.isEmpty {
            try events.update(startID) { r in
                var marks = r.relationships
                for id in loose { marks[id] = "starts" }
                r.relationships = marks
            }
            report.relationships = loose.count
        }
        return report
    }
}
