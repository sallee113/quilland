import Foundation

public struct EventRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }
    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var title: String? { get { object.string("title") } set { object.setString("title", newValue) } }
    /// Where the event stands among the events of its scene, in the author's own order (a number; the gaps are free).
    public var order: Int? { get { object.int("order") } set { object.setInt("order", newValue) } }
    /// The colour the event has on the Plan (a name such as `teal`); none is the plain look.
    public var color: String? { get { object.string("color") } set { object.setString("color", newValue) } }
    /// Free text ("spring, year 214", "several years later"); never read as a date.
    public var date: String { get { object.string("date") ?? "" } set { object.setString("date", newValue.isEmpty ? nil : newValue) } }
    public var notes: [String] { get { object.strings("notes") ?? [] } set { object.setStrings("notes", newValue) } }
    /// World entry ids to what happens there.
    public var places: [String: String] { get { object.stringMap("places") ?? [:] } set { object.setStringMap("places", newValue) } }
    /// Scene (or fragment) ids to what happens there.
    public var links: [String: String] { get { object.stringMap("links") ?? [:] } set { object.setStringMap("links", newValue) } }
    /// Character ids to what they do in the event. The event holds these links (the characters' files do not): quilland-format.md, section 12.
    public var characters: [String: String] { get { object.stringMap("characters") ?? [:] } set { object.setStringMap("characters", newValue) } }
    /// The book's default event ("Book starts"): it comes before everything in the book, needs no scene and cannot be deleted. Only relationships start there.
    public var start: Bool { get { object.bool("start") ?? false } set { object.setBool("start", newValue ? true : nil) } }
    /// What the event changes, by the id of what it changes (a character, a place, a relationship): only the fields that were filled in.
    public var effects: JSONObject { get { object.object("effects") ?? [:] } set { if newValue.isEmpty { object.removeValue(forKey: "effects") } else { object["effects"] = .object(newValue) } } }
    /// Relationship ids to `starts`, `ends` or an empty text (the event only changes it).
    public var relationships: [String: String] { get { object.stringMap("relationships") ?? [:] } set { object.setStringMap("relationships", newValue) } }
}

public struct EventStoreError: Error, CustomStringConvertible {
    public var description: String
}

/// The real events of a book: `bible/events/<id>.json` (quilland-format.md, section 12), with the free text in `<id>.md`.
/// Where an event sits on the plan is not here but in `plan/canvas.json`. Who takes part is in the event itself (`characters`).
///
/// `events` are the events of the story. The default event "Book starts" is kept apart (`startEvent`), so that what lists, draws or counts the events of the
/// story never meets it; `event(_:)` and `update(_:_:)` know both.
public final class EventStore {
    public let book: URL
    public private(set) var events: [EventRecord] = []
    public private(set) var startEvent: EventRecord?
    public private(set) var problems: [String] = []

    public init(book: URL) {
        self.book = book
        reload()
    }

    private var directory: URL { book.appendingPathComponent("bible/events") }
    private func url(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }
    private func textURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".md") }

    public func reload() {
        events = []
        startEvent = nil
        problems = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() where name.hasSuffix(".json") {
            do {
                let r = EventRecord(object: try JSONParser.parseObject(Data(contentsOf: directory.appendingPathComponent(name))))
                guard r.id != nil, r.title != nil else { problems.append("\(name): no id or title"); continue }
                // (Two events that say they are the default one: the first is, the other is an event of the story.)
                if r.start, startEvent == nil { startEvent = r } else { events.append(r) }
            } catch { problems.append("\(name): \(error)") }
        }
    }

    public func event(_ id: String) -> EventRecord? { events.first { $0.id == id } ?? (startEvent?.id == id ? startEvent : nil) }

    /// Every record, the default event first.
    public var allEvents: [EventRecord] { (startEvent.map { [$0] } ?? []) + events }

    /// The default event: made when the book has none. Returns its id.
    @discardableResult
    public func ensureStartEvent(title: String) throws -> String {
        if let id = startEvent?.id { return id }
        let id = UUID().uuidString.lowercased()
        var record = EventRecord(object: ["id": .string(id), "title": .string(title)])
        record.start = true
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(id))
        startEvent = record
        return id
    }

    private static func before(_ a: EventRecord, _ b: EventRecord) -> Bool {
        switch (a.order, b.order) {
        case let (x?, y?) where x != y: return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return (a.title ?? "").localizedLowercase < (b.title ?? "").localizedLowercase
        }
    }

    /// The scene that decides where an event stands in the book: the first of its scenes.
    private static func firstScene(_ e: EventRecord, _ position: [String: Int]) -> Int? { e.links.keys.compactMap { position[SceneLinks.scene(of: $0)] }.min() }

    /// In the order of the book: by the first scene each event is linked to, and within a scene by the author's own order (then by title); the ones
    /// linked to no scene come last, in the same way.
    public func ordered(sceneOrder: [String]) -> [EventRecord] {
        let position = Dictionary(uniqueKeysWithValues: sceneOrder.enumerated().map { ($1, $0) })
        return events.sorted { a, b in
            switch (Self.firstScene(a, position), Self.firstScene(b, position)) {
            case let (x?, y?): return x != y ? x < y : Self.before(a, b)
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return Self.before(a, b)
            }
        }
    }

    /// The events grouped by the scene that decides their place (nil: linked to no scene), in the order of the book.
    public func groups(sceneOrder: [String]) -> [(scene: String?, events: [EventRecord])] {
        let position = Dictionary(uniqueKeysWithValues: sceneOrder.enumerated().map { ($1, $0) })
        var out: [(scene: String?, events: [EventRecord])] = []
        for e in ordered(sceneOrder: sceneOrder) {
            let scene = Self.firstScene(e, position).map { sceneOrder[$0] }
            if let last = out.last, last.scene == scene { out[out.count - 1].events.append(e) } else { out.append((scene, [e])) }
        }
        return out
    }

    /// Puts the events of one scene in a new order among themselves: they take, in that sequence, the numbers they already had, so each keeps its place and
    /// only the files that change are written. When some of them have no number yet, they are numbered in the new order (100, 200, 300…).
    public func reorder(_ ids: [String]) throws {
        let known = ids.filter { event($0) != nil }
        if known.contains(where: { event($0)?.order == nil }) {
            for (i, id) in known.enumerated() { try update(id) { $0.order = (i + 1) * 100 } }
            return
        }
        let slots = known.compactMap { event($0)?.order }.sorted()
        guard slots.count == known.count else { return }
        for (i, id) in known.enumerated() where event(id)?.order != slots[i] { try update(id) { $0.order = slots[i] } }
    }

    @discardableResult
    public func add(title: String) throws -> String {
        let id = UUID().uuidString.lowercased()
        let record = EventRecord(object: ["id": .string(id), "title": .string(title)])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(id))
        events.append(record)
        CardAges.stamp(id, book: book)
        return id
    }

    public func update(_ id: String, _ change: (inout EventRecord) -> Void) throws {
        if startEvent?.id == id, var r = startEvent {
            change(&r)
            r.start = true   // (it stays the default event whatever the change did)
            guard r != startEvent else { return }
            try AtomicFile.write(JSONWriter.data(r.object), to: url(id))
            startEvent = r
            return
        }
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        var r = events[i]
        change(&r)
        guard r != events[i] else { return }
        try AtomicFile.write(JSONWriter.data(r.object), to: url(id))
        events[i] = r
    }

    public func text(_ id: String) -> String { (try? String(contentsOf: textURL(id), encoding: .utf8)) ?? "" }

    public func setText(_ id: String, _ text: String) throws {
        if text.isEmpty { try? FileManager.default.removeItem(at: textURL(id)) } else { try AtomicFile.write(Data(text.utf8), to: textURL(id)) }
    }

    /// Takes an event out of the book (into the trash folder).
    public func delete(_ id: String) throws {
        if startEvent?.id == id { throw EventStoreError(description: L("The event the book starts with cannot be deleted.")) }
        let fm = FileManager.default
        let stamp = TrashFolder.newName()
        let trash = book.appendingPathComponent(".quilland/trash/\(stamp)/bible/events")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        for file in [url(id), textURL(id)] where fm.fileExists(atPath: file.path) {
            try fm.moveItem(at: file, to: trash.appendingPathComponent(file.lastPathComponent))
        }
        events.removeAll { $0.id == id }
    }
}
