import Foundation

// The editor shows a `Document` as styled text. What the bridge puts into the
// styled text is what the editor will keep while the author types, so reading
// it back gives the author's edits as a `Document` again.
//
// - one paragraph = one line of text, paragraphs separated by "\n";
// - the kind of paragraph is the attribute `quillandBlock`;
// - bold and italic are `quillandBold` and `quillandItalic` (the editor adds
//   real fonts on top for display; only these attributes are read back, so a
//   bold heading is not mistaken for bold text);
// - a line break inside a paragraph is U+2028;
// - a footnote is one U+FFFC character carrying `quillandNote`;
// - a scene break is a paragraph showing "* * *";
// - a fragment marker is a paragraph holding one U+FFFC with `quillandFragment`.

public extension NSAttributedString.Key {
    static let quillandBlock = NSAttributedString.Key("quilland.block")
    static let quillandBold = NSAttributedString.Key("quilland.bold")
    static let quillandItalic = NSAttributedString.Key("quilland.italic")
    static let quillandNote = NSAttributedString.Key("quilland.note")
    static let quillandFragment = NSAttributedString.Key("quilland.fragment")
}

/// Carries a footnote's content as an attribute value.
public final class NoteBox: NSObject {
    public let runs: [Run]
    public init(_ runs: [Run]) { self.runs = runs }
}

public enum BlockKind {
    public static let body = "body"
    public static let heading1 = "h1"
    public static let heading2 = "h2"
    public static let heading3 = "h3"
    public static let quote = "quote"
    public static let sceneBreak = "sceneBreak"
    public static let fragment = "fragment"
}

public enum AttributedBridge {
    public static let object = "\u{FFFC}"
    public static let lineSeparator = "\u{2028}"

    // MARK: Document -> styled text

    public static func attributedString(from document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func add(_ paragraph: NSAttributedString) {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(paragraph)
        }
        for block in Normalizer.normalize(document).blocks {
            switch block {
            case .paragraph(let inlines):
                add(paragraph(inlines, kind: BlockKind.body))
            case .heading(let level, let inlines):
                add(paragraph(inlines, kind: "h\(level)"))
            case .quote(let paragraphs):
                for inlines in paragraphs { add(paragraph(inlines, kind: BlockKind.quote)) }
            case .emptyLine:
                add(NSAttributedString(string: ""))
            case .sceneBreak:
                add(NSAttributedString(string: "* * *", attributes: [.quillandBlock: BlockKind.sceneBreak]))
            case .fragment(let id):
                add(NSAttributedString(string: object, attributes: [
                    .quillandBlock: BlockKind.fragment, .quillandFragment: id,
                ]))
            }
        }
        return result
    }

    private static func paragraph(_ inlines: [Inline], kind: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for inline in inlines {
            switch inline {
            case .run(let run):
                out.append(NSAttributedString(string: run.text, attributes: attributes(kind: kind, style: run.style)))
            case .lineBreak:
                out.append(NSAttributedString(string: lineSeparator, attributes: attributes(kind: kind, style: [])))
            case .note(let note):
                var attrs = attributes(kind: kind, style: note.style)
                attrs[.quillandNote] = NoteBox(note.content)
                out.append(NSAttributedString(string: object, attributes: attrs))
            }
        }
        return out
    }

    private static func attributes(kind: String, style: Style) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.quillandBlock: kind]
        if style.contains(.bold) { attrs[.quillandBold] = true }
        if style.contains(.italic) { attrs[.quillandItalic] = true }
        return attrs
    }

    // MARK: Styled text -> document

    public static func document(from attributed: NSAttributedString) -> Document {
        let text = attributed.string as NSString
        var blocks: [Block] = []
        var pendingQuote: [[Inline]] = []
        func flushQuote() {
            if !pendingQuote.isEmpty {
                blocks.append(.quote(pendingQuote))
                pendingQuote = []
            }
        }

        var start = 0
        while start <= text.length {
            var end = start
            while end < text.length, text.character(at: end) != 0x0A { end += 1 }
            let range = NSRange(location: start, length: end - start)
            start = end + 1
            if range.length == 0 {
                // An empty paragraph is a pause (one at the very start or end is dropped when the document is made canonical).
                flushQuote()
                blocks.append(.emptyLine)
                continue
            }

            let kind = attributed.attribute(.quillandBlock, at: range.location, effectiveRange: nil) as? String ?? BlockKind.body
            switch kind {
            case BlockKind.sceneBreak:
                flushQuote()
                blocks.append(.sceneBreak)
            case BlockKind.fragment:
                flushQuote()
                let id = attributed.attribute(.quillandFragment, at: range.location, effectiveRange: nil) as? String ?? ""
                blocks.append(.fragment(id))
            case BlockKind.quote:
                pendingQuote.append(inlines(of: attributed, in: range))
            default:
                flushQuote()
                let inlines = inlines(of: attributed, in: range)
                switch kind {
                case BlockKind.heading1: blocks.append(.heading(1, inlines))
                case BlockKind.heading2: blocks.append(.heading(2, inlines))
                case BlockKind.heading3: blocks.append(.heading(3, inlines))
                default: blocks.append(.paragraph(inlines))
                }
            }
        }
        flushQuote()
        return Normalizer.normalize(Document(blocks))
    }

    private static func inlines(of attributed: NSAttributedString, in range: NSRange) -> [Inline] {
        var out: [Inline] = []
        attributed.enumerateAttributes(in: range, options: []) { attrs, subrange, _ in
            var style: Style = []
            if attrs[.quillandBold] as? Bool == true { style.insert(.bold) }
            if attrs[.quillandItalic] as? Bool == true { style.insert(.italic) }
            let text = (attributed.string as NSString).substring(with: subrange)
            if let box = attrs[.quillandNote] as? NoteBox {
                out.append(.note(Note(box.runs, style: style)))
                return
            }
            var current = ""
            for ch in text {
                if String(ch) == lineSeparator {
                    if !current.isEmpty { out.append(.run(Run(current, style))); current = "" }
                    out.append(.lineBreak)
                } else {
                    current.append(ch)
                }
            }
            if !current.isEmpty { out.append(.run(Run(current, style))) }
        }
        return out
    }
}
