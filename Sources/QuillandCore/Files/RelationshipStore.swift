import Foundation

/// A relationship between two or more characters: `bible/relationships/<id>.json` (quilland-format.md, section 13), with the free text in `<id>.md`.
/// The characters' own files never mention it; it is found from here.
public struct RelationshipRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }
    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    /// Free text: "sisters", "he owes her money".
    public var kind: String? { get { object.string("kind") } set { object.setString("kind", newValue) } }
    /// Two or more character ids.
    public var characters: [String] { get { object.strings("characters") ?? [] } set { object.setStrings("characters", newValue) } }
    public var notes: [String] { get { object.strings("notes") ?? [] } set { object.setStrings("notes", newValue) } }
    /// Scene (or event) ids to what the relationship does there.
    public var links: [String: String] { get { object.stringMap("links") ?? [:] } set { object.setStringMap("links", newValue) } }
}

public final class RelationshipStore {
    public let book: URL
    public private(set) var relationships: [RelationshipRecord] = []
    public private(set) var problems: [String] = []

    public init(book: URL) {
        self.book = book
        reload()
    }

    private var directory: URL { book.appendingPathComponent("bible/relationships") }
    private func url(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }
    private func textURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".md") }

    public func reload() {
        relationships = []
        problems = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() where name.hasSuffix(".json") {
            do {
                let r = RelationshipRecord(object: try JSONParser.parseObject(Data(contentsOf: directory.appendingPathComponent(name))))
                if r.id != nil, r.kind != nil, r.characters.count >= 2 { relationships.append(r) } else { problems.append("\(name): needs an id, a kind and two characters") }
            } catch { problems.append("\(name): \(error)") }
        }
    }

    public func relationship(_ id: String) -> RelationshipRecord? { relationships.first { $0.id == id } }

    /// The relationships a character takes part in.
    public func relationships(of character: String) -> [RelationshipRecord] { relationships.filter { $0.characters.contains(character) } }

    @discardableResult
    public func add(characters: [String], kind: String) throws -> String {
        let id = UUID().uuidString.lowercased()
        var record = RelationshipRecord(object: ["id": .string(id)])
        record.kind = kind
        record.characters = characters
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(id))
        relationships.append(record)
        return id
    }

    /// Changes a relationship. Fewer than two characters is refused (the relationship would mean nothing).
    public func update(_ id: String, _ change: (inout RelationshipRecord) -> Void) throws {
        guard let i = relationships.firstIndex(where: { $0.id == id }) else { return }
        var r = relationships[i]
        change(&r)
        guard r != relationships[i], r.characters.count >= 2, !(r.kind ?? "").isEmpty else { return }
        try AtomicFile.write(JSONWriter.data(r.object), to: url(id))
        relationships[i] = r
    }

    public func text(_ id: String) -> String { (try? String(contentsOf: textURL(id), encoding: .utf8)) ?? "" }

    public func setText(_ id: String, _ text: String) throws {
        if text.isEmpty { try? FileManager.default.removeItem(at: textURL(id)) } else { try AtomicFile.write(Data(text.utf8), to: textURL(id)) }
    }

    public func delete(_ id: String) throws {
        let fm = FileManager.default
        let trash = book.appendingPathComponent(".quilland/trash/\(TrashFolder.newName())/bible/relationships")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        for file in [url(id), textURL(id)] where fm.fileExists(atPath: file.path) { try fm.moveItem(at: file, to: trash.appendingPathComponent(file.lastPathComponent)) }
        relationships.removeAll { $0.id == id }
    }

    /// A character was deleted: it leaves its relationships. One that is left with fewer than two characters goes to the trash too.
    /// Returns how many relationships were removed.
    @discardableResult
    public func characterDeleted(_ character: String) throws -> Int {
        var removed = 0
        for r in relationships(of: character) {
            guard let id = r.id else { continue }
            let rest = r.characters.filter { $0 != character }
            if rest.count >= 2 { try update(id) { $0.characters = rest } } else { try delete(id); removed += 1 }
        }
        return removed
    }
}
