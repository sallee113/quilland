import Foundation
@testable import QuillandCore

/// Corpus files, shipped with the tests (Tests/QuillandCoreTests/Corpus).
enum Corpus {
    static var root: URL { Bundle.module.resourceURL!.appendingPathComponent("Corpus") }

    static func files(_ folder: String, suffix: String) -> [URL] {
        let dir = root.appendingPathComponent(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(suffix) }.sorted().map { dir.appendingPathComponent($0) }
    }

    /// Bytes decoded as UTF-8, a BOM kept as a character.
    static func read(_ url: URL) -> String {
        String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
    }
}

/// Where two texts first differ, with the characters around it spelled out.
func describeDifference(_ expected: String, _ actual: String) -> String {
    let e = Array(expected.unicodeScalars)
    let a = Array(actual.unicodeScalars)
    var i = 0
    while i < e.count, i < a.count, e[i] == a[i] { i += 1 }
    func context(_ s: [Unicode.Scalar]) -> String {
        let lo = max(0, i - 24)
        let hi = min(s.count, i + 24)
        return lo < hi ? s[lo..<hi].map { $0.escaped(asASCII: false) }.joined() : ""
    }
    return "first difference at scalar \(i) (expected \(e.count), got \(a.count) scalars): expected «\(context(e))» got «\(context(a))»"
}

/// How many blocks (paragraphs separated by blank lines) of `before` were replaced, and by how many.
func changedBlocks(before: String, after: String) -> (removed: Int, added: Int) {
    let b = before.components(separatedBy: "\n\n")
    let a = after.components(separatedBy: "\n\n")
    var prefix = 0
    while prefix < b.count, prefix < a.count, b[prefix] == a[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < b.count - prefix, suffix < a.count - prefix, b[b.count - 1 - suffix] == a[a.count - 1 - suffix] { suffix += 1 }
    return (b.count - prefix - suffix, a.count - prefix - suffix)
}

// MARK: Random generation (a fixed seed, so a failure can be repeated)

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Fuzz {
    /// Characters that matter to the format, plus ordinary and awkward ones.
    static let alphabet: [String] = [
        "а", "б", "в", "ё", "й", " ", " ", " ", "a", "b", "*", "*", "\\", "^", "[", "]", "#", ">", "<",
        "-", "!", "\u{00A0}", "\u{202F}", "«", "»", "—", ".", ",", "\u{0301}", "1", "_", "|", "~", "`", "😀",
    ]

    static func text(_ rng: inout SplitMix64, maxLength: Int = 8) -> String {
        let n = Int.random(in: 0...maxLength, using: &rng)
        return (0..<n).map { _ in alphabet.randomElement(using: &rng)! }.joined()
    }

    static func style(_ rng: inout SplitMix64) -> Style {
        var s: Style = []
        if Bool.random(using: &rng) { s.insert(.bold) }
        if Int.random(in: 0..<3, using: &rng) == 0 { s.insert(.italic) }
        return s
    }

    static func runs(_ rng: inout SplitMix64) -> [Run] {
        (0..<Int.random(in: 1...3, using: &rng)).map { _ in Run(text(&rng), style(&rng)) }
    }

    static func inlines(_ rng: inout SplitMix64, allowBreaks: Bool) -> [Inline] {
        (0..<Int.random(in: 1...6, using: &rng)).map { _ in
            switch Int.random(in: 0..<10, using: &rng) {
            case 0: return Inline.note(Note(runs(&rng), style: style(&rng)))
            case 1 where allowBreaks: return Inline.lineBreak
            default: return Inline.run(Run(text(&rng), style(&rng)))
            }
        }
    }

    static func document(_ rng: inout SplitMix64) -> Document {
        let ids = ["3f2504e0-4f89-41d3-9a0c-0305e82c3301", "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"]
        var blocks: [Block] = []
        for _ in 0..<Int.random(in: 1...6, using: &rng) {
            switch Int.random(in: 0..<10, using: &rng) {
            case 0: blocks.append(.heading(Int.random(in: 1...3, using: &rng), inlines(&rng, allowBreaks: false)))
            case 1: blocks.append(.sceneBreak)
            case 2: blocks.append(.fragment(ids.randomElement(using: &rng)!))
            case 3: blocks.append(.quote((0..<Int.random(in: 1...3, using: &rng)).map { _ in inlines(&rng, allowBreaks: true) }))
            default: blocks.append(.paragraph(inlines(&rng, allowBreaks: true)))
            }
        }
        return Document(blocks)
    }

    // MARK: Realistic text: words separated by spaces, styles changing between words

    static let letters = Array("абвгдеёжзийклмнопрстуфхцчшщыэюяabcdefghijklmnopqrstuvwxyz").map(String.init)
    static let wordEnds = ["", "", "", "", ".", ",", "!", "?", "…", ":", ";", "»", ")", "\""]
    static let wordStarts = ["", "", "", "", "«", "(", "\"", "„", "“", "—\u{00A0}"]

    static func word(_ rng: inout SplitMix64) -> String {
        let n = Int.random(in: 1...9, using: &rng)
        let body = (0..<n).map { _ in letters.randomElement(using: &rng)! }.joined()
        return wordStarts.randomElement(using: &rng)! + body + wordEnds.randomElement(using: &rng)!
    }

    static func realisticInlines(_ rng: inout SplitMix64, allowBreaks: Bool = true) -> [Inline] {
        var out: [Inline] = []
        var style: Style = []
        let count = Int.random(in: 1...14, using: &rng)
        for w in 0..<count {
            if Int.random(in: 0..<5, using: &rng) == 0 { style = Fuzz.style(&rng) }
            let text = word(&rng)
            if text.count >= 3, Int.random(in: 0..<25, using: &rng) == 0 {
                // a style that starts or ends inside a word
                let cut = text.index(text.startIndex, offsetBy: Int.random(in: 1..<(text.count), using: &rng))
                out.append(.run(Run(String(text[..<cut]), style)))
                style = Fuzz.style(&rng)
                out.append(.run(Run(String(text[cut...]), style)))
            } else {
                out.append(.run(Run(text, style)))
            }
            if Int.random(in: 0..<14, using: &rng) == 0 {
                out.append(.note(Note((0..<Int.random(in: 1...2, using: &rng)).map { _ in
                    Run(word(&rng) + " " + word(&rng), Fuzz.style(&rng))
                }, style: style)))
            }
            if allowBreaks, Int.random(in: 0..<30, using: &rng) == 0 {
                out.append(.lineBreak)
            } else if w < count - 1 {
                out.append(.run(Run(" ", style)))
            }
        }
        return out
    }

    static func realisticDocument(_ rng: inout SplitMix64) -> Document {
        let ids = ["3f2504e0-4f89-41d3-9a0c-0305e82c3301", "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d"]
        var blocks: [Block] = []
        for _ in 0..<Int.random(in: 1...8, using: &rng) {
            switch Int.random(in: 0..<20, using: &rng) {
            case 0, 1: blocks.append(.heading(Int.random(in: 1...3, using: &rng), realisticInlines(&rng, allowBreaks: false)))
            case 2: blocks.append(.sceneBreak)
            case 3: blocks.append(.fragment(ids.randomElement(using: &rng)!))
            case 4, 5: blocks.append(.quote((0..<Int.random(in: 1...3, using: &rng)).map { _ in realisticInlines(&rng) }))
            default: blocks.append(.paragraph(realisticInlines(&rng)))
            }
        }
        return Document(blocks)
    }

    /// Source text built from pieces that the parser treats specially.
    static let tokens: [String] = [
        "а", "б", "слово", " ", " ", "\n", "\n\n", "> ", ">", "# ", "## ", "#### ", "* * *", "**", "*", "***", "^[", "]",
        "\\", "\\\n", "<!-- fragment: 3f2504e0-4f89-41d3-9a0c-0305e82c3301 -->", "- ", "1. ", "\t", "\u{00A0}", "\r\n",
        "_", "`", "[", "(", ")", "\u{0301}", "\u{2028}", "\u{FEFF}",
    ]

    static func source(_ rng: inout SplitMix64) -> String {
        (0..<Int.random(in: 1...30, using: &rng)).map { _ in tokens.randomElement(using: &rng)! }.joined()
    }
}

// MARK: Compact printing of a model, for readable failure messages

func compact(_ document: Document) -> String {
    document.blocks.map { compact($0) }.joined(separator: " | ")
}

func compact(_ block: Block) -> String {
    switch block {
    case .paragraph(let i): return "P(" + compact(i) + ")"
    case .heading(let l, let i): return "H\(l)(" + compact(i) + ")"
    case .quote(let ps): return "Q(" + ps.map { compact($0) }.joined(separator: " // ") + ")"
    case .sceneBreak: return "SB"
    case .fragment(let id): return "F(\(id.prefix(4)))"
    }
}

func compact(_ inlines: [Inline]) -> String {
    inlines.map { inline in
        switch inline {
        case .run(let r): return compact(r)
        case .lineBreak: return "⏎"
        case .note(let n): return "^[" + n.content.map { compact($0) }.joined() + "]\(compactStyle(n.style))"
        }
    }.joined(separator: " ")
}

func compact(_ run: Run) -> String {
    let s = compactStyle(run.style)
    return s.isEmpty ? run.text.debugDescription : "\(s):\(run.text.debugDescription)"
}

func compactStyle(_ s: Style) -> String { (s.contains(.bold) ? "b" : "") + (s.contains(.italic) ? "i" : "") }

/// Equal, except possibly in the bold or italic of spaces (which the writer may drop to make spans nest).
func sameDocument(_ a: Document, _ b: Document) -> Bool {
    a.blocks.map(Normalizer.withoutWhitespaceStyles) == b.blocks.map(Normalizer.withoutWhitespaceStyles)
}

/// The document with all bold and italic removed: what the text says, whatever its styling.
func unstyled(_ document: Document) -> Document {
    func plain(_ inlines: [Inline]) -> [Inline] {
        inlines.map { inline in
            switch inline {
            case .run(let run): return .run(Run(run.text))
            case .note(let note): return .note(Note(note.content.map { Run($0.text) }))
            case .lineBreak: return .lineBreak
            }
        }
    }
    return Normalizer.normalize(Document(document.blocks.map { block in
        switch block {
        case .paragraph(let i): return .paragraph(plain(i))
        case .heading(let l, let i): return .heading(l, plain(i))
        case .quote(let ps): return .quote(ps.map(plain))
        default: return block
        }
    }))
}
