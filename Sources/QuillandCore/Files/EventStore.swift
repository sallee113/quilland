import Foundation

public struct EventRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }
    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var title: String? { get { object.string("title") } set { object.setString("title", newValue) } }
    /// Free text ("spring, year 214", "several years later"); never read as a date.
    public var date: String { get { object.string("date") ?? "" } set { object.setString("date", newValue.isEmpty ? nil : newValue) } }
    public var notes: [String] { get { object.strings("notes") ?? [] } set { object.setStrings("notes", newValue) } }
    /// World entry ids to what happens there.
    public var places: [String: String] { get { object.stringMap("places") ?? [:] } set { object.setStringMap("places", newValue) } }
    /// Scene (or fragment) ids to what happens there.
    public var links: [String: String] { get { object.stringMap("links") ?? [:] } set { object.setStringMap("links", newValue) } }
}

/// The real events of a book: `bible/events/<id>.json` (quilland-format.md, section 12), with the free text in `<id>.md`.
/// Where an event sits on the plan is not here but in `plan/canvas.json`; who takes part is in the characters' files.
public final class EventStore {
    public let book: URL
    public private(set) var events: [EventRecord] = []
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
        problems = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() where name.hasSuffix(".json") {
            do {
                let r = EventRecord(object: try JSONParser.parseObject(Data(contentsOf: directory.appendingPathComponent(name))))
                if r.id != nil, r.title != nil { events.append(r) } else { problems.append("\(name): no id or title") }
            } catch { problems.append("\(name): \(error)") }
        }
    }

    public func event(_ id: String) -> EventRecord? { events.first { $0.id == id } }

    /// In the order of the book: by the first scene each event is linked to; the ones linked to no scene come last, by title.
    public func ordered(sceneOrder: [String]) -> [EventRecord] {
        let position = Dictionary(uniqueKeysWithValues: sceneOrder.enumerated().map { ($1, $0) })
        func first(_ e: EventRecord) -> Int? { e.links.keys.compactMap { position[$0] }.min() }
        return events.sorted { a, b in
            switch (first(a), first(b)) {
            case let (x?, y?): return x != y ? x < y : (a.title ?? "").localizedLowercase < (b.title ?? "").localizedLowercase
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return (a.title ?? "").localizedLowercase < (b.title ?? "").localizedLowercase
            }
        }
    }

    @discardableResult
    public func add(title: String) throws -> String {
        let id = UUID().uuidString.lowercased()
        let record = EventRecord(object: ["id": .string(id), "title": .string(title)])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(id))
        events.append(record)
        return id
    }

    public func update(_ id: String, _ change: (inout EventRecord) -> Void) throws {
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
