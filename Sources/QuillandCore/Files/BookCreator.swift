import Foundation

/// What the New Book dialog asks.
public struct NewBookRequest: Sendable {
    public var title: String
    public var author: String
    /// `en` (the default), `ru` or `fr` (the language of the book: quotes, checkers, the names of what is created).
    public var language: String
    /// The folder in which the book's folder is made.
    public var parentFolder: URL
    public init(title: String, author: String = "", language: String = "en", parentFolder: URL) {
        self.title = title
        self.author = author
        self.language = language
        self.parentFolder = parentFolder
    }
}

/// Makes a new book: a folder with what every book has (quilland-format.md, sections 3, 16, 19 and the spec's "Starting"):
/// `book.json`, a first chapter with an empty first scene, a default world, the starter kind "Belongings" and a `.gitignore`.
public enum BookCreator {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    struct Words {
        var chapter, scene, world, kindOne, kindMany, kindDescription, owner, keptAt, seenAt: String
        static func words(for language: String) -> Words {
            if language == "ru" {
                return Words(chapter: "Глава 1", scene: "Сцена 1", world: "Мир", kindOne: "Вещь", kindMany: "Вещи",
                             kindDescription: "Вещи: предметы, которые люди носят, хранят или теряют.", owner: "Владелец", keptAt: "Хранится", seenAt: "Появляется")
            }
            if language == "fr" {
                return Words(chapter: "Chapitre 1", scene: "Scène 1", world: "Monde", kindOne: "Objet", kindMany: "Objets",
                             kindDescription: "Objets : choses que les gens portent, gardent ou perdent.", owner: "Propriétaire", keptAt: "Conservé à", seenAt: "Apparaît à")
            }
            return Words(chapter: "Chapter 1", scene: "Scene 1", world: "World", kindOne: "Belonging", kindMany: "Belongings",
                         kindDescription: "Belongings: things that people carry, keep or lose.", owner: "Owner", keptAt: "Kept at", seenAt: "Seen at")
        }
    }

    /// A folder name from a title: no slashes or colons, no dots at the start.
    static func folderName(for title: String) -> String {
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        return name.isEmpty ? "New Book" : name
    }

    static func uuid() -> JSONValue { .string(UUID().uuidString.lowercased()) }

    /// Returns the new book's folder. Never writes into a folder that exists: a name taken gets " 2", " 3"…
    @discardableResult
    public static func create(_ request: NewBookRequest) throws -> URL {
        let fm = FileManager.default
        guard !request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure(description: L("A book needs a title.")) }
        let base = folderName(for: request.title)
        var folder = request.parentFolder.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: folder.path) { folder = request.parentFolder.appendingPathComponent("\(base) \(n)"); n += 1 }
        let words = Words.words(for: request.language)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        func write(_ path: String, _ object: JSONObject) throws {
            let url = folder.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AtomicFile.write(JSONWriter.data(object), to: url)
        }
        var book: JSONObject = ["format": .int(1), "id": uuid(), "language": .string(request.language), "title": .string(request.title)]
        if !request.author.isEmpty { book["author"] = .string(request.author) }
        try write("book.json", book)
        try AtomicFile.write(Data(".quilland/\n".utf8), to: folder.appendingPathComponent(".gitignore"))

        // The first chapter and its empty first scene (a chapter with no part is allowed).
        try write("manuscript/001-chapter/_chapter.json", ["id": uuid(), "title": .string(words.chapter)])
        try write("manuscript/001-chapter/001-scene.json", ["id": uuid(), "status": .string("idea"), "title": .string(words.scene)])
        try AtomicFile.write(Data(), to: folder.appendingPathComponent("manuscript/001-chapter/001-scene.md"))

        // The default world, so that a place can be made without setting one up.
        try write("bible/worlds/\(UUID().uuidString.lowercased()).json", ["id": uuid(), "name": .string(words.world)])

        // The starter kind (format, section 19).
        func field(_ name: String, _ kind: String, many: Bool = false) -> JSONValue {
            var f: JSONObject = ["id": uuid(), "name": .string(name), "type": .string("link"), "to": .array([.string(kind)])]
            if many { f["many"] = .bool(true) }
            return .object(f)
        }
        let kind: JSONObject = [
            "color": .string("teal"),
            "description": .string(words.kindDescription),
            "fields": .array([field(words.keptAt, "place"), field(words.owner, "character"), field(words.seenAt, "event", many: true)]),
            "findable": .bool(true),
            "hidden": .bool(false),
            "icon": .string("bag"),
            "id": uuid(),
            "name": .object(["many": .string(words.kindMany), "one": .string(words.kindOne)]),
        ]
        try write("bible/kinds/\(UUID().uuidString.lowercased()).json", kind)
        return folder
    }
}
