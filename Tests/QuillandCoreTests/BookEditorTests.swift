import Foundation
import Testing
@testable import QuillandCore

@Suite("Changing the structure of a book")
struct BookEditorTests {
    static func book() throws -> (URL, URL) {
        let parent = try NewBookTests.folder()
        return (parent, try BookCreator.create(NewBookRequest(title: "B", language: "en", parentFolder: parent)))
    }

    static func editor(_ book: URL) throws -> BookEditor { BookEditor(structure: try BookStructure.load(folder: book)) }
    static func titles(_ book: URL) throws -> [String] { try BookStructure.load(folder: book).scenes.map(\.node.title) }

    @Test("new scenes go before, after and into a chapter, and the numbers stay consecutive")
    func scenes() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let first = try Self.editor(book).structure.scenes[0].id
        let b = try Self.editor(book).add(.scene, relativeTo: first, title: "B")
        let a = try Self.editor(book).add(.scene, relativeTo: first, place: .before, title: "A")
        _ = try Self.editor(book).add(.scene, relativeTo: b, title: "C")
        #expect(try Self.titles(book) == ["A", "Scene 1", "B", "C"])
        let names = try FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent("manuscript/001-chapter").path).sorted()
        #expect(names.filter { $0.hasSuffix(".md") } == ["001-scene.md", "002-scene.md", "003-scene.md", "004-scene.md"])
        #expect(try BookStructure.load(folder: book).problems.isEmpty && a != b)
    }

    @Test("a new chapter after a scene goes beside its chapter; a scene into a chapter goes at the end")
    func chapters() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let scene = try Self.editor(book).structure.scenes[0].id
        let chapter = try Self.editor(book).add(.chapter, relativeTo: scene, title: "Two")
        var s = try BookStructure.load(folder: book)
        #expect(s.roots.map(\.title) == ["Chapter 1", "Two"] && s.roots[1].children.count == 1)
        _ = try Self.editor(book).add(.scene, relativeTo: chapter, title: "Last")
        s = try BookStructure.load(folder: book)
        #expect(s.roots[1].children.map(\.title) == ["New Scene", "Last"])
        let part = try Self.editor(book).add(.part, relativeTo: chapter, title: "Part")
        s = try BookStructure.load(folder: book)
        #expect(s.roots.map(\.kind) == [.chapter, .chapter, .part] && s.roots[2].id == part)
        // A chapter into a part: inside, at the end.
        _ = try Self.editor(book).add(.chapter, relativeTo: part, title: "In part")
        s = try BookStructure.load(folder: book)
        #expect(s.roots[2].children.map(\.title) == ["In part"])
        #expect(s.problems.isEmpty)
    }

    @Test("rename and status change the JSON and never a file name")
    func rename() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let s = try BookStructure.load(folder: book)
        try Self.editor(book).rename(s.scenes[0].id, to: "Первая")
        try Self.editor(book).setStatus(s.scenes[0].id, to: "draft")
        try Self.editor(book).rename(s.roots[0].id, to: "Глава")
        let t = try BookStructure.load(folder: book)
        #expect(t.scenes[0].node.title == "Первая" && t.scenes[0].node.status == "draft" && t.roots[0].title == "Глава" && t.scenes[0].node.base == s.scenes[0].node.base)
    }

    @Test("moving swaps neighbours, stops at the ends; deleting closes the gap and keeps the files in the trash")
    func moveDelete() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let first = try Self.editor(book).structure.scenes[0].id
        let two = try Self.editor(book).add(.scene, relativeTo: first, title: "Two")
        _ = try Self.editor(book).add(.scene, relativeTo: two, title: "Three")
        try Data("text".utf8).write(to: BookStructure.load(folder: book).markdownURL(for: BookStructure.load(folder: book).scenes[1].node))
        #expect(try Self.editor(book).move(two, by: -1))
        #expect(try Self.titles(book) == ["Two", "Scene 1", "Three"])
        #expect(try !Self.editor(book).move(two, by: -1))
        #expect(try Self.editor(book).move(two, by: 1) && Self.titles(book) == ["Scene 1", "Two", "Three"])
        // The text moved with its scene.
        let s = try BookStructure.load(folder: book)
        #expect(try String(contentsOf: s.markdownURL(for: s.scenes[1].node), encoding: .utf8) == "text")
        try Self.editor(book).delete(two)
        #expect(try Self.titles(book) == ["Scene 1", "Three"])
        let trash = book.appendingPathComponent(".quilland/trash")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []).count == 1)
        #expect(try Self.editor(book).structure.problems.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent(".quilland/journal.json").path))
    }
}

@Suite("Characters and section texts")
struct CharacterStoreTests {
    @Test("a character is made, edited, found again and keeps what the app does not know")
    func characters() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = CharacterStore(book: book)
        #expect(store.characters.isEmpty)
        let id = try store.add(name: "Анна Петровна")
        try store.update(id) { $0.aliases = ["Аня"]; $0.main = true; $0.notes = ["кольцо матери"] }
        // A field of a newer version, written by hand, survives the next edit.
        let file = book.appendingPathComponent("bible/characters/\(id).json")
        var raw = try JSONParser.parseObject(Data(contentsOf: file))
        raw["future"] = .string("kept")
        try AtomicFile.write(JSONWriter.data(raw), to: file)
        let again = CharacterStore(book: book)
        try again.update(id) { $0.notes = ["кольцо матери", "упрямая"] }
        let back = CharacterStore(book: book)
        #expect(back.characters.count == 1 && back.characters[0].aliases == ["Аня"] && back.characters[0].main && back.characters[0].notes.count == 2)
        #expect(try JSONParser.parseObject(Data(contentsOf: file)).string("future") == "kept")
        let found = ParadigmMatcher(entries: back.entries).matches(in: "Она сказала Анне Петровне, что Аня права.")
        #expect(Set(found.map(\.entry)) == [id])
    }

    @Test("a character's free text is a file beside the record; deleting moves both to the trash")
    func profileAndDelete() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = CharacterStore(book: book)
        let id = try store.add(name: "Пётр")
        #expect(store.profile(id) == "")
        try store.setProfile(id, "Высокий, молчаливый.")
        #expect(CharacterStore(book: book).profile(id) == "Высокий, молчаливый.")
        try store.setProfile(id, "")
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent("bible/characters/\(id).md").path))
        try store.setProfile(id, "Ещё раз.")
        try store.delete(id)
        #expect(store.characters.isEmpty && CharacterStore(book: book).characters.isEmpty)
        let trash = book.appendingPathComponent(".quilland/trash")
        let stamps = try FileManager.default.contentsOfDirectory(atPath: trash.path)
        #expect(stamps.count == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: trash.appendingPathComponent(stamps[0] + "/bible/characters").path)
        #expect(files.sorted() == ["\(id).json", "\(id).md"])
    }

    @Test("a section's synopsis and note are written, and removed when empty")
    func texts() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let scene = try BookEditorTests.editor(book).structure.scenes[0].id
        try BookEditorTests.editor(book).setText(scene, key: "synopsis", to: "Анна приходит домой.")
        #expect(try BookEditorTests.editor(book).record(scene)?.string("synopsis") == "Анна приходит домой.")
        try BookEditorTests.editor(book).setText(scene, key: "synopsis", to: "")
        #expect(try BookEditorTests.editor(book).record(scene)?.string("synopsis") == nil)
        #expect(try BookEditorTests.editor(book).record(scene)?.string("title") == "Scene 1")
    }
}

@Suite("Moving sections across the tree")
struct MoveAcrossTests {
    /// Two chapters: "One" with scenes a, b, c, and "Two" with scene x (and the texts as their titles).
    static func book() throws -> (URL, URL) {
        let (parent, book) = try BookEditorTests.book()
        let e = try BookEditorTests.editor(book)
        let first = e.structure.scenes[0].id
        try e.rename(first, to: "a")
        let b = try BookEditorTests.editor(book).add(.scene, relativeTo: first, title: "b")
        _ = try BookEditorTests.editor(book).add(.scene, relativeTo: b, title: "c")
        let two = try BookEditorTests.editor(book).add(.chapter, relativeTo: first, title: "Two")
        let s = try BookEditor(structure: BookStructure.load(folder: book))
        let x = s.structure.roots[1].children[0].id
        try s.rename(x, to: "x")
        let t = try BookStructure.load(folder: book)
        for e in t.scenes { try Data(e.node.title.utf8).write(to: t.markdownURL(for: e.node)) }
        _ = two
        return (parent, book)
    }

    static func shape(_ book: URL) throws -> String {
        let s = try BookStructure.load(folder: book)
        return s.roots.map { r in
            (r.kind == .scene ? "" : r.title + ":") + r.children.map { c in c.kind == .scene ? c.title : c.title + "(" + c.children.map(\.title).joined(separator: ",") + ")" }.joined(separator: ",")
        }.joined(separator: " | ")
    }

    @Test("a scene goes to another chapter at a place, with its text, and both folders stay consecutive")
    func sceneToChapter() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        #expect(try Self.shape(book) == "Chapter 1:a,b,c | Two:x")
        let s = try BookStructure.load(folder: book)
        let b = s.roots[0].children[1].id
        #expect(try BookEditor(structure: s).move(b, toParent: s.roots[1].id, at: 0))
        #expect(try Self.shape(book) == "Chapter 1:a,c | Two:b,x")
        let t = try BookStructure.load(folder: book)
        #expect(t.problems.isEmpty)
        for e in t.scenes { #expect(try String(contentsOf: t.markdownURL(for: e.node), encoding: .utf8) == e.node.title) }
        let names = try FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent("manuscript/002-chapter").path).sorted()
        #expect(names.filter { $0.hasSuffix(".md") } == ["001-scene.md", "002-scene.md"])
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent(".quilland/journal.json").path))
    }

    @Test("a move within a chapter uses the drop index as it is before the section is taken out")
    func within() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let s = try BookStructure.load(folder: book)
        let a = s.roots[0].children[0].id
        #expect(try BookEditor(structure: s).move(a, toParent: s.roots[0].id, at: 3))
        #expect(try Self.shape(book) == "Chapter 1:b,c,a | Two:x")
        let t = try BookStructure.load(folder: book)
        let c = t.roots[0].children[1].id
        #expect(try !BookEditor(structure: t).move(c, toParent: t.roots[0].id, at: 1), "dropped where it is: nothing happens")
        #expect(try !BookEditor(structure: t).move(c, toParent: t.roots[0].id, at: 2))
    }

    @Test("a chapter goes into a part and out to the book; a scene cannot go to the book or into a part")
    func chapters() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let part = try BookEditorTests.editor(book).add(.part, relativeTo: BookStructure.load(folder: book).roots[1].id, title: "P")
        var s = try BookStructure.load(folder: book)
        let two = s.roots[1].id
        #expect(try BookEditor(structure: s).move(two, toParent: part, at: 0))
        #expect(try Self.shape(book) == "Chapter 1:a,b,c | P:Two(x)")
        s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty && s.scenes.count == 4)
        #expect(throws: (any Error).self) { try BookEditor(structure: s).move(s.scenes[0].id, toParent: nil, at: 0) }
        #expect(throws: (any Error).self) { try BookEditor(structure: s).move(s.scenes[0].id, toParent: part, at: 0) }
        #expect(try BookEditor(structure: s).move(s.roots[1].children[0].id, toParent: nil, at: 0))
        #expect(try Self.shape(book) == "Two:x | Chapter 1:a,b,c | P:")
    }
}

@Suite("Merging, grouping, ungrouping")
struct MergeGroupTests {
    @Test("merging two scenes joins the text, the synopsis, the note and the tags, moves the links, and trashes the second")
    func merge() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let a = s.scenes[0].id
        let b = try BookEditor(structure: s).add(.scene, relativeTo: a, title: "Вторая")
        s = try BookStructure.load(folder: book)
        try Data("Первый абзац.\n".utf8).write(to: s.markdownURL(for: s.scenes[0].node))
        try Data("Второй абзац.\n".utf8).write(to: s.markdownURL(for: s.scenes[1].node))
        let e = BookEditor(structure: s)
        try e.setText(a, key: "synopsis", to: "Один.")
        try e.setText(b, key: "synopsis", to: "Два.")
        try e.setText(b, key: "note", to: "Заметка.")
        let chars = CharacterStore(book: book)
        let anna = try chars.add(name: "Анна")
        try chars.update(anna) { $0.links = [b: "приходит", a: "ждёт"]; $0.povScenes = [b] }
        let events = EventStore(book: book)
        let ev = try events.add(title: "Встреча")
        try events.update(ev) { $0.links = [b: "они встречаются"] }
        let moved = try BookEditor(structure: s).merge(a, with: b)
        #expect(moved == 2)
        let after = try BookStructure.load(folder: book)
        #expect(after.scenes.count == 1 && after.scenes[0].id == a && after.problems.isEmpty)
        let text = try String(contentsOf: after.markdownURL(for: after.scenes[0].node), encoding: .utf8)
        #expect(text.contains("Первый абзац.") && text.contains("Второй абзац.") && text.range(of: "Первый")!.lowerBound < text.range(of: "Второй")!.lowerBound)
        let rec = try #require(BookEditor(structure: after).record(a))
        #expect(rec.string("synopsis") == "Один.\n\nДва." && rec.string("note") == "Заметка.")
        let back = CharacterStore(book: book).character(anna)!
        #expect(back.links == [a: "ждёт приходит"] && back.povScenes == [a])
        #expect(EventStore(book: book).event(ev)?.links == [a: "они встречаются"])
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent(".quilland/trash").path)) ?? []).count == 1)
    }

    @Test("scenes of two chapters are not merged")
    func mergeAcrossChapters() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let a = s.scenes[0].id
        try BookEditor(structure: s).add(.chapter, relativeTo: a, title: "Вторая глава")
        s = try BookStructure.load(folder: book)
        #expect(s.scenes.count == 2 && s.roots.count == 2)
        #expect(throws: (any Error).self) { try BookEditor(structure: s).merge(s.scenes[0].id, with: s.scenes[1].id) }
        #expect(try BookStructure.load(folder: book).scenes.count == 2, "nothing was merged")
    }

    @Test("a scene at the edge of its chapter moves into the neighbouring chapter, and back")
    func moveAcrossChapters() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let a = s.scenes[0].id
        let b = try BookEditor(structure: s).add(.scene, relativeTo: a, title: "Вторая")
        s = try BookStructure.load(folder: book)
        try BookEditor(structure: s).add(.chapter, relativeTo: a, title: "Вторая глава")
        s = try BookStructure.load(folder: book)
        let editor = BookEditor(structure: s)
        #expect(s.roots.count == 2 && s.roots[0].children.map(\.id) == [a, b])
        #expect(!editor.canMove(a, by: -1) && editor.canMove(b, by: 1) && editor.canMove(a, by: 1))
        #expect(try editor.moveAcrossChapters(b, by: 1))
        s = try BookStructure.load(folder: book)
        #expect(s.roots[0].children.map(\.id) == [a] && s.roots[1].children.first?.id == b, "the scene starts the next chapter")
        #expect(try BookEditor(structure: s).moveAcrossChapters(b, by: -1))
        s = try BookStructure.load(folder: book)
        #expect(s.roots[0].children.map(\.id) == [a, b], "and goes back to the end of the first")
        #expect(try BookEditor(structure: s).moveAcrossChapters(a, by: -1) == false, "the first scene of the book has nowhere to go")
        #expect(try BookStructure.load(folder: book).problems.isEmpty)
    }

    @Test("an empty scene merges without leaving a stray blank paragraph")
    func mergeEmpty() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let a = s.scenes[0].id
        let b = try BookEditor(structure: s).add(.scene, relativeTo: a, title: "Вторая")
        s = try BookStructure.load(folder: book)
        try Data("Только второй.\n".utf8).write(to: s.markdownURL(for: s.scenes[1].node))
        try BookEditor(structure: s).merge(a, with: b)
        let after = try BookStructure.load(folder: book)
        #expect(try String(contentsOf: after.markdownURL(for: after.scenes[0].node), encoding: .utf8) == "Только второй.\n")
    }

    @Test("grouping makes a part around loose chapters; ungrouping gives them back and trashes the part")
    func group() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let c1 = s.roots[0].id
        let c2 = try BookEditor(structure: s).add(.chapter, relativeTo: c1, title: "Два")
        s = try BookStructure.load(folder: book)
        let c3 = try BookEditor(structure: s).add(.chapter, relativeTo: c2, title: "Три")
        s = try BookStructure.load(folder: book)
        let part = try BookEditor(structure: s).group([c1, c2], intoNewPart: "Часть первая")
        s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty && s.roots.map(\.title) == ["Часть первая", "Три"] && s.roots[0].children.map(\.id) == [c1, c2] && s.roots[1].id == c3)
        #expect(s.scenes.count == 3)
        #expect(throws: (any Error).self) { try BookEditor(structure: s).group([c1], intoNewPart: "Нельзя") }
        try BookEditor(structure: s).ungroup(part)
        s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty && s.roots.map(\.id) == [c1, c2, c3] && s.scenes.count == 3)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent(".quilland/trash").path)) ?? []).count == 1)
    }

    @Test("a snapshot tells whether the book changed since it was taken")
    func changedSince() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = SnapshotStore(bookFolder: book)
        let info = try store.take(.automatic, reason: "x")
        #expect(!store.changed(since: info))
        let s = try BookStructure.load(folder: book)
        try Data("Новый текст.\n".utf8).write(to: s.markdownURL(for: s.scenes[0].node))
        #expect(store.changed(since: info))
    }
}

@Suite("Removing several things in the same second")
struct TrashCollisionTests {
    @Test("merging scenes one after another, within a second, never meets itself in the trash")
    func repeatedMerges() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let a = s.scenes[0].id
        var last = a
        for title in ["b", "c", "d", "e"] {
            last = try BookEditor(structure: s).add(.scene, relativeTo: last, title: title)
            s = try BookStructure.load(folder: book)
        }
        for e in s.scenes { try Data("Текст \(e.node.title).\n".utf8).write(to: s.markdownURL(for: e.node)) }
        // The scenes after the first, merged into it one by one: every one is removed from number 002.
        for _ in 0..<4 {
            s = try BookStructure.load(folder: book)
            try BookEditor(structure: s).merge(a, with: s.scenes[1].id)
        }
        s = try BookStructure.load(folder: book)
        #expect(s.scenes.count == 1 && s.problems.isEmpty)
        let text = try String(contentsOf: s.markdownURL(for: s.scenes[0].node), encoding: .utf8)
        #expect(["b", "c", "d", "e"].allSatisfy { text.contains("Текст \($0).") })
        let folders = try FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent(".quilland/trash").path)
        #expect(folders.count == 4 && Set(folders).count == 4, "each removal has a folder of its own")
    }

    @Test("two characters, two places and two deletes of scenes in a row all reach the trash")
    func otherStores() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let chars = CharacterStore(book: book)
        let a = try chars.add(name: "А"), b = try chars.add(name: "Б")
        try chars.delete(a); try chars.delete(b)
        let events = EventStore(book: book)
        let e1 = try events.add(title: "1"), e2 = try events.add(title: "2")
        try events.delete(e1); try events.delete(e2)
        let trash = book.appendingPathComponent(".quilland/trash")
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).count == 4)
    }
}

@Suite("Interrupted moves are finished")
struct InterruptedMoveTests {
    @Test("a journal left behind is finished when the book is opened, even if a file of that name is already in the trash")
    func recoverWithCollision() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        var s = try BookStructure.load(folder: book)
        let a = s.scenes[0].id
        let b = try BookEditor(structure: s).add(.scene, relativeTo: a, title: "b")
        s = try BookStructure.load(folder: book)
        _ = try BookEditor(structure: s).add(.scene, relativeTo: b, title: "c")
        s = try BookStructure.load(folder: book)
        for e in s.scenes { try Data("Текст \(e.node.title).\n".utf8).write(to: s.markdownURL(for: e.node)) }
        // The trash folder of the removal already holds a file with the name the removed scene will get (what the old naming allowed).
        let trashName = "2026-10-07T15-47-09Z"
        let trash = book.appendingPathComponent(".quilland/trash/\(trashName)")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("старый файл".utf8).write(to: trash.appendingPathComponent("002-scene.md"))
        // Removing scene b through the journal, stopped by a crash just before the files reach the trash.
        let items = try Renumber.scan(book.appendingPathComponent("manuscript/001-chapter"))
        let order: [Renumber.Slot] = [.item("001-scene"), .item("003-scene")]
        let steps = try Renumber.plan(folder: "manuscript/001-chapter", items: items, order: order, removed: ["002-scene"], trash: ".quilland/trash/\(trashName)")
        let journal = book.appendingPathComponent(".quilland/journal.json")
        struct Stop: Error {}
        var last = 0
        #expect(throws: Stop.self) { try Renumber.execute(steps, root: book, journal: journal) { k in last = k; if k >= steps.count + 1 { throw Stop() } } }
        #expect(FileManager.default.fileExists(atPath: journal.path))
        // Opening the book finishes it.
        #expect(try Renumber.recover(root: book, journal: journal))
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        let after = try BookStructure.load(folder: book)
        #expect(after.problems.isEmpty && after.scenes.map(\.node.title) == ["Scene 1", "c"])
        let inTrash = try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted()
        #expect(inTrash.contains("002-scene.md") && inTrash.contains("002-scene-2.md"), "\(inTrash) (last step \(last))")
        let kept = try String(contentsOf: trash.appendingPathComponent("002-scene.md"), encoding: .utf8)
        #expect(kept == "старый файл", "the file that was already there is not replaced")
    }
}
