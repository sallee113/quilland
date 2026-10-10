import Foundation
import Testing
@testable import QuillandCore

/// Experiment 2: renumbering a folder of items, with a crash at every possible point.
@Suite("Renumbering with a journal", .serialized)
struct RenumberTests {
    /// A book folder with `manuscript/` holding items. Each item's files all contain its token, so after any
    /// operation we can tell which files belong together.
    final class Book {
        let root: URL
        let manuscript: URL
        let journal: URL
        /// token -> the suffixes its files have (".json", ".md", ".notes.json", "" for a folder)
        var shapes: [String: [String]] = [:]

        init(items: [(token: String, kind: String, suffixes: [String])]) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-renumber-\(UUID().uuidString)")
            manuscript = root.appendingPathComponent("manuscript")
            journal = root.appendingPathComponent(".quilland/journal.json")
            try FileManager.default.createDirectory(at: manuscript, withIntermediateDirectories: true)
            for (index, item) in items.enumerated() {
                shapes[item.token] = item.suffixes
                let base = String(format: "%03d-%@", index + 1, item.kind)
                for suffix in item.suffixes {
                    if suffix.isEmpty {
                        let dir = manuscript.appendingPathComponent(base)
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        try Data("child of \(item.token)".utf8).write(to: dir.appendingPathComponent("_chapter.json"))
                    } else {
                        try Data("belongs to \(item.token)".utf8).write(to: manuscript.appendingPathComponent(base + suffix))
                    }
                }
            }
        }

        deinit { try? FileManager.default.removeItem(at: root) }

        func names() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: manuscript.path)) ?? []).sorted() }

        /// What is on disk, as a list of problems (empty when it is exactly `order`, numbered 1, 2, 3, … with every item whole).
        func problems(expecting order: [String]) -> [String] {
            var problems: [String] = []
            guard let items = try? Renumber.scan(manuscript) else { return ["the folder cannot be scanned"] }
            if items.count != order.count { problems.append("\(items.count) items, expected \(order.count)") }
            for (index, item) in items.enumerated() {
                if item.number != index + 1 { problems.append("item \(index) is numbered \(item.number)") }
                guard index < order.count else { continue }
                let token = order[index]
                var found: [String] = []
                for member in item.members {
                    let suffix = String(member.dropFirst(item.base.count))
                    found.append(suffix)
                    let url = manuscript.appendingPathComponent(member)
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    let text = isDirectory.boolValue
                        ? ((try? String(contentsOf: url.appendingPathComponent("_chapter.json"), encoding: .utf8)) ?? "")
                        : ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                    if !text.hasSuffix(token) { problems.append("\(member) holds \(text.debugDescription), expected \(token)") }
                }
                if found.sorted() != (shapes[token] ?? []).sorted() { problems.append("\(item.base) has \(found.sorted()), expected \(shapes[token] ?? [])") }
            }
            let strays = names().filter { $0.hasPrefix(".quilland-mv") }
            if !strays.isEmpty { problems.append("temporary names left: \(strays)") }
            if FileManager.default.fileExists(atPath: journal.path) { problems.append("the journal was not removed") }
            return problems
        }
    }

    static func tokens(_ n: Int) -> [String] { (1...n).map { "S\($0)" } }

    /// Ten scenes: some with a note file, some without text.
    static func tenScenes() throws -> Book {
        try Book(items: tokens(10).enumerated().map { i, token in
            (token, "scene", i % 3 == 0 ? [".json", ".md", ".notes.json"] : (i % 3 == 1 ? [".json", ".md"] : [".json"]))
        })
    }

    // MARK: Plain operations

    @Test("inserting at position 4 renumbers the items after it; a pair never separates")
    func insert() throws {
        let book = try Self.tenScenes()
        let items = try Renumber.scan(book.manuscript)
        var order: [Renumber.Slot] = items.map { .item($0.base) }
        order.insert(.gap, at: 3)
        let steps = try Renumber.plan(folder: "manuscript", items: items, order: order)
        try Renumber.execute(steps, root: book.root, journal: book.journal)
        var expected = Self.tokens(10)
        expected.insert("(new)", at: 3)
        let names = book.names()
        #expect(!names.contains("004-scene.json") && !names.contains("004-scene.md"), "the number 4 is free for the new item")
        #expect(names.contains("005-scene.json"))
        // Fill the gap like the app would, then everything must be in order.
        try Data("belongs to (new)".utf8).write(to: book.manuscript.appendingPathComponent("004-scene.json"))
        book.shapes["(new)"] = [".json"]
        #expect(book.problems(expecting: expected) == [])
    }

    @Test("moving an item from 2 to 8")
    func move() throws {
        let book = try Self.tenScenes()
        let items = try Renumber.scan(book.manuscript)
        var bases = items.map(\.base)
        let moved = bases.remove(at: 1)
        bases.insert(moved, at: 7)
        let steps = try Renumber.plan(folder: "manuscript", items: items, order: bases.map { .item($0) })
        try Renumber.execute(steps, root: book.root, journal: book.journal)
        var expected = Self.tokens(10)
        let token = expected.remove(at: 1)
        expected.insert(token, at: 7)
        #expect(book.problems(expecting: expected) == [])
    }

    @Test("deleting an item moves its files to the trash and closes the gap")
    func delete() throws {
        let book = try Self.tenScenes()
        let items = try Renumber.scan(book.manuscript)
        let victim = items[4]
        let kept = items.filter { $0.base != victim.base }.map { Renumber.Slot.item($0.base) }
        let steps = try Renumber.plan(folder: "manuscript", items: items, order: kept, removed: [victim.base], trash: ".quilland/trash/test")
        try Renumber.execute(steps, root: book.root, journal: book.journal)
        var expected = Self.tokens(10)
        expected.remove(at: 4)
        #expect(book.problems(expecting: expected) == [])
        let trash = try FileManager.default.contentsOfDirectory(atPath: book.root.appendingPathComponent(".quilland/trash/test").path).sorted()
        #expect(trash == victim.members.sorted())
    }

    @Test("parts, chapters (folders) and scenes in one folder")
    func mixedKinds() throws {
        let book = try Book(items: [
            ("P1", "part", [""]), ("C1", "chapter", [""]), ("C2", "chapter", [""]), ("S1", "scene", [".json", ".md"]), ("P2", "part", [""]),
        ])
        let items = try Renumber.scan(book.manuscript)
        var order: [Renumber.Slot] = items.map { .item($0.base) }
        order.insert(.gap, at: 1)
        try Renumber.execute(try Renumber.plan(folder: "manuscript", items: items, order: order), root: book.root, journal: book.journal)
        let after = try Renumber.scan(book.manuscript)
        #expect(after.map(\.base) == ["001-part", "003-chapter", "004-chapter", "005-scene", "006-part"])
        for item in after { #expect(item.members.count == (item.kind == "scene" ? 2 : 1)) }
    }

    @Test("what is not an item is left alone")
    func otherFiles() throws {
        let book = try Self.tenScenes()
        for name in ["_chapter.json", "_chapter.md", ".DS_Store", "notes.txt", "12-scene.json", "0003-scene.json", "003-scenes.json"] {
            try Data("x".utf8).write(to: book.manuscript.appendingPathComponent(name))
        }
        let items = try Renumber.scan(book.manuscript)
        #expect(items.count == 10, "only the ten numbered items count")
        var order = items.map { Renumber.Slot.item($0.base) }
        order.insert(.gap, at: 0)
        try Renumber.execute(try Renumber.plan(folder: "manuscript", items: items, order: order), root: book.root, journal: book.journal)
        for name in ["_chapter.json", "_chapter.md", ".DS_Store", "notes.txt", "12-scene.json", "0003-scene.json", "003-scenes.json"] {
            #expect(book.names().contains(name), "\(name) was touched")
        }
    }

    @Test("refusals: two items with one number, a name that is not there, more than 999 items")
    func refusals() throws {
        let book = try Self.tenScenes()
        try Data("x".utf8).write(to: book.manuscript.appendingPathComponent("003-chapter.json"))
        #expect(throws: Renumber.Failure.self) { _ = try Renumber.scan(book.manuscript) }
        try FileManager.default.removeItem(at: book.manuscript.appendingPathComponent("003-chapter.json"))
        let items = try Renumber.scan(book.manuscript)
        #expect(throws: Renumber.Failure.self) { _ = try Renumber.plan(folder: "manuscript", items: items, order: [.item("099-scene")]) }
        #expect(throws: Renumber.Failure.self) { _ = try Renumber.plan(folder: "manuscript", items: items, order: items.dropFirst().map { .item($0.base) }) }
        let many = (0..<1000).map { _ in Renumber.Slot.gap }
        #expect(throws: Renumber.Failure.self) { _ = try Renumber.plan(folder: "manuscript", items: items, order: many) }
        #expect(try Renumber.recover(root: book.root, journal: book.journal) == false, "nothing to recover")
    }

    // MARK: Crashing at every point

    /// The operation used for the crash tests: a gap opens at the start and the last item moves to third place,
    /// so every one of the ten items gets a new number.
    static func operation(_ book: Book) throws -> (steps: [Renumber.Step], expected: [String]) {
        let items = try Renumber.scan(book.manuscript)
        var bases = items.map(\.base)
        let moved = bases.removeLast()
        bases.insert(moved, at: 1)
        var order: [Renumber.Slot] = bases.map { .item($0) }
        order.insert(.gap, at: 0)
        var expected = Self.tokens(10)
        let token = expected.removeLast()
        expected.insert(token, at: 1)
        expected.insert("(new)", at: 0)
        return (try Renumber.plan(folder: "manuscript", items: items, order: order), expected)
    }

    /// How many points a crash can happen at (each rename, and the journal's change of phase).
    static func crashPoints() throws -> Int {
        let book = try tenScenes()
        let (steps, _) = try operation(book)
        var points = 0
        try Renumber.execute(steps, root: book.root, journal: book.journal) { points = max(points, $0 + 1) }
        return points
    }

    @Test("a crash at every point (before, between and after the renames, and at the journal's phase change): recovery always finishes the job")
    func crashAtEveryPoint() throws {
        let points = try Self.crashPoints()
        #expect(points > 30, "the operation must be big enough to matter: \(points)")
        var failures: [String] = []
        for crashAt in 0...points {
            let book = try Self.tenScenes()
            let (steps, expected) = try Self.operation(book)
            var crashed = false
            do {
                try Renumber.execute(steps, root: book.root, journal: book.journal) { if $0 == crashAt { throw Renumber.SimulatedCrash() } }
            } catch is Renumber.SimulatedCrash {
                crashed = true
            }
            if crashed != (crashAt < points) { failures.append("crash at \(crashAt): crashed=\(crashed)") }
            let recovered = try Renumber.recover(root: book.root, journal: book.journal)
            if recovered != crashed { failures.append("crash at \(crashAt): recovered=\(recovered)") }
            // The app now creates the new item in the number that was kept free for it.
            try Data("belongs to (new)".utf8).write(to: book.manuscript.appendingPathComponent("001-scene.json"))
            book.shapes["(new)"] = [".json"]
            let problems = book.problems(expecting: expected)
            if !problems.isEmpty { failures.append("crash at \(crashAt): \(problems.prefix(3))") }
        }
        print("RENUMBER: \(points) crash points, all recovered: \(failures.isEmpty)")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("a crash during the recovery itself: recover again, and again")
    func crashDuringRecovery() throws {
        let points = try Self.crashPoints()
        var failures: [String] = []
        var cases = 0
        for first in 0..<points {
            for second in 0...points {
                let book = try Self.tenScenes()
                let (steps, expected) = try Self.operation(book)
                _ = try? Renumber.execute(steps, root: book.root, journal: book.journal) { if $0 == first { throw Renumber.SimulatedCrash() } }
                _ = try? Renumber.recover(root: book.root, journal: book.journal) { if $0 == second { throw Renumber.SimulatedCrash() } }
                try Renumber.recover(root: book.root, journal: book.journal)
                try Renumber.recover(root: book.root, journal: book.journal) // a third time changes nothing
                // The app now creates the new item in the number that was kept free for it.
                try Data("belongs to (new)".utf8).write(to: book.manuscript.appendingPathComponent("001-scene.json"))
                book.shapes["(new)"] = [".json"]
                let problems = book.problems(expecting: expected)
                cases += 1
                if !problems.isEmpty { failures.append("crash at \(first), then at \(second): \(problems.prefix(3))") }
            }
        }
        print("RENUMBER: \(cases) double-crash cases, \(failures.count) failed")
        #expect(failures.isEmpty, "\(failures.prefix(10).joined(separator: "\n"))")
    }

    @Test("a journal that names a file that is gone is refused, not guessed; the journal stays")
    func lostFile() throws {
        let book = try Self.tenScenes()
        let (steps, _) = try Self.operation(book)
        _ = try? Renumber.execute(steps, root: book.root, journal: book.journal) { _ in throw Renumber.SimulatedCrash() }
        #expect(FileManager.default.fileExists(atPath: book.journal.path))
        let lost = book.root.appendingPathComponent(steps[0].from)
        try FileManager.default.removeItem(at: lost)
        #expect(throws: Renumber.Failure.self) { try Renumber.recover(root: book.root, journal: book.journal) }
        #expect(FileManager.default.fileExists(atPath: book.journal.path), "kept, so nothing is lost by guessing")
    }
}
