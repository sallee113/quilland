import AppKit
import QuillandCore

/// What an opened text looks like: italic, bold and headings keep their fonts when a view is made and when a setting changes.
extension AppSelfTest {
    func fonts() -> Int32? {
        let url = temp.appendingPathComponent("fonts-probe.md")
        try? Data("# Заголовок\n\nОбычный *курсив* и **жирный** текст.\n\n*Весь курсивный абзац.*\n".utf8).write(to: url)
        let saved = Fonts.name
        defer { Fonts.name = saved; try? FileManager.default.removeItem(at: url) }
        Fonts.name = "Helvetica Neue"
        let doc = SceneDocument(id: "fonts-probe", title: "t", status: nil, url: url)
        let view = doc.makeTextView(width: 700)
        let text = doc.storage.string as NSString
        func traits(_ word: String) -> (italic: Bool, bold: Bool, size: CGFloat) {
            let f = doc.storage.attribute(.font, at: text.range(of: word).location, effectiveRange: nil) as? NSFont
            let t = f.map { NSFontManager.shared.traits(of: $0) } ?? []
            return (t.contains(.italicFontMask), t.contains(.boldFontMask), f?.pointSize ?? 0)
        }
        func checkLooks(_ when: String) {
            check(traits("курсив ").italic && !traits("Обычный").italic, "italic text is drawn in an italic font \(when)", "\(traits("курсив "))")
            check(traits("жирный").bold && !traits("Обычный").bold, "bold text is drawn in a bold font \(when)", "\(traits("жирный"))")
            check(traits("Заголовок").bold && traits("Заголовок").size > traits("Обычный").size, "a heading is drawn large and bold \(when)", "\(traits("Заголовок")) \(traits("Обычный"))")
            check(traits("Весь").italic && traits("абзац").italic, "an italic paragraph is italic all through \(when)")
        }
        checkLooks("when a view is made")
        doc.preferencesChanged()
        checkLooks("after a setting changes")

        // A second view of the same text does not undo it either.
        _ = doc.makeTextView(width: 500)
        checkLooks("when another view is made")

        // ⌘I on an italic paragraph takes italic off and brings it back, and the look follows.
        let paragraph = text.range(of: "Весь курсивный абзац.")
        view.setSelectedRange(paragraph)
        view.toggleItalic(nil)
        check(!traits("Весь").italic && doc.storage.attribute(.quillandItalic, at: paragraph.location, effectiveRange: nil) == nil, "Italic on an italic paragraph takes it off, in the text and in the look")
        view.toggleItalic(nil)
        check(traits("Весь").italic && doc.storage.attribute(.quillandItalic, at: paragraph.location, effectiveRange: nil) != nil, "and pressed again brings it back")
        return nil
    }
}
