import Foundation

/// Writes a `Document` as canonical Markdown (quilland-format.md, section 4).
///
/// Each block is verified: the writer parses what it wrote and compares it with
/// the block it meant. Bold and italic markers placed right next to each other
/// can be read in more than one way, so if the first way of writing them does
/// not read back identically, other ways are tried: the order of closing and
/// opening, restarting a span, and leaving a space unstyled where bold and
/// italic overlap (the style of a space is not significant).
///
/// Some overlaps cannot be written at all: partly overlapping bold and italic
/// with no space at either boundary. Then, as a last resort, the bold or italic
/// of the shortest spans in the block is dropped until it can be written. **No
/// text is ever lost**, only the styling of a few letters, and the block is
/// listed in `Report.simplified` so the app can tell the author.
public enum MarkdownWriter {
    public struct Report: Equatable, Sendable {
        /// Indexes (in the normalised document) of blocks whose bold or italic had to be
        /// simplified in a few places because it could not be written as Markdown.
        public var simplified: [Int] = []
    }

    public static func write(_ document: Document) -> String {
        writeWithReport(document).text
    }

    public static func writeWithReport(_ document: Document) -> (text: String, report: Report) {
        let normalized = Normalizer.normalize(document)
        var report = Report()
        var chunks: [String] = []
        for (index, block) in normalized.blocks.enumerated() {
            let (text, ok) = render(block)
            if !ok { report.simplified.append(index) }
            chunks.append(text)
        }
        return (chunks.isEmpty ? "" : chunks.joined(separator: "\n\n") + "\n", report)
    }

    // MARK: Blocks

    /// Reads the choices that vary between ways of writing the same styles.
    private struct Chooser {
        var bits: Int
        private(set) var used = 0
        mutating func flip() -> Bool {
            let bit = (bits >> used) & 1 == 1
            used += 1
            return bit
        }
    }

    private static func render(_ block: Block) -> (String, Bool) {
        switch block {
        case .sceneBreak:
            return ("* * *", true)
        case .emptyLine:
            return ("&nbsp;", true)
        case .fragment(let id):
            return ("<!-- fragment: \(id) -->", true)
        case .paragraph, .heading, .quote:
            if let text = search(block) { return (text, true) }
            for simplified in simplifications(of: block) {
                if let text = search(simplified) { return (text, false) }
            }
            var chooser = Chooser(bits: 0)
            return (renderStyled(block, chooser: &chooser), false)
        }
    }

    /// The first way of writing `block` that reads back as the same block
    /// (up to the style of spaces), or nil.
    private static func search(_ block: Block) -> String? {
        let wanted = Normalizer.withoutWhitespaceStyles(block)
        for alternative in Normalizer.whitespaceVariants(of: block) {
            var choices = 0
            var variant = 0
            while true {
                var chooser = Chooser(bits: variant)
                let candidate = renderStyled(alternative, chooser: &chooser)
                if variant == 0 { choices = chooser.used }
                let parsed = MarkdownParser.parse(candidate).blocks
                if parsed.count == 1, Normalizer.withoutWhitespaceStyles(parsed[0]) == wanted { return candidate }
                variant += 1
                if variant >= (1 << min(choices, 6)) { break }
            }
        }
        return nil
    }

    /// Blocks with a little less styling, least first: one flag dropped from the
    /// shortest runs, then two runs, then everything plain.
    private static func simplifications(of block: Block) -> [Block] {
        var lists: [[Inline]]
        var rebuild: ([[Inline]]) -> Block
        switch block {
        case .paragraph(let inlines):
            lists = [inlines]
            rebuild = { .paragraph($0[0]) }
        case .heading(let level, let inlines):
            lists = [inlines]
            rebuild = { .heading(level, $0[0]) }
        case .quote(let paragraphs):
            lists = paragraphs
            rebuild = { .quote($0) }
        default:
            return []
        }
        // Every (list, item, flag) that could be dropped, shortest text first.
        var options: [(length: Int, list: Int, item: Int, flag: Style)] = []
        for (n, inlines) in lists.enumerated() {
            for (i, inline) in inlines.enumerated() {
                guard case .run(let run) = inline else { continue }
                for flag in [Style.italic, Style.bold] where run.style.contains(flag) {
                    options.append((run.text.unicodeScalars.count, n, i, flag))
                }
            }
        }
        options.sort { $0.length < $1.length }
        func apply(_ chosen: [(length: Int, list: Int, item: Int, flag: Style)]) -> Block {
            var copy = lists
            for option in chosen {
                if case .run(var run) = copy[option.list][option.item] {
                    run.style.remove(option.flag)
                    copy[option.list][option.item] = .run(run)
                }
            }
            return Normalizer.normalize(Document([rebuild(copy.map { Normalizer.merge($0) })])).blocks.first ?? block
        }
        var out: [Block] = []
        let shortest = Array(options.prefix(12))
        for option in shortest { out.append(apply([option])) }
        for i in 0..<shortest.count {
            for j in (i + 1)..<max(shortest.count, i + 1) where j < shortest.count {
                out.append(apply([shortest[i], shortest[j]]))
            }
        }
        // Last resort: no bold or italic anywhere in the block, notes included.
        func plain(_ inlines: [Inline]) -> [Inline] {
            inlines.map { inline in
                switch inline {
                case .run(let run): return .run(Run(run.text))
                case .note(let note): return .note(Note(note.content.map { Run($0.text) }))
                case .lineBreak: return .lineBreak
                }
            }
        }
        out.append(Normalizer.normalize(Document([rebuild(lists.map { Normalizer.merge(plain($0)) })])).blocks.first ?? block)
        return out
    }

    private static func renderStyled(_ block: Block, chooser: inout Chooser) -> String {
        switch block {
        case .paragraph(let inlines):
            var lines = renderLines(inlines, chooser: &chooser)
            lines[0] = escapeLineStart(lines[0])
            return lines.joined(separator: "\n")
        case .heading(let level, let inlines):
            let line = renderLines(inlines, chooser: &chooser).joined(separator: " ")
            return String(repeating: "#", count: level) + " " + line
        case .quote(let paragraphs):
            var out: [String] = []
            for (n, paragraph) in paragraphs.enumerated() {
                if n > 0 { out.append(">") }
                for line in renderLines(paragraph, chooser: &chooser) {
                    out.append("> " + line)
                }
            }
            return out.joined(separator: "\n")
        default:
            return ""
        }
    }

    /// A first line that the parser would take for something else is escaped.
    private static func escapeLineStart(_ line: String) -> String {
        if MarkdownParser.startsWith(line, ">") || MarkdownParser.startsWith(line, "<!--") { return "\\" + line }
        if MarkdownParser.headingParts(line) != nil { return "\\" + line }
        return line
    }

    // MARK: Lines

    /// The physical lines of a paragraph; every line but the last ends in the break backslash.
    private static func renderLines(_ inlines: [Inline], chooser: inout Chooser) -> [String] {
        var lines: [[Inline]] = [[]]
        for inline in inlines {
            if case .lineBreak = inline { lines.append([]) } else { lines[lines.count - 1].append(inline) }
        }
        var out: [String] = []
        for line in lines {
            var pieces: [(Style, String)] = []
            for item in line {
                switch item {
                case .run(let run):
                    pieces.append((run.style, escape(run.text, inNote: false)))
                case .note(let note):
                    let content = assemble(note.content.map { ($0.style, escape($0.text, inNote: true)) }, chooser: &chooser)
                    pieces.append((note.style, "^[" + content + "]"))
                case .lineBreak:
                    break
                }
            }
            out.append(assemble(pieces, chooser: &chooser))
        }
        for k in 0..<(out.count - 1) { out[k] += "\\" }
        return out
    }

    private static func marker(_ style: Style) -> String { style == .bold ? "**" : "*" }

    /// Puts the markers of bold and italic around the pieces. Where the style
    /// changes, the markers that must close are closed (and those above them
    /// reopened); the `chooser` decides the order of reopening, whether the
    /// whole stack is restarted, and the order of opening two at once.
    private static func assemble(_ pieces: [(Style, String)], chooser: inout Chooser) -> String {
        var out = ""
        var stack: [Style] = []
        for (target, content) in pieces {
            if let lowest = stack.firstIndex(where: { !target.contains($0) }) {
                var reopen: [Style] = []
                while stack.count > lowest {
                    let style = stack.removeLast()
                    out += marker(style)
                    if target.contains(style) { reopen.insert(style, at: 0) }
                }
                if reopen.count >= 2, chooser.flip() { reopen.reverse() }
                for style in reopen {
                    out += marker(style)
                    stack.append(style)
                }
            }
            var missing = [Style.bold, Style.italic].filter { target.contains($0) && !stack.contains($0) }
            if !missing.isEmpty, !stack.isEmpty, chooser.flip() {
                while let style = stack.popLast() { out += marker(style) }
                missing = [Style.bold, Style.italic].filter { target.contains($0) }
            }
            if missing.count >= 2, chooser.flip() { missing.reverse() }
            for style in missing {
                out += marker(style)
                stack.append(style)
            }
            out += content
        }
        while let style = stack.popLast() { out += marker(style) }
        return out
    }

    // MARK: Escapes

    /// A literal `*`, `\` and `^[` are escaped; so is `]` inside a footnote.
    private static func escape(_ text: String, inNote: Bool) -> String {
        var out = String.UnicodeScalarView()
        let scalars = Array(text.unicodeScalars)
        for (i, scalar) in scalars.enumerated() {
            switch scalar {
            case "\\":
                out.append(contentsOf: "\\\\".unicodeScalars)
            case "*":
                out.append(contentsOf: "\\*".unicodeScalars)
            case "^":
                if i + 1 < scalars.count, scalars[i + 1] == "[" {
                    out.append(contentsOf: "\\^".unicodeScalars)
                } else {
                    out.append(scalar)
                }
            case "]":
                if inNote { out.append(contentsOf: "\\]".unicodeScalars) } else { out.append(scalar) }
            default:
                out.append(scalar)
            }
        }
        return String(out)
    }
}
