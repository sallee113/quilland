import Foundation
import CryptoKit

/// What a book (or a snapshot of it) holds, as items the author knows: scenes, chapters, parts, characters, cards… found by id, not by file
/// name, so a scene that only moved (and was renumbered) is the same scene.
public struct ItemCatalog: Sendable {
    public enum Group: Int, Sendable, CaseIterable {
        case part, chapter, scene, character, world, place, event, relationship, other, card, plan, book
        public var label: String {
            switch self {
            case .part: return L("Parts")
            case .chapter: return L("Chapters")
            case .scene: return L("Scenes")
            case .character: return L("Characters")
            case .world: return L("Worlds")
            case .place: return L("Places")
            case .event: return L("Events")
            case .relationship: return L("Relationships")
            case .other: return L("Other")
            case .card: return L("Plan cards")
            case .plan: return L("Plan lines")
            case .book: return L("Book settings")
            }
        }
    }

    public struct Item: Sendable {
        public var key: String
        public var group: Group
        public var title: String
        /// Where it sits ("Part › Chapter").
        public var place: String
        /// The key of the chapter or part it is in, and its place among its brothers (for putting a deleted one back).
        public var parentKey: String?
        public var index: Int
        /// The files of the item, relative to the root, by role (`json`, `md`, `notes`, `file`).
        public var files: [String: String]
        public var digest: String
    }

    public private(set) var items: [Item] = []
    public var byKey: [String: Item] { Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }) }
    public func children(of key: String) -> [Item] { items.filter { $0.parentKey == key }.sorted { $0.index < $1.index } }

    public static func scan(_ root: URL) -> ItemCatalog {
        var catalog = ItemCatalog()
        let fm = FileManager.default
        func names(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
        func isDirectory(_ url: URL) -> Bool { var d: ObjCBool = false; return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue }
        func object(_ relative: String) -> JSONObject? { (try? Data(contentsOf: root.appendingPathComponent(relative))).flatMap { try? JSONParser.parseObject($0) } }
        func exists(_ relative: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(relative).path) }
        func digest(_ files: [String: String]) -> String {
            var hasher = SHA256()
            for role in files.keys.sorted() {
                hasher.update(data: Data(role.utf8))
                hasher.update(data: (try? Data(contentsOf: root.appendingPathComponent(files[role]!))) ?? Data())
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        func add(_ key: String, _ group: Group, title: String, place: String = "", parent: String? = nil, index: Int = 0, files: [String: String]) {
            let present = files.filter { exists($0.value) }
            guard !present.isEmpty else { return }
            catalog.items.append(Item(key: key, group: group, title: title, place: place, parentKey: parent, index: index, files: present, digest: digest(present)))
        }

        // The manuscript.
        let manuscript = "manuscript"
        func chapter(_ folder: String, partKey: String?, partTitle: String, index: Int) {
            guard let meta = object("\(folder)/_chapter.json"), let id = meta.string("id") else { return }
            let title = meta.string("title") ?? ""
            let place = partTitle.isEmpty ? "" : partTitle
            add("chapter:\(id)", .chapter, title: title, place: place, parent: partKey, index: index, files: ["json": "\(folder)/_chapter.json", "md": "\(folder)/_chapter.md"])
            var i = 0
            for file in names(root.appendingPathComponent(folder)) where file.hasSuffix("-scene.json") && !file.hasSuffix(".notes.json") {
                let base = "\(folder)/" + String(file.dropLast(5))
                guard let s = object(base + ".json"), let sid = s.string("id") else { continue }
                i += 1
                add("scene:\(sid)", .scene, title: s.string("title") ?? "", place: [partTitle, title].filter { !$0.isEmpty }.joined(separator: " › "),
                    parent: "chapter:\(id)", index: i, files: ["json": base + ".json", "md": base + ".md", "notes": base + ".notes.json"])
            }
        }
        var rootIndex = 0
        for name in names(root.appendingPathComponent(manuscript)) {
            let rel = "\(manuscript)/\(name)"
            if name == "001-title-page.json", let t = object(rel), let id = t.string("id") {
                add("titlepage:\(id)", .other, title: t.string("title") ?? "Title page", files: ["json": rel, "md": "\(manuscript)/001-title-page.md"])
                continue
            }
            guard isDirectory(root.appendingPathComponent(rel)) else { continue }
            rootIndex += 1
            if name.hasSuffix("-part"), let meta = object("\(rel)/_part.json"), let id = meta.string("id") {
                let title = meta.string("title") ?? ""
                add("part:\(id)", .part, title: title, index: rootIndex, files: ["json": "\(rel)/_part.json", "md": "\(rel)/_part.md"])
                var ci = 0
                for sub in names(root.appendingPathComponent(rel)) where sub.hasSuffix("-chapter") { ci += 1; chapter("\(rel)/\(sub)", partKey: "part:\(id)", partTitle: title, index: ci) }
            } else if name.hasSuffix("-chapter") {
                chapter(rel, partKey: nil, partTitle: "", index: rootIndex)
            }
        }

        // The data of the book.
        let kinds: [(String, Group)] = [("characters", .character), ("worlds", .world), ("places", .place), ("events", .event), ("relationships", .relationship)]
        for (folder, group) in kinds {
            for file in names(root.appendingPathComponent("bible/\(folder)")) where file.hasSuffix(".json") {
                let id = String(file.dropLast(5))
                let o = object("bible/\(folder)/\(file)")
                add("\(folder):\(id)", group, title: o?.string("name") ?? o?.string("title") ?? id, files: ["json": "bible/\(folder)/\(file)", "md": "bible/\(folder)/\(id).md"])
            }
        }
        for file in names(root.appendingPathComponent("bible/kinds")) where file.hasSuffix(".json") {
            let o = object("bible/kinds/\(file)")
            add("kind:\(file.dropLast(5))", .other, title: o?.object("name")?.string("many") ?? String(file.dropLast(5)), files: ["json": "bible/kinds/\(file)"])
        }
        add("plot", .other, title: "The plot", files: ["md": "bible/plot.md"])
        for file in names(root.appendingPathComponent("plan/cards")) where file.hasSuffix(".json") {
            let o = object("plan/cards/\(file)")
            add("card:\(file.dropLast(5))", .card, title: o?.string("title") ?? String(file.dropLast(5)), files: ["json": "plan/cards/\(file)"])
        }
        add("plan", .plan, title: "Plot lines and the order of events", files: ["json": "plan/canvas.json"])
        add("book", .book, title: "Book (title, author, language)", files: ["json": "book.json"])
        add("export", .book, title: "Export profiles", files: ["json": "export.json"])
        add("dictionary", .book, title: "Dictionary", files: ["json": "dictionary.json"])
        for file in names(root.appendingPathComponent("assets")) { add("asset:\(file)", .other, title: file, files: ["file": "assets/\(file)"]) }
        return catalog
    }
}

public struct ItemChange: Sendable {
    public enum Status: String, Sendable { case changed, addedSince, deletedSince }
    public var status: Status
    /// The item as the snapshot had it (nil for what was added since).
    public var snapshot: ItemCatalog.Item?
    /// The item as the book has it now (nil for what was deleted since).
    public var book: ItemCatalog.Item?
    public var item: ItemCatalog.Item { (snapshot ?? book)! }
    public var label: String {
        switch status {
        case .changed: return "changed"
        case .addedSince: return "added since"
        case .deletedSince: return "deleted since"
        }
    }
}

public enum SnapshotInspector {
    /// What differs between a snapshot and the book now, by item, in the order of the book (the snapshot's order for what is gone).
    public static func diff(snapshot: URL, book: URL) -> [ItemChange] {
        let was = ItemCatalog.scan(snapshot)
        let now = ItemCatalog.scan(book)
        let nowByKey = now.byKey
        let wasByKey = was.byKey
        var out: [ItemChange] = []
        for item in was.items {
            if let current = nowByKey[item.key] {
                if current.digest != item.digest { out.append(ItemChange(status: .changed, snapshot: item, book: current)) }
            } else {
                out.append(ItemChange(status: .deletedSince, snapshot: item, book: nil))
            }
        }
        for item in now.items where wasByKey[item.key] == nil { out.append(ItemChange(status: .addedSince, snapshot: nil, book: item)) }
        return out.sorted {
            ($0.item.group.rawValue, $0.status == .addedSince ? 1 : 0, $0.item.index) < ($1.item.group.rawValue, $1.status == .addedSince ? 1 : 0, $1.item.index)
        }
    }

    /// The text of an item for showing: its Markdown if it has one, otherwise its JSON.
    public static func text(of item: ItemCatalog.Item, in root: URL) -> String {
        let role = item.files["md"] != nil ? "md" : (item.files["json"] != nil ? "json" : item.files.keys.first ?? "")
        guard let path = item.files[role], let data = try? Data(contentsOf: root.appendingPathComponent(path)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: Comparing paragraphs

public enum ParagraphDiff {
    public struct Op: Equatable, Sendable {
        public enum Kind: Sendable { case same, removed, added }
        public var kind: Kind
        public var text: String
    }

    public static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// What was removed and what was added, paragraph by paragraph (the longest common run is kept).
    public static func diff(old: [String], new: [String]) -> [Op] {
        let n = old.count, m = new.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = old[i] == new[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, old[i] == new[j] { ops.append(Op(kind: .same, text: old[i])); i += 1; j += 1 }
            else if i < n, j >= m || table[i + 1][j] >= table[i][j + 1] { ops.append(Op(kind: .removed, text: old[i])); i += 1 }
            else { ops.append(Op(kind: .added, text: new[j])); j += 1 }
        }
        return ops
    }
}
