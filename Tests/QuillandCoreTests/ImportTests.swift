import Foundation
import Testing
@testable import QuillandCore

@Suite("Importing a text")
struct ImportTests {
    static let markdown = """
        # Дом на Сосновой

        ## Глава 1

        Первый абзац.

        Второй абзац.

        * * *

        Третий абзац после разрыва.

        ## Глава 2

        Текст **жирный** и *курсив*.

        """

    @Test("one H1 is the book's title, H2 are chapters, and a scene break splits a chapter into scenes")
    func markdownTree() {
        let (kinds, title) = TextImporter.analyze(Self.markdown, source: .markdown, joinWrappedLines: false)
        #expect(title == "Дом на Сосновой")
        #expect(kinds.map(\.id) == ["h1", "h2", "break"])
        #expect(kinds.first { $0.id == "h1" }?.defaultRole == ImportRole.none && kinds.first { $0.id == "h2" }?.defaultRole == ImportRole.chapter)
        #expect(kinds.first { $0.id == "h2" }?.count == 2 && kinds.first { $0.id == "h2" }?.examples == ["Глава 1", "Глава 2"])
        var options = ImportOptions()
        options.language = "ru"
        let plan = TextImporter.plan(Self.markdown, source: .markdown, options: options)
        #expect(plan.chapterCount == 2 && plan.sceneCount == 3 && plan.partCount == 0)
        guard case .chapter(let first) = plan.items[0], case .chapter(let second) = plan.items[1] else { Issue.record("two chapters"); return }
        #expect(first.title == "Глава 1" && first.scenes.map(\.title) == ["Сцена 1", "Сцена 2"])
        #expect(first.scenes[0].markdown.contains("Первый абзац.") && first.scenes[0].markdown.contains("Второй абзац.") && !first.scenes[0].markdown.contains("Третий"))
        #expect(second.scenes[0].markdown.contains("**жирный**") && second.scenes[0].markdown.contains("*курсив*"))
        options.splitAtSceneBreaks = false
        let kept = TextImporter.plan(Self.markdown, source: .markdown, options: options)
        #expect(kept.sceneCount == 2)
        guard case .chapter(let c) = kept.items[0] else { return }
        #expect(c.scenes[0].markdown.contains("* * *"), "without the split a break stays in the text")
    }

    @Test("a plain text with Часть and Глава lines becomes parts and chapters; wrapped lines are joined on request")
    func plainText() {
        let text = "Часть 1. Дорога\n\nГлава 1. Станция\n\nОна приехала на\nстанцию ночью.\n\nГлава 2\n\nУтро.\n\nЧасть 2\n\nГлава 3\n\nКонец.\n"
        var options = ImportOptions()
        options.joinWrappedLines = true
        let plan = TextImporter.plan(text, source: .text, options: options)
        #expect(plan.partCount == 2 && plan.chapterCount == 3 && plan.sceneCount == 3)
        guard case .part(let p1) = plan.items[0] else { Issue.record("a part first"); return }
        #expect(p1.title == "Часть 1. Дорога" && p1.chapters.map(\.title) == ["Глава 1. Станция", "Глава 2"])
        #expect(p1.chapters[0].scenes[0].markdown.contains("Она приехала на станцию ночью."))
        options.joinWrappedLines = false
        let split = TextImporter.plan(text, source: .text, options: options)
        guard case .part(let q1) = split.items[0] else { return }
        #expect(q1.chapters[0].scenes[0].markdown.contains("Она приехала на\n\nстанцию ночью."))
    }

    @Test("the author's choice of role for a kind changes the tree")
    func roles() {
        let text = "ДОРОГА ДОМОЙ\n\nТекст.\n\nВТОРОЙ ДЕНЬ\n\nЕщё текст.\n"
        let (kinds, _) = TextImporter.analyze(text, source: .text, joinWrappedLines: false)
        #expect(kinds.map(\.id) == ["caps"] && kinds[0].defaultRole == ImportRole.none && kinds[0].count == 2)
        var options = ImportOptions()
        #expect(TextImporter.plan(text, source: .text, options: options).chapterCount == 1)
        options.roles["caps"] = .chapter
        let plan = TextImporter.plan(text, source: .text, options: options)
        #expect(plan.chapterCount == 2)
        guard case .chapter(let c) = plan.items[0] else { return }
        #expect(c.title == "ДОРОГА ДОМОЙ")
    }

    @Test("HTML: headings, bold, entities and rules are read; everything else goes")
    func html() {
        let html = "<html><head><title>x</title><style>p{}</style></head><body><h1>Книга</h1><h2>Глава 1</h2><p>Текст <b>жирный</b> &amp; всё&nbsp;тут.</p><hr><p>Второй <i>абзац</i>.</p><script>bad()</script></body></html>"
        let plan = TextImporter.plan(html, source: .html, options: ImportOptions())
        #expect(plan.chapterCount == 1 && plan.sceneCount == 2)
        guard case .chapter(let c) = plan.items[0] else { return }
        #expect(c.scenes[0].markdown.contains("**жирный**") && c.scenes[0].markdown.contains("& всё тут.") && !c.scenes[0].markdown.contains("<"))
        #expect(c.scenes[1].markdown.contains("*абзац*") && !c.scenes[1].markdown.contains("bad"))
    }

    @Test("lists, tables, links, images and footnote marks become plain paragraphs and inline footnotes")
    func simplified() {
        let text = "Текст со ссылкой [сайт](http://x.example) и сноской[^1].\n\n- пункт один\n- пункт два\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n![картинка](x.png)\n\n[^1]: Сноска.\n"
        let plan = TextImporter.plan(text, source: .markdown, options: ImportOptions())
        guard case .chapter(let c) = plan.items[0] else { Issue.record("a chapter"); return }
        let md = c.scenes[0].markdown
        #expect(md.contains("^[Сноска.]") && md.contains("сайт") && !md.contains("http") && md.contains("пункт один") && !md.contains("- пункт"))
        #expect(!md.contains("![") && !md.contains("|---") && md.contains("a b"))
    }

    @Test("Windows-1251 and UTF-8 are told apart by the bytes")
    func encodings() throws {
        let text = "Привет, мир! Ёлка."
        let old = try #require(text.data(using: .windowsCP1251))
        #expect(TextImporter.decode(old, encoding: .windows1251) == text)
        #expect(TextImporter.decode(old, encoding: .utf8) == nil)
        var withBOM = Data([0xEF, 0xBB, 0xBF]); withBOM.append(Data(text.utf8))
        #expect(TextImporter.decode(withBOM, encoding: .utf8) == text)
    }

    @Test("a plan is written into a book: numbered folders, ids, statuses; the empty start of a new book is replaced; a second import goes after the first")
    func writing() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Импорт", language: "ru", parentFolder: parent))
        let plan = TextImporter.plan("Часть 1\n\nГлава 1\n\nТекст один.\n\n* * *\n\nТекст два.\n\nГлава 2\n\nТекст три.\n", source: .text, options: ImportOptions())
        let written = try TextImporter.write(plan, into: book, replacingEmptyStart: true)
        #expect(written.parts == 1 && written.chapters == 2 && written.scenes == 3 && written.firstSceneID != nil)
        var s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty && s.roots.map(\.kind) == [.part] && s.roots[0].children.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(s.scenes.count == 3 && s.scenes.allSatisfy { $0.node.status == "draft" } && s.scenes[0].id == written.firstSceneID)
        #expect(try String(contentsOf: s.markdownURL(for: s.scenes[0].node), encoding: .utf8).contains("Текст один."))
        _ = try TextImporter.write(TextImporter.plan("Глава 3\n\nКонец.\n", source: .text, options: ImportOptions()), into: book)
        s = try BookStructure.load(folder: book)
        #expect(s.problems.isEmpty && s.roots.count == 2 && s.roots[1].kind == .chapter && s.roots[1].base.hasPrefix("manuscript/002-chapter"))
        #expect(s.scenes.count == 4)
    }

    @Test("an empty text makes an empty plan, and a text with no titles makes one chapter with one scene")
    func edges() {
        #expect(TextImporter.plan("", source: .text, options: ImportOptions()).sceneCount == 0)
        let plan = TextImporter.plan("Просто текст.\n\nИ ещё.\n", source: .text, options: ImportOptions())
        #expect(plan.chapterCount == 1 && plan.sceneCount == 1)
    }
}
