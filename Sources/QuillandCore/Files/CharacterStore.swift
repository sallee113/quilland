import Foundation

/// The characters of a book: `bible/characters/<id>.json`, one file each (quilland-format.md, section 7).
/// Unknown fields are kept when a file is written again. A file that does not parse is reported in `problems` and never touched.
public final class CharacterStore {
    public let book: URL
    public private(set) var characters: [CharacterRecord] = []
    public private(set) var problems: [String] = []

    public init(book: URL) {
        self.book = book
        reload()
    }

    private var directory: URL { book.appendingPathComponent("bible/characters") }
    private func url(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }

    public func reload() {
        characters = []
        problems = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() where name.hasSuffix(".json") {
            let file = directory.appendingPathComponent(name)
            do {
                let record = CharacterRecord(object: try JSONParser.parseObject(Data(contentsOf: file)))
                if record.id != nil, record.name != nil { characters.append(record) } else { problems.append("\(name): no id or name") }
            } catch { problems.append("\(name): \(error)") }
        }
        sortCharacters()
    }

    private func sortCharacters() {
        characters.sort { ($0.main ? 0 : 1, ($0.name ?? "").localizedLowercase) < ($1.main ? 0 : 1, ($1.name ?? "").localizedLowercase) }
    }

    public func character(_ id: String) -> CharacterRecord? { characters.first { $0.id == id } }

    /// The characters whose point of view the scene is (its narrators: in the first person, the "I" of the text).
    public func narrators(of scene: String) -> [CharacterRecord] { characters.filter { $0.povScenes.contains(scene) } }

    /// Makes a character a narrator of a scene, or not (the same data as the point of view on the character's card).
    public func setNarrator(_ on: Bool, of scene: String, character id: String) throws {
        try update(id) { r in
            var list = r.povScenes
            if on { if !list.contains(scene) { list.append(scene) } } else { list.removeAll { $0 == scene } }
            r.povScenes = list
        }
    }

    /// The names of the narrators of each scene, for telling the model who "I" is.
    public func narratorNames() -> [String: [String]] {
        var out: [String: [String]] = [:]
        for c in characters { if let name = c.name, !name.isEmpty { for s in c.povScenes { out[s, default: []].append(name) } } }
        return out
    }

    /// More names for a character, from outside its card (the new names events give it: `EventStore.addedAliases`); the application sets it.
    public var extraAliases: (String) -> [String] = { _ in [] }

    /// Names and aliases for finding the characters in a text: the card's and the ones events add.
    public var entries: [NameEntry] {
        characters.compactMap { c in
            c.id.flatMap { id in
                c.name.map { name in
                    let known = Set(([name] + c.aliases).map { $0.lowercased() })
                    return NameEntry(id: id, name: name, aliases: c.aliases + extraAliases(id).filter { !known.contains($0.lowercased()) })
                }
            }
        }
    }

    @discardableResult
    public func add(name: String) throws -> String {
        let id = UUID().uuidString.lowercased()
        let record = CharacterRecord(object: ["id": .string(id), "name": .string(name)])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(id))
        characters.append(record)
        sortCharacters()
        CardAges.stamp(id, book: book)
        return id
    }

    // MARK: The free text (profile, appearance, speech): `<id>.md` beside the record

    private func profileURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".md") }

    public func profile(_ id: String) -> String { (try? String(contentsOf: profileURL(id), encoding: .utf8)) ?? "" }

    /// An empty text removes the file (an absent file means no text).
    public func setProfile(_ id: String, _ text: String) throws {
        if text.isEmpty {
            try? FileManager.default.removeItem(at: profileURL(id))
        } else {
            try AtomicFile.write(Data(text.utf8), to: profileURL(id))
        }
    }

    /// Takes a character out of the book, into `.quilland/trash/<stamp>/` (the record and its text).
    public func delete(_ id: String) throws {
        let fm = FileManager.default
        let stamp = TrashFolder.newName()
        let trash = book.appendingPathComponent(".quilland/trash/\(stamp)/bible/characters")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        for url in [self.url(id), profileURL(id)] where fm.fileExists(atPath: url.path) {
            try fm.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
        characters.removeAll { $0.id == id }
    }

    public func update(_ id: String, _ change: (inout CharacterRecord) -> Void) throws {
        guard let index = characters.firstIndex(where: { $0.id == id }) else { return }
        var record = characters[index]
        change(&record)
        guard record != characters[index] else { return }
        try AtomicFile.write(JSONWriter.data(record.object), to: url(id))
        characters[index] = record
        sortCharacters()
    }
}
