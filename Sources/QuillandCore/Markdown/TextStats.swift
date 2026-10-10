import Foundation

public struct TextCounts: Equatable, Sendable {
    public var words = 0
    /// Characters with spaces (line breaks and paragraph breaks not counted): the author's sheet is 40,000 of them.
    public var characters = 0
    public var charactersWithoutSpaces = 0

    public init(words: Int = 0, characters: Int = 0, charactersWithoutSpaces: Int = 0) {
        self.words = words
        self.characters = characters
        self.charactersWithoutSpaces = charactersWithoutSpaces
    }

    public var sheets: Double { Double(characters) / TextStats.authorSheet }

    public static func + (a: TextCounts, b: TextCounts) -> TextCounts {
        TextCounts(words: a.words + b.words, characters: a.characters + b.characters, charactersWithoutSpaces: a.charactersWithoutSpaces + b.charactersWithoutSpaces)
    }
}

/// The size of a text, by the counting rules of the spec ("Behaviour: counting the book's size").
///
/// Counted: the text of paragraphs, headings, footnotes and set-off blocks. Not counted: scene-break lines,
/// fragment markers, Markdown markup (the model has none), line and paragraph breaks.
/// A word is a run of letters or digits with inner hyphens and apostrophes. Invisible characters
/// (soft hyphen, zero-width spaces, word joiner) never count.
public enum TextStats {
    public static let authorSheet = 40_000.0

    public static func count(_ document: Document) -> TextCounts {
        var total = TextCounts()
        for block in document.blocks {
            switch block {
            case .paragraph(let inlines), .heading(_, let inlines): total = total + count(inlines)
            case .quote(let paragraphs): for p in paragraphs { total = total + count(p) }
            case .sceneBreak, .fragment: break
            }
        }
        return total
    }

    public static func count(_ inlines: [Inline]) -> TextCounts {
        var texts: [String] = []
        for inline in inlines {
            switch inline {
            case .run(let run): texts.append(run.text)
            case .note(let note): texts.append("\n" + note.content.map(\.text).joined() + "\n") // a footnote separates words, and is not itself a character
            case .lineBreak: texts.append("\n") // separates words, is not a character
            }
        }
        return count(texts.joined())
    }

    public static func count(_ text: String) -> TextCounts {
        var counts = TextCounts()
        var inWord = false
        var previousWasLetter = false
        var pendingJoiner = false
        for scalar in text.unicodeScalars {
            if isInvisible(scalar) { continue }
            let isLetterOrDigit = scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                || scalar.properties.generalCategory == .nonspacingMark
            if isLetterOrDigit {
                if !inWord { counts.words += 1; inWord = true }
                pendingJoiner = false
                previousWasLetter = true
            } else if inWord, previousWasLetter, scalar == "-" || scalar == "'" || scalar == "\u{2019}" || scalar == "\u{2010}" {
                pendingJoiner = true // a word continues only if a letter follows
                previousWasLetter = false
            } else {
                if pendingJoiner { pendingJoiner = false }
                inWord = false
                previousWasLetter = false
            }
            if scalar == "\n" || scalar == "\u{2028}" || scalar == "\u{2029}" || scalar == "\r" { continue }
            if scalar.properties.generalCategory != .nonspacingMark { // a mark belongs to the character before it
                counts.characters += 1
                if !scalar.properties.isWhitespace { counts.charactersWithoutSpaces += 1 }
            }
        }
        return counts
    }

    private static func isInvisible(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x00AD, 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0xFFFC: return true
        default: return false
        }
    }
}
