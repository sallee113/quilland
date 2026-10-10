import Foundation

/// Changes to the structure of a book on disk: new parts, chapters and scenes, titles, statuses, moving and deleting
/// (quilland-ui.md, "The Section menu"). Every change of position goes through `Renumber`, so the numbers stay consecutive and a crash
/// never leaves an item half renamed. Reading the result back is `BookStructure.load`.
public struct BookEditor {
    public enum Place: Sendable { case before, after, insideEnd }

    public struct Failure: Error, CustomStringConvertible {
        public var description: String
        public init(description: String) { self.description = description }
    }

    public let folder: URL
    public let structure: BookStructure
    public var language: String

    public init(structure: BookStructure) {
        self.structure = structure
        folder = structure.folder
        let info = (try? JSONParser.parseObject(Data(contentsOf: structure.folder.appendingPathComponent("book.json")))) ?? [:]
        language = info.string("language") ?? "ru"
    }

    private var journal: URL { folder.appendingPathComponent(".quilland/journal.json") }

    // MARK: Looking up

    /// The node with this id and the folder (relative to the book) and the list of its siblings.
    private func locate(_ id: String) -> (node: BookStructure.Node, folder: String, siblings: [BookStructure.Node], parent: BookStructure.Node?)? {
        for root in structure.roots {
            if root.id == id { return (root, "manuscript", structure.roots, nil) }
            for child in root.children {
                if child.id == id { return (child, root.base, root.children, root) }
                for scene in child.children where scene.id == id { return (scene, child.base, child.children, child) }
            }
        }
        return nil
    }

    private func node(_ id: String) -> BookStructure.Node? { locate(id)?.node }

    /// The name of an item (`003-scene`) from the base path of a node.
    private func itemName(_ base: String) -> String { base.split(separator: "/").last.map(String.init) ?? base }

    // MARK: New sections

    /// A new scene, chapter or part next to `anchor` (or inside it, at the end). Returns the new section's id.
    /// A scene goes into a chapter, a chapter into a part or the book, a part into the book: where the anchor is of another level,
    /// the new section goes beside the anchor's ancestor of its own level.
    @discardableResult
    public func add(_ kind: BookStructure.Kind, relativeTo anchorID: String?, place: Place = .after, title: String? = nil) throws -> String {
        let (targetFolder, siblings, index) = try target(for: kind, anchor: anchorID, place: place)
        let id = UUID().uuidString.lowercased()
        let name = title ?? defaultTitle(kind)
        let slots = siblings.map { Renumber.Slot.item(itemName($0.base)) }
        var order = slots
        order.insert(.gap, at: min(index, order.count))
        let items = try Renumber.scan(folder.appendingPathComponent(targetFolder))
        let steps = try Renumber.plan(folder: targetFolder, items: items, order: order)
        try Renumber.execute(steps, root: folder, journal: journal)

        let number = min(index, siblings.count) + 1
        let base = String(format: "%03d-%@", number, kind.rawValue)
        let fm = FileManager.default
        func write(_ path: String, _ object: JSONObject) throws {
            let url = folder.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AtomicFile.write(JSONWriter.data(object), to: url)
        }
        switch kind {
        case .scene:
            try write("\(targetFolder)/\(base).json", ["id": .string(id), "status": .string("idea"), "title": .string(name)])
            try AtomicFile.write(Data(), to: folder.appendingPathComponent("\(targetFolder)/\(base).md"))
        case .chapter:
            try write("\(targetFolder)/\(base)/_chapter.json", ["id": .string(id), "title": .string(name)])
            // A chapter starts with an empty first scene, so it is never an empty folder in the Book view.
            try write("\(targetFolder)/\(base)/001-scene.json", ["id": .string(UUID().uuidString.lowercased()), "status": .string("idea"), "title": .string(defaultTitle(.scene))])
            try AtomicFile.write(Data(), to: folder.appendingPathComponent("\(targetFolder)/\(base)/001-scene.md"))
        case .part:
            try write("\(targetFolder)/\(base)/_part.json", ["id": .string(id), "title": .string(name)])
        }
        return id
    }

    private func defaultTitle(_ kind: BookStructure.Kind) -> String {
        let ru = language == "ru"
        switch kind {
        case .scene: return ru ? "Новая сцена" : "New Scene"
        case .chapter: return ru ? "Новая глава" : "New Chapter"
        case .part: return ru ? "Новая часть" : "New Part"
        }
    }

    /// The folder the new section goes into, the siblings already there, and its index among them.
    private func target(for kind: BookStructure.Kind, anchor: String?, place: Place) throws -> (String, [BookStructure.Node], Int) {
        guard let anchorID = anchor, let here = locate(anchorID) else {
            // No anchor: at the end of the book (a scene or a chapter without a place goes into the last chapter or the book).
            switch kind {
            case .part, .chapter: return ("manuscript", structure.roots, structure.roots.count)
            case .scene:
                guard let chapter = structure.roots.last(where: { $0.kind == .chapter }) ?? structure.roots.last?.children.last else { throw Failure(description: L("A scene needs a chapter.")) }
                return (chapter.base, chapter.children, chapter.children.count)
            }
        }
        // The anchor's ancestors and itself, from the outside in.
        func level(_ k: BookStructure.Kind) -> Int { k == .part ? 0 : k == .chapter ? 1 : 2 }
        if level(here.node.kind) == level(kind) {
            let index = siblingIndex(here.node.id, in: here.siblings) + (place == .before ? 0 : 1)
            return (here.folder, here.siblings, index)
        }
        if level(here.node.kind) < level(kind) {
            // The anchor is a bigger section (a chapter for a new scene): inside it, at the end.
            if kind == .scene, here.node.kind == .part {
                guard let chapter = here.node.children.last else { throw Failure(description: L("A scene needs a chapter.")) }
                return (chapter.base, chapter.children, chapter.children.count)
            }
            return (here.node.base, here.node.children, here.node.children.count)
        }
        // The anchor is a smaller section (a scene for a new chapter): beside its chapter or part.
        var up = here
        while level(up.node.kind) > level(kind), let parent = up.parent, let found = locate(parent.id) { up = found }
        if level(up.node.kind) != level(kind) {
            // A chapter that sits straight in the book has no part: a new part goes beside it.
            guard kind == .part, up.parent == nil else { throw Failure(description: L("No place for a {kind} here.", ["kind": L(kind.rawValue)])) }
            let index = siblingIndex(up.node.id, in: up.siblings) + (place == .before ? 0 : 1)
            return ("manuscript", structure.roots, index)
        }
        let index = siblingIndex(up.node.id, in: up.siblings) + (place == .before ? 0 : 1)
        return (up.folder, up.siblings, index)
    }

    private func siblingIndex(_ id: String, in list: [BookStructure.Node]) -> Int { list.firstIndex { $0.id == id } ?? list.count }

    // MARK: Titles and statuses (never rename a file)

    private func jsonURL(_ node: BookStructure.Node) -> URL {
        switch node.kind {
        case .scene: return folder.appendingPathComponent(node.base + ".json")
        case .chapter: return folder.appendingPathComponent(node.base + "/_chapter.json")
        case .part: return folder.appendingPathComponent(node.base + "/_part.json")
        }
    }

    private func update(_ id: String, _ change: (inout JSONObject) -> Void) throws {
        guard let node = node(id) else { throw Failure(description: L("No such section.")) }
        let url = jsonURL(node)
        var object = try JSONParser.parseObject(Data(contentsOf: url))
        change(&object)
        try AtomicFile.write(JSONWriter.data(object), to: url)
    }

    /// The whole JSON record of a section (a scene's, a chapter's or a part's), with what the app does not know.
    public func record(_ id: String) -> JSONObject? {
        guard let node = node(id) else { return nil }
        return try? JSONParser.parseObject(Data(contentsOf: jsonURL(node)))
    }

    /// Sets (or, with an empty text, removes) a text field of a section: `synopsis` or `note`.
    public func setText(_ id: String, key: String, to text: String) throws { try update(id) { $0.setString(key, text.isEmpty ? nil : text) } }

    /// The size a scene should reach, in characters; nil removes it.
    public func setTarget(_ id: String, to characters: Int?) throws { try update(id) { $0.setInt("target_characters", characters) } }

    public func rename(_ id: String, to title: String) throws { try update(id) { $0.setString("title", title) } }
    public func setStatus(_ id: String, to status: String) throws { try update(id) { $0.setString("status", status) } }

    // MARK: Moving and deleting

    /// Moves a section one place up or down among its siblings. Returns false at the end of the row.
    @discardableResult
    public func move(_ id: String, by step: Int) throws -> Bool {
        guard let here = locate(id), let index = here.siblings.firstIndex(where: { $0.id == id }) else { throw Failure(description: L("No such section.")) }
        let target = index + step
        guard here.siblings.indices.contains(target) else { return false }
        var names = here.siblings.map { itemName($0.base) }
        names.swapAt(index, target)
        let items = try Renumber.scan(folder.appendingPathComponent(here.folder))
        let steps = try Renumber.plan(folder: here.folder, items: items, order: names.map { .item($0) })
        try Renumber.execute(steps, root: folder, journal: journal)
        return true
    }

    /// Moves a section under another parent (a chapter for a scene, a part or the book for a chapter, the book for a part) at `index`
    /// among the parent's children as they are now (the index of a drop, before the section is taken out). One journalled change.
    /// Returns false when the section would stay where it is.
    @discardableResult
    public func move(_ id: String, toParent parentID: String?, at index: Int) throws -> Bool {
        guard let here = locate(id), let from = here.siblings.firstIndex(where: { $0.id == id }) else { throw Failure(description: L("No such section.")) }
        let targetFolder: String
        let targetSiblings: [BookStructure.Node]
        if let parentID {
            guard let parent = node(parentID) else { throw Failure(description: L("No such parent.")) }
            let fits = (here.node.kind == .scene && parent.kind == .chapter) || (here.node.kind == .chapter && parent.kind == .part)
            guard fits else { throw Failure(description: L("A {kind} cannot go into a {parent}.", ["kind": L(here.node.kind.rawValue), "parent": L(parent.kind.rawValue)])) }
            targetFolder = parent.base
            targetSiblings = parent.children
        } else {
            guard here.node.kind != .scene else { throw Failure(description: L("A scene goes into a chapter.")) }
            targetFolder = "manuscript"
            targetSiblings = structure.roots
        }
        let name = itemName(here.node.base)
        let sameFolder = targetFolder == here.folder
        if sameFolder {
            var names = here.siblings.map { itemName($0.base) }
            let at = min(max(0, index), names.count)
            names.remove(at: from)
            names.insert(name, at: at > from ? at - 1 : at)
            guard names != here.siblings.map({ itemName($0.base) }) else { return false }
            let items = try Renumber.scan(folder.appendingPathComponent(here.folder))
            let steps = try Renumber.plan(folder: here.folder, items: items, order: names.map { .item($0) })
            try Renumber.execute(steps, root: folder, journal: journal)
            return true
        }
        // Another folder, in two journalled steps: the new folder opens a gap and the section's files go into it (the item first, while the
        // folders still have their old names); then the old folder closes its gap, found again by the id of its parent, since renumbering
        // may have renamed it.
        let targetItems = try Renumber.scan(folder.appendingPathComponent(targetFolder))
        let sourceItems = try Renumber.scan(folder.appendingPathComponent(here.folder))
        guard let item = sourceItems.first(where: { $0.base == name }) else { throw Failure(description: L("No such item.")) }
        var targetOrder = targetSiblings.map { Renumber.Slot.item(itemName($0.base)) }
        let at = min(max(0, index), targetOrder.count)
        targetOrder.insert(.gap, at: at)
        let newBase = String(format: "%03d-%@", at + 1, item.kind)
        var steps: [Renumber.Step] = []
        for (k, member) in item.members.enumerated() {
            steps.append(Renumber.Step(from: "\(here.folder)/\(member)", temp: "\(targetFolder)/.quilland-mv-item-\(k)", to: "\(targetFolder)/\(newBase)\(member.dropFirst(name.count))"))
        }
        steps += try Renumber.plan(folder: targetFolder, items: targetItems, order: targetOrder)
        try Renumber.execute(steps, root: folder, journal: journal)

        let fresh = try BookStructure.load(folder: folder)
        let sourceFolder: String
        if let parent = here.parent?.id {
            guard let base = BookEditor(structure: fresh).node(parent)?.base else { return true }
            sourceFolder = base
        } else {
            sourceFolder = "manuscript"
        }
        let remaining = try Renumber.scan(folder.appendingPathComponent(sourceFolder))
        let close = try Renumber.plan(folder: sourceFolder, items: remaining, order: remaining.map { .item($0.base) })
        try Renumber.execute(close, root: folder, journal: journal)
        return true
    }

    // MARK: Merging, grouping

    /// Merges the second scene into the first: its text follows the first's, its synopsis and note are added as new paragraphs, its tags are
    /// added without duplicates, and links to it point at the first scene. The second scene's files go to the trash folder.
    /// The files on disk are what is merged (save the open scenes first). Returns how many data files had links moved.
    @discardableResult
    public func merge(_ firstID: String, with secondID: String) throws -> Int {
        guard let a = locate(firstID), let b = locate(secondID), a.node.kind == .scene, b.node.kind == .scene, firstID != secondID else {
            throw Failure(description: L("Two scenes are needed."))
        }
        let first = MarkdownParser.parse((try? String(contentsOf: structure.markdownURL(for: a.node), encoding: .utf8)) ?? "")
        let second = MarkdownParser.parse((try? String(contentsOf: structure.markdownURL(for: b.node), encoding: .utf8)) ?? "")
        let merged = MarkdownWriter.write(Document(first.blocks + second.blocks))
        try AtomicFile.write(Data(merged.utf8), to: structure.markdownURL(for: a.node))
        let other = record(secondID) ?? [:]
        try update(firstID) { o in
            func join(_ key: String) {
                let x = o.string(key) ?? "", y = other.string(key) ?? ""
                if !y.isEmpty { o.setString(key, x.isEmpty ? y : x + "\n\n" + y) }
            }
            join("synopsis"); join("note")
            var tags = o.strings("tags") ?? []
            for t in other.strings("tags") ?? [] where !tags.contains(t) { tags.append(t) }
            if !tags.isEmpty { o.setStrings("tags", tags) }
        }
        let moved = try BookRelinker.retarget(book: folder, from: secondID, to: firstID)
        try delete(secondID)
        return moved
    }

    /// A new part around these chapters (loose chapters of the book), which move into it keeping their order and ids.
    /// The part takes the place of the first of them. Returns the new part's id.
    @discardableResult
    public func group(_ chapterIDs: [String], intoNewPart title: String) throws -> String {
        let roots = structure.roots
        let chosen = roots.filter { chapterIDs.contains($0.id) }
        guard !chosen.isEmpty, chosen.count == chapterIDs.count, chosen.allSatisfy({ $0.kind == .chapter }) else {
            throw Failure(description: L("Only chapters that are not in a part can be grouped."))
        }
        let part = try add(.part, relativeTo: chosen[0].id, place: .before, title: title)
        for chapter in chosen {
            let fresh = try BookStructure.load(folder: folder)
            try BookEditor(structure: fresh).move(chapter.id, toParent: part, at: Int.max)
        }
        return part
    }

    /// The chapters of a part move up to where the part was; the part's own title, text, synopsis and note go to the trash folder.
    public func ungroup(_ partID: String) throws {
        guard let here = locate(partID), here.node.kind == .part else { throw Failure(description: L("Not a part.")) }
        for chapter in here.node.children {
            let fresh = try BookStructure.load(folder: folder)
            guard let at = fresh.roots.firstIndex(where: { $0.id == partID }) else { break }
            try BookEditor(structure: fresh).move(chapter.id, toParent: nil, at: at)
        }
        let fresh = try BookStructure.load(folder: folder)
        try BookEditor(structure: fresh).delete(partID)
    }

    /// Takes a section out of the book into `.quilland/trash/<stamp>/` (a part or a chapter with everything in it), and closes the gap.
    public func delete(_ id: String) throws {
        guard let here = locate(id) else { throw Failure(description: L("No such section.")) }
        let remaining = here.siblings.filter { $0.id != id }.map { Renumber.Slot.item(itemName($0.base)) }
        let stamp = TrashFolder.newName()
        let trash = ".quilland/trash/\(stamp)"
        let items = try Renumber.scan(folder.appendingPathComponent(here.folder))
        let steps = try Renumber.plan(folder: here.folder, items: items, order: remaining, removed: [itemName(here.node.base)], trash: trash)
        try Renumber.execute(steps, root: folder, journal: journal)
    }

    /// How much goes with a section: its scenes and its characters, for the warning before a delete.
    public func weight(of id: String, characters: (String) -> Int) -> (scenes: Int, characters: Int) {
        guard let n = node(id) else { return (0, 0) }
        func scenes(_ node: BookStructure.Node) -> [BookStructure.Node] { node.kind == .scene ? [node] : node.children.flatMap(scenes) }
        let list = scenes(n)
        return (list.count, list.reduce(0) { $0 + characters($1.id) })
    }
}
