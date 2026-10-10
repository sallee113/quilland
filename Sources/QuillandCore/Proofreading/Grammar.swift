import Foundation

/// One difference between a passage and its corrected version.
public struct TextHunk: Equatable, Sendable {
    /// In UTF-16 units of the original.
    public var range: NSRange
    public var before: String
    public var after: String
}

/// The differences between a text and a corrected version of it, word by word: the model rewrites a passage, and what it really changed becomes a list of
/// small findings, each of which can be accepted or dismissed on its own.
public enum TextDiff {
    private struct Token { var text: String; var range: NSRange; var isSpace: Bool }

    private static func tokens(_ text: String) -> [Token] {
        let ns = text as NSString
        guard let re = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:[-’'][\\p{L}\\p{N}]+)*|\\s+|.", options: [.dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            let s = ns.substring(with: m.range)
            return Token(text: s, range: m.range, isSpace: s.allSatisfy { $0.isWhitespace })
        }
    }

    /// The hunks, in order. Changes that are only spacing are left out (the typography rules deal with them); a pure insertion is shown with the word before it.
    public static func hunks(from original: String, to corrected: String) -> [TextHunk] {
        let a = tokens(original), b = tokens(corrected)
        let n = a.count, m = b.count
        guard n > 0 || m > 0 else { return [] }
        // Longest common subsequence of the tokens.
        var table = [[Int32]](repeating: [Int32](repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i].text == b[j].text ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }
        // Walk it: runs of tokens that differ become hunks.
        var out: [TextHunk] = []
        var i = 0, j = 0
        var hunkStartA: Int?, hunkStartB = 0
        func close(_ endA: Int, _ endB: Int) {
            guard let sa = hunkStartA else { return }
            hunkStartA = nil
            var from = sa, to = endA   // original tokens [from, to)
            var newText = b[hunkStartB..<endB].map(\.text).joined()
            // A hunk is only worth showing if more than spacing changed.
            let oldWords = a[from..<to].filter { !$0.isSpace }.map(\.text), newWords = b[hunkStartB..<endB].filter { !$0.isSpace }.map(\.text)
            if oldWords == newWords { return }
            // A pure insertion has no words of its own to point at: take the word before it (or after it, at the very start).
            if from == to {
                if let prev = (0..<from).reversed().first(where: { !a[$0].isSpace }) { newText = a[prev..<from].map(\.text).joined() + newText; from = prev }
                else if let next = (to..<n).first(where: { !a[$0].isSpace }) { newText += a[to...next].map(\.text).joined(); to = next + 1 }
            }
            // Spaces around the change are not part of it.
            while from < to, a[from].isSpace { from += 1 }
            while to > from, a[to - 1].isSpace { to -= 1 }
            guard from < to else { return }
            var range = NSRange(location: a[from].range.location, length: NSMaxRange(a[to - 1].range) - a[from].range.location)
            let after = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            // A word taken out takes one space with it, so that no double space is left.
            if after.isEmpty, range.location > 0, (original as NSString).substring(with: NSRange(location: range.location - 1, length: 1)) == " " { range = NSRange(location: range.location - 1, length: range.length + 1) }
            out.append(TextHunk(range: range, before: (original as NSString).substring(with: range), after: after))
        }
        while i < n || j < m {
            if i < n, j < m, a[i].text == b[j].text, table[i][j] == table[i + 1][j + 1] + 1 {
                close(i, j)
                i += 1; j += 1
            } else {
                if hunkStartA == nil { hunkStartA = i; hunkStartB = j }
                if j < m, i >= n || table[i][j + 1] >= table[i + 1][j] { j += 1 } else { i += 1 }
            }
        }
        close(n, m)
        // Hunks separated by nothing but a space are one change.
        var merged: [TextHunk] = []
        let ns = original as NSString
        for h in out {
            if let last = merged.last, h.range.location >= NSMaxRange(last.range), h.range.location - NSMaxRange(last.range) <= 1,
               ns.substring(with: NSRange(location: NSMaxRange(last.range), length: h.range.location - NSMaxRange(last.range))).allSatisfy({ $0.isWhitespace }) {
                let gap = ns.substring(with: NSRange(location: NSMaxRange(last.range), length: h.range.location - NSMaxRange(last.range)))
                let range = NSRange(location: last.range.location, length: NSMaxRange(h.range) - last.range.location)
                merged[merged.count - 1] = TextHunk(range: range, before: last.before + gap + h.before, after: last.after + gap + h.after)
            } else { merged.append(h) }
        }
        return merged
    }
}

public enum GrammarPrompt {
    public static func system(language: String) -> String {
        let russian = language.lowercased().hasPrefix("ru")
        return AIPrompts.resolve(russian ? "grammar.ru" : "grammar.en", language: language, builtIn: builtIn(russian: russian))
    }

    static func builtIn(russian: Bool) -> String {
        var s = """
        You are a careful proofreader. Fix ONLY mistakes of spelling, punctuation and grammar in the passage.
        Do not change words that are correct, do not rephrase, do not improve the style, do not reorder, add or remove sentences. Keep names, quotation marks, dashes and line breaks exactly as they are.
        If there are no mistakes, return the passage unchanged. Return ONLY the passage, with nothing before or after it, no comments and no markup.
        """
        if russian {
            s += """

            Russian rules to apply: commas before «что», «чтобы», «который», «но», «а», «хотя», «потому что» and around introductory words, participial and adverbial phrases; the dash and the commas in dialogue; «ё» is not required; check endings, «не» with verbs and «ться/тся».
            """
        }
        return s
    }

    public static func user(_ passage: String) -> String { "Passage:\n\"\"\"\n\(passage)\n\"\"\"" }

    /// The corrected passage out of a reply: without fences, quotes of the wrapper or a spoken introduction.
    public static func extract(_ reply: String) -> String {
        var s = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") { s = s.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n"); if let end = s.range(of: "```", options: .backwards) { s = String(s[..<end.lowerBound]) } }
        if s.hasPrefix("\"\"\""), s.hasSuffix("\"\"\""), s.count > 6 { s = String(s.dropFirst(3).dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct GrammarScene: Sendable {
    public var id: String
    public var title: String
    public var text: String
    public init(id: String, title: String, text: String) { self.id = id; self.title = title; self.text = text }
}

public struct GrammarSummary: Equatable, Sendable {
    public var piecesDone = 0
    public var found = 0
    /// Answers that changed too much to be corrections (the model rewrote the passage): not shown.
    public var rewritten = 0
    public var failedPieces = 0
    public var stopped = false
    public var error: String?
}

public enum GrammarJob {
    /// How much text goes in one request: small pieces are corrected more faithfully.
    public static let pieceSize = 1800

    /// When over a third of the words of a piece were touched, the model rewrote it rather than corrected it.
    static func rewrote(hunks: [TextHunk], words: Int) -> Bool {
        let changed = hunks.reduce(0) { $0 + max($1.before.split { $0.isWhitespace }.count, $1.after.split { $0.isWhitespace }.count) }
        return changed > max(6, Int(Double(words) * 0.35))
    }

    /// Reads the scenes piece by piece. `found` gets the findings of each piece as they come (their ranges are in the scene's text); Stop keeps them.
    public static func run(scenes: [GrammarScene], language: String, temperature: Double? = nil, client: LMStudioClient,
                           progress: @Sendable (CollectProgress) -> Void, found: @Sendable (String, [TypographyFinding]) -> Void) async -> GrammarSummary {
        var summary = GrammarSummary()
        let system = GrammarPrompt.system(language: language)
        let totalPieces = scenes.reduce(0) { $0 + CollectChunker.chunks($1.text, maxCharacters: pieceSize).filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 }.count }
        var readPieces = 0
        for (index, scene) in scenes.enumerated() {
            if Task.isCancelled { summary.stopped = true; break }
            progress(CollectProgress(scene: index + 1, of: scenes.count, title: scene.title, found: summary.found, piece: readPieces, pieces: totalPieces))
            let ns = scene.text as NSString
            for piece in CollectChunker.chunks(scene.text, maxCharacters: pieceSize) {
                if Task.isCancelled { summary.stopped = true; break }
                let original = piece.text
                guard original.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else { continue }
                progress(CollectProgress(scene: index + 1, of: scenes.count, title: scene.title, found: summary.found, piece: readPieces, pieces: totalPieces))
                readPieces += 1
                do {
                    let reply = try await client.chat([ChatMessage("system", system), ChatMessage("user", GrammarPrompt.user(original))], think: false, temperature: temperature ?? AIPrompts.temperature("grammar", default: 0.1), maxTokens: max(400, original.count))
                    let corrected = GrammarPrompt.extract(reply)
                    let words = original.split { $0.isWhitespace }.count
                    // A passage that came back much shorter or longer is not a correction of it.
                    let ratio = Double(corrected.count) / Double(max(1, original.trimmingCharacters(in: .whitespacesAndNewlines).count))
                    guard !corrected.isEmpty, ratio > 0.8, ratio < 1.25 else { summary.rewritten += 1; summary.piecesDone += 1; continue }
                    let hunks = TextDiff.hunks(from: original, to: corrected)
                    if rewrote(hunks: hunks, words: words) { summary.rewritten += 1; summary.piecesDone += 1; continue }
                    let findings: [TypographyFinding] = hunks.map { h in
                        let abs = NSRange(location: h.range.location + piece.offset, length: h.range.length)
                        let from = max(0, abs.location - 24), to = min(ns.length, NSMaxRange(abs) + 24)
                        var cb = ns.substring(with: NSRange(location: from, length: abs.location - from)), ca = ns.substring(with: NSRange(location: NSMaxRange(abs), length: to - NSMaxRange(abs)))
                        if let i = cb.lastIndex(of: "\n") { cb = String(cb[cb.index(after: i)...]) }
                        if let i = ca.firstIndex(of: "\n") { ca = String(ca[..<i]) }
                        return TypographyFinding(rule: .grammar, range: abs, before: h.before, after: h.after, contextBefore: cb, contextAfter: ca)
                    }
                    summary.found += findings.count
                    summary.piecesDone += 1
                    if !findings.isEmpty { found(scene.id, findings) }
                } catch {
                    if Task.isCancelled || error is CancellationError { summary.stopped = true; break }
                    if let e = error as? LLMError, e == .unreachable || e.description.contains("not found") { summary.error = e.description; return summary }
                    summary.failedPieces += 1
                }
            }
            if summary.stopped { break }
        }
        return summary
    }
}
