import Foundation
import Testing
@testable import QuillandCore

@Suite("Looking at snapshots and putting things back")
struct SnapshotInspectorTests {
    /// A book with one chapter of three scenes a, b, c (their text is their title) and a character.
    static func book() throws -> (parent: URL, book: URL, ids: [String]) {
        let (parent, book) = try BookEditorTests.book()
        var s = try BookStructure.load(folder: book)
        let a = s.scenes[0].id
        try BookEditor(structure: s).rename(a, to: "a")
        let b = try BookEditor(structure: s).add(.scene, relativeTo: a, title: "b")
        s = try BookStructure.load(folder: book)
        let c = try BookEditor(structure: s).add(.scene, relativeTo: b, title: "c")
        s = try BookStructure.load(folder: book)
        for e in s.scenes { try Data("Текст \(e.node.title).\n".utf8).write(to: s.markdownURL(for: e.node)) }
        return (parent, book, [a, b, c])
    }

    static func titles(_ book: URL) throws -> [String] { try BookStructure.load(folder: book).scenes.map(\.node.title) }

    @Test("the diff is by item: a changed text, a rename, a deleted scene and a new one are told apart, and a scene that only moved is not a change")
    func diff() throws {
        let (parent, book, ids) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = SnapshotStore(bookFolder: book)
        let info = try store.take(.manual, reason: "x")
        var s = try BookStructure.load(folder: book)
        try Data("Другой текст a.\n".utf8).write(to: s.markdownURL(for: s.scenes[0].node))
        try BookEditor(structure: s).rename(ids[1], to: "b2")
        try BookEditor(structure: s).delete(ids[2])
        s = try BookStructure.load(folder: book)
        let d = try BookEditor(structure: s).add(.scene, relativeTo: ids[0], place: .before, title: "новая")   // everything after it is renumbered
        let changes = SnapshotInspector.diff(snapshot: store.filesFolder(info), book: book)
        let byKey = Dictionary(uniqueKeysWithValues: changes.map { ($0.item.key, $0.status) })
        #expect(byKey["scene:\(ids[0])"] == .changed && byKey["scene:\(ids[1])"] == .changed)
        #expect(byKey["scene:\(ids[2])"] == .deletedSince && byKey["scene:\(d)"] == .addedSince)
        #expect(changes.count == 4, "renumbering moved a scene's files but changed nothing: \(changes.map { "\($0.item.key) \($0.status)" })")
        #expect(changes.first { $0.item.key == "scene:\(ids[0])" }?.item.place == "Chapter 1")
    }

    @Test("restoring a changed scene puts back its text and title where the scene is now")
    func restoreChanged() throws {
        let (parent, book, ids) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = SnapshotStore(bookFolder: book)
        let info = try store.take(.manual)
        var s = try BookStructure.load(folder: book)
        try Data("Испорчено.\n".utf8).write(to: s.markdownURL(for: s.scenes[1].node))
        try BookEditor(structure: s).rename(ids[1], to: "испорчено")
        s = try BookStructure.load(folder: book)
        _ = try BookEditor(structure: s).add(.scene, relativeTo: ids[0], place: .before, title: "перед")
        let change = try #require(SnapshotInspector.diff(snapshot: store.filesFolder(info), book: book).first { $0.item.key == "scene:\(ids[1])" })
        try SnapshotRecovery(book: book).restore(change, snapshotRoot: store.filesFolder(info))
        s = try BookStructure.load(folder: book)
        let restored = try #require(s.scenes.first { $0.id == ids[1] })
        let restoredText = try String(contentsOf: s.markdownURL(for: restored.node), encoding: .utf8)
        #expect(restored.node.title == "b" && restoredText == "Текст b.\n")
        #expect(s.problems.isEmpty && s.scenes.count == 4)
    }

    @Test("a deleted scene comes back in its old place; if its chapter is gone too, in a chapter called Recovered at the end")
    func recoverScene() throws {
        let (parent, book, ids) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = SnapshotStore(bookFolder: book)
        let info = try store.take(.manual)
        var s = try BookStructure.load(folder: book)
        try BookEditor(structure: s).delete(ids[1])
        var change = try #require(SnapshotInspector.diff(snapshot: store.filesFolder(info), book: book).first { $0.item.key == "scene:\(ids[1])" })
        #expect(change.status == .deletedSince)
        try SnapshotRecovery(book: book).restore(change, snapshotRoot: store.filesFolder(info))
        s = try BookStructure.load(folder: book)
        #expect(s.scenes.map(\.node.title) == ["a", "b", "c"] && s.scenes[1].id == ids[1] && s.problems.isEmpty)
        #expect(try String(contentsOf: s.markdownURL(for: s.scenes[1].node), encoding: .utf8) == "Текст b.\n")
        // The whole chapter goes, and a new one is made, so the scene's own chapter is not there.
        let other = try BookEditor(structure: s).add(.chapter, relativeTo: s.roots[0].id, title: "Другая")
        s = try BookStructure.load(folder: book)
        try BookEditor(structure: s).delete(s.roots[0].id)
        change = try #require(SnapshotInspector.diff(snapshot: store.filesFolder(info), book: book).first { $0.item.key == "scene:\(ids[2])" })
        try SnapshotRecovery(book: book).restore(change, snapshotRoot: store.filesFolder(info))
        s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty && s.roots.map(\.title) == ["Другая", "Recovered"] && s.roots[1].children.map(\.id) == [ids[2]] && other == s.roots[0].id)
    }

    @Test("a deleted chapter comes back with its scenes, a deleted part with its chapters, and a deleted character with its text")
    func recoverBigger() throws {
        let (parent, book, ids) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let chapter2 = try BookEditor(structure: s).add(.chapter, relativeTo: s.roots[0].id, title: "Вторая")
        s = try BookStructure.load(folder: book)
        let part = try BookEditor(structure: s).group([s.roots[0].id], intoNewPart: "Часть")
        let chars = CharacterStore(book: book)
        let anna = try chars.add(name: "Анна")
        try chars.setProfile(anna, "Описание Анны.")
        let store = SnapshotStore(bookFolder: book)
        let info = try store.take(.manual)
        s = try BookStructure.load(folder: book)
        try BookEditor(structure: s).delete(chapter2)
        try chars.delete(anna)
        s = try BookStructure.load(folder: book)
        try BookEditor(structure: s).delete(part)
        let changes = SnapshotInspector.diff(snapshot: store.filesFolder(info), book: book)
        let recovery = SnapshotRecovery(book: book)
        // The part first (a part takes its chapters), then the chapter that was in the book at the top level.
        for key in ["part:\(part)", "chapter:\(chapter2)", "characters:\(anna)"] {
            try recovery.restore(try #require(changes.first { $0.item.key == key }), snapshotRoot: store.filesFolder(info))
        }
        s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty)
        #expect(s.roots.map(\.kind) == [.part, .chapter] && s.roots[0].children.map(\.title) == ["Chapter 1"] && s.roots[0].children[0].children.map(\.id) == ids)
        #expect(s.roots[1].id == chapter2 && s.scenes.count == 4)
        let back = CharacterStore(book: book)
        #expect(back.character(anna)?.name == "Анна" && back.profile(anna) == "Описание Анны.")
    }

    @Test("a copy of a scene or a character is made beside the present one with a new id and \"(restored)\"")
    func copy() throws {
        let (parent, book, ids) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let chars = CharacterStore(book: book)
        let anna = try chars.add(name: "Анна")
        let store = SnapshotStore(bookFolder: book)
        let info = try store.take(.manual)
        var s = try BookStructure.load(folder: book)
        try Data("Теперь по-другому.\n".utf8).write(to: s.markdownURL(for: s.scenes[0].node))
        try chars.update(anna) { $0.name = "Анна П." }
        let changes = SnapshotInspector.diff(snapshot: store.filesFolder(info), book: book)
        let recovery = SnapshotRecovery(book: book)
        let newScene = try recovery.restoreAsCopy(try #require(changes.first { $0.item.key == "scene:\(ids[0])" }), snapshotRoot: store.filesFolder(info))
        _ = try recovery.restoreAsCopy(try #require(changes.first { $0.item.key == "characters:\(anna)" }), snapshotRoot: store.filesFolder(info))
        s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty && s.scenes.map(\.node.title) == ["a", "a (restored)", "b", "c"] && s.scenes[1].id == newScene)
        #expect(try String(contentsOf: s.markdownURL(for: s.scenes[1].node), encoding: .utf8) == "Текст a.\n")
        #expect(try String(contentsOf: s.markdownURL(for: s.scenes[0].node), encoding: .utf8) == "Теперь по-другому.\n")
        let names = CharacterStore(book: book).characters.compactMap(\.name).sorted()
        #expect(names == ["Анна (restored)", "Анна П."])
    }

    @Test("paragraphs are compared: what was removed and what was added, the rest kept")
    func paragraphs() {
        let ops = ParagraphDiff.diff(old: ["один", "два", "три"], new: ["один", "два!", "три", "четыре"])
        #expect(ops == [.init(kind: .same, text: "один"), .init(kind: .removed, text: "два"), .init(kind: .added, text: "два!"), .init(kind: .same, text: "три"), .init(kind: .added, text: "четыре")])
        #expect(ParagraphDiff.diff(old: [], new: ["x"]) == [.init(kind: .added, text: "x")])
        #expect(ParagraphDiff.diff(old: ["x"], new: []) == [.init(kind: .removed, text: "x")])
        #expect(ParagraphDiff.paragraphs("a\n\n  b  \n") == ["a", "b"])
    }

    @Test("a snapshot can be named and is then kept; the quick count and the disk use make sense")
    func storeExtras() throws {
        let (parent, book, _) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = SnapshotStore(bookFolder: book)
        let info = try store.take(.automatic, reason: "x")
        #expect(store.quickDiff(info) == (0, 0, 0))
        let s = try BookStructure.load(folder: book)
        try Data(String(repeating: "новый текст ", count: 200).utf8).write(to: s.markdownURL(for: s.scenes[0].node))
        try Data("x".utf8).write(to: book.appendingPathComponent("extra.txt"))
        try FileManager.default.removeItem(at: s.markdownURL(for: s.scenes[1].node))
        let q = store.quickDiff(info)
        #expect(q.changed == 1 && q.added == 1 && q.deleted == 1)
        #expect(store.diskUsage() > 0)
        try store.name(info, as: "До правки")
        let named = try #require(store.list().first)
        #expect(named.name == "До правки" && named.kind == .manual)
        // A named snapshot survives thinning however old it is.
        let old = Date().addingTimeInterval(-400 * 24 * 3600)
        #expect(store.survivors(of: [SnapshotStore.Info(id: named.id, date: old, kind: .manual, name: "До правки", reason: nil, cloned: true)], now: Date()).contains(named.id))
    }
}
