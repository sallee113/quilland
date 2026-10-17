import Foundation

/// Things in the book's data that need the author's decision: links that point to nothing (a scene that was merged away, a card whose line is gone),
/// and data files that cannot be read. Found by looking at the files themselves, so it works on a book that does not open cleanly.
public struct LooseEnd: Equatable, Sendable {
    public enum Kind: String, Sendable { case missingLink, damagedFile }
    public var kind: Kind
    /// The file, relative to the book (`bible/characters/<id>.json`).
    public var file: String
    /// What owns the link: a character's name, an event's title… (the file name for a damaged file).
    public var owner: String
    /// `links`, `pov_scenes`, `places`; empty for a damaged file.
    public var field: String
    /// The id that points to nothing.
    public var target: String
    public var message: String

    /// What "Keep it" is remembered by.
    public var key: String { "\(kind.rawValue)|\(file)|\(field)|\(target)" }
}

public struct LooseEnds {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
        public init(description: String) { self.description = description }
    }

    public let book: URL
    public init(book: URL) { self.book = book }

    private static let dataFolders = ["manuscript", "bible", "plan"]
    private static let rootFiles = ["book.json", "dictionary.json", "export.json", "reminders.json"]
    /// The link fields of an owner: a map of ids to text, or a list of ids; `places` point to world entries.
    static let mapFields = ["links", "places"]
    static let listFields = ["pov_scenes", "worlds", "characters"]

    private func files() -> [String] {
        let fm = FileManager.default
        var out: [String] = Self.rootFiles.filter { fm.fileExists(atPath: book.appendingPathComponent($0).path) }
        for folder in Self.dataFolders {
            guard let walker = fm.enumerator(at: book.appendingPathComponent(folder), includingPropertiesForKeys: nil) else { continue }
            let base = book.resolvingSymlinksInPath().path
            for case let url as URL in walker where url.pathExtension == "json" {
                let path = url.resolvingSymlinksInPath().path
                if path.hasPrefix(base + "/") { out.append(String(path.dropFirst(base.count + 1))) }
            }
        }
        return out.sorted()
    }

    /// Everything wrong, in the order of the files. Damaged files are listed once; a damaged file's links cannot be read, so it has none.
    public func scan(ignoring ignored: Set<String> = []) -> [LooseEnd] {
        let names = files()
        var parsed: [String: JSONObject] = [:]
        var out: [LooseEnd] = []
        for name in names {
            let url = book.appendingPathComponent(name)
            do { parsed[name] = try JSONParser.parseObject(Data(contentsOf: url)) } catch {
                out.append(LooseEnd(kind: .damagedFile, file: name, owner: (name as NSString).lastPathComponent, field: "", target: "", message: "\(error)"))
            }
        }
        var ids = Set<String>()
        for object in parsed.values { if let id = object.string("id") { ids.insert(id) } }
        // Lines of the plan have ids too; they live in `canvas.json`.
        // A file that cannot be read still exists; the ones named by their id are not "missing" for the links that point to them.
        for out in out where out.kind == .damagedFile { ids.insert(((out.file as NSString).lastPathComponent as NSString).deletingPathExtension) }
        for lane in (parsed["plan/canvas.json"]?.objects("lanes") ?? []) { if let id = lane.string("id") { ids.insert(id) } }
        for name in names {
            guard let object = parsed[name], !Self.rootFiles.contains(name) else { continue }
            let owner = object.string("name") ?? object.string("title") ?? (name as NSString).lastPathComponent
            for field in Self.mapFields {
                for target in (object.stringMap(field) ?? [:]).keys.sorted() where !ids.contains(target) {
                    out.append(LooseEnd(kind: .missingLink, file: name, owner: owner, field: field, target: target, message: ""))
                }
            }
            for field in Self.listFields {
                for target in (object.strings(field) ?? []) where !ids.contains(target) {
                    out.append(LooseEnd(kind: .missingLink, file: name, owner: owner, field: field, target: target, message: ""))
                }
            }
            if name == "plan/canvas.json" {
                for entry in object.objects("entries") ?? [] {
                    if let event = entry.string("event"), !ids.contains(event) { out.append(LooseEnd(kind: .missingLink, file: name, owner: L("The plan"), field: "entries", target: event, message: "")) }
                }
            }
        }
        return out.filter { !ignored.contains($0.key) }
    }

    private func edit(_ file: String, _ change: (inout JSONObject) throws -> Void) throws {
        let url = book.appendingPathComponent(file)
        var object = try JSONParser.parseObject(Data(contentsOf: url))
        try change(&object)
        try AtomicFile.write(JSONWriter.data(object), to: url)
    }

    /// Takes the link out of its owner. Everything else in the file stays.
    public func remove(_ end: LooseEnd) throws {
        guard end.kind == .missingLink else { return }
        try edit(end.file) { o in
            if Self.mapFields.contains(end.field) { var map = o.stringMap(end.field) ?? [:]; map.removeValue(forKey: end.target); o.setStringMap(end.field, map) }
            else if Self.listFields.contains(end.field) { o.setStrings(end.field, (o.strings(end.field) ?? []).filter { $0 != end.target }) }
            else if end.field == "entries" { o["entries"] = .array((o.objects("entries") ?? []).filter { $0.string("event") != end.target }.map { .object($0) }) }
        }
    }

    /// Points the link at another thing; its text stays. If the owner already links to the new one, the old link just goes.
    public func repoint(_ end: LooseEnd, to new: String) throws {
        guard end.kind == .missingLink, end.field != "entries" else { return }
        try edit(end.file) { o in
            if Self.mapFields.contains(end.field) {
                var map = o.stringMap(end.field) ?? [:]
                let text = map.removeValue(forKey: end.target)
                if map[new] == nil { map[new] = text ?? "" }
                o.setStringMap(end.field, map)
            } else {
                var list = (o.strings(end.field) ?? []).filter { $0 != end.target }
                if !list.contains(new) { list.append(new) }
                o.setStrings(end.field, list)
            }
        }
    }

    /// Puts back the newest version of a damaged file that can still be read, from the snapshots. The damaged file is kept beside it as `<name>.damaged`.
    /// Returns the snapshot it came from.
    @discardableResult
    public func restoreDamaged(_ end: LooseEnd) throws -> SnapshotStore.Info {
        guard end.kind == .damagedFile else { throw Failure(description: "not a damaged file") }
        let snapshots = SnapshotStore(bookFolder: book)
        for info in snapshots.list().reversed() {
            let candidate = snapshots.filesFolder(info).appendingPathComponent(end.file)
            guard let data = try? Data(contentsOf: candidate), (try? JSONParser.parseObject(data)) != nil else { continue }
            let target = book.appendingPathComponent(end.file)
            let keep = target.appendingPathExtension("damaged")
            try? FileManager.default.removeItem(at: keep)
            try FileManager.default.moveItem(at: target, to: keep)
            try AtomicFile.write(data, to: target)
            return info
        }
        throw Failure(description: L("No snapshot has a readable copy of this file."))
    }

    // MARK: What the author chose to keep

    static func url(_ book: URL) -> URL { book.appendingPathComponent(".quilland/looseends.json") }

    public static func ignored(book: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data) else { return [] }
        return Set(o.strings("ignored") ?? [])
    }

    public static func ignore(_ end: LooseEnd, book: URL) {
        var keys = ignored(book: book)
        keys.insert(end.key)
        var o: JSONObject = ["format": .int(1)]
        o["ignored"] = .array(keys.sorted().map { .string($0) })
        try? FileManager.default.createDirectory(at: url(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: url(book))
    }

    public static func forgetIgnored(book: URL) { try? FileManager.default.removeItem(at: url(book)) }
}
