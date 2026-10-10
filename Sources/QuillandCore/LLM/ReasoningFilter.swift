import Foundation

/// Reasoning kept out of the answer (ported from the old app's `llm/client.py`).
///
/// Models that think out loud wrap it in `<think>…</think>` or `[THINK]…[/THINK]`. LM Studio usually moves it
/// to a separate field, but not for every model or server, so the text is filtered as well.
public enum Reasoning {
    static let tags: [(open: [Unicode.Scalar], close: [Unicode.Scalar])] = [
        (Array("<think>".unicodeScalars), Array("</think>".unicodeScalars)),
        (Array("[THINK]".unicodeScalars), Array("[/THINK]".unicodeScalars)),
    ]

    /// The answer without reasoning blocks, or the blank lines before it. A block that never closes is dropped to its end.
    public static func strip(_ text: String) -> String {
        var filter = ReasoningFilter()
        let visible = filter.feed(text) + filter.finish()
        return visible
    }
}

/// The streaming form of `Reasoning.strip`: fed the reply piece by piece, it returns only what belongs to the
/// answer. A tag split across pieces is held back until it can be told apart from ordinary text.
public struct ReasoningFilter: Sendable {
    private var pending: [Unicode.Scalar] = []
    private var closing: [Unicode.Scalar]?
    private var started = false
    /// How much reasoning has been swallowed so far (characters), so an interface can say "thinking…".
    public private(set) var reasoningScalars = 0

    public init() {}

    /// Is the reply inside a reasoning block right now?
    public var isThinking: Bool { closing != nil }

    public mutating func feed(_ piece: String) -> String {
        pending.append(contentsOf: piece.unicodeScalars)
        var out: [Unicode.Scalar] = []
        while !pending.isEmpty {
            if let closing {
                if let end = Self.find(closing, in: pending) {
                    reasoningScalars += end
                    pending.removeFirst(end + closing.count)
                    self.closing = nil
                    continue
                }
                // Keep only what could be the start of the closing tag.
                let keep = min(pending.count, closing.count - 1)
                reasoningScalars += pending.count - keep
                pending.removeFirst(pending.count - keep)
                break
            }
            var best: (index: Int, tag: Int)?
            for (t, tag) in Reasoning.tags.enumerated() {
                if let i = Self.find(tag.open, in: pending), best == nil || i < best!.index { best = (i, t) }
            }
            if let (i, t) = best {
                out.append(contentsOf: pending[0..<i])
                pending.removeFirst(i + Reasoning.tags[t].open.count)
                closing = Reasoning.tags[t].close
                continue
            }
            let keep = partialTagLength()
            out.append(contentsOf: pending[0..<(pending.count - keep)])
            pending.removeFirst(pending.count - keep)
            break
        }
        return visible(out)
    }

    /// Whatever was held back, once the reply is complete (nothing, if it ended inside a reasoning block).
    public mutating func finish() -> String {
        let rest = closing == nil ? pending : []
        pending = []
        return visible(rest)
    }

    private func partialTagLength() -> Int {
        var n = min(pending.count, 7)
        while n > 0 {
            let tail = Array(pending[(pending.count - n)...])
            if Reasoning.tags.contains(where: { $0.open.starts(with: tail) }) { return n }
            n -= 1
        }
        return 0
    }

    private mutating func visible(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        var text = String(view)
        if !started {
            text = String(text.drop(while: { $0.isWhitespace }))
            started = !text.isEmpty
        }
        return text
    }

    static func find(_ needle: [Unicode.Scalar], in haystack: [Unicode.Scalar]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] && Array(haystack[i..<(i + needle.count)]) == needle { return i }
        return nil
    }
}
