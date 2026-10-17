import CryptoKit
import Foundation

/// The file of a research document: copied into the book (`embedded`, in `research/<id>.file/<name>`) or left where it is (`path`, a full path on this machine).
public struct ResearchFile: Equatable, Sendable {
    public var embedded: Bool
    /// The file's own name ("hearings.pdf").
    public var name: String
    public var path: String?
    public var size: Int
    public var hash: String

    public var json: JSONValue {
        var o: JSONObject = ["name": .string(name), "size": .int(size), "hash": .string(hash)]
        if embedded { o["embedded"] = .bool(true) }
        if let path, !embedded { o["path"] = .string(path) }
        return .object(o)
    }

    init?(_ o: JSONObject?) {
        guard let o, let name = o.string("name") else { return nil }
        self.name = name
        embedded = o.bool("embedded") ?? false
        path = o.string("path")
        size = o.int("size") ?? 0
        hash = o.string("hash") ?? ""
    }

    init(embedded: Bool, name: String, path: String?, size: Int, hash: String) {
        self.embedded = embedded; self.name = name; self.path = path; self.size = size; self.hash = hash
    }
}

public struct ResearchRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }
    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var title: String? { get { object.string("title") } set { object.setString("title", newValue) } }
    /// Where the material comes from: a book, an article, an address (free text).
    public var source: String { get { object.string("source") ?? "" } set { object.setString("source", newValue.isEmpty ? nil : newValue) } }
    public var file: ResearchFile? {
        get { ResearchFile(object.object("file")) }
        set { if let newValue { object["file"] = newValue.json } else { object.removeValue(forKey: "file") } }
    }
    /// Ids of what this document is about (the book itself, a scene, a character, a place, an event) to a short remark.
    public var links: [String: String] { get { object.stringMap("links") ?? [:] } set { object.setStringMap("links", newValue) } }
}

public enum ResearchFileState: Equatable, Sendable { case none, present, missing }

/// Research documents: `research/<id>.json`, the typed text in `<id>.md`, an embedded file in `<id>.file/` (quilland-format.md, section 9).
/// A document is an object of its own that owns its links; a scene or a character shows the research linked to it by asking the store.
public final class ResearchStore {
    public let book: URL
    public private(set) var documents: [ResearchRecord] = []
    public private(set) var problems: [String] = []

    /// Above this an embedded file is worth a warning: Git keeps every version of it.
    public static let embedWarningBytes = 20_000_000

    public init(book: URL) {
        self.book = book
        reload()
    }

    private var directory: URL { book.appendingPathComponent("research") }
    private func url(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }
    private func textURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".md") }
    /// An embedded file keeps its own name in a folder of its own, so that it can never meet the document's `<id>.md`.
    private func embeddedFolder(_ id: String) -> URL { directory.appendingPathComponent(id + ".file") }
    private func embeddedURL(_ id: String, name: String) -> URL { embeddedFolder(id).appendingPathComponent(name) }

    public func reload() {
        documents = []
        problems = []
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() where name.hasSuffix(".json") {
            do {
                let r = ResearchRecord(object: try JSONParser.parseObject(Data(contentsOf: directory.appendingPathComponent(name))))
                if r.id != nil, r.title != nil { documents.append(r) } else { problems.append("\(name): no id or title") }
            } catch { problems.append("\(name): \(error)") }
        }
    }

    public func document(_ id: String) -> ResearchRecord? { documents.first { $0.id == id } }

    /// By title.
    public var ordered: [ResearchRecord] { documents.sorted { ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending } }

    /// The documents that mention something in their title, source, remarks or typed text (the case and the accents do not matter).
    public func matching(_ needle: String) -> [ResearchRecord] {
        let n = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return ordered }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return ordered.filter { r in
            let fields = [r.title ?? "", r.source, r.file?.name ?? ""] + Array(r.links.values) + [text(r.id ?? "")]
            return fields.contains { $0.range(of: n, options: options) != nil }
        }
    }

    /// The documents linked to an object (a scene, a character, a place, an event, or the book's own id).
    public func linked(to target: String) -> [ResearchRecord] { ordered.filter { $0.links[target] != nil } }

    @discardableResult
    public func add(title: String) throws -> String {
        let id = UUID().uuidString.lowercased()
        let record = ResearchRecord(object: ["id": .string(id), "title": .string(title)])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(record.object), to: url(id))
        documents.append(record)
        return id
    }

    public func update(_ id: String, _ change: (inout ResearchRecord) -> Void) throws {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        var r = documents[i]
        change(&r)
        guard r != documents[i] else { return }
        try AtomicFile.write(JSONWriter.data(r.object), to: url(id))
        documents[i] = r
    }

    public func text(_ id: String) -> String { (try? String(contentsOf: textURL(id), encoding: .utf8)) ?? "" }

    public func setText(_ id: String, _ text: String) throws {
        if text.isEmpty { try? FileManager.default.removeItem(at: textURL(id)) } else { try AtomicFile.write(Data(text.utf8), to: textURL(id)) }
    }

    // MARK: The file

    public enum FileError: Error, Equatable { case notFound, notAFile }

    static func fingerprint(of file: URL) throws -> (size: Int, hash: String) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            size += chunk.count
        }
        return (size, "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    /// Gives the document a file: a copy in the book (`embed`) or a note of where the file lies. A file it had before is let go (an embedded copy goes to the trash).
    public func attach(_ id: String, file source: URL, embed: Bool) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else { throw FileError.notFound }
        guard !isDirectory.boolValue else { throw FileError.notAFile }
        guard document(id) != nil else { return }
        let print = try Self.fingerprint(of: source)
        try detachFile(id)
        let name = source.lastPathComponent
        if embed {
            try fm.createDirectory(at: embeddedFolder(id), withIntermediateDirectories: true)
            let target = embeddedURL(id, name: name)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: source, to: target)
        }
        let entry = ResearchFile(embedded: embed, name: name, path: embed ? nil : source.standardizedFileURL.path, size: print.size, hash: print.hash)
        try update(id) { $0.file = entry }
    }

    /// Takes the file off the document (the typed text stays); an embedded copy goes to the trash folder.
    public func detachFile(_ id: String) throws {
        guard let file = document(id)?.file else { return }
        if file.embedded { try moveToTrash([embeddedFolder(id)]) }
        try update(id) { $0.file = nil }
    }

    /// Where the file is now: the copy in the book, or the place it was left; nil if the document has no file.
    public func fileURL(_ id: String) -> URL? {
        guard let file = document(id)?.file else { return nil }
        if file.embedded { return embeddedURL(id, name: file.name) }
        return file.path.map { URL(fileURLWithPath: $0) }
    }

    public func fileState(_ id: String) -> ResearchFileState {
        guard let url = fileURL(id) else { return .none }
        return FileManager.default.fileExists(atPath: url.path) ? .present : .missing
    }

    // MARK: Deleting

    private func moveToTrash(_ files: [URL]) throws {
        let fm = FileManager.default
        let present = files.filter { fm.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return }
        let trash = book.appendingPathComponent(".quilland/trash/\(TrashFolder.newName())/research")
        try fm.createDirectory(at: trash, withIntermediateDirectories: true)
        for file in present { try fm.moveItem(at: file, to: trash.appendingPathComponent(file.lastPathComponent)) }
    }

    /// Takes a document out of the book (into the trash folder), with its text and its embedded file. A file left where it was is not touched.
    public func delete(_ id: String) throws {
        var files = [url(id), textURL(id)]
        files.append(embeddedFolder(id))
        try moveToTrash(files)
        documents.removeAll { $0.id == id }
    }
}
