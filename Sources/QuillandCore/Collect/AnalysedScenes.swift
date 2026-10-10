import Foundation

/// Which scenes the model has already read for Collect from the Book, and the text they had then (a fingerprint): kept on this machine in
/// `.quilland/ai-analysed.json`, never in the book's own files. A scene that is still the same is not read again unless the author asks.
public enum AnalysedScenes {
    static func url(_ book: URL) -> URL { book.appendingPathComponent(".quilland/ai-analysed.json") }

    public static func load(book: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data) else { return [:] }
        return o.stringMap("scenes") ?? [:]
    }

    public static func remember(_ new: [String: String], book: URL) {
        guard !new.isEmpty else { return }
        var all = load(book: book)
        for (k, v) in new { all[k] = v }
        var o: JSONObject = ["format": .int(1)]
        o.setStringMap("scenes", all)
        try? FileManager.default.createDirectory(at: url(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: url(book))
    }

    public static func forget(book: URL) { try? FileManager.default.removeItem(at: url(book)) }
}
