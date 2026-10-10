import Foundation

/// A finding is shown only when its quote is really in the scene: the model's words are looked for in the text, ignoring case, ё/е, quotation marks,
/// dashes and spacing. The range returned is the text's own, so the author's click goes to the right place.
public enum QuoteVerifier {
    private struct Word { var norm: String; var range: NSRange }

    private static func words(_ text: String) -> [Word] {
        var out: [Word] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { word, range, _, _ in
            guard let word else { return }
            let norm = Names.normalize(word)
            if !norm.isEmpty { out.append(Word(norm: norm, range: NSRange(range, in: text))) }
        }
        return out
    }

    /// Where the quote is in the text, or nil. A long quote may differ from the text at its end (models like to shorten): its first words must be there,
    /// in a row, at least four and three fifths of the quote (a shorter quote must be there whole).
    public static func find(_ quote: String, in text: String) -> NSRange? {
        let q = words(quote)
        guard !q.isEmpty else { return nil }
        let t = words(text)
        let need = q.count <= 4 ? q.count : max(4, Int((Double(q.count) * 0.6).rounded(.up)))
        guard t.count >= need else { return nil }
        let wanted = q.prefix(need).map(\.norm)
        var i = 0
        while i + need <= t.count {
            if (0..<need).allSatisfy({ t[i + $0].norm == wanted[$0] }) {
                // Extend over as many of the remaining quote words as follow.
                var last = i + need - 1
                var k = need
                while k < q.count, last + 1 < t.count, t[last + 1].norm == q[k].norm { last += 1; k += 1 }
                let start = t[i].range.location
                return NSRange(location: start, length: NSMaxRange(t[last].range) - start)
            }
            i += 1
        }
        return nil
    }
}
