import Foundation

/// The book's own settings (Book Settings…): title, author, copyright, language, target size and cover in `book.json`, and the words the
/// spell checker accepts in `dictionary.json`. Both are the author's content and go to Git. Unknown keys are kept.
public struct BookSettings: Equatable, Sendable {
    public var title = ""
    public var author = ""
    public var copyright = ""
    public var language = "ru"
    /// The size the book should reach, in characters (nil: none).
    public var targetCharacters: Int?
    /// The file name of the cover in `assets/`.
    public var cover: String?

    public init() {}

    public static func load(book: URL) -> BookSettings {
        var s = BookSettings()
        guard let o = (try? Data(contentsOf: book.appendingPathComponent("book.json"))).flatMap({ try? JSONParser.parseObject($0) }) else { return s }
        s.title = o.string("title") ?? ""
        s.author = o.string("author") ?? ""
        s.copyright = o.string("copyright") ?? ""
        s.language = o.string("language") ?? "ru"
        s.targetCharacters = o.int("target_characters")
        s.cover = o.string("cover")
        return s
    }

    /// Writes the fields into `book.json`; an empty optional field is left out (absent means not set).
    public func save(book: URL) throws {
        let url = book.appendingPathComponent("book.json")
        var o = try JSONParser.parseObject(Data(contentsOf: url))
        o.setString("title", title)
        o.setString("author", author.isEmpty ? nil : author)
        o.setString("copyright", copyright.isEmpty ? nil : copyright)
        o.setString("language", language)
        o.setInt("target_characters", targetCharacters)
        o.setString("cover", cover)
        try AtomicFile.write(JSONWriter.data(o), to: url)
    }

    /// Copies an image into `assets/` and returns its name there (a name already taken gets a number).
    public static func addCover(from source: URL, to book: URL) throws -> String {
        let fm = FileManager.default
        let assets = book.appendingPathComponent("assets")
        try fm.createDirectory(at: assets, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.lowercased()
        var name = "cover.\(ext)"
        var n = 2
        _ = base
        while fm.fileExists(atPath: assets.appendingPathComponent(name).path) { name = "cover-\(n).\(ext)"; n += 1 }
        try fm.copyItem(at: source, to: assets.appendingPathComponent(name))
        return name
    }
}

public enum BookDictionary {
    /// Words are lowercase, in NFC, sorted, with no duplicates (the format's rule).
    public static func normalized(_ words: [String]) -> [String] {
        Array(Set(words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased() }.filter { !$0.isEmpty && !$0.contains(" ") })).sorted()
    }

    public static func load(book: URL) -> [String] {
        guard let o = (try? Data(contentsOf: book.appendingPathComponent("dictionary.json"))).flatMap({ try? JSONParser.parseObject($0) }) else { return [] }
        return normalized(o.strings("words") ?? [])
    }

    public static func save(_ words: [String], book: URL) throws {
        let url = book.appendingPathComponent("dictionary.json")
        var o: JSONObject = (try? JSONParser.parseObject(Data(contentsOf: url))) ?? ["format": .int(1)]
        o.setStrings("words", normalized(words))
        try AtomicFile.write(JSONWriter.data(o), to: url)
    }
}
