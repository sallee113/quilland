import Foundation

/// Renumbering the items of a folder (quilland-format.md, section 3).
///
/// Items are named `NNN-kind` (`003-scene.json`, `003-scene.md`, `003-scene.notes.json`, or a
/// folder `002-chapter/`). Inserting, moving or deleting an item changes the numbers of the
/// ones after it, and all the files of an item must change together.
///
/// A crash in the middle must never leave an item half renamed. So:
/// 1. the whole plan is written to a journal first (atomically), marked "phase 1";
/// 2. phase 1: every file is renamed to a temporary name, so no new name can clash with an
///    old one that has not moved yet;
/// 3. the journal is rewritten (atomically) as "phase 2", and only then
///    phase 2: every temporary name is renamed to its final name;
/// 4. the journal is deleted.
/// If the app stops anywhere in between, `recover` reads the journal and finishes the job.
/// The phase in the journal matters: once phase 2 has begun, an old name may already be in
/// use by a new file, so recovery must never look for old names again.
/// Every step first looks at what already exists, so doing it twice does no harm.
public enum Renumber {
    public struct Item: Equatable, Sendable {
        public var number: Int
        public var kind: String
        /// The names in the folder that belong to this item.
        public var members: [String]
        public var base: String { String(format: "%03d-%@", number, kind) }
    }

    /// A rename, with paths relative to the book's root folder.
    public struct Step: Equatable, Sendable {
        public var from: String
        public var temp: String
        public var to: String
    }

    public enum Slot: Equatable, Sendable {
        /// An existing item, by its current base name (`003-scene`).
        case item(String)
        /// A number kept free for an item that is about to be created.
        case gap
    }

    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    private static let kinds = ["part", "chapter", "scene"]

    // MARK: Scanning and planning

    /// The numbered items of a folder, in order. Anything else in the folder (`_chapter.json`, `.DS_Store`) is not an item.
    public static func scan(_ folder: URL) throws -> [Item] {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var items: [String: Item] = [:]
        for name in names {
            guard let (number, kind) = parse(name) else { continue }
            let key = String(format: "%03d-%@", number, kind)
            var item = items[key] ?? Item(number: number, kind: kind, members: [])
            item.members.append(name)
            items[key] = item
        }
        let sorted = items.values.sorted { ($0.number, $0.kind) < ($1.number, $1.kind) }
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.number == b.number {
            throw Failure(description: "two items have the number \(a.number): \(a.base) and \(b.base)")
        }
        return sorted
    }

    /// `003-scene.json` gives (3, "scene"); a name that is not an item gives nil.
    static func parse(_ name: String) -> (Int, String)? {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count > 4, scalars[3] == "-", scalars[0...2].allSatisfy({ $0.properties.numericType != nil && $0.isASCII }) else { return nil }
        guard let number = Int(String(String.UnicodeScalarView(scalars[0...2]))) else { return nil }
        let rest = String(String.UnicodeScalarView(scalars[4...]))
        for kind in kinds where rest == kind || rest.hasPrefix(kind + ".") { return (number, kind) }
        return nil
    }

    /// The renames that give `order` the numbers 1, 2, 3, … (a `.gap` takes a number and renames nothing),
    /// and move the items in `removed` into `trash` (a path relative to the root).
    /// `folder` is the folder's path relative to the book's root.
    public static func plan(folder: String, items: [Item], order: [Slot], removed: [String] = [], trash: String? = nil) throws -> [Step] {
        guard order.count <= 999 else { throw Failure(description: "more than 999 items in one folder") }
        let byBase = Dictionary(uniqueKeysWithValues: items.map { ($0.base, $0) })
        var seen = Set<String>()
        var steps: [Step] = []
        var counter = 0
        func temp() -> String {
            counter += 1
            return "\(folder)/.quilland-mv-\(counter)"
        }
        for (index, slot) in order.enumerated() {
            guard case .item(let base) = slot else { continue }
            guard let item = byBase[base] else { throw Failure(description: "no item \(base)") }
            guard seen.insert(base).inserted else { throw Failure(description: "\(base) appears twice") }
            let newBase = String(format: "%03d-%@", index + 1, item.kind)
            for member in item.members {
                let newName = newBase + member.dropFirst(base.count)
                if newName != member { steps.append(Step(from: "\(folder)/\(member)", temp: temp(), to: "\(folder)/\(newName)")) }
            }
        }
        for base in removed {
            guard let item = byBase[base] else { throw Failure(description: "no item \(base)") }
            guard seen.insert(base).inserted else { throw Failure(description: "\(base) appears twice") }
            guard let trash else { throw Failure(description: "no trash folder given") }
            for member in item.members { steps.append(Step(from: "\(folder)/\(member)", temp: temp(), to: "\(trash)/\(member)")) }
        }
        guard seen.count == items.count else { throw Failure(description: "an item is neither kept nor removed") }
        return steps
    }

    // MARK: Doing it

    public struct SimulatedCrash: Error {}

    /// Writes the journal, then does the renames, then removes the journal.
    /// `hook(k)` is called before the k-th rename and before the journal's change to phase 2
    /// (counting from 0), so a test can stop at every point.
    public static func execute(_ steps: [Step], root: URL, journal: URL, hook: ((Int) throws -> Void)? = nil) throws {
        guard !steps.isEmpty else { return }
        try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(encode(steps, phase: 1)), to: journal)
        try finish(steps, phase: 1, root: root, journal: journal, hook: hook)
    }

    /// Finishes what a journal says, if there is one. Returns whether there was one.
    @discardableResult
    public static func recover(root: URL, journal: URL, hook: ((Int) throws -> Void)? = nil) throws -> Bool {
        guard FileManager.default.fileExists(atPath: journal.path) else { return false }
        let (steps, phase) = try decode(try JSONParser.parseObject(try Data(contentsOf: journal)))
        try finish(steps, phase: phase, root: root, journal: journal, hook: hook)
        return true
    }

    private static func finish(_ steps: [Step], phase: Int, root: URL, journal: URL, hook: ((Int) throws -> Void)?) throws {
        var counter = 0
        if phase == 1 {
            try phaseOne(steps, root: root, hook: hook, counter: &counter)
            try hook?(counter)
            counter += 1
            try AtomicFile.write(JSONWriter.data(encode(steps, phase: 2)), to: journal)
        }
        try phaseTwo(steps, root: root, hook: hook, counter: &counter)
        try FileManager.default.removeItem(at: journal)
    }

    /// Every source to its temporary name. Nothing has a final name yet, so a source that exists is
    /// the original, and a source that is gone and has no temporary name is lost.
    private static func phaseOne(_ steps: [Step], root: URL, hook: ((Int) throws -> Void)?, counter: inout Int) throws {
        let fm = FileManager.default
        for step in steps {
            let from = root.appendingPathComponent(step.from)
            let temp = root.appendingPathComponent(step.temp)
            if fm.fileExists(atPath: temp.path) { continue }
            guard fm.fileExists(atPath: from.path) else { throw Failure(description: "\(step.from) is gone") }
            try hook?(counter)
            counter += 1
            try fm.moveItem(at: from, to: temp)
        }
    }

    /// Every temporary name to its final name. One that is already gone was moved before the crash.
    private static func phaseTwo(_ steps: [Step], root: URL, hook: ((Int) throws -> Void)?, counter: inout Int) throws {
        let fm = FileManager.default
        for step in steps {
            let temp = root.appendingPathComponent(step.temp)
            let target = root.appendingPathComponent(step.to)
            if !fm.fileExists(atPath: temp.path) {
                guard fm.fileExists(atPath: target.path) else { throw Failure(description: "\(step.temp) and \(step.to) are both gone") }
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try hook?(counter)
            counter += 1
            try fm.moveItem(at: temp, to: uniqueIfInTrash(target, step.to))
        }
    }

    /// A file going into the trash folder never replaces or collides with one that is already there: it gets `-2`, `-3`… before its extension.
    private static func uniqueIfInTrash(_ target: URL, _ relative: String) -> URL {
        guard relative.hasPrefix(".quilland/trash/"), FileManager.default.fileExists(atPath: target.path) else { return target }
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            let candidate = target.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    // MARK: The journal file

    private static func encode(_ steps: [Step], phase: Int) -> JSONObject {
        ["format": .int(1), "phase": .int(phase),
         "steps": .array(steps.map { .object(["from": .string($0.from), "temp": .string($0.temp), "to": .string($0.to)]) })]
    }

    private static func decode(_ object: JSONObject) throws -> ([Step], Int) {
        guard let list = object.objects("steps"), let phase = object.int("phase"), phase == 1 || phase == 2 else {
            throw Failure(description: "the journal is damaged")
        }
        return (try list.map {
            guard let from = $0.string("from"), let temp = $0.string("temp"), let to = $0.string("to") else {
                throw Failure(description: "a step of the journal is incomplete")
            }
            return Step(from: from, temp: temp, to: to)
        }, phase)
    }
}
