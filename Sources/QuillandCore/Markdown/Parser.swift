import Foundation

/// Reads a scene's Markdown (quilland-format.md, section 4) into a `Document`.
///
/// Anything the format does not know is plain text. Nothing is dropped: a line
/// starting with `- `, `1. `, `####` or `| ` is an ordinary paragraph; links and
/// images are text. Input that is not canonical (CRLF, a BOM, tabs, indentation,
/// extra blank lines, NFD letters, an unescaped lone `*`) is read and comes back
/// canonical when written.
public enum MarkdownParser {
    public static func parse(_ source: String) -> Document {
        let lines = prepare(source)
        var blocks: [Block] = []
        var i = 0
        while i < lines.count {
            let line = trimLeadingSpaces(lines[i])
            if line.isEmpty {
                i += 1
                continue
            }
            if let id = fragmentID(in: line) {
                blocks.append(.fragment(id))
                i += 1
                continue
            }
            if line == "* * *" {
                blocks.append(.sceneBreak)
                i += 1
                continue
            }
            if isQuoteLine(line) {
                var contents: [String] = []
                while i < lines.count, isQuoteLine(trimLeadingSpaces(lines[i])) {
                    let quoted = trimLeadingSpaces(lines[i])
                    contents.append(quoted == ">" ? "" : trimLeadingSpaces(dropScalars(quoted, 2)))
                    i += 1
                }
                blocks.append(.quote(quoteParagraphs(contents)))
                continue
            }
            if let (level, rest) = headingParts(line) {
                blocks.append(.heading(level, parseLine(trimLeadingSpaces(rest))))
                i += 1
                continue
            }
            // An ordinary paragraph, possibly continued by trailing backslashes.
            var parts: [String] = []
            var content = line
            i += 1
            while trailingBackslashes(content) % 2 == 1, i < lines.count {
                let next = trimLeadingSpaces(lines[i])
                if next.isEmpty { break }
                parts.append(dropLastScalar(content))
                content = next
                i += 1
            }
            parts.append(content)
            blocks.append(.paragraph(join(parts)))
        }
        return Normalizer.normalize(Document(blocks))
    }

    // MARK: Lines

    /// The source as lines: a leading byte order mark dropped, every kind of line
    /// ending turned into one, tabs into spaces, NFC, trailing spaces removed.
    /// Works on code points, so a combining mark never hides a separator.
    static func prepare(_ source: String) -> [String] {
        var scalars = Array(source.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var mapped = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if s == "\r" {
                mapped.append("\n")
                if i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
            } else if s == "\u{2028}" || s == "\u{2029}" {
                mapped.append("\n")
            } else if s == "\t" {
                mapped.append(" ")
            } else {
                mapped.append(s)
            }
            i += 1
        }
        let normalized = String(mapped).precomposedStringWithCanonicalMapping
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        for s in normalized.unicodeScalars {
            if s == "\n" {
                lines.append(trimTrailingSpaces(String(current)))
                current = String.UnicodeScalarView()
            } else {
                current.append(s)
            }
        }
        lines.append(trimTrailingSpaces(String(current)))
        return lines
    }

    static func trimLeadingSpaces(_ s: String) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s.unicodeScalars.drop(while: { $0 == " " }))
        return String(view)
    }

    static func trimTrailingSpaces(_ s: String) -> String {
        var scalars = Array(s.unicodeScalars)
        while scalars.last == " " { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    static func trailingBackslashes(_ s: String) -> Int {
        var n = 0
        for scalar in s.unicodeScalars.reversed() {
            if scalar == "\\" { n += 1 } else { break }
        }
        return n
    }

    static func startsWith(_ s: String, _ prefix: String) -> Bool {
        s.unicodeScalars.starts(with: prefix.unicodeScalars)
    }

    static func isQuoteLine(_ line: String) -> Bool {
        let scalars = Array(line.unicodeScalars)
        return scalars.first == ">" && (scalars.count == 1 || scalars[1] == " ")
    }

    static func headingParts(_ line: String) -> (Int, String)? {
        let scalars = Array(line.unicodeScalars)
        var level = 0
        while level < scalars.count, scalars[level] == "#", level < 4 { level += 1 }
        guard level >= 1, level <= 3, level < scalars.count, scalars[level] == " " else { return nil }
        var rest = String.UnicodeScalarView()
        rest.append(contentsOf: scalars[(level + 1)...])
        return (level, String(rest))
    }

    /// `<!-- fragment: <uuid> -->` exactly; returns the id in lowercase.
    static func fragmentID(in line: String) -> String? {
        let prefix = "<!-- fragment: "
        let suffix = " -->"
        guard line.hasPrefix(prefix), line.hasSuffix(suffix), line.count > prefix.count + suffix.count else { return nil }
        let id = String(line.dropFirst(prefix.count).dropLast(suffix.count))
        guard isUUID(id) else { return nil }
        return id.lowercased()
    }

    static func dropLastScalar(_ s: String) -> String {
        var view = s.unicodeScalars
        view.removeLast()
        return String(view)
    }

    static func dropScalars(_ s: String, _ n: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s.unicodeScalars.dropFirst(n))
        return String(view)
    }

    static func isUUID(_ s: String) -> Bool {
        let scalars = Array(s.unicodeScalars)
        guard scalars.count == 36 else { return false }
        for (i, scalar) in scalars.enumerated() {
            if [8, 13, 18, 23].contains(i) {
                if scalar != "-" { return false }
            } else if !scalar.properties.isASCIIHexDigit {
                return false
            }
        }
        return true
    }

    /// Paragraphs of a quote, from its lines with the `> ` removed. A line with
    /// nothing on it separates paragraphs; a trailing backslash continues one.
    static func quoteParagraphs(_ contents: [String]) -> [[Inline]] {
        var paragraphs: [[Inline]] = []
        var i = 0
        while i < contents.count {
            if contents[i].isEmpty {
                i += 1
                continue
            }
            var parts: [String] = []
            var content = contents[i]
            i += 1
            while trailingBackslashes(content) % 2 == 1, i < contents.count, !contents[i].isEmpty {
                parts.append(dropLastScalar(content))
                content = contents[i]
                i += 1
            }
            parts.append(content)
            paragraphs.append(join(parts))
        }
        return paragraphs
    }

    /// The physical lines of one paragraph (break backslashes already removed) as inlines.
    static func join(_ parts: [String]) -> [Inline] {
        var out: [Inline] = []
        for (n, part) in parts.enumerated() {
            if n > 0 { out.append(.lineBreak) }
            out += parseLine(part)
        }
        return out
    }

    // MARK: Inline text: escapes, footnotes, emphasis

    private static let escapable: Set<Unicode.Scalar> = ["\\", "*", "^", "#", ">", "<", "]"]

    private enum Kind {
        case scalar(Unicode.Scalar)
        case star
        case note([Run])
    }

    private struct Cell {
        var kind: Kind
        var style: Style = []
        var consumed = false
    }

    /// One physical line of paragraph text.
    static func parseLine(_ text: String) -> [Inline] {
        var cells = makeCells(Array(text.unicodeScalars), allowNotes: true)
        applyEmphasis(&cells)
        return inlines(from: cells)
    }

    private static func parseNoteContent(_ text: String) -> [Run] {
        var cells = makeCells(Array(text.unicodeScalars), allowNotes: false)
        applyEmphasis(&cells)
        return Normalizer.normalizeRuns(inlines(from: cells).compactMap {
            if case .run(let run) = $0 { return run } else { return nil }
        })
    }

    private static func makeCells(_ scalars: [Unicode.Scalar], allowNotes: Bool) -> [Cell] {
        var cells: [Cell] = []
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if s == "\\", i + 1 < scalars.count, escapable.contains(scalars[i + 1]) {
                cells.append(Cell(kind: .scalar(scalars[i + 1])))
                i += 2
            } else if s == "*" {
                cells.append(Cell(kind: .star))
                i += 1
            } else if allowNotes, s == "^", i + 1 < scalars.count, scalars[i + 1] == "[",
                      let close = noteEnd(scalars, from: i + 2) {
                var inner = String.UnicodeScalarView()
                inner.append(contentsOf: scalars[(i + 2)..<close])
                cells.append(Cell(kind: .note(parseNoteContent(String(inner)))))
                i = close + 1
            } else {
                cells.append(Cell(kind: .scalar(s)))
                i += 1
            }
        }
        return cells
    }

    /// The index of the first unescaped `]` at or after `start`.
    private static func noteEnd(_ scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var j = start
        while j < scalars.count {
            if scalars[j] == "\\", j + 1 < scalars.count, escapable.contains(scalars[j + 1]) {
                j += 2
            } else if scalars[j] == "]" {
                return j
            } else {
                j += 1
            }
        }
        return nil
    }

    private struct Delimiter {
        var lo: Int
        var hi: Int
        let original: Int
        let canOpen: Bool
        let canClose: Bool
        var count: Int { hi - lo }
    }

    private static func isWhitespace(_ cell: Cell) -> Bool {
        if case .scalar(let s) = cell.kind { return s.properties.isWhitespace }
        return false
    }

    /// The delimiter-run algorithm of CommonMark (section 6.2) for `*` only, with
    /// the flanking rule reduced to whitespace: a run may open when what follows
    /// is not whitespace, and close when what precedes is not whitespace.
    private static func applyEmphasis(_ cells: inout [Cell]) {
        var delimiters: [Delimiter] = []
        var i = 0
        while i < cells.count {
            guard case .star = cells[i].kind else {
                i += 1
                continue
            }
            var j = i
            while j < cells.count, case .star = cells[j].kind { j += 1 }
            let before = i == 0 ? true : isWhitespace(cells[i - 1])
            let after = j == cells.count ? true : isWhitespace(cells[j])
            delimiters.append(Delimiter(lo: i, hi: j, original: j - i, canOpen: !after, canClose: !before))
            i = j
        }

        var index = 0
        while index < delimiters.count {
            guard delimiters[index].canClose else {
                index += 1
                continue
            }
            let closer = delimiters[index]
            var found = -1
            var j = index - 1
            while j >= 0 {
                let opener = delimiters[j]
                if opener.canOpen {
                    // The "rule of 3".
                    let oddMatch = (closer.canOpen || opener.canClose)
                        && (opener.original + closer.original) % 3 == 0
                        && !(opener.original % 3 == 0 && closer.original % 3 == 0)
                    if !oddMatch {
                        found = j
                        break
                    }
                }
                j -= 1
            }
            if found < 0 {
                if closer.canOpen { index += 1 } else { delimiters.remove(at: index) }
                continue
            }
            let use = (delimiters[index].count >= 2 && delimiters[found].count >= 2) ? 2 : 1
            let openerEnd = delimiters[found].hi
            let closerStart = delimiters[index].lo
            for k in (openerEnd - use)..<openerEnd { cells[k].consumed = true }
            for k in closerStart..<(closerStart + use) { cells[k].consumed = true }
            if openerEnd < closerStart {
                for k in openerEnd..<closerStart { cells[k].style.insert(use == 2 ? .bold : .italic) }
            }
            delimiters[found].hi -= use
            delimiters[index].lo += use
            if index - found > 1 {
                delimiters.removeSubrange((found + 1)..<index)
                index = found + 1
            }
            if delimiters[found].count == 0 {
                delimiters.remove(at: found)
                index -= 1
            }
            if delimiters[index].count == 0 { delimiters.remove(at: index) }
        }
    }

    private static func inlines(from cells: [Cell]) -> [Inline] {
        var out: [Inline] = []
        for cell in cells where !cell.consumed {
            switch cell.kind {
            case .scalar(let s):
                out.append(.run(Run(String(Character(s)), cell.style)))
            case .star:
                out.append(.run(Run("*", cell.style)))
            case .note(let runs):
                out.append(.note(Note(runs, style: cell.style)))
            }
        }
        return Normalizer.merge(out)
    }
}
