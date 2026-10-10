import Foundation
import Testing
@testable import QuillandCore

/// Experiment 1, second half: an edit in the editor changes only what was edited.
///
/// The editor's text is simulated with `NSMutableAttributedString`, edited the
/// way a text view edits it (typed text takes the style of its neighbour), read
/// back and written. The number of paragraphs of the file that differ must be
/// exactly the number the edit touched.
@Suite("Edits change only what was edited")
struct EditTests {
    /// A realistic scene (the corpus' 43-realistic-scene.md) loaded as styled text.
    final class Scene {
        let original: String
        let styled: NSMutableAttributedString

        init() {
            let url = Corpus.files("canonical", suffix: "43-realistic-scene.md")[0]
            original = Corpus.read(url)
            styled = NSMutableAttributedString(attributedString: AttributedBridge.attributedString(from: MarkdownParser.parse(original)))
        }

        var text: NSString { styled.string as NSString }

        func range(of needle: String) -> NSRange {
            let r = text.range(of: needle)
            precondition(r.location != NSNotFound, "\(needle) not found")
            return r
        }

        /// Text as the editor would type it at `location`: the style of the character before it.
        func typed(_ string: String, after location: Int) -> NSAttributedString {
            var attrs = styled.attributes(at: max(0, location - 1), effectiveRange: nil)
            attrs[.quillandNote] = nil
            attrs[.quillandFragment] = nil
            return NSAttributedString(string: string, attributes: attrs)
        }

        func insert(_ string: String, after location: Int) {
            styled.insert(typed(string, after: location), at: location)
        }

        func saved() -> String {
            MarkdownWriter.write(AttributedBridge.document(from: styled))
        }

        func changes() -> (removed: Int, added: Int) {
            changedBlocks(before: original, after: saved())
        }
    }

    @Test("nothing edited: the file is the same")
    func untouched() {
        let scene = Scene()
        #expect(scene.saved() == scene.original)
    }

    @Test("typing in the middle of a plain paragraph changes that paragraph only")
    func typing() {
        let scene = Scene()
        let at = scene.range(of: "поднялась").location
        scene.insert("осторожно ", after: at)
        #expect(scene.changes() == (1, 1))
        #expect(scene.saved().contains("Анна осторожно поднялась на чердак"))
    }

    @Test("typing inside a bold word stays bold")
    func typingInBold() {
        let scene = Scene()
        let word = scene.range(of: "тот")
        scene.insert("-то", after: word.location + word.length)
        #expect(scene.changes() == (1, 1))
        #expect(scene.saved().contains("**тот-то**"))
    }

    @Test("deleting a sentence changes that paragraph only")
    func deleting() {
        let scene = Scene()
        scene.styled.deleteCharacters(in: scene.range(of: "Никто не ответил. "))
        #expect(scene.changes() == (1, 1))
        #expect(!scene.saved().contains("Никто не ответил"))
    }

    @Test("making a word bold, and plain again, changes that paragraph only")
    func boldAndBack() {
        let scene = Scene()
        let word = scene.range(of: "Только")
        scene.styled.addAttribute(.quillandBold, value: true, range: word)
        #expect(scene.changes() == (1, 1))
        #expect(scene.saved().contains("**Только**"))
        scene.styled.removeAttribute(.quillandBold, range: word)
        #expect(scene.saved() == scene.original)
    }

    @Test("removing italic from a word")
    func removeItalic() {
        let scene = Scene()
        scene.styled.removeAttribute(.quillandItalic, range: scene.range(of: "где-то"))
        #expect(scene.changes() == (1, 1))
        #expect(!scene.saved().contains("*где-то*"))
        #expect(scene.saved().contains("Только где-то внизу"))
    }

    @Test("pressing Return in a paragraph makes two paragraphs")
    func splitParagraph() {
        let scene = Scene()
        let at = scene.range(of: "— Ты здесь?").location + "— Ты здесь?".utf16.count
        scene.styled.insert(NSAttributedString(string: "\n"), at: at)
        // The part after the new line needs its paragraph kind; as in a text view, it keeps its own attributes.
        #expect(scene.changes() == (1, 2))
        #expect(scene.saved().contains("— Ты здесь?\n\n — позвала она.") || scene.saved().contains("— Ты здесь?\n\n— позвала она."))
    }

    @Test("joining two paragraphs (deleting the paragraph break)")
    func joinParagraphs() {
        let scene = Scene()
        let end = scene.range(of: "позвала она.")
        scene.styled.deleteCharacters(in: NSRange(location: end.location + end.length, length: 1))
        #expect(scene.changes() == (2, 1))
    }

    @Test("deleting a footnote")
    func deleteFootnote() {
        let scene = Scene()
        var footnote: NSRange?
        scene.styled.enumerateAttribute(.quillandNote, in: NSRange(location: 0, length: scene.styled.length)) { value, range, stop in
            if value != nil { footnote = range; stop.pointee = true }
        }
        scene.styled.deleteCharacters(in: footnote!)
        #expect(scene.changes() == (1, 1))
        #expect(!scene.saved().contains("^["))
    }

    @Test("turning a paragraph into a heading")
    func makeHeading() {
        let scene = Scene()
        let start = scene.range(of: "В углу стоял сундук.")
        let paragraph = scene.text.paragraphRange(for: start)
        scene.styled.addAttribute(.quillandBlock, value: BlockKind.heading2, range: paragraph)
        #expect(scene.changes() == (1, 1))
        #expect(scene.saved().contains("## В углу стоял сундук."))
    }

    @Test("typing characters that are special in Markdown is escaped, and reads back as typed")
    func typingSpecialCharacters() {
        for (typed, expectedStart) in [
            ("# ", "\\# Анна"), ("> ", "\\> Анна"), ("<!-- ", "\\<!-- Анна"), ("* ", "\\* Анна"), ("- ", "- Анна"), ("1. ", "1. Анна"),
        ] {
            let scene = Scene()
            let start = scene.range(of: "Анна поднялась").location
            scene.insert(typed, after: start)
            // Typed at the very start: take the style of what follows instead (there is nothing before).
            let saved = scene.saved()
            #expect(saved.contains(expectedStart), "typing \(typed.debugDescription): \(saved.prefix(200))")
            #expect(scene.changes() == (1, 1), "typing \(typed.debugDescription)")
            // And reading the file again gives the same text the author typed.
            #expect(MarkdownWriter.write(MarkdownParser.parse(saved)) == saved)
            #expect(unstyled(MarkdownParser.parse(saved)) == unstyled(AttributedBridge.document(from: scene.styled)))
        }
    }

    @Test("a line break typed with Shift+Return")
    func lineBreak() {
        let scene = Scene()
        let at = scene.range(of: "Ты здесь?").location
        scene.insert(AttributedBridge.lineSeparator, after: at)
        #expect(scene.changes() == (1, 1))
        #expect(scene.saved().contains("\\\n"))
    }

    @Test("typing and then deleting the same text leaves no trace")
    func typeThenDelete() {
        let scene = Scene()
        let at = scene.range(of: "поднялась").location
        scene.insert("осторожно ", after: at)
        scene.styled.deleteCharacters(in: NSRange(location: at, length: "осторожно ".utf16.count))
        #expect(scene.saved() == scene.original)
    }

    @Test("selecting everything and putting it back (cut and paste)")
    func cutAndPaste() {
        let scene = Scene()
        let all = NSAttributedString(attributedString: scene.styled)
        scene.styled.deleteCharacters(in: NSRange(location: 0, length: scene.styled.length))
        scene.styled.append(all)
        #expect(scene.saved() == scene.original)
    }
}
