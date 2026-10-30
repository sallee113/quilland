import Foundation

/// The structure of a book as it is on disk: parts, chapters and scenes in book order, with their ids, titles and statuses.
/// Read once and kept by the application; the text of a scene is not in it (that is `<base>.md`).
public struct BookStructure: Sendable {
    /// `subsection` is only in the tree the application shows (the part of a scene between two markers): the files of the book have parts, chapters and scenes.
    public enum Kind: String, Sendable { case part, chapter, scene, subsection }

    public struct Node: Identifiable, Sendable, Equatable {
        public var id: String
        public var kind: Kind
        public var title: String
        /// Scenes only: idea, draft, revised, done (or an unknown word, kept).
        public var status: String?
        /// The path of the object's files relative to the book, without the extension (`manuscript/001-part/002-chapter/003-scene`).
        /// For a part or a chapter, the folder.
        public var base: String
        public var children: [Node]

        public init(id: String, kind: Kind, title: String, status: String?, base: String, children: [Node]) {
            self.id = id; self.kind = kind; self.title = title; self.status = status; self.base = base; self.children = children
        }
    }

    /// A scene with the place it has in the book, in book order.
    public struct SceneEntry: Identifiable, Sendable, Equatable {
        public var node: Node
        public var chapterID: String?
        public var chapterTitle: String?
        public var partID: String?
        public var partTitle: String?
        public var id: String { node.id }
    }

    public let folder: URL
    public var roots: [Node] = []
    /// Every scene in book order.
    public var scenes: [SceneEntry] = []
    /// What could not be read (a file that does not parse is reported and left alone).
    public var problems: [String] = []
    /// The subsections of the scenes that have any, by scene id (read from the scene files when the structure is loaded).
    public var subsections: [String: [Subsection]] = [:]

    public init(folder: URL) { self.folder = folder }

    /// Changes a section's title or status in what is kept (the files are written by `BookEditor`).
    public mutating func update(id: String, title: String? = nil, status: String? = nil) {
        func patch(_ node: inout Node) {
            if node.id == id {
                if let title { node.title = title }
                if let status { node.status = status }
            }
            for i in node.children.indices { patch(&node.children[i]) }
        }
        for i in roots.indices { patch(&roots[i]) }
        for i in scenes.indices where scenes[i].node.id == id {
            if let title { scenes[i].node.title = title }
            if let status { scenes[i].node.status = status }
        }
        for i in scenes.indices {
            if scenes[i].chapterID == id, let title { scenes[i].chapterTitle = title }
            if scenes[i].partID == id, let title { scenes[i].partTitle = title }
        }
    }

    /// True when the book's files all read (for the checks).
    public static func problemsFree(_ folder: URL) -> Bool { ((try? load(folder: folder))?.problems.isEmpty) ?? false }

    public func markdownURL(for node: Node) -> URL { folder.appendingPathComponent(node.base + ".md") }
    public func jsonURL(for node: Node) -> URL { folder.appendingPathComponent(node.base + ".json") }

    public static func load(folder: URL) throws -> BookStructure {
        var book = BookStructure(folder: folder)
        let manuscript = folder.appendingPathComponent("manuscript")
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: manuscript.path) else { return book }

        func object(_ url: URL) -> JSONObject? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            do { return try JSONParser.parseObject(data) } catch {
                book.problems.append("\(url.lastPathComponent): \(error)")
                return nil
            }
        }
        func isDirectory(_ url: URL) -> Bool {
            var flag: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
        }
        func chapter(at url: URL, relative: String) -> Node? {
            guard let meta = object(url.appendingPathComponent("_chapter.json")), let id = meta.string("id") else { return nil }
            var node = Node(id: id, kind: .chapter, title: meta.string("title") ?? "", status: nil, base: relative, children: [])
            for file in ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() where file.hasSuffix("-scene.json") && !file.hasSuffix(".notes.json") {
                guard let scene = object(url.appendingPathComponent(file)), let sceneID = scene.string("id") else { continue }
                let record = SceneRecord(object: scene)
                node.children.append(Node(id: sceneID, kind: .scene, title: record.title ?? "", status: record.status, base: relative + "/" + String(file.dropLast(5)), children: []))
            }
            return node
        }

        for name in names.sorted() {
            let url = manuscript.appendingPathComponent(name)
            guard isDirectory(url) else { continue }
            let relative = "manuscript/" + name
            if name.hasSuffix("-part") {
                guard let meta = object(url.appendingPathComponent("_part.json")), let id = meta.string("id") else { continue }
                var part = Node(id: id, kind: .part, title: meta.string("title") ?? "", status: nil, base: relative, children: [])
                for sub in ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() where sub.hasSuffix("-chapter") {
                    if let c = chapter(at: url.appendingPathComponent(sub), relative: relative + "/" + sub) { part.children.append(c) }
                }
                book.roots.append(part)
            } else if name.hasSuffix("-chapter") {
                if let c = chapter(at: url, relative: relative) { book.roots.append(c) }
            }
        }
        for root in book.roots {
            switch root.kind {
            case .part:
                for c in root.children { for s in c.children { book.scenes.append(SceneEntry(node: s, chapterID: c.id, chapterTitle: c.title, partID: root.id, partTitle: root.title)) } }
            case .chapter:
                for s in root.children { book.scenes.append(SceneEntry(node: s, chapterID: root.id, chapterTitle: root.title, partID: nil, partTitle: nil)) }
            case .scene, .subsection: break
            }
        }
        // The subsections: the markers in the text of the scenes (and the titles typed for them), and the table that tells a link to a subsection which scene it belongs to.
        var table: [String: String] = [:]
        for s in book.scenes {
            let base = folder.appendingPathComponent(s.node.base)
            guard let data = try? Data(contentsOf: base.appendingPathExtension("md")), let text = String(data: data, encoding: .utf8), text.contains("<!-- fragment: ") else { continue }
            let titles = (try? JSONParser.parseObject(Data(contentsOf: base.appendingPathExtension("json")))).map { SceneRecord(object: $0).fragmentTitles } ?? [:]
            let list = Subsections.parse(scene: s.node.id, markdown: text, titles: titles)
            guard !list.isEmpty else { continue }
            book.subsections[s.node.id] = list
            for sub in list where sub.isMarked { table[sub.id] = s.node.id }
        }
        SceneLinks.set(table, forBook: folder)
        return book
    }
}
