import Foundation

/// The cache of a book (quilland-format.md: `.quilland/cache.sqlite`, ignored by Git).
///
/// Everything in it is derived from the files and can be thrown away: it holds the counts, a full-text
/// index with word endings (SQLite FTS5, trigram tokens), where each name is mentioned, and the backlinks.
/// A file that is missing, damaged or made by another version of the app is simply rebuilt.
public final class BookCache {
    public static let schemaVersion = 1

    public struct Refresh: Equatable, Sendable {
        public var added = 0
        public var changed = 0
        public var removed = 0
        public var unchanged = 0
        public var recovered = false
        public var namesChanged = false
        public var seconds = 0.0
    }

    public struct SearchHit: Equatable, Sendable {
        public enum Kind: String, Sendable { case scene, character }
        public var kind: Kind
        public var id: String
        public var title: String
        public var path: String
        /// How many times the text occurs there (counted for every hit).
        public var occurrences: Int
    }

    public struct Backlink: Equatable, Sendable {
        public enum Why: String, Sendable { case mentionsByName, link, pointOfView }
        public var why: Why
        public var id: String
        public var title: String
        /// For a mention: how many times the name occurs in the scene.
        public var count: Int
    }

    public let folder: URL
    public let databaseURL: URL
    private var db: SQLiteDatabase
    private var matcher: ParadigmMatcher?

    // MARK: Opening

    /// Opens the cache of `folder`, or makes an empty one. Damage is repaired by starting over.
    public init(folder: URL, databaseURL: URL? = nil) throws {
        self.folder = folder
        let url = databaseURL ?? folder.appendingPathComponent(".quilland/cache.sqlite")
        self.databaseURL = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            db = try Self.open(url)
            wasRecovered = false
        } catch {
            Self.removeDatabaseFiles(url)
            db = try Self.open(url)
            wasRecovered = true
        }
    }

    /// True when the old file could not be used and an empty cache was made instead.
    public private(set) var wasRecovered: Bool

    private static func removeDatabaseFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    private static func open(_ url: URL) throws -> SQLiteDatabase {
        let db = try SQLiteDatabase(path: url.path)
        // The cache can always be rebuilt, so it is written without waiting for the disk.
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA synchronous = OFF")
        let exists = (try? db.scalar("SELECT count(*) FROM sqlite_master WHERE name = 'meta'")) ?? 0
        if exists == 0 {
            try createSchema(db)
        } else {
            var version = ""
            try db.prepare("SELECT value FROM meta WHERE key = 'schema'").rows { version = $0.text(0) }
            guard version == String(schemaVersion) else { throw SQLiteDatabase.Failure(message: "another version of the cache") }
            // Reads every page of the structure once; a damaged file fails here and not later.
            try db.prepare("PRAGMA quick_check").rows { if $0.text(0) != "ok" { throw SQLiteDatabase.Failure(message: "damaged cache") } }
        }
        return db
    }

    private static func createSchema(_ db: SQLiteDatabase) throws {
        try db.execute("""
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
            CREATE TABLE files (path TEXT PRIMARY KEY, mtime INTEGER NOT NULL, size INTEGER NOT NULL) WITHOUT ROWID;
            CREATE TABLE scenes (
                rowid INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, base TEXT NOT NULL UNIQUE, dir TEXT NOT NULL,
                title TEXT NOT NULL, status TEXT, words INTEGER NOT NULL, chars INTEGER NOT NULL, chars_ns INTEGER NOT NULL,
                text TEXT NOT NULL);
            CREATE TABLE cards (
                rowid INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, base TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
                aliases TEXT NOT NULL, text TEXT NOT NULL);
            CREATE VIRTUAL TABLE scene_fts USING fts5(folded, tokenize = 'trigram');
            CREATE VIRTUAL TABLE card_fts USING fts5(folded, tokenize = 'trigram');
            CREATE TABLE mentions (scene TEXT NOT NULL, entry TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (scene, entry)) WITHOUT ROWID;
            CREATE INDEX mentions_by_entry ON mentions (entry);
            CREATE TABLE links (source TEXT NOT NULL, target TEXT NOT NULL, kind TEXT NOT NULL, PRIMARY KEY (source, target, kind)) WITHOUT ROWID;
            CREATE INDEX links_by_target ON links (target);
            INSERT INTO meta VALUES ('schema', '\(schemaVersion)');
            """)
    }

    // MARK: Reading the files of a book

    /// A scene or a card as it is on disk: the JSON, and the Markdown beside it.
    private struct Unit {
        enum Kind { case scene, character }
        var kind: Kind
        /// The path of the pair without its extension, relative to the book.
        var base: String
    }

    private struct Stamp: Equatable { var mtime: Int; var size: Int }

    /// Every file that belongs to a scene or a character, with its stamp.
    private func listFiles() -> [String: Stamp] {
        var out: [String: Stamp] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let rootPath = folder.standardizedFileURL.path
        for sub in ["manuscript", "bible/characters"] {
            let start = folder.appendingPathComponent(sub)
            guard let walker = FileManager.default.enumerator(at: start, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker {
                let name = url.lastPathComponent
                guard name.hasSuffix(".json") || name.hasSuffix(".md"), !name.hasSuffix(".notes.json") else { continue }
                if name.hasPrefix("_") { continue } // _part and _chapter files: not in this experiment
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let path = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
                let stamp = Stamp(mtime: Int((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000_000), size: values.fileSize ?? 0)
                out[path] = stamp
            }
        }
        return out
    }

    private static func unit(of path: String) -> Unit? {
        var base = path
        if base.hasSuffix(".json") { base.removeLast(5) } else if base.hasSuffix(".md") { base.removeLast(3) } else { return nil }
        if base.hasPrefix("manuscript/") { return Unit(kind: .scene, base: base) }
        if base.hasPrefix("bible/characters/") { return Unit(kind: .character, base: base) }
        return nil
    }

    // MARK: Plain text

    /// The text of a scene as the reader sees it: no markup, footnotes included, paragraphs on their own lines.
    static func plainText(_ document: Document) -> String {
        func inlines(_ list: [Inline]) -> String {
            var out = ""
            for inline in list {
                switch inline {
                case .run(let run): out += run.text
                case .note(let note): out += " " + note.content.map(\.text).joined() + " "
                case .lineBreak: out += "\n"
                }
            }
            return out
        }
        var lines: [String] = []
        for block in document.blocks {
            switch block {
            case .paragraph(let list), .heading(_, let list): lines.append(inlines(list))
            case .quote(let paragraphs): for p in paragraphs { lines.append(inlines(p)) }
            case .sceneBreak, .fragment, .emptyLine: break
            }
        }
        return lines.joined(separator: "\n")
    }

    /// What a search compares: lowercase, ё as е, stress marks removed.
    static func folded(_ text: String) -> String { Words.fold(text) }

    private func read(_ relative: String) -> Data? { try? Data(contentsOf: folder.appendingPathComponent(relative)) }

    // MARK: Building

    /// Throws everything away and reads all the files again.
    @discardableResult
    public func rebuild() throws -> Refresh {
        let started = Date()
        try db.transaction {
            for table in ["files", "scenes", "cards", "scene_fts", "card_fts", "mentions", "links"] { try db.execute("DELETE FROM \(table)") }
            try db.execute("DELETE FROM meta WHERE key = 'entries'")
        }
        matcher = nil
        var report = try refresh()
        report.seconds = Date().timeIntervalSince(started)
        return report
    }

    /// Looks at every file's stamp (modification time and size) and reads only what changed, appeared or went away.
    @discardableResult
    public func refresh() throws -> Refresh {
        let started = Date()
        var report = Refresh()
        report.recovered = wasRecovered
        let onDisk = listFiles()
        var known: [String: Stamp] = [:]
        try db.prepare("SELECT path, mtime, size FROM files").rows { known[$0.text(0)] = Stamp(mtime: $0.int(1), size: $0.int(2)) }

        var changedUnits = Set<String>()
        var removedUnits = Set<String>()
        for (path, stamp) in onDisk {
            guard let unit = Self.unit(of: path) else { continue }
            if known[path] != stamp { changedUnits.insert(unit.base) }
        }
        for path in known.keys where onDisk[path] == nil {
            if let unit = Self.unit(of: path) { removedUnits.insert(unit.base) }
        }
        // A unit whose pair lost one file is a change, not a removal.
        let remainingBases = Set(onDisk.keys.compactMap { Self.unit(of: $0)?.base })
        for base in removedUnits where remainingBases.contains(base) { changedUnits.insert(base) }
        removedUnits = removedUnits.filter { !remainingBases.contains($0) }

        report.removed = removedUnits.count
        let knownBases = Set(known.keys.compactMap { Self.unit(of: $0)?.base })
        report.added = changedUnits.filter { !knownBases.contains($0) }.count
        report.changed = changedUnits.count - report.added
        report.unchanged = remainingBases.count - changedUnits.count

        try db.transaction {
            for base in removedUnits { try deleteUnit(base) }
            // Characters first: a changed name or alias changes what every scene mentions.
            let characters = changedUnits.filter { $0.hasPrefix("bible/characters/") }
            for base in characters.sorted() { try indexCharacter(base: base) }
            let entriesChanged = try refreshMatcherIfNeeded()
            report.namesChanged = entriesChanged
            let scenes = changedUnits.filter { $0.hasPrefix("manuscript/") }
            for base in scenes.sorted() { try indexScene(base: base) }
            if entriesChanged {
                // Scenes that did not change are matched again from the text kept in the cache.
                try rematchScenes(except: scenes)
            }
            let files = try db.prepare("INSERT OR REPLACE INTO files (path, mtime, size) VALUES (?, ?, ?)")
            for (path, stamp) in onDisk where Self.unit(of: path) != nil && known[path] != stamp {
                try files.run([.text(path), .int(stamp.mtime), .int(stamp.size)])
            }
            let gone = try db.prepare("DELETE FROM files WHERE path = ?")
            for path in known.keys where onDisk[path] == nil { try gone.run([.text(path)]) }
        }
        wasRecovered = false
        report.seconds = Date().timeIntervalSince(started)
        return report
    }

    /// Reads one unit again, because the app itself has just written it: no walk through the folder.
    @discardableResult
    public func update(file url: URL) throws -> Refresh {
        let started = Date()
        var report = Refresh()
        let rootPath = folder.standardizedFileURL.path
        let path = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
        guard let unit = Self.unit(of: path) else { return report }
        try db.transaction {
            switch unit.kind {
            case .character:
                try indexCharacter(base: unit.base)
                report.namesChanged = try refreshMatcherIfNeeded()
                if report.namesChanged { try rematchScenes(except: []) }
            case .scene:
                try indexScene(base: unit.base)
            }
            let files = try db.prepare("INSERT OR REPLACE INTO files (path, mtime, size) VALUES (?, ?, ?)")
            for ext in ["json", "md"] {
                let name = unit.base + "." + ext
                if let values = try? folder.appendingPathComponent(name).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) {
                    try files.run([.text(name), .int(Int((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000_000)), .int(values.fileSize ?? 0)])
                }
            }
        }
        report.changed = 1
        report.seconds = Date().timeIntervalSince(started)
        return report
    }

    private func deleteUnit(_ base: String) throws {
        try db.prepare("DELETE FROM scene_fts WHERE rowid IN (SELECT rowid FROM scenes WHERE base = ?)").run([.text(base)])
        try db.prepare("DELETE FROM card_fts WHERE rowid IN (SELECT rowid FROM cards WHERE base = ?)").run([.text(base)])
        try db.prepare("DELETE FROM mentions WHERE scene IN (SELECT id FROM scenes WHERE base = ?)").run([.text(base)])
        try db.prepare("DELETE FROM links WHERE source IN (SELECT id FROM cards WHERE base = ?)").run([.text(base)])
        try db.prepare("DELETE FROM scenes WHERE base = ?").run([.text(base)])
        try db.prepare("DELETE FROM cards WHERE base = ?").run([.text(base)])
    }

    private func indexScene(base: String) throws {
        try deleteUnit(base)
        guard let jsonData = read(base + ".json"), let object = try? JSONParser.parseObject(jsonData) else { return }
        let record = SceneRecord(object: object)
        guard let id = record.id else { return }
        let source = read(base + ".md").map { String(decoding: $0, as: UTF8.self) } ?? ""
        let document = MarkdownParser.parse(source)
        let counts = TextStats.count(document)
        let text = Self.plainText(document)
        let dir = (base as NSString).deletingLastPathComponent
        try db.prepare("INSERT INTO scenes (id, base, dir, title, status, words, chars, chars_ns, text) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)")
            .run([.text(id), .text(base), .text(dir), .text(record.title ?? ""), record.status.map { .text($0) } ?? .null,
                  .int(counts.words), .int(counts.characters), .int(counts.charactersWithoutSpaces), .text(text)])
        try db.prepare("INSERT INTO scene_fts (rowid, folded) VALUES ((SELECT rowid FROM scenes WHERE id = ?), ?)").run([.text(id), .text(Self.folded(text))])
        try storeMentions(sceneID: id, text: text)
    }

    private func indexCharacter(base: String) throws {
        try deleteUnit(base)
        guard let jsonData = read(base + ".json"), let object = try? JSONParser.parseObject(jsonData) else { return }
        let record = CharacterRecord(object: object)
        guard let id = record.id else { return }
        let free = read(base + ".md").map { String(decoding: $0, as: UTF8.self) } ?? ""
        let text = ([record.name ?? ""] + record.aliases + record.notes + [Self.plainText(MarkdownParser.parse(free))]).joined(separator: "\n")
        try db.prepare("INSERT INTO cards (id, base, name, aliases, text) VALUES (?, ?, ?, ?, ?)")
            .run([.text(id), .text(base), .text(record.name ?? ""), .text(record.aliases.joined(separator: "\n")), .text(text)])
        try db.prepare("INSERT INTO card_fts (rowid, folded) VALUES ((SELECT rowid FROM cards WHERE id = ?), ?)").run([.text(id), .text(Self.folded(text))])
        let link = try db.prepare("INSERT OR IGNORE INTO links (source, target, kind) VALUES (?, ?, ?)")
        for target in record.links.keys { try link.run([.text(id), .text(target.lowercased()), .text("link")]) }
        for target in record.povScenes { try link.run([.text(id), .text(target.lowercased()), .text("pov")]) }
        for target in record.worlds { try link.run([.text(id), .text(target.lowercased()), .text("link")]) }
    }

    // MARK: Names

    private func currentEntries() throws -> [NameEntry] {
        var entries: [NameEntry] = []
        try db.prepare("SELECT id, name, aliases FROM cards ORDER BY id").rows {
            entries.append(NameEntry(id: $0.text(0), name: $0.text(1), aliases: $0.text(2).split(separator: "\n").map(String.init)))
        }
        return entries
    }

    /// Builds the matcher again when the names or aliases of any character are not the ones it was made from.
    private func refreshMatcherIfNeeded() throws -> Bool {
        let entries = try currentEntries()
        let signature = entries.map { ([$0.id, $0.name] + $0.aliases).joined(separator: "|") }.joined(separator: "\n")
        var old = ""
        try db.prepare("SELECT value FROM meta WHERE key = 'entries'").rows { old = $0.text(0) }
        if matcher == nil || signature != old { matcher = ParadigmMatcher(entries: entries) }
        if signature == old { return false }
        try db.prepare("INSERT OR REPLACE INTO meta (key, value) VALUES ('entries', ?)").run([.text(signature)])
        return true
    }

    private func storeMentions(sceneID: String, text: String) throws {
        guard let matcher else { return }
        var counts: [String: Int] = [:]
        for match in matcher.matches(in: text) { counts[match.entry, default: 0] += 1 }
        try db.prepare("DELETE FROM mentions WHERE scene = ?").run([.text(sceneID)])
        let insert = try db.prepare("INSERT INTO mentions (scene, entry, n) VALUES (?, ?, ?)")
        for (entry, n) in counts { try insert.run([.text(sceneID), .text(entry), .int(n)]) }
    }

    private func rematchScenes(except skip: Set<String>) throws {
        var scenes: [(id: String, base: String, text: String)] = []
        try db.prepare("SELECT id, base, text FROM scenes").rows { scenes.append(($0.text(0), $0.text(1), $0.text(2))) }
        for scene in scenes where !skip.contains(scene.base) { try storeMentions(sceneID: scene.id, text: scene.text) }
    }

    // MARK: Questions

    /// A search by letters, so that a word's endings are found: «Анн» finds Анна, Анны, Анне. ё and е are the same,
    /// capitals do not matter. With `wholeWords` the text must be whole words (the endings mode switched off).
    public func search(_ query: String, wholeWords: Bool = false, limit: Int = 200) throws -> [SearchHit] {
        let needle = Self.folded(query.precomposedStringWithCanonicalMapping)
        guard !needle.isEmpty else { return [] }
        let needleBytes = Array(needle.utf8)
        var hits: [SearchHit] = []
        func collect(kind: SearchHit.Kind, table: String, fts: String, titleColumn: String) throws {
            // The index finds the texts that contain the letters; counting them is then a plain scan of those texts.
            let select = "SELECT t.id, t.\(titleColumn), t.base, f.folded, \(wholeWords ? "t.text" : "''") FROM \(table) t JOIN \(fts) f ON f.rowid = t.rowid"
            let sql: String
            var values: [SQLiteDatabase.Value] = []
            if needle.unicodeScalars.count >= 3 {
                sql = select + " WHERE \(fts) MATCH ? ORDER BY t.base"
                values = [.text("folded: \"" + needle.replacingOccurrences(of: "\"", with: "\"\"") + "\"")]
            } else {
                // Shorter than a trigram: every text is looked through (still fast for a book).
                sql = select + " ORDER BY t.base"
            }
            try db.prepare(sql).rows(values) { row in
                let n = wholeWords ? Self.countWholeWords(of: needle, in: row.text(4)) : Self.countOccurrences(of: needleBytes, in: row.text(3))
                if n > 0 { hits.append(SearchHit(kind: kind, id: row.text(0), title: row.text(1), path: row.text(2), occurrences: n)) }
            }
        }
        try collect(kind: .scene, table: "scenes", fts: "scene_fts", titleColumn: "title")
        try collect(kind: .character, table: "cards", fts: "card_fts", titleColumn: "name")
        return Array(hits.prefix(limit))
    }

    /// Occurrences of the bytes of `needle` (UTF-8 is self-synchronising, so a byte match is a character match).
    static func countOccurrences(of needle: [UInt8], in text: String) -> Int {
        var text = text
        return text.withUTF8 { haystack in
            guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
            var count = 0
            var i = 0
            let last = haystack.count - needle.count
            let first = needle[0]
            while i <= last {
                if haystack[i] == first {
                    var j = 1
                    while j < needle.count, haystack[i + j] == needle[j] { j += 1 }
                    if j == needle.count { count += 1; i += needle.count; continue }
                }
                i += 1
            }
            return count
        }
    }

    static func countOccurrences(of needle: String, in text: String) -> Int { countOccurrences(of: Array(needle.utf8), in: text) }

    static func countWholeWords(of needle: String, in text: String) -> Int {
        let wanted = Words.split(needle).map(\.folded)
        guard !wanted.isEmpty else { return 0 }
        let words = Words.split(text).map(\.folded)
        guard words.count >= wanted.count else { return 0 }
        var count = 0
        for i in 0...(words.count - wanted.count) where Array(words[i..<(i + wanted.count)]) == wanted { count += 1 }
        return count
    }

    /// Who points to `id`: scenes that mention the character by name, and characters whose links name it.
    public func backlinks(of id: String) throws -> [Backlink] {
        var out: [Backlink] = []
        try db.prepare("""
            SELECT scenes.id, scenes.title, mentions.n FROM mentions JOIN scenes ON scenes.id = mentions.scene
            WHERE mentions.entry = ? ORDER BY scenes.base
            """).rows([.text(id)]) { out.append(Backlink(why: .mentionsByName, id: $0.text(0), title: $0.text(1), count: $0.int(2))) }
        try db.prepare("""
            SELECT cards.id, cards.name, links.kind FROM links JOIN cards ON cards.id = links.source
            WHERE links.target = ? ORDER BY cards.name
            """).rows([.text(id.lowercased())]) { out.append(Backlink(why: $0.text(2) == "pov" ? .pointOfView : .link, id: $0.text(0), title: $0.text(1), count: 1)) }
        return out
    }

    public func totals() throws -> TextCounts {
        var counts = TextCounts()
        try db.prepare("SELECT sum(words), sum(chars), sum(chars_ns) FROM scenes").rows { counts = TextCounts(words: $0.int(0), characters: $0.int(1), charactersWithoutSpaces: $0.int(2)) }
        return counts
    }

    /// The counts of every folder (chapter, part) with the scenes under it.
    public func countsByFolder(prefix: String = "manuscript") throws -> [String: TextCounts] {
        var out: [String: TextCounts] = [:]
        try db.prepare("SELECT dir, sum(words), sum(chars), sum(chars_ns) FROM scenes GROUP BY dir").rows {
            out[$0.text(0)] = TextCounts(words: $0.int(1), characters: $0.int(2), charactersWithoutSpaces: $0.int(3))
        }
        return out
    }

    /// Folds the journal into the database file (the app does it when it quits).
    public func checkpoint() throws { try db.execute("PRAGMA wal_checkpoint(TRUNCATE)") }

    public func sceneCount() throws -> Int { try db.scalar("SELECT count(*) FROM scenes") }
    public func cardCount() throws -> Int { try db.scalar("SELECT count(*) FROM cards") }
    public func mentionCount(of entry: String) throws -> Int { try db.scalar("SELECT coalesce(sum(n), 0) FROM mentions WHERE entry = ?", [.text(entry)]) }
}
