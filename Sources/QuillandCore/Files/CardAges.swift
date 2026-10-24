import Foundation

/// When each card was made, kept on this machine (`.quilland/card-ages.json`, never in Git): the cards of characters, places, events and relationships get their time noted
/// when the application creates them. It tells which of two cards that look like one is the new one (the Duplicates tab). A card with no time (made before this, or on
/// another machine) is older than any with one.
public enum CardAges {
    private static func url(_ book: URL) -> URL { book.appendingPathComponent(".quilland/card-ages.json") }

    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    /// The times noted, by card id.
    public static func ages(book: URL) -> [String: Date] {
        guard let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data), let map = o.stringMap("ages") else { return [:] }
        let f = formatter()
        return map.compactMapValues { f.date(from: $0) }
    }

    /// Notes the time a card was made (once: a card already noted keeps its time).
    public static func stamp(_ id: String, book: URL, at date: Date = Date()) {
        var map: [String: String] = [:]
        if let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data) { map = o.stringMap("ages") ?? [:] }
        guard map[id] == nil else { return }
        map[id] = formatter().string(from: date)
        var o: JSONObject = ["format": .int(1)]
        o.setStringMap("ages", map)
        try? FileManager.default.createDirectory(at: url(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: url(book))
    }
}
