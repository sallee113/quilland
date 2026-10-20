import Foundation
import Testing
@testable import QuillandCore

@Suite("Empty lines kept on purpose")
struct EmptyLineTests {
    @Test("a paragraph of &nbsp; is an empty line: it is read, written and read again as the same")
    func roundTrip() {
        let source = "Эпиграф.\n\n&nbsp;\n\nПервый абзац.\n"
        let document = MarkdownParser.parse(source)
        #expect(document.blocks.count == 3)
        #expect(document.blocks[1] == .emptyLine)
        #expect(MarkdownWriter.write(document) == source)
        #expect(MarkdownParser.parse(MarkdownWriter.write(document)) == document)
    }

    @Test("several empty lines in a row are each kept; none is kept at the very start or end")
    func severalAndEdges() {
        let source = "&nbsp;\n\nОдин.\n\n&nbsp;\n\n&nbsp;\n\nДва.\n\n&nbsp;\n"
        let document = MarkdownParser.parse(source)
        #expect(document.blocks == [.paragraph([.text("Один.")]), .emptyLine, .emptyLine, .paragraph([.text("Два.")])])
        #expect(MarkdownWriter.write(document) == "Один.\n\n&nbsp;\n\n&nbsp;\n\nДва.\n")
        #expect(Normalizer.normalize(Document([.emptyLine, .emptyLine])).blocks.isEmpty)
    }

    @Test("&nbsp; inside a paragraph of text stays text")
    func literal() {
        let document = MarkdownParser.parse("Пример: &nbsp; в тексте.\n")
        #expect(document.blocks.count == 1)
        #expect(MarkdownWriter.write(document) == "Пример: &nbsp; в тексте.\n")
    }

    @Test("the editor's empty paragraph between two paragraphs is an empty line; at the start or the end it is nothing")
    func editorBridge() {
        let styled = NSMutableAttributedString(attributedString: AttributedBridge.attributedString(from: MarkdownParser.parse("Эпиграф.\n\nДальше.\n")))
        // The author puts the cursor at the end of the first paragraph and presses Return: an empty paragraph appears.
        styled.insert(NSAttributedString(string: "\n"), at: (styled.string as NSString).range(of: "Эпиграф.").upperBoundLocation)
        let document = AttributedBridge.document(from: styled)
        #expect(document.blocks == [.paragraph([.text("Эпиграф.")]), .emptyLine, .paragraph([.text("Дальше.")])])
        #expect(MarkdownWriter.write(document) == "Эпиграф.\n\n&nbsp;\n\nДальше.\n")
        // And back: the file's empty line is an empty paragraph in the editor.
        let again = AttributedBridge.attributedString(from: document)
        #expect(again.string == "Эпиграф.\n\nДальше.")
        #expect(AttributedBridge.document(from: again) == document)
        // At the ends nothing is kept.
        let edges = NSMutableAttributedString(attributedString: AttributedBridge.attributedString(from: MarkdownParser.parse("Текст.\n")))
        edges.insert(NSAttributedString(string: "\n\n"), at: 0)
        edges.append(NSAttributedString(string: "\n\n"))
        #expect(AttributedBridge.document(from: edges) == MarkdownParser.parse("Текст.\n"))
    }

    @Test("an empty line is not counted as text")
    func counts() {
        let with = TextStats.count(MarkdownParser.parse("Один два.\n\n&nbsp;\n\nТри.\n"))
        let without = TextStats.count(MarkdownParser.parse("Один два.\n\nТри.\n"))
        #expect(with == without)
    }

    @Test("an empty line stays a gap in the exports")
    func exports() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = try BookCreator.create(NewBookRequest(title: "Пауза", language: "ru", parentFolder: parent))
        let structure = try BookStructure.load(folder: folder)
        let scene = try #require(structure.scenes.first)
        try Data("Эпиграф.\n\n&nbsp;\n\nДальше.\n".utf8).write(to: structure.markdownURL(for: scene.node))
        let book = try BookLoader.load(folder: folder)
        let options = ExportOptions()
        let html = String(decoding: HtmlExporter.export(book, options: options), as: UTF8.self)
        #expect(html.contains("<p>Эпиграф.</p>\n<p class=\"gap\">&#160;</p>\n<p>Дальше.</p>"), "the gap is an empty paragraph in HTML")
        let txt = String(decoding: TxtExporter.export(book, options: options), as: UTF8.self)
        #expect(txt.contains("Эпиграф.\n\n\nДальше."), "and an extra blank line in TXT")
        let fb2 = String(decoding: Fb2Exporter.export(book, options: options), as: UTF8.self)
        #expect(fb2.contains("<p>Эпиграф.</p><empty-line/><p>Дальше.</p>") || fb2.contains("<empty-line/>"), "and an empty line in FB2")
        #expect(!txt.contains("&nbsp;") && !html.contains("&nbsp;") && !fb2.contains("&nbsp;"), "the marker itself is never exported")
    }
}

extension NSRange { var upperBoundLocation: Int { location + length } }
