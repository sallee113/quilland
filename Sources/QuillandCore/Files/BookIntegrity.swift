import Foundation

/// What leaves the book takes every reference to it along, in one step (quilland-change-events.md, "Deleting and merging"): a character, a place, a world, a
/// relationship or an event. The job is done here in the core and not by whoever happens to be listening, so that it is done the same way when a window is
/// open, in a test or by an import, and it is all or nothing as far as the files allow: with `snapshot` a snapshot of the book is taken first, which brings
/// everything back (the application takes its own snapshots around an undoable change and passes `snapshot: false`).
public enum BookIntegrity {
    public struct Report: Equatable, Sendable {
        /// Event files that lost a row, an effect or a marker.
        public var eventsChanged = 0
        /// Relationships that went with it (a relationship needs two characters).
        public var relationshipsRemoved = 0
        /// Links and fields in other files (research documents, plan cards, things of the author's own kinds, other cards).
        public var otherReferences = 0
        public var snapshot: String?
        public init() {}
    }

    /// What to do with the relationships that start in an event that is deleted.
    public enum StartedRelationships: Equatable, Sendable {
        case deleteThem
        /// They start in this other event instead.
        case moveStart(to: String)
    }

    private static func snapshot(_ book: URL, _ reason: String, _ report: inout Report, _ wanted: Bool) throws {
        guard wanted else { return }
        report.snapshot = try SnapshotStore(bookFolder: book).take(.beforeOperation, reason: reason).id
    }

    // MARK: Characters

    @discardableResult
    public static func deleteCharacter(_ id: String, book: URL, snapshot wanted: Bool = true) throws -> Report {
        var report = Report()
        let characters = CharacterStore(book: book)
        guard characters.character(id) != nil else { return report }
        try snapshot(book, L("Deleting a character"), &report, wanted)
        let events = EventStore(book: book)
        let relationships = RelationshipStore(book: book)
        // Its rows and what events change in it.
        for e in events.allEvents { if try drop(id, from: e, in: events, rows: ["characters"], effects: true) { report.eventsChanged += 1 } }
        // The relationships it is in: one left with fewer than two characters goes, with its place in the events.
        for r in relationships.relationships(of: id) {
            guard let rid = r.id else { continue }
            let rest = r.characters.filter { $0 != id }
            if rest.count >= 2 { try relationships.update(rid) { $0.characters = rest } }
            else { try removeRelationship(rid, relationships: relationships, events: events, report: &report) }
        }
        report.otherReferences += try scrub(book: book, id: id)
        try characters.delete(id)
        return report
    }

    // MARK: Places and worlds

    @discardableResult
    public static func deletePlace(_ id: String, book: URL, snapshot wanted: Bool = true) throws -> Report {
        var report = Report()
        let worlds = WorldStore(book: book)
        guard worlds.entry(id) != nil else { return report }
        try snapshot(book, L("Deleting a place"), &report, wanted)
        let events = EventStore(book: book)
        for e in events.allEvents { if try drop(id, from: e, in: events, rows: ["places"], effects: true) { report.eventsChanged += 1 } }
        report.otherReferences += try scrub(book: book, id: id)
        try worlds.deleteEntry(id)
        return report
    }

    @discardableResult
    public static func deleteWorld(_ id: String, book: URL, snapshot wanted: Bool = true) throws -> Report {
        var report = Report()
        let worlds = WorldStore(book: book)
        guard worlds.world(id) != nil else { return report }
        try snapshot(book, L("Deleting a world"), &report, wanted)
        // (The world must be empty and not the last one: the store says so before anything is touched.)
        try worlds.deleteWorld(id)
        report.otherReferences += try scrub(book: book, id: id)
        let characters = CharacterStore(book: book)
        for c in characters.characters where c.worlds.contains(id) {
            guard let cid = c.id else { continue }
            try characters.update(cid) { $0.worlds = $0.worlds.filter { $0 != id } }
            report.otherReferences += 1
        }
        return report
    }

    // MARK: Relationships

    @discardableResult
    public static func deleteRelationship(_ id: String, book: URL, snapshot wanted: Bool = true) throws -> Report {
        var report = Report()
        let relationships = RelationshipStore(book: book)
        guard relationships.relationship(id) != nil else { return report }
        try snapshot(book, L("Deleting a relationship"), &report, wanted)
        try removeRelationship(id, relationships: relationships, events: EventStore(book: book), report: &report)
        return report
    }

    private static func removeRelationship(_ id: String, relationships: RelationshipStore, events: EventStore, report: inout Report) throws {
        for e in events.allEvents { if try drop(id, from: e, in: events, rows: ["relationships"], effects: true) { report.eventsChanged += 1 } }
        try relationships.delete(id)
        report.relationshipsRemoved += 1
    }

    // MARK: Events

    /// The relationships that start in an event: a decision is needed about them before it is deleted.
    public static func relationshipsStarting(in event: String, book: URL) -> [String] {
        (EventStore(book: book).event(event)?.relationships ?? [:]).filter { $0.value == "starts" }.map(\.key).sorted()
    }

    /// Deletes an event (never the default one). The relationships that **start** in it are deleted or start in another event, as asked; one that **ends** in it
    /// is active again, since the marker is in the event's own file.
    @discardableResult
    public static func deleteEvent(_ id: String, book: URL, started: StartedRelationships = .deleteThem, snapshot wanted: Bool = true) throws -> Report {
        var report = Report()
        let events = EventStore(book: book)
        guard let event = events.event(id) else { return report }
        guard !event.start else { throw EventStoreError(description: L("The event the book starts with cannot be deleted.")) }
        if case .moveStart(let target) = started, target == id || events.event(target) == nil {
            throw EventStoreError(description: L("The relationships cannot start in that event."))
        }
        try snapshot(book, L("Deleting an event"), &report, wanted)
        let starting = relationshipsStarting(in: id, book: book)
        switch started {
        case .deleteThem:
            let relationships = RelationshipStore(book: book)
            for rid in starting where relationships.relationship(rid) != nil {
                try removeRelationship(rid, relationships: relationships, events: events, report: &report)
            }
        case .moveStart(let target):
            try events.update(target) { r in var marks = r.relationships; for rid in starting { marks[rid] = "starts" }; r.relationships = marks }
            report.eventsChanged += 1
        }
        try? PlanStore(folder: book).removeEntry(forEvent: id)
        report.otherReferences += try scrub(book: book, id: id)
        try events.delete(id)
        return report
    }

    // MARK: The files

    /// Takes an id out of an event's rows (`characters`, `places`, `relationships`) and out of its effects. Returns whether the file changed.
    private static func drop(_ id: String, from event: EventRecord, in store: EventStore, rows: [String], effects: Bool) throws -> Bool {
        guard let eid = event.id else { return false }
        var touched = false
        try store.update(eid) { r in
            for key in rows {
                var map = r.object.stringMap(key) ?? [:]
                if map.removeValue(forKey: id) != nil { r.object.setStringMap(key, map); touched = true }
            }
            if effects {
                var all = r.effects
                if all.removeValue(forKey: id) != nil { r.effects = all; touched = true }
            }
        }
        return touched
    }

    /// Takes an id out of the `links` of the cards, research documents and things, and out of the `fields` of things of the author's own kinds (a field that
    /// holds the id, or a list that has it). Returns how many references went.
    @discardableResult
    static func scrub(book: URL, id: String) throws -> Int {
        let fm = FileManager.default
        var removed = 0
        for relative in ["bible/characters", "bible/places", "bible/worlds", "bible/relationships", "bible/things", "plan/cards", "research"] {
            guard let walker = fm.enumerator(at: book.appendingPathComponent(relative), includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "json" && !url.path.contains(".file/") {   // (a file kept inside a research document is the author's, not ours)
                guard var object = try? JSONParser.parseObject(Data(contentsOf: url)) else { continue }
                var touched = false
                var links = object.stringMap("links") ?? [:]
                if links.removeValue(forKey: id) != nil { object.setStringMap("links", links); touched = true; removed += 1 }
                if var fields = object.object("fields") {
                    for (key, value) in fields {
                        switch value {
                        case .string(let s) where s == id: fields.removeValue(forKey: key); touched = true; removed += 1
                        case .array(let items):
                            let kept = items.filter { if case .string(let s) = $0 { return s != id } else { return true } }
                            if kept.count != items.count { fields[key] = kept.isEmpty ? nil : .array(kept); touched = true; removed += 1 }
                        default: break
                        }
                    }
                    if touched { if fields.isEmpty { object.removeValue(forKey: "fields") } else { object["fields"] = .object(fields) } }
                }
                if touched { try AtomicFile.write(JSONWriter.data(object), to: url) }
            }
        }
        return removed
    }
}
