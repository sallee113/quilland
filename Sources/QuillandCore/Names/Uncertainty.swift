import AppKit
import Foundation

/// A capital letter tells a name from an ordinary word, except where every word has one: at the
/// start of a sentence. «Вера» there may be a person or faith, «Роман» a person or a novel.
/// A match is *uncertain* when it stands at the start of a sentence and its lowercase form is an
/// ordinary Russian word. The app shows such matches as "maybe" and never links them silently.
public enum Uncertainty {
    /// Whether the word at `index` starts a sentence: nothing before it, or only an opening
    /// quote or dash after a full stop, a question or exclamation mark, or an ellipsis.
    public static func startsSentence(wordIndex: Int, in text: String, words: [Word]) -> Bool {
        let scalars = Array(text.unicodeScalars)
        var i = words[wordIndex].scalars.lowerBound - 1
        while i >= 0 {
            let s = scalars[i]
            if s.properties.isWhitespace || "«“„\"'(—–-".unicodeScalars.contains(s) { i -= 1; continue }
            return ".!?…\n".unicodeScalars.contains(s)
        }
        return true
    }

    /// Asks the macOS spell checker (Russian) whether a lowercase word is an ordinary word.
    /// Must be called on the main thread (NSSpellChecker is not thread-safe).
    @MainActor
    public final class Dictionary {
        private let checker = NSSpellChecker.shared
        private let tag = NSSpellChecker.uniqueSpellDocumentTag()
        private var cache: [String: Bool] = [:]

        public init() {
            checker.automaticallyIdentifiesLanguages = false
        }

        public func isOrdinaryWord(_ lowercase: String) -> Bool {
            if let known = cache[lowercase] { return known }
            let range = checker.checkSpelling(of: lowercase, startingAt: 0, language: "ru", wrap: false, inSpellDocumentWithTag: tag, wordCount: nil)
            let ok = range.location == NSNotFound
            cache[lowercase] = ok
            return ok
        }
    }
}
