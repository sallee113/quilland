import Foundation

/// Puts a document into its canonical form: the one the writer produces and the
/// parser reads back unchanged. Both the parser and the writer end with it, and
/// the editor bridge uses it after reading the editor's text.
///
/// Rules (quilland-format.md, section 4):
/// - text is NFC; tabs become spaces; no line or paragraph separators inside a run;
/// - no empty runs; neighbouring runs with the same style are one run;
/// - whitespace at the edge of a bold or italic span is moved outside the span
///   (a closing marker may not follow a space);
/// - ASCII spaces at the start and end of each line are removed (indentation is
///   never used); trailing line breaks are removed;
/// - empty paragraphs, headings and quotes disappear; neighbouring quote blocks
///   are one block; fragment ids are lowercase.
public enum Normalizer {
    public static func normalize(_ document: Document) -> Document {
        var out: [Block] = []
        for block in document.blocks {
            switch block {
            case .paragraph(let inlines):
                let normalized = normalizeInlines(inlines)
                if !normalized.isEmpty { out.append(.paragraph(normalized)) }
            case .heading(let level, let inlines):
                let normalized = normalizeInlines(inlines, allowBreaks: false)
                if !normalized.isEmpty { out.append(.heading(min(max(level, 1), 3), normalized)) }
            case .quote(let paragraphs):
                let normalized = paragraphs.map { normalizeInlines($0) }.filter { !$0.isEmpty }
                if normalized.isEmpty { continue }
                if case .quote(let previous)? = out.last {
                    out[out.count - 1] = .quote(previous + normalized)
                } else {
                    out.append(.quote(normalized))
                }
            case .sceneBreak:
                out.append(.sceneBreak)
            case .fragment(let id):
                out.append(.fragment(id.lowercased()))
            }
        }
        return Document(out)
    }

    // MARK: Inlines

    public static func normalizeInlines(_ inlines: [Inline], allowBreaks: Bool = true) -> [Inline] {
        var items = expand(inlines, allowBreaks: allowBreaks)
        items = merge(items)
        items = moveEdgeWhitespaceOut(items, flag: .bold)
        items = moveEdgeWhitespaceOut(items, flag: .italic)
        items = merge(items)
        items = trimLines(items)
        items = merge(items)
        while case .lineBreak? = items.last { items.removeLast() }
        return items
    }

    /// Footnote content: runs only.
    static func normalizeRuns(_ runs: [Run]) -> [Run] {
        var items = expand(runs.map { Inline.run($0) }, allowBreaks: false)
        items = merge(items)
        items = moveEdgeWhitespaceOut(items, flag: .bold)
        items = moveEdgeWhitespaceOut(items, flag: .italic)
        items = merge(items)
        // Note content has no lines: trim spaces at both ends of the whole.
        var lines = splitLines(items)
        lines = lines.map { trimEdges($0) }
        items = lines.first ?? []
        items = merge(items)
        return items.compactMap { if case .run(let r) = $0 { return r } else { return nil } }
    }

    private static let lineSeparators: Set<Character> = ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}"]

    /// NFC, tabs to spaces, separators inside text turned into line breaks (or spaces).
    private static func expand(_ inlines: [Inline], allowBreaks: Bool) -> [Inline] {
        var out: [Inline] = []
        for inline in inlines {
            switch inline {
            case .run(let run):
                // U+FEFF inside text (a zero width no-break space) becomes its modern form, U+2060:
                // at the start of a file U+FEFF would be taken for a byte order mark.
                var mapped = String.UnicodeScalarView()
                mapped.append(contentsOf: run.text.unicodeScalars.map { $0 == "\u{FEFF}" ? "\u{2060}" : $0 })
                let text = String(mapped).precomposedStringWithCanonicalMapping
                var current = ""
                func flush() {
                    if !current.isEmpty { out.append(.run(Run(current, run.style))); current = "" }
                }
                for ch in text {
                    if ch == "\t" {
                        current.append(" ")
                    } else if lineSeparators.contains(ch) {
                        if allowBreaks {
                            flush()
                            out.append(.lineBreak)
                        } else {
                            current.append(" ")
                        }
                    } else {
                        current.append(ch)
                    }
                }
                flush()
            case .note(let note):
                out.append(.note(Note(normalizeRuns(note.content), style: note.style)))
            case .lineBreak:
                if allowBreaks { out.append(.lineBreak) } else { out.append(.run(Run(" "))) }
            }
        }
        return out
    }

    /// Joins neighbouring runs with the same style and drops empty ones.
    static func merge(_ items: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for item in items {
            if case .run(let run) = item {
                if run.text.isEmpty { continue }
                if case .run(var last)? = out.last, last.style == run.style {
                    last.text += run.text
                    out[out.count - 1] = .run(last)
                    continue
                }
            }
            out.append(item)
        }
        return out
    }

    private static func inSpan(_ item: Inline, _ flag: Style) -> Bool {
        switch item {
        case .run(let run): return run.style.contains(flag)
        case .note(let note): return note.style.contains(flag)
        case .lineBreak: return false
        }
    }

    /// A span of `flag` may not start or end with whitespace: that whitespace is
    /// taken out of the span (it keeps its other style).
    static func moveEdgeWhitespaceOut(_ items: [Inline], flag: Style) -> [Inline] {
        var out: [Inline] = []
        var i = 0
        while i < items.count {
            guard inSpan(items[i], flag) else {
                out.append(items[i])
                i += 1
                continue
            }
            var j = i
            while j < items.count && inSpan(items[j], flag) { j += 1 }
            var span = Array(items[i..<j])
            var leading: [Inline] = []
            var trailing: [Inline] = []
            while case .run(var run)? = span.first, let first = run.text.unicodeScalars.first, first.properties.isWhitespace {
                let scalars = Array(run.text.unicodeScalars)
                var k = 0
                while k < scalars.count, scalars[k].properties.isWhitespace { k += 1 }
                leading.append(.run(Run(string(scalars[..<k]), run.style.subtracting(flag))))
                run.text = string(scalars[k...])
                if run.text.isEmpty { span.removeFirst() } else { span[0] = .run(run) }
            }
            while case .run(var run)? = span.last, let last = run.text.unicodeScalars.last, last.properties.isWhitespace {
                let scalars = Array(run.text.unicodeScalars)
                var k = scalars.count
                while k > 0, scalars[k - 1].properties.isWhitespace { k -= 1 }
                trailing.append(.run(Run(string(scalars[k...]), run.style.subtracting(flag))))
                run.text = string(scalars[..<k])
                if run.text.isEmpty { span.removeLast() } else { span[span.count - 1] = .run(run) }
            }
            out += leading
            out += span
            out += trailing.reversed()
            i = j
        }
        return out
    }

    // MARK: Lines

    private static func splitLines(_ items: [Inline]) -> [[Inline]] {
        var lines: [[Inline]] = [[]]
        for item in items {
            if case .lineBreak = item { lines.append([]) } else { lines[lines.count - 1].append(item) }
        }
        return lines
    }

    /// Removes ASCII spaces (only U+0020) at both ends of one line.
    private static func trimEdges(_ line: [Inline]) -> [Inline] {
        var line = line
        while case .run(var run)? = line.first, run.text.unicodeScalars.first == " " {
            run.text = string(run.text.unicodeScalars.drop(while: { $0 == " " }))
            if run.text.isEmpty { line.removeFirst() } else { line[0] = .run(run) }
        }
        while case .run(var run)? = line.last, run.text.unicodeScalars.last == " " {
            var scalars = Array(run.text.unicodeScalars)
            while scalars.last == " " { scalars.removeLast() }
            run.text = string(scalars[...])
            if run.text.isEmpty { line.removeLast() } else { line[line.count - 1] = .run(run) }
        }
        return line
    }

    private static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func trimLines(_ items: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for (n, line) in splitLines(items).enumerated() {
            if n > 0 { out.append(.lineBreak) }
            out += trimEdges(line)
        }
        return out
    }

    // MARK: Whitespace styles are not significant

    /// The block with every whitespace character unstyled. Two blocks that are
    /// equal after this differ at most in the bold or italic of spaces, which
    /// the writer may drop to make overlapping spans nest.
    public static func withoutWhitespaceStyles(_ block: Block) -> Block {
        func clean(_ inlines: [Inline]) -> [Inline] {
            var out: [Inline] = []
            for inline in inlines {
                switch inline {
                case .run(let run):
                    out += unstyleWhitespace(run).map { Inline.run($0) }
                case .note(let note):
                    out.append(.note(Note(note.content.flatMap { unstyleWhitespace($0) }, style: note.style)))
                case .lineBreak:
                    out.append(.lineBreak)
                }
            }
            return merge(out).map { inline in
                if case .note(let note) = inline {
                    return .note(Note(mergeRuns(note.content), style: note.style))
                }
                return inline
            }
        }
        switch block {
        case .paragraph(let inlines): return .paragraph(clean(inlines))
        case .heading(let level, let inlines): return .heading(level, clean(inlines))
        case .quote(let paragraphs): return .quote(paragraphs.map { clean($0) })
        default: return block
        }
    }

    private static func mergeRuns(_ runs: [Run]) -> [Run] {
        merge(runs.map { Inline.run($0) }).compactMap { if case .run(let r) = $0 { return r } else { return nil } }
    }

    private static func unstyleWhitespace(_ run: Run) -> [Run] {
        guard !run.style.isEmpty else { return [run] }
        var out: [Run] = []
        var current = String.UnicodeScalarView()
        var currentIsSpace: Bool?
        for scalar in run.text.unicodeScalars {
            let isSpace = scalar.properties.isWhitespace
            if currentIsSpace != nil, currentIsSpace != isSpace {
                out.append(Run(String(current), currentIsSpace! ? [] : run.style))
                current = String.UnicodeScalarView()
            }
            currentIsSpace = isSpace
            current.append(scalar)
        }
        if let isSpace = currentIsSpace { out.append(Run(String(current), isSpace ? [] : run.style)) }
        return out
    }

    // MARK: Boundary spaces (for the writer)

    /// All the ways to unstyle the whitespace that sits where the style changes,
    /// the block itself first, then fewest changes first (at most 80 blocks).
    static func whitespaceVariants(of block: Block) -> [Block] {
        switch block {
        case .paragraph(let inlines):
            return variants(of: [inlines]).map { .paragraph($0[0]) }
        case .heading(let level, let inlines):
            return variants(of: [inlines]).map { .heading(level, $0[0]) }
        case .quote(let paragraphs):
            return variants(of: paragraphs).map { .quote($0) }
        default:
            return [block]
        }
    }

    private static func variants(of lists: [[Inline]]) -> [[[Inline]]] {
        // Split the whitespace at the edges of styled runs out, remembering which pieces sit at a style change.
        var split: [[Inline]] = []
        var boundary: [(list: Int, index: Int)] = []
        for (n, inlines) in lists.enumerated() {
            var out: [Inline] = []
            for (i, inline) in inlines.enumerated() {
                guard case .run(let run) = inline, !run.style.isEmpty else {
                    out.append(inline)
                    continue
                }
                let before = i > 0 ? styleOf(inlines[i - 1]) : nil
                let after = i + 1 < inlines.count ? styleOf(inlines[i + 1]) : nil
                let scalars = Array(run.text.unicodeScalars)
                var lead = 0
                while lead < scalars.count, scalars[lead].properties.isWhitespace { lead += 1 }
                var trail = scalars.count
                while trail > lead, scalars[trail - 1].properties.isWhitespace { trail -= 1 }
                if lead > 0, let before, before != run.style {
                    boundary.append((n, out.count))
                    out.append(.run(Run(piece(scalars[..<lead]), run.style)))
                } else {
                    lead = 0
                }
                if trail < scalars.count, let after, after != run.style {
                    out.append(.run(Run(piece(scalars[lead..<trail]), run.style)))
                    boundary.append((n, out.count))
                    out.append(.run(Run(piece(scalars[trail...]), run.style)))
                } else {
                    out.append(.run(Run(piece(scalars[lead...]), run.style)))
                }
            }
            split.append(out)
        }
        guard !boundary.isEmpty else { return [lists] }
        let k = min(boundary.count, 12)
        var masks = (0..<(1 << k)).sorted { ($0.nonzeroBitCount, $0) < ($1.nonzeroBitCount, $1) }
        masks = Array(masks.prefix(80))
        return masks.map { mask in
            var copy = split
            for bit in 0..<k where mask & (1 << bit) != 0 {
                let (n, index) = boundary[bit]
                if case .run(var run) = copy[n][index] {
                    run.style = []
                    copy[n][index] = .run(run)
                }
            }
            return copy.map { merge($0) }
        }
    }

    private static func styleOf(_ inline: Inline) -> Style? {
        switch inline {
        case .run(let run): return run.style
        case .note(let note): return note.style
        case .lineBreak: return nil
        }
    }

    private static func piece<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
