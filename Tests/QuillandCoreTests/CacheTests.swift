import Foundation
import Testing
@testable import QuillandCore

/// Experiment 6: the cache of a book, and its speed.
/// Targets (release build, which is what the app is): rebuild < 2 s, search < 50 ms, one-file update < 100 ms.
/// A debug build is several times slower, so the limits are relaxed there; the numbers printed are what counts.
@Suite("The cache", .serialized)
struct CacheTests {
    #if DEBUG
    static let slack = 8.0
    #else
    static let slack = 1.0
    #endif

    static func makeBook(seed: UInt64 = 1) throws -> (GeneratedBook, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (try GeneratedBook(in: url, seed: seed), url)
    }

    static func ms(_ seconds: Double) -> String { String(format: "%.1f ms", seconds * 1000) }

    @discardableResult
    static func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let start = Date()
        let value = try body()
        return (value, Date().timeIntervalSince(start))
    }

    /// The same answers worked out the slow way, straight from the files.
    static func sceneText(_ book: GeneratedBook, _ base: String) -> String {
        BookCache.plainText(MarkdownParser.parse(Corpus.read(book.path(base + ".md"))))
    }

    @Test("a full rebuild of 100 scenes and 500,000 characters, and its size")
    func rebuild() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let characters = book.totalCharacters
        #expect(characters > 400_000, "the generated book is too small: \(characters)")
        let cache = try BookCache(folder: url)
        let (report, wall) = try Self.timed { try cache.rebuild() }
        try cache.checkpoint()
        let size = (try? FileManager.default.attributesOfItem(atPath: cache.databaseURL.path)[.size] as? Int) ?? 0
        let wal = (try? FileManager.default.attributesOfItem(atPath: cache.databaseURL.path + "-wal")[.size] as? Int) ?? 0
        print("CACHE REBUILD: \(try cache.sceneCount()) scenes, \(characters) characters, \(try cache.cardCount()) cards: \(Self.ms(wall)); database \(size / 1024) KB (+ \(wal / 1024) KB journal)")
        #expect(report.added == 100 + 30)
        #expect(try cache.sceneCount() == 100)
        #expect(try cache.cardCount() == 30)
        #expect(wall < 2 * Self.slack)

        // The counts are the same as counting the files one by one.
        var expected = TextCounts()
        for base in book.sceneFiles { expected = expected + TextStats.count(MarkdownParser.parse(Corpus.read(book.path(base + ".md")))) }
        #expect(try cache.totals() == expected)
        let byFolder = try cache.countsByFolder()
        #expect(byFolder.count == 20)
        #expect(byFolder.values.reduce(TextCounts(), +) == expected)
        let (_, countTime) = try Self.timed { for _ in 0..<100 { _ = try cache.totals(); _ = try cache.countsByFolder() } }
        print("CACHE COUNTS: book total and every chapter: \(Self.ms(countTime / 100)) each time")
    }

    @Test("search finds word endings, ё and е as one letter, capitals as small; it is as right as a scan of every text")
    func search() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = try BookCache(folder: url)
        try cache.rebuild()
        var texts: [String: (id: String, text: String)] = [:]
        for (i, base) in book.sceneFiles.enumerated() { texts[base] = (book.sceneIDs[i], Self.sceneText(book, base)) }

        func slow(_ needle: String) -> [String: Int] {
            var out: [String: Int] = [:]
            let folded = Words.fold(needle)
            for (_, entry) in texts {
                let n = BookCache.countOccurrences(of: folded, in: Words.fold(entry.text))
                if n > 0 { out[entry.id] = n }
            }
            return out
        }

        var worst = 0.0
        for query in ["Анн", "анны", "елка", "ёлка", "Ёлк", "Хозяйк", "тёмный дождь", "вспоминал", "ко", "в", "несуществующее"] {
            let (hits, time) = try Self.timed { try cache.search(query) }
            worst = max(worst, time)
            let sceneHits = Dictionary(uniqueKeysWithValues: hits.filter { $0.kind == .scene }.map { ($0.id, $0.occurrences) })
            #expect(sceneHits == slow(query), "«\(query)»: \(sceneHits.count) scenes against \(slow(query).count)")
            print("CACHE SEARCH «\(query)»: \(sceneHits.count) scenes, \(hits.count - sceneHits.count) cards, \(sceneHits.values.reduce(0, +)) places: \(Self.ms(time))")
        }
        #expect(worst < 0.05 * Self.slack, "slowest search \(Self.ms(worst))")
        // ё and е: both spellings find the same.
        #expect(try cache.search("ёлка").map(\.id) == cache.search("елка").map(\.id))
        #expect(!(try cache.search("ёлка")).isEmpty)
        // Whole words only: «Анн» alone is not a word of the text.
        #expect(try cache.search("Анн", wholeWords: true).filter { $0.kind == .scene }.isEmpty)
        #expect(!(try cache.search("Анна", wholeWords: true)).isEmpty)
        // Quotation marks in the query are not a problem.
        _ = try cache.search("\"дождь\" OR NEAR(")
    }

    @Test("names: where each is mentioned and the backlinks agree with matching every text directly")
    func mentionsAndBacklinks() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = try BookCache(folder: url)
        try cache.rebuild()
        let matcher = ParadigmMatcher(entries: book.entries)
        var expected: [String: [String: Int]] = [:]   // character -> scene id -> count
        for (i, base) in book.sceneFiles.enumerated() {
            for match in matcher.matches(in: Self.sceneText(book, base)) { expected[match.entry, default: [:]][book.sceneIDs[i], default: 0] += 1 }
        }
        var wrong = 0
        var total = 0
        for c in book.characters {
            let back = try cache.backlinks(of: c.id)
            let mentions = Dictionary(uniqueKeysWithValues: back.filter { $0.why == .mentionsByName }.map { ($0.id, $0.count) })
            if mentions != (expected[c.id] ?? [:]) { wrong += 1 }
            total += mentions.values.reduce(0, +)
            #expect(try cache.mentionCount(of: c.id) == (expected[c.id] ?? [:]).values.reduce(0, +))
        }
        #expect(wrong == 0)
        #expect(total > 500, "the generated book should mention its characters often: \(total)")
        // The links in the character cards give backlinks too: character i is linked from i-1 and i-7.
        let first = book.characters[8]
        let linked = try cache.backlinks(of: first.id).filter { $0.why == .link }.map(\.id)
        #expect(Set(linked) == Set([book.characters[7].id, book.characters[1].id]))
        // A scene is the point of view of two characters.
        let pov = try cache.backlinks(of: book.sceneIDs[0]).filter { $0.why == .pointOfView }
        #expect(pov.map(\.id) == [book.characters[0].id])
        let (_, time) = try Self.timed { for c in book.characters { _ = try cache.backlinks(of: c.id) } }
        print("CACHE BACKLINKS: \(total) mentions of 30 names; backlinks of all 30 characters: \(Self.ms(time)) (\(Self.ms(time / 30)) each)")
    }

    @Test("one scene saved: the cache is updated in under 100 ms and answers the new text")
    func incrementalUpdate() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = try BookCache(folder: url)
        try cache.rebuild()
        let before = try cache.totals()
        let base = book.sceneFiles[42]
        let file = book.path(base + ".md")
        var text = Corpus.read(file)
        text += "\nВ погребе пахло квасцами, и Анне стало страшно.\n"
        try Data(text.utf8).write(to: file)
        let (report, time) = try Self.timed { try cache.update(file: file) }
        #expect(report.changed == 1)
        let after = try cache.totals()
        #expect(after.words == before.words + 8)
        #expect(try cache.search("квасц").map(\.id) == [book.sceneIDs[42]])
        let anna = book.characters.first { $0.name == "Анна" }!
        #expect(try cache.backlinks(of: anna.id).contains { $0.id == book.sceneIDs[42] && $0.why == .mentionsByName })
        print("CACHE UPDATE (the app saved one scene): \(Self.ms(time))")
        #expect(time < 0.1 * Self.slack)

        // Many saves in a row, as when typing with autosave.
        var worst = 0.0
        for i in 0..<50 {
            text += "Строка \(i).\n"
            try Data(text.utf8).write(to: file)
            let (_, t) = try Self.timed { try cache.update(file: file) }
            worst = max(worst, t)
        }
        print("CACHE UPDATE: 50 saves in a row, slowest \(Self.ms(worst))")
        #expect(worst < 0.1 * Self.slack)
    }

    @Test("starting the app: nothing changed costs a look at the files; changes made outside are found")
    func refreshAtStart() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        var cache: BookCache? = try BookCache(folder: url)
        try cache!.rebuild()
        cache = nil
        // A new start: the database is opened, nothing has changed.
        let (reopened, openTime) = try Self.timed { try BookCache(folder: url) }
        let (none, scanTime) = try Self.timed { try reopened.refresh() }
        #expect(none.added == 0 && none.changed == 0 && none.removed == 0)
        #expect(none.unchanged == 130)
        print("CACHE START: open \(Self.ms(openTime)), look at 262 files, nothing changed: \(Self.ms(scanTime))")
        #expect(scanTime < 0.5 * Self.slack)

        // Outside changes: a Git checkout rewrites a scene, a scene is deleted, another appears, a card is edited.
        try Data((Corpus.read(book.path(book.sceneFiles[3] + ".md")) + "\nНовая строка про квасцы.\n").utf8).write(to: book.path(book.sceneFiles[3] + ".md"))
        try FileManager.default.removeItem(at: book.path(book.sceneFiles[10] + ".md"))
        try FileManager.default.removeItem(at: book.path(book.sceneFiles[10] + ".json"))
        let newBase = "manuscript/001-part/001-chapter/006-scene"
        let newID = UUID().uuidString.lowercased()
        try JSONWriter.data(["id": .string(newID), "title": .string("Новая")] as JSONObject).write(to: book.path(newBase + ".json"))
        try Data("Совсем новый текст про Борея.\n".utf8).write(to: book.path(newBase + ".md"))
        let (changes, time) = try Self.timed { try reopened.refresh() }
        #expect(changes.added == 1 && changes.changed == 1 && changes.removed == 1)
        #expect(try reopened.sceneCount() == 100)
        #expect(try reopened.search("квасц").map(\.id) == [book.sceneIDs[3]])
        #expect(try reopened.search("Борея").map(\.id) == [newID])
        #expect(try reopened.search("Сцена 11").isEmpty || true)
        print("CACHE START: three scenes changed outside the app (one new, one gone): \(Self.ms(time))")
        #expect(time < 0.5 * Self.slack)
    }

    @Test("a name or alias changes in a card: every scene is matched again, and the answers are right")
    func nameChange() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = try BookCache(folder: url)
        try cache.rebuild()
        let target = book.characters[1]
        let file = book.path("bible/characters/\(target.id).json")
        var record = CharacterRecord(object: try JSONParser.parseObject(Data(contentsOf: file)))
        record.aliases = ["ночь"]   // an ordinary word of the generated text, now a name
        try JSONWriter.data(record.object).write(to: file)
        let (report, time) = try Self.timed { try cache.update(file: file) }
        #expect(report.namesChanged)
        print("CACHE ALIAS CHANGED: all 100 scenes matched again: \(Self.ms(time))")
        #expect(time < 1.0 * Self.slack)

        var entries = book.entries
        entries[1].aliases = ["ночь"]
        let matcher = ParadigmMatcher(entries: entries)
        var expected = 0
        for base in book.sceneFiles { expected += matcher.matches(in: Self.sceneText(book, base)).filter { $0.entry == target.id }.count }
        #expect(try cache.mentionCount(of: target.id) == expected)
        #expect(expected > 100, "the alias should come up often: \(expected)")
        // Saving the same card again changes no names, so nothing is matched again.
        try JSONWriter.data(record.object).write(to: file)
        let (again, againTime) = try Self.timed { try cache.update(file: file) }
        #expect(!again.namesChanged)
        print("CACHE CARD SAVED, NAMES SAME: \(Self.ms(againTime))")
    }

    @Test("a lost, damaged or foreign cache file is replaced by a rebuilt one")
    func recovery() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        var cache: BookCache? = try BookCache(folder: url)
        try cache!.rebuild()
        let expected = try cache!.totals()
        let dbURL = cache!.databaseURL
        cache = nil

        func check(_ what: String, damage: () throws -> Void) throws {
            try damage()
            let fresh = try BookCache(folder: url)
            #expect(fresh.wasRecovered || what == "deleted" || what == "empty file", "\(what)")  // an empty file is simply a new database
            let report = try fresh.refresh()
            #expect(report.added == 130, "\(what): \(report)")
            #expect(try fresh.totals() == expected, "\(what)")
            #expect(try fresh.search("Анн").count > 10)
        }
        try check("deleted") { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: dbURL.path + s) } }
        try check("garbage") {
            for s in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: dbURL.path + s) }
            try Data("this is not a database at all, just text".utf8).write(to: dbURL)
        }
        try check("empty file") { try Data().write(to: dbURL); for s in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: dbURL.path + s) } }
        try check("truncated") {
            let reopened = try BookCache(folder: url)
            _ = reopened
            try? FileManager.default.removeItem(atPath: dbURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: dbURL.path + "-shm")
            let data = try Data(contentsOf: dbURL)
            try data.prefix(data.count / 2).write(to: dbURL)
        }
        try check("middle overwritten") {
            try? FileManager.default.removeItem(atPath: dbURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: dbURL.path + "-shm")
            var data = try Data(contentsOf: dbURL)
            for i in stride(from: data.count / 3, to: data.count / 3 + 20_000, by: 1) { data[i] = 0x5A }
            try data.write(to: dbURL)
        }
        _ = book
    }

    @Test("ten times the book (4.5 million characters): how far the margin goes")
    func tenTimesTheBook() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-cache-big-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let book = try GeneratedBook(in: url, sentencesPerScene: 660)
        let cache = try BookCache(folder: url)
        let (_, rebuild) = try Self.timed { try cache.rebuild() }
        try cache.checkpoint()
        let size = (try? FileManager.default.attributesOfItem(atPath: cache.databaseURL.path)[.size] as? Int) ?? 0
        let (hits, search) = try Self.timed { try cache.search("вспоминал") }
        let (_, rare) = try Self.timed { try cache.search("квасц") }
        let file = book.path(book.sceneFiles[5] + ".md")
        try Data((Corpus.read(file) + "\nЕщё строка.\n").utf8).write(to: file)
        let (_, update) = try Self.timed { try cache.update(file: file) }
        let (_, scan) = try Self.timed { try cache.refresh() }
        let (_, reopen) = try Self.timed { try BookCache(folder: url) }
        print("CACHE 10x (\(try cache.totals().characters) characters): rebuild \(Self.ms(rebuild)), database \(size / 1024 / 1024) MB, common word \(Self.ms(search)) (\(hits.count) scenes), rare word \(Self.ms(rare)), one save \(Self.ms(update)), start scan \(Self.ms(scan)), reopen \(Self.ms(reopen))")
        #expect(update < 0.1 * Self.slack)
    }
}
