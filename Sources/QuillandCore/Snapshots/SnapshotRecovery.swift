import Foundation

/// Puts items of a snapshot back into a book: one changed item over its present self, a deleted item in its old place (or, when the place
/// is gone, in a chapter called "Recovered" at the end), or an item as a copy beside the present one. Takes no snapshot itself: the caller
/// takes the safety snapshot first.
public struct SnapshotRecovery {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
        public init(description: String) { self.description = description }
    }

    public let book: URL
    public init(book: URL) { self.book = book }

    private var journal: URL { book.appendingPathComponent(".quilland/journal.json") }
    private let fm = FileManager.default

    // MARK: Small helpers

    private func url(_ relative: String) -> URL { book.appendingPathComponent(relative) }

    private func directory(of relative: String) -> String { (relative as NSString).deletingLastPathComponent }

    /// Moves a file out of the book into the trash folder (never deleted outright).
    private func trash(_ relative: String) throws {
        guard fm.fileExists(atPath: url(relative).path) else { return }
        let stamp = TrashFolder.newName()
        let target = book.appendingPathComponent(".quilland/trash/\(stamp)/\(relative)")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: url(relative), to: target)
    }

    private func write(_ data: Data, to relative: String) throws {
        try fm.createDirectory(at: url(relative).deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.write(data, to: url(relative))
    }

    private func suffix(for role: String) -> String {
        switch role {
        case "json": return ".json"
        case "md": return ".md"
        case "notes": return ".notes.json"
        default: return ""
        }
    }

    // MARK: Restoring

    /// A changed item goes back to how the snapshot had it (its files stay where they are now); a deleted one is recovered.
    public func restore(_ change: ItemChange, snapshotRoot: URL) throws {
        switch change.status {
        case .changed: try restoreChanged(change, snapshotRoot: snapshotRoot)
        case .deletedSince: try recover(change, snapshotRoot: snapshotRoot)
        case .addedSince: throw Failure(description: L("That was added after the snapshot; there is nothing of it to restore."))
        }
    }

    private func restoreChanged(_ change: ItemChange, snapshotRoot: URL) throws {
        guard let was = change.snapshot, let now = change.book else { return }
        // Where each file of the item is now; a file the item did not have gets a name beside its main file.
        let anchor = now.files["json"] ?? now.files["md"] ?? now.files.values.first ?? ""
        let base = anchor.hasSuffix(".json") ? String(anchor.dropLast(5)) : (anchor as NSString).deletingPathExtension
        for (role, path) in was.files {
            let data = try Data(contentsOf: snapshotRoot.appendingPathComponent(path))
            let destination = now.files[role] ?? (role == "file" ? path : base + suffix(for: role))
            try write(data, to: destination)
        }
        for (role, path) in now.files where was.files[role] == nil { try trash(path) }
    }

    // MARK: Recovering what was deleted

    private func currentCatalog() -> ItemCatalog { ItemCatalog.scan(book) }

    private func uuid() -> String { UUID().uuidString.lowercased() }

    /// Writes numbered files (or a folder) into `folder` at `position` (1-based), making room by renumbering through the journal.
    private func insert(kind: String, into folder: String, at position: Int, _ place: (_ base: String) throws -> Void) throws {
        try fm.createDirectory(at: url(folder), withIntermediateDirectories: true)
        let items = try Renumber.scan(url(folder))
        var order = items.map { Renumber.Slot.item($0.base) }
        let at = min(max(0, position - 1), order.count)
        order.insert(.gap, at: at)
        let steps = try Renumber.plan(folder: folder, items: items, order: order)
        try Renumber.execute(steps, root: book, journal: journal)
        try place(String(format: "%03d-%@", at + 1, kind))
    }

    private func language() -> String {
        ((try? JSONParser.parseObject(Data(contentsOf: url("book.json"))))?.string("language")) ?? "ru"
    }

    /// The chapter called "Recovered" at the top level: found, or made at the end of the book.
    private func recoveredChapterFolder() throws -> String {
        let title = language() == "ru" ? "Восстановлено" : "Recovered"
        let now = currentCatalog()
        if let found = now.items.first(where: { $0.group == .chapter && $0.title == title && $0.parentKey == nil }), let json = found.files["json"] { return directory(of: json) }
        var folder = ""
        let count = try Renumber.scan(url("manuscript")).count
        try insert(kind: "chapter", into: "manuscript", at: count + 1) { base in
            folder = "manuscript/\(base)"
            try write(JSONWriter.data(["id": .string(uuid()), "title": .string(title)]), to: "\(folder)/_chapter.json")
        }
        return folder
    }

    private func folder(ofKey key: String?, in catalog: ItemCatalog) -> String? {
        guard let key, let item = catalog.byKey[key], let json = item.files["json"] else { return nil }
        return directory(of: json)
    }

    /// Puts a deleted item back where it was.
    private func recover(_ change: ItemChange, snapshotRoot: URL) throws {
        guard let was = change.snapshot else { return }
        let now = currentCatalog()
        switch was.group {
        case .scene:
            let chapter = try folder(ofKey: was.parentKey, in: now) ?? recoveredChapterFolder()
            let position = folder(ofKey: was.parentKey, in: now) == nil ? Int.max : was.index
            try insert(kind: "scene", into: chapter, at: position) { base in
                for (role, path) in was.files { try write(Data(contentsOf: snapshotRoot.appendingPathComponent(path)), to: "\(chapter)/\(base)\(suffix(for: role))") }
            }
        case .chapter:
            let parent = folder(ofKey: was.parentKey, in: now)
            let target = parent ?? "manuscript"
            guard let json = was.files["json"] else { return }
            let source = snapshotRoot.appendingPathComponent(directory(of: json))
            try insert(kind: "chapter", into: target, at: parent == nil && was.parentKey != nil ? Int.max : was.index) { base in
                try fm.copyItem(at: source, to: url("\(target)/\(base)"))
            }
        case .part:
            guard let json = was.files["json"] else { return }
            let source = snapshotRoot.appendingPathComponent(directory(of: json))
            try insert(kind: "part", into: "manuscript", at: was.index) { base in
                try fm.copyItem(at: source, to: url("manuscript/\(base)"))
            }
        default:
            // Data files are not numbered: they go back to where they were.
            for path in was.files.values { try write(Data(contentsOf: snapshotRoot.appendingPathComponent(path)), to: path) }
        }
    }

    // MARK: A copy beside the present one

    /// A changed scene, character, place, event… as it was, beside the present one, titled "… (restored)". Returns the new item's id.
    @discardableResult
    public func restoreAsCopy(_ change: ItemChange, snapshotRoot: URL) throws -> String {
        guard let was = change.snapshot else { throw Failure(description: L("Only an item that still exists can be copied beside itself.")) }
        let id = uuid()
        let marker = " (restored)"
        func renamed(_ jsonData: Data, titleKey: String) throws -> Data {
            var object = try JSONParser.parseObject(jsonData)
            object.setString("id", id)
            if let t = object.string(titleKey) { object.setString(titleKey, t + marker) }
            return JSONWriter.data(object)
        }
        switch was.group {
        case .scene:
            let now = currentCatalog()
            guard let current = change.book, let chapter = folder(ofKey: current.parentKey, in: now) else { throw Failure(description: L("The scene's chapter is gone.")) }
            try insert(kind: "scene", into: chapter, at: current.index + 1) { base in
                if let json = was.files["json"] { try write(renamed(Data(contentsOf: snapshotRoot.appendingPathComponent(json)), titleKey: "title"), to: "\(chapter)/\(base).json") }
                if let md = was.files["md"] { try write(Data(contentsOf: snapshotRoot.appendingPathComponent(md)), to: "\(chapter)/\(base).md") }
            }
        case .character, .world, .place, .event, .relationship, .card:
            guard let json = was.files["json"] else { throw Failure(description: L("Nothing to copy.")) }
            let folder = directory(of: json)
            let titleKey = was.group == .event || was.group == .card ? "title" : "name"
            try write(renamed(Data(contentsOf: snapshotRoot.appendingPathComponent(json)), titleKey: titleKey), to: "\(folder)/\(id).json")
            if let md = was.files["md"] { try write(Data(contentsOf: snapshotRoot.appendingPathComponent(md)), to: "\(folder)/\(id).md") }
        default:
            throw Failure(description: L("This kind of item cannot be copied."))
        }
        return id
    }
}
