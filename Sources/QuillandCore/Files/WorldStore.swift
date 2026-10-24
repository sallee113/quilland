import Foundation

// MARK: Records (quilland-format.md, sections 10 and 11)

public struct WorldRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }
    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var name: String? { get { object.string("name") } set { object.setString("name", newValue) } }
    public var aliases: [String] { get { object.strings("aliases") ?? [] } set { object.setStrings("aliases", newValue) } }
    public var notes: [String] { get { object.strings("notes") ?? [] } set { object.setStrings("notes", newValue) } }
}

public struct PlaceRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }
    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var name: String? { get { object.string("name") } set { object.setString("name", newValue) } }
    public var world: String? { get { object.string("world") } set { object.setString("world", newValue) } }
    public var parent: String? { get { object.string("parent") } set { object.setString("parent", newValue) } }
    /// A free label; suggested `place`, `people`, `thing`, `term`. Absent means `place`.
    public var type: String { get { object.string("type") ?? "place" } set { object.setString("type", newValue == "place" ? nil : newValue) } }
    public var aliases: [String] { get { object.strings("aliases") ?? [] } set { object.setStrings("aliases", newValue) } }
    public var notes: [String] { get { object.strings("notes") ?? [] } set { object.setStrings("notes", newValue) } }
    /// Scene (or fragment) ids to what happens there.
    public var links: [String: String] { get { object.stringMap("links") ?? [:] } set { object.setStringMap("links", newValue) } }
}

/// The worlds of a book and their entries (places, peoples, things, terms): `bible/worlds/` and `bible/places/`.
/// Membership is a field of the entry (`world`, `parent`), never a folder. Unknown fields are kept; a file that does not parse is reported
/// and never touched.
public final class WorldStore {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    public let book: URL
    public private(set) var worlds: [WorldRecord] = []
    public private(set) var entries: [PlaceRecord] = []
    public private(set) var problems: [String] = []

    public init(book: URL) {
        self.book = book
        reload()
    }

    private var worldsDirectory: URL { book.appendingPathComponent("bible/worlds") }
    private var placesDirectory: URL { book.appendingPathComponent("bible/places") }
    /// The file each record was read from (a file is normally named by its id, but one that is not is written again where it is, not beside it).
    private var worldFiles: [String: URL] = [:]
    private var entryFiles: [String: URL] = [:]

    // MARK: Reading

    public func reload() {
        worlds = []
        entries = []
        problems = []
        func files(_ dir: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted().filter { $0.hasSuffix(".json") }.map { dir.appendingPathComponent($0) }
        }
        worldFiles = [:]
        entryFiles = [:]
        // Two files with one id (an older version wrote a changed world beside the file it came from): the one named by the id is the later one, and is kept.
        func keep(_ id: String, _ url: URL, in map: [String: URL]) -> Bool {
            guard let existing = map[id] else { return true }
            return url.lastPathComponent == id + ".json" && existing.lastPathComponent != id + ".json"
        }
        for url in files(worldsDirectory) {
            do {
                let r = WorldRecord(object: try JSONParser.parseObject(Data(contentsOf: url)))
                guard let id = r.id, r.name != nil else { problems.append("\(url.lastPathComponent): no id or name"); continue }
                if worldFiles[id] != nil {
                    guard keep(id, url, in: worldFiles) else { continue }
                    worlds.removeAll { $0.id == id }
                }
                worlds.append(r)
                worldFiles[id] = url
            } catch { problems.append("\(url.lastPathComponent): \(error)") }
        }
        for url in files(placesDirectory) {
            do {
                let r = PlaceRecord(object: try JSONParser.parseObject(Data(contentsOf: url)))
                guard let id = r.id, r.name != nil, r.world != nil else { problems.append("\(url.lastPathComponent): no id, name or world"); continue }
                if entryFiles[id] != nil {
                    guard keep(id, url, in: entryFiles) else { continue }
                    entries.removeAll { $0.id == id }
                }
                entries.append(r)
                entryFiles[id] = url
            } catch { problems.append("\(url.lastPathComponent): \(error)") }
        }
        sortAll()
        for e in entries {
            if let p = e.parent, let parent = entry(p), parent.world != e.world { problems.append("\(e.name ?? ""): its parent is in another world") }
            if let p = e.parent, entry(p) == nil { problems.append("\(e.name ?? ""): its parent is missing") }
            if hasLoop(e) { problems.append("\(e.name ?? ""): the chain of parents loops") }
        }
    }

    private func sortAll() {
        let key: (String?) -> String = { ($0 ?? "").localizedLowercase }
        worlds.sort { key($0.name) < key($1.name) }
        entries.sort { key($0.name) < key($1.name) }
    }

    public func world(_ id: String) -> WorldRecord? { worlds.first { $0.id == id } }
    public func entry(_ id: String) -> PlaceRecord? { entries.first { $0.id == id } }

    /// The entries directly inside a world (no parent) or inside another entry, in name order.
    public func children(of parent: String?, in world: String) -> [PlaceRecord] {
        entries.filter { $0.world == world && $0.parent == parent }
    }

    /// Every entry below this one.
    public func descendants(of id: String) -> [PlaceRecord] {
        var out: [PlaceRecord] = []
        var queue = entries.filter { $0.parent == id }
        while let next = queue.popLast() {
            out.append(next)
            queue += entries.filter { $0.parent == next.id }
        }
        return out
    }

    private func hasLoop(_ e: PlaceRecord) -> Bool {
        var seen: Set<String> = []
        var current: PlaceRecord? = e
        while let c = current {
            guard let id = c.id, seen.insert(id).inserted else { return true }
            current = c.parent.flatMap { entry($0) }
        }
        return false
    }

    /// The names of the chain from the world down to the entry.
    public func path(of id: String) -> [String] {
        var names: [String] = []
        var current = entry(id)
        var guardCount = 0
        while let c = current, guardCount < 100 {
            names.insert(c.name ?? "", at: 0)
            current = c.parent.flatMap { entry($0) }
            guardCount += 1
        }
        if let w = entry(id)?.world, let world = world(w) { names.insert(world.name ?? "", at: 0) }
        return names
    }

    /// Names and aliases of the worlds and entries, for finding them in a text.
    public var nameEntries: [NameEntry] {
        worlds.compactMap { w in w.id.flatMap { id in w.name.map { NameEntry(id: id, name: $0, aliases: w.aliases, ignoresCapitals: true) } } }
            + entries.compactMap { e in e.id.flatMap { id in e.name.map { NameEntry(id: id, name: $0, aliases: e.aliases, ignoresCapitals: true) } } }
    }

    // MARK: Writing

    private func url(world id: String) -> URL { worldFiles[id] ?? worldsDirectory.appendingPathComponent(id + ".json") }
    private func url(entry id: String) -> URL { entryFiles[id] ?? placesDirectory.appendingPathComponent(id + ".json") }
    private func textURL(_ id: String) -> URL {
        (world(id) != nil ? worldsDirectory : placesDirectory).appendingPathComponent(id + ".md")
    }

    @discardableResult
    public func addWorld(name: String) throws -> String {
        let id = UUID().uuidString.lowercased()
        let record = WorldRecord(object: ["id": .string(id), "name": .string(name)])
        try FileManager.default.createDirectory(at: worldsDirectory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(world: id))
        worlds.append(record)
        sortAll()
        return id
    }

    /// A new entry in a world, inside another entry when `parent` is given (which must be in that world).
    @discardableResult
    public func addEntry(name: String, world: String, parent: String? = nil, type: String = "place") throws -> String {
        guard self.world(world) != nil else { throw Failure(description: L("No such world.")) }
        if let parent { guard entry(parent)?.world == world else { throw Failure(description: L("The parent must be in the same world.")) } }
        let id = UUID().uuidString.lowercased()
        var record = PlaceRecord(object: ["id": .string(id), "name": .string(name), "world": .string(world)])
        record.parent = parent
        record.type = type
        try FileManager.default.createDirectory(at: placesDirectory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(entry: id))
        entries.append(record)
        sortAll()
        CardAges.stamp(id, book: book)
        return id
    }

    public func updateWorld(_ id: String, _ change: (inout WorldRecord) -> Void) throws {
        guard let i = worlds.firstIndex(where: { $0.id == id }) else { return }
        var r = worlds[i]
        change(&r)
        guard r != worlds[i] else { return }
        try AtomicFile.write(JSONWriter.data(r.object), to: url(world: id))
        worlds[i] = r
        sortAll()
    }

    public func updateEntry(_ id: String, _ change: (inout PlaceRecord) -> Void) throws {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var r = entries[i]
        change(&r)
        guard r != entries[i] else { return }
        try AtomicFile.write(JSONWriter.data(r.object), to: url(entry: id))
        entries[i] = r
        sortAll()
    }

    /// Moves an entry (with everything inside it) into a world, under a parent or at the top. A loop (into itself or into what is inside it)
    /// is refused.
    public func move(entry id: String, toWorld world: String, parent: String?) throws {
        guard let moving = entry(id) else { throw Failure(description: L("No such place.")) }
        guard self.world(world) != nil else { throw Failure(description: L("No such world.")) }
        if let parent {
            guard parent != id, !descendants(of: id).contains(where: { $0.id == parent }) else { throw Failure(description: L("A place cannot go inside itself.")) }
            guard entry(parent)?.world == world else { throw Failure(description: L("The parent must be in the same world.")) }
        }
        let below = descendants(of: id).compactMap(\.id)
        try updateEntry(id) { $0.world = world; $0.parent = parent }
        if moving.world != world { for d in below { try updateEntry(d) { $0.world = world } } }
    }

    // MARK: The free text (description and rules): `<id>.md` beside the record

    public func text(_ id: String) -> String { (try? String(contentsOf: textURL(id), encoding: .utf8)) ?? "" }

    public func setText(_ id: String, _ text: String) throws {
        if text.isEmpty { try? FileManager.default.removeItem(at: textURL(id)) } else { try AtomicFile.write(Data(text.utf8), to: textURL(id)) }
    }

    // MARK: Deleting

    private func trashFolder(_ kind: String) throws -> URL {
        let stamp = TrashFolder.newName()
        let dir = book.appendingPathComponent(".quilland/trash/\(stamp)/bible/\(kind)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Takes an entry out of the book (into the trash folder). What was inside it goes up to its parent (or the top of its world).
    public func deleteEntry(_ id: String) throws {
        guard let gone = entry(id) else { return }
        for child in entries.filter({ $0.parent == id }) {
            guard let cid = child.id else { continue }
            try updateEntry(cid) { $0.parent = gone.parent }
        }
        let trash = try trashFolder("places")
        for file in [url(entry: id), textURL(id)] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.moveItem(at: file, to: trash.appendingPathComponent(file.lastPathComponent))
        }
        entries.removeAll { $0.id == id }
    }

    /// A world can be taken out only when it holds nothing, and never the last one.
    public func deleteWorld(_ id: String) throws {
        guard worlds.count > 1 else { throw Failure(description: L("A book keeps at least one world.")) }
        guard !entries.contains(where: { $0.world == id }) else { throw Failure(description: L("Move or delete the places of this world first.")) }
        let trash = try trashFolder("worlds")
        for file in [url(world: id), textURL(id)] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.moveItem(at: file, to: trash.appendingPathComponent(file.lastPathComponent))
        }
        worlds.removeAll { $0.id == id }
    }
}
