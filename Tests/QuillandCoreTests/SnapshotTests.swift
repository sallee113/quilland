import Foundation
import Testing
@testable import QuillandCore

/// Experiment 8: snapshots by the file system's clone, and the thinning rule.
@Suite("Snapshots", .serialized)
struct SnapshotTests {
    static func makeBook(sentences: Int = 66) throws -> (GeneratedBook, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return (try GeneratedBook(in: url, sentencesPerScene: sentences), url)
    }

    /// Every file under `folder` with its bytes, leaving out the top-level names in `skipping`.
    static func tree(_ folder: URL, skipping: Set<String> = [".quilland", ".git"]) -> [String: Data] {
        var out: [String: Data] = [:]
        let base = folder.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return out }
        for case let url as URL in walker {
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if skipping.contains(relative.split(separator: "/").first.map(String.init) ?? "") { walker.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { out[relative] = try? Data(contentsOf: url) }
        }
        return out
    }

    static func size(of folder: URL) -> Int {
        tree(folder, skipping: []).values.reduce(0) { $0 + $1.count }
    }

    /// Bytes the volume has free (what a copy would eat).
    static func freeBytes(_ url: URL) -> Int {
        var s = statfs()
        statfs(url.path, &s)
        return Int(s.f_bavail) * Int(s.f_bsize)
    }

    static func ms(_ seconds: Double) -> String { String(format: "%.1f ms", seconds * 1000) }

    static func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let start = Date()
        let value = try body()
        return (value, Date().timeIntervalSince(start))
    }

    @Test("a snapshot of a 1 MB book (130 files) takes milliseconds and is identical to the book")
    func speedAndContent() throws {
        let (_, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnapshotStore(bookFolder: url)
        let bytes = Self.size(of: url)
        let first = try store.take(.manual)   // the first one makes the folder
        var times: [Double] = []
        for i in 0..<20 { times.append(Self.timed { try! store.take(.automatic, now: Date().addingTimeInterval(Double(i + 1))) }.1) }
        times.sort()
        print("SNAPSHOT: a book of \(bytes / 1024) KB in 130 files: median \(Self.ms(times[10])), slowest of 20 \(Self.ms(times[19])), cloned: \(first.cloned)")
        #expect(first.cloned, "the temporary folder is expected to be on APFS")
        #expect(times[19] < 0.05 * Self.slackFactor)
        let list = store.list()
        #expect(list.count == 21)
        // The copy is the book, and does not contain the snapshots themselves.
        #expect(Self.tree(store.filesFolder(list[0]), skipping: []) == Self.tree(url))
        #expect(!Self.tree(store.filesFolder(list[0]), skipping: []).keys.contains { $0.hasPrefix(".quilland") })
    }

    #if DEBUG
    static let slackFactor = 6.0
    #else
    static let slackFactor = 1.0
    #endif

    @Test("a snapshot shares the disk blocks: a 150 MB file costs almost nothing, a real copy costs 150 MB")
    func spaceUsed() throws {
        let (_, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        // A big research file (a PDF, a scan) next to the text.
        let big = url.appendingPathComponent("research/scan.bin")
        try FileManager.default.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
        var rng = SplitMix64(seed: 5)
        let block = Data((0..<(1 << 20)).map { _ in UInt8.random(in: 0...255, using: &rng) })
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        for _ in 0..<150 { try handle.write(contentsOf: block) }
        try handle.close()

        let store = SnapshotStore(bookFolder: url)
        let before = Self.freeBytes(url)
        let (clone, cloneTime) = try Self.timed { try store.take(.manual) }
        let afterClone = Self.freeBytes(url)
        var plain = SnapshotStore(bookFolder: url)
        plain.allowClone = false
        let (copy, copyTime) = try Self.timed { try plain.take(.automatic, now: Date().addingTimeInterval(1)) }
        let afterCopy = Self.freeBytes(url)
        let cloneCost = before - afterClone
        let copyCost = afterClone - afterCopy
        print("SNAPSHOT SPACE: book 150 MB + text: clone took \(Self.ms(cloneTime)) and \(cloneCost / 1024) KB of disk; a real copy took \(Self.ms(copyTime)) and \(copyCost / 1024 / 1024) MB")
        #expect(clone.cloned && !copy.cloned)
        #expect(cloneCost < 8 * 1024 * 1024, "the clone used \(cloneCost) bytes")
        #expect(copyCost > 100 * 1024 * 1024, "the control copy should really cost the space")

        // Changing the original leaves the snapshot alone, and costs only what changed.
        let beforeEdit = Self.freeBytes(url)
        let edit = try FileHandle(forWritingTo: big)
        try edit.seek(toOffset: 70 << 20)
        try edit.write(contentsOf: Data(repeating: 0xEE, count: 4096))
        try edit.close()
        try Data("changed".utf8).write(to: url.appendingPathComponent("manuscript/001-part/001-chapter/001-scene.md"))
        let editCost = beforeEdit - Self.freeBytes(url)
        let snapshotFile = store.filesFolder(clone).appendingPathComponent("research/scan.bin")
        let snapshotData = try Data(contentsOf: snapshotFile, options: .alwaysMapped)
        #expect(snapshotData.subdata(in: (70 << 20)..<((70 << 20) + 4096)) != Data(repeating: 0xEE, count: 4096), "the snapshot must not see the edit")
        #expect(try Data(contentsOf: store.filesFolder(clone).appendingPathComponent("manuscript/001-part/001-chapter/001-scene.md")) != Data("changed".utf8))
        print("SNAPSHOT SPACE: editing 4 KB of the 150 MB file and one scene afterwards cost \(editCost / 1024) KB")
        #expect(editCost < 8 * 1024 * 1024)
    }

    @Test("a crash in the middle of taking a snapshot leaves no half snapshot")
    func crash() throws {
        let (_, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        var store = SnapshotStore(bookFolder: url)
        try store.take(.manual)
        store.crashAfterEntries = 1
        #expect(throws: SnapshotStore.Crash.self) { try store.take(.automatic, now: Date().addingTimeInterval(5)) }
        #expect(store.list().count == 1, "an unfinished snapshot is not listed")
        #expect(store.removeLeftovers().count == 1)
        #expect(store.removeLeftovers().isEmpty)
        #expect(store.list().count == 1)
    }

    @Test("has the book changed since the last snapshot? (so an idle book takes no more snapshots)")
    func changes() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnapshotStore(bookFolder: url)
        #expect(store.changedSinceLatest(), "no snapshot yet")
        try store.take(.automatic)
        let (same, time) = Self.timed { store.changedSinceLatest() }
        #expect(!same)
        print("SNAPSHOT CHANGED?: compared 130 files with the newest snapshot in \(Self.ms(time))")
        let file = book.path(book.sceneFiles[7] + ".md")
        try Data((Corpus.read(file) + "\nещё\n").utf8).write(to: file)
        #expect(store.changedSinceLatest())
        try store.take(.automatic, now: Date().addingTimeInterval(1))
        #expect(!store.changedSinceLatest())
        try FileManager.default.removeItem(at: book.path(book.sceneFiles[8] + ".md"))
        #expect(store.changedSinceLatest())
        try store.take(.automatic, now: Date().addingTimeInterval(2))
        try Data("x".utf8).write(to: url.appendingPathComponent("bible/new.json"))
        #expect(store.changedSinceLatest())
    }

    @Test("restoring: one deleted scene comes back; the whole book comes back byte for byte, and can be undone")
    func restore() throws {
        let (book, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SnapshotStore(bookFolder: url)
        let original = Self.tree(url)
        let snapshot = try store.take(.manual, name: "before the rewrite")
        // The author deletes a scene, rewrites another, adds a file.
        let gone = book.sceneFiles[20]
        try FileManager.default.removeItem(at: book.path(gone + ".md"))
        try FileManager.default.removeItem(at: book.path(gone + ".json"))
        try Data("rewritten".utf8).write(to: book.path(book.sceneFiles[21] + ".md"))
        try Data("new".utf8).write(to: url.appendingPathComponent("bible/extra.json"))
        let damaged = Self.tree(url)

        try store.restore(gone + ".md", from: snapshot)
        try store.restore(gone + ".json", from: snapshot)
        #expect(try Data(contentsOf: book.path(gone + ".md")) == original[gone + ".md"])
        // Put the deletion back and restore everything.
        try FileManager.default.removeItem(at: book.path(gone + ".md"))
        let (safety, time) = try Self.timed { try store.restoreAll(from: snapshot, now: Date().addingTimeInterval(10)) }
        #expect(Self.tree(url) == original)
        print("SNAPSHOT RESTORE: the whole book back in \(Self.ms(time)) (including a safety snapshot of the present state)")
        // And the restore itself can be undone.
        _ = try store.restoreAll(from: safety, now: Date().addingTimeInterval(20))
        var expected = damaged
        expected[gone + ".md"] = nil   // that deletion was repeated on purpose before the restore
        expected[gone + ".json"] = original[gone + ".json"]   // and this file had been restored one by one
        expect(Self.tree(url), equals: expected)
        #expect(store.list().count == 3, "the snapshot and one safety snapshot for each restore")
    }

    private func expect(_ a: [String: Data], equals b: [String: Data]) {
        #expect(Set(a.keys) == Set(b.keys), "\(Set(a.keys).symmetricDifference(Set(b.keys)))")
        #expect(a == b)
    }

    @Test("without cloning (another file system) a snapshot is a real copy and works the same")
    func fallback() throws {
        let (_, url) = try Self.makeBook()
        defer { try? FileManager.default.removeItem(at: url) }
        var store = SnapshotStore(bookFolder: url)
        store.allowClone = false
        let (info, time) = try Self.timed { try store.take(.manual) }
        #expect(!info.cloned)
        #expect(Self.tree(store.filesFolder(info), skipping: []) == Self.tree(url))
        print("SNAPSHOT WITHOUT CLONE: a real copy of the 1 MB book took \(Self.ms(time))")
    }

    // MARK: Thinning

    /// The rule written out a second way, independent of the code: for every snapshot, the reason to keep it.
    static func reference(_ all: [SnapshotStore.Info], now: Date, calendar: Calendar, policy: SnapshotStore.Policy) -> Set<String> {
        var keep = Set<String>()
        for info in all where info.name != nil { keep.insert(info.id) }
        for manual in [false, true] {
            let group = all.filter { ($0.kind == .manual) == manual && $0.name == nil }
            let (full, daily) = manual ? (policy.manualFull, policy.manualDaily) : (policy.automaticFull, policy.automaticDaily)
            let old = group.filter { now.timeIntervalSince($0.date) > full && now.timeIntervalSince($0.date) <= daily }
            for info in group where now.timeIntervalSince(info.date) <= full { keep.insert(info.id) }
            for day in Set(old.map { calendar.startOfDay(for: $0.date) }) {
                let ofDay = old.filter { calendar.startOfDay(for: $0.date) == day }
                keep.insert(ofDay.max { $0.date < $1.date }!.id)
            }
        }
        return keep
    }

    @Test("thinning: last 24 hours in full, then one a day for a month; manual ones for 30 days; named ones always")
    func thinning() throws {
        let (_, url) = try Self.makeBook(sentences: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        var store = SnapshotStore(bookFolder: url)
        store.calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)   // a fixed moment
        // 60 days of work: an automatic snapshot every 15 minutes in the last 2 days, every 3 hours before that,
        // a manual one every 4 days, a named one at day 50, a "before operation" one at day 3.
        var made: [SnapshotStore.Info] = []
        func take(_ kind: SnapshotStore.Kind, hoursAgo: Double, name: String? = nil) throws {
            made.append(try store.take(kind, name: name, now: now.addingTimeInterval(-hoursAgo * 3600)))
        }
        var h = 60.0 * 24
        while h > 48 { try take(.automatic, hoursAgo: h); h -= 3 }
        while h >= 0 { try take(.automatic, hoursAgo: h); h -= 0.25 }
        for day in stride(from: 4, through: 60, by: 4) { try take(.manual, hoursAgo: Double(day) * 24 + 1) }
        try take(.manual, hoursAgo: 50 * 24, name: "first draft done")
        try take(.beforeOperation, hoursAgo: 3 * 24 + 5)
        #expect(made.count > 600)

        let all = store.list()
        #expect(all.count == made.count)
        let expected = Self.reference(all, now: now, calendar: store.calendar, policy: store.policy)
        let (removed, time) = try Self.timed { try store.thin(now: now) }
        let left = store.list()
        print("SNAPSHOT THINNING: \(all.count) snapshots over 60 days -> \(left.count) kept, \(removed.count) deleted in \(Self.ms(time))")
        #expect(Set(left.map(\.id)) == expected)
        #expect(left.count < 160, "97 of the last day, about 30 days, 15 manual, one named")

        // The rule itself, spot-checked.
        let recent = left.filter { now.timeIntervalSince($0.date) <= 24 * 3600 && $0.kind == .automatic }
        #expect(recent.count == 97, "every quarter hour of the last day: \(recent.count)")
        let oldAutomatic = left.filter { $0.kind != .manual && $0.name == nil && now.timeIntervalSince($0.date) > 24 * 3600 }
        let days = oldAutomatic.map { store.calendar.startOfDay(for: $0.date) }
        #expect(Set(days).count == days.count, "one automatic snapshot per day after the first day")
        #expect(oldAutomatic.allSatisfy { now.timeIntervalSince($0.date) <= 30 * 24 * 3600 })
        #expect(left.contains { $0.name == "first draft done" }, "a named snapshot is never thinned out")
        #expect(left.filter { $0.kind == .manual && $0.name == nil }.count == 15, "manual ones are kept past 30 days (these are 4 days apart, so one a day keeps them all)")
        // Thinning twice changes nothing.
        #expect(try store.thin(now: now).isEmpty)
        // A month later, the automatic ones are all gone except what the rule keeps.
        let later = now.addingTimeInterval(40 * 24 * 3600)
        try store.thin(now: later)
        #expect(store.list().allSatisfy { $0.kind == .manual || $0.name != nil })
    }
}
