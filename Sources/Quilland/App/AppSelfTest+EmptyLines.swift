import AppKit
import QuillandCore

/// A pause: an empty paragraph typed between two paragraphs is kept in the file as `&nbsp;`, shown again when the book is opened, and dropped at the ends of a scene.
extension AppSelfTest {
    func emptyLines() -> Int32? {
        let url = temp.appendingPathComponent("empty-lines-probe.md")
        defer { try? FileManager.default.removeItem(at: url) }
        try? Data("Эпиграф.\n\nДальше идёт текст.\n".utf8).write(to: url)
        let doc = SceneDocument(id: "empty-lines-probe", title: "t", status: nil, url: url)
        let view = doc.makeTextView(width: 700)
        func file() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "?" }
        let text = doc.storage.string as NSString

        // The author puts the cursor at the end of the epigraph and presses Return: an empty paragraph, a pause.
        view.setSelectedRange(NSRange(location: text.range(of: "Эпиграф.").location + 8, length: 0))
        view.insertNewline(nil)
        _ = doc.saveNow()
        check(file() == "Эпиграф.\n\n&nbsp;\n\nДальше идёт текст.\n", "an empty paragraph typed between two is saved as &nbsp;", file().debugDescription)
        doc.load()
        check(doc.storage.string == "Эпиграф.\n\nДальше идёт текст.", "and shows again as an empty paragraph when the book is opened", doc.storage.string.debugDescription)
        check(doc.counts.characters == TextStats.count(MarkdownParser.parse("Эпиграф.\n\nДальше идёт текст.\n")).characters, "the pause is not counted as text")

        // Another Return makes a second one; typing in an empty paragraph makes it text.
        let again = doc.makeTextView(width: 700)
        let now = doc.storage.string as NSString
        again.setSelectedRange(NSRange(location: now.range(of: "Эпиграф.").location + 9, length: 0))
        again.insertNewline(nil)
        _ = doc.saveNow()
        check(file() == "Эпиграф.\n\n&nbsp;\n\n&nbsp;\n\nДальше идёт текст.\n", "every empty paragraph is kept", file().debugDescription)

        // At the very start and the very end of the scene they are dropped.
        doc.storage.replaceCharacters(in: NSRange(location: 0, length: doc.storage.length), with: "\n\nПросто текст.\n\n")
        doc.textDidChange(); _ = doc.saveNow()
        check(file() == "Просто текст.\n", "an empty paragraph at the start or the end is not kept", file().debugDescription)
        _ = view
        return nil
    }
}
