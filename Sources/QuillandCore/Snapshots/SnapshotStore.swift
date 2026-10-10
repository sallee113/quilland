import Foundation

/// Local safety snapshots of a whole book (`.quilland/snapshots/`, ignored by Git).
///
/// A snapshot is a copy of everything in the book folder except `.quilland` and `.git`, made with the
/// file system's clone (APFS `clonefile`): it takes milliseconds and shares the disk blocks with the
/// original until one of them changes. Where cloning is impossible the folder is copied.
public final class SnapshotStore {
    public enum Kind: String, Sendable { case automatic, beforeOperation, manual }

    public struct Info: Equatable, Sendable {
        /// The folder name: a UTC timestamp, then the kind. Sorts by time.
        public var id: String
        public var date: Date
        public var kind: Kind
        /// A name the author gave (a named snapshot is never thinned out).
        public var name: String?
        /// What the app was about to do ("replace Washington", "delete scene").
        public var reason: String?
        public var cloned: Bool
    }

    /// How long snapshots are kept. The defaults are the rule of the spec.
    public struct Policy: Sendable {
        /// Automatic snapshots (periodic, and before an operation): all of them for this long…
        public var automaticFull: TimeInterval = 24 * 3600
        /// …then the last of each day until this age, then none.
        public var automaticDaily: TimeInterval = 30 * 24 * 3600
        /// Manual ones (Save): all of them for this long, then one a day until the second age.
        public var manualFull: TimeInterval = 30 * 24 * 3600
        public var manualDaily: TimeInterval = 365 * 24 * 3600
        public init() {}
    }

    public struct Crash: Error {}

    public let bookFolder: URL
    public let root: URL
    public var policy = Policy()
    public var calendar = Calendar.current
    /// For tests: stop after this many entries have been copied, as a crash would.
    var crashAfterEntries: Int?
    /// For tests: pretend the file system cannot clone.
    var allowClone = true

    static let excluded: Set<String> = [".quilland", ".git"]

    public init(bookFolder: URL) {
        self.bookFolder = bookFolder
        root = bookFolder.appendingPathComponent(".quilland/snapshots")
    }

    // MARK: Taking

    @discardableResult
    public func take(_ kind: Kind, name: String? = nil, reason: String? = nil, now: Date = Date()) throws -> Info {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let id = Self.id(for: now, kind: kind)
        let temporary = root.appendingPathComponent(".\(id).tmp")
        let final = root.appendingPathComponent(id)
        try? fm.removeItem(at: temporary)
        let files = temporary.appendingPathComponent("files")
        try fm.createDirectory(at: files, withIntermediateDirectories: true)
        var cloned = allowClone
        var copied = 0
        for entry in try fm.contentsOfDirectory(atPath: bookFolder.path).sorted() where !Self.excluded.contains(entry) {
            let source = bookFolder.appendingPathComponent(entry)
            let target = files.appendingPathComponent(entry)
            if allowClone, clonefile(source.path, target.path, 0) == 0 { /* cloned */ }
            else {
                cloned = false
                try Self.copy(source, to: target)
            }
            copied += 1
            if let limit = crashAfterEntries, copied >= limit { throw Crash() }
        }
        var meta: JSONObject = ["date": .string(Self.iso(now)), "kind": .string(kind.rawValue), "cloned": .bool(cloned)]
        if let name { meta["name"] = .string(name) }
        if let reason { meta["reason"] = .string(reason) }
        try JSONWriter.data(meta).write(to: temporary.appendingPathComponent("snapshot.json"))
        try fm.moveItem(at: temporary, to: final)   // the snapshot exists only from this moment
        return Info(id: id, date: now, kind: kind, name: name, reason: reason, cloned: cloned)
    }

    /// A copy that really copies the bytes (`copyfile` without the clone flag), keeping times and attributes.
    static func copy(_ source: URL, to target: URL) throws {
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW)
        if copyfile(source.path, target.path, nil, flags) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: source.path])
        }
    }

    static func id(for date: Date, kind: Kind) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return f.string(from: date) + "-" + kind.rawValue
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func parseISO(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text)
    }

    // MARK: Listing

    /// Finished snapshots, oldest first. A snapshot that was being made when the app stopped is not one.
    public func list() -> [Info] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        var out: [Info] = []
        for id in names {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(id).appendingPathComponent("snapshot.json")),
                  let object = try? JSONParser.parseObject(data), let date = object.string("date").flatMap(Self.parseISO),
                  let kind = object.string("kind").flatMap(Kind.init(rawValue:)) else { continue }
            out.append(Info(id: id, date: date, kind: kind, name: object.string("name"), reason: object.string("reason"), cloned: object.bool("cloned") ?? false))
        }
        return out
    }

    /// Removes what a crash left (snapshots that were never finished). Returns their names.
    @discardableResult
    public func removeLeftovers() -> [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0.hasPrefix(".") && $0.hasSuffix(".tmp") }
        for name in names { try? FileManager.default.removeItem(at: root.appendingPathComponent(name)) }
        return names
    }

    /// The folder inside a snapshot that holds the book's files as they were.
    public func filesFolder(_ info: Info) -> URL { root.appendingPathComponent(info.id).appendingPathComponent("files") }

    // MARK: Thinning

    /// Which snapshots the policy keeps at `now`, as ids. Pure: touches nothing.
    public func survivors(of all: [Info], now: Date) -> Set<String> {
        var keep = Set<String>()
        func thin(_ group: [Info], full: TimeInterval, daily: TimeInterval) {
            var newestOfDay: [DateComponents: Info] = [:]
            for info in group {
                let age = now.timeIntervalSince(info.date)
                if age <= full { keep.insert(info.id); continue }
                if age > daily { continue }
                let day = calendar.dateComponents([.year, .month, .day], from: info.date)
                if let current = newestOfDay[day], current.date >= info.date { continue }
                newestOfDay[day] = info
            }
            for info in newestOfDay.values { keep.insert(info.id) }
        }
        for info in all where info.name != nil { keep.insert(info.id) }   // a name is a promise
        thin(all.filter { $0.kind != .manual && $0.name == nil }, full: policy.automaticFull, daily: policy.automaticDaily)
        thin(all.filter { $0.kind == .manual && $0.name == nil }, full: policy.manualFull, daily: policy.manualDaily)
        return keep
    }

    /// Deletes the snapshots the policy no longer keeps. Returns their ids.
    @discardableResult
    public func thin(now: Date = Date()) throws -> [String] {
        let all = list()
        let keep = survivors(of: all, now: now)
        var removed: [String] = []
        for info in all where !keep.contains(info.id) {
            try FileManager.default.removeItem(at: root.appendingPathComponent(info.id))
            removed.append(info.id)
        }
        return removed
    }

    // MARK: Has anything changed?

    private func stamps(of folder: URL, skipping: Set<String>) -> [String: String] {
        var out: [String: String] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let base = folder.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return out }
        for case let url as URL in walker {
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if skipping.contains(relative.split(separator: "/").first.map(String.init) ?? relative) { walker.skipDescendants(); continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            out[relative] = "\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)/\(values.fileSize ?? 0)"
        }
        return out
    }

    /// Is the book different from the newest snapshot? (A clone keeps every file's time and size, so this is a stat comparison.)
    public func changedSinceLatest() -> Bool {
        guard let latest = list().last else { return true }
        return stamps(of: bookFolder, skipping: Self.excluded) != stamps(of: filesFolder(latest), skipping: [])
    }

    /// Is the book different from this snapshot? (The same stat comparison as `changedSinceLatest`.)
    public func changed(since info: Info) -> Bool {
        stamps(of: bookFolder, skipping: Self.excluded) != stamps(of: filesFolder(info), skipping: [])
    }

    /// How many files differ between a snapshot and the book now: changed, added since, deleted since (a stat comparison, quick).
    public func quickDiff(_ info: Info) -> (changed: Int, added: Int, deleted: Int) {
        let now = stamps(of: bookFolder, skipping: Self.excluded)
        let was = stamps(of: filesFolder(info), skipping: [])
        var changed = 0, added = 0, deleted = 0
        for (path, stamp) in was { if let current = now[path] { if current != stamp { changed += 1 } } else { deleted += 1 } }
        for path in now.keys where was[path] == nil { added += 1 }
        return (changed, added, deleted)
    }

    /// About how much disk the snapshots take. Cloned files share their blocks with the book, so a file counts once, by size and time.
    public func diskUsage() -> Int64 {
        var seen = Set<String>()
        var total: Int64 = 0
        for key in stamps(of: bookFolder, skipping: Self.excluded).values { seen.insert(key) }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        for info in list() {
            guard let walker = FileManager.default.enumerator(at: filesFolder(info), includingPropertiesForKeys: keys) else { continue }
            for case let url as URL in walker {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
                let key = "\(v.contentModificationDate?.timeIntervalSince1970 ?? 0)/\(v.fileSize ?? 0)"
                if seen.insert(key).inserted { total += Int64(v.fileSize ?? 0) }
            }
        }
        return total
    }

    /// Gives a snapshot a name. A named snapshot is kept for good (it becomes a saved one, never thinned out).
    public func name(_ info: Info, as name: String) throws {
        let file = root.appendingPathComponent(info.id).appendingPathComponent("snapshot.json")
        var meta = try JSONParser.parseObject(Data(contentsOf: file))
        meta.setString("name", name)
        meta.setString("kind", Kind.manual.rawValue)
        try AtomicFile.write(JSONWriter.data(meta), to: file)
    }

    // MARK: Restoring

    /// Puts one file (or folder) of a snapshot back into the book, replacing what is there.
    public func restore(_ relativePath: String, from info: Info) throws {
        let source = filesFolder(info).appendingPathComponent(relativePath)
        let target = bookFolder.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try place(source, at: target)
    }

    /// Puts the whole book back as it was. The present state is kept first as a snapshot, so this can be undone too.
    @discardableResult
    public func restoreAll(from info: Info, now: Date = Date()) throws -> Info {
        let safety = try take(.beforeOperation, reason: "before restoring \(info.id)", now: now)
        let fm = FileManager.default
        let source = filesFolder(info)
        let wanted = Set(try fm.contentsOfDirectory(atPath: source.path))
        for entry in try fm.contentsOfDirectory(atPath: bookFolder.path) where !Self.excluded.contains(entry) && !wanted.contains(entry) {
            try fm.removeItem(at: bookFolder.appendingPathComponent(entry))
        }
        for entry in wanted { try place(source.appendingPathComponent(entry), at: bookFolder.appendingPathComponent(entry)) }
        return safety
    }

    /// A clone of `source` at `target`, put in place with a rename so there is no moment without it.
    private func place(_ source: URL, at target: URL) throws {
        let fm = FileManager.default
        let staged = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).restoring")
        try? fm.removeItem(at: staged)
        if !(allowClone && clonefile(source.path, staged.path, 0) == 0) { try Self.copy(source, to: staged) }
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: target)
        }
    }
}
