import Foundation
import NaturalLanguage

/// A character, place or thing that can be found in the text by its name or an alias.
public struct NameEntry: Equatable, Sendable {
    public var id: String
    public var name: String
    public var aliases: [String]
    /// Found in lowercase text too. For places and things, whose names are often ordinary words (a campsite, a river); a character's
    /// name needs its capital letter, or every "вера" would be Vera.
    public var ignoresCapitals: Bool
    public init(id: String, name: String, aliases: [String] = [], ignoresCapitals: Bool = false) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.ignoresCapitals = ignoresCapitals
    }
    var spellings: [String] { [name] + aliases }
}

public struct NameMatch: Equatable, Hashable, Sendable {
    public var entry: String
    /// Indexes into `Words.split(text)`.
    public var words: Range<Int>
}

public protocol NameMatcher {
    func matches(in text: String) -> [NameMatch]
}

/// One spelling of a name, word by word.
struct Spelling {
    var entry: String
    /// For each word of the spelling: does it need a capital letter, and the folded words it accepts.
    var tokens: [(capital: Bool, accepts: Set<String>)]
}

/// Finds spellings in a text, word by word. `accepts` decides which words fit a word of a spelling.
func scan(text: String, spellings: [Spelling], lemma: ((Int) -> String?)? = nil) -> [NameMatch] {
    let words = Words.split(text)
    var index: [String: [Int]] = [:]
    for (n, spelling) in spellings.enumerated() {
        for form in spelling.tokens[0].accepts { index[form, default: []].append(n) }
    }
    var out: [NameMatch] = []
    var seen = Set<NameMatch>()
    for (i, word) in words.enumerated() {
        var candidates = index[word.folded] ?? []
        if let lemma, let l = lemma(i) { candidates += index["\u{1}" + l] ?? [] }
        for n in candidates {
            let spelling = spellings[n]
            guard i + spelling.tokens.count <= words.count else { continue }
            var ok = true
            for (k, token) in spelling.tokens.enumerated() {
                let w = words[i + k]
                let viaLemma = lemma?(i + k).map { token.accepts.contains("\u{1}" + $0) } ?? false
                if token.capital && !w.startsUppercase { ok = false; break }
                if !token.accepts.contains(w.folded) && !viaLemma { ok = false; break }
            }
            if ok {
                let match = NameMatch(entry: spelling.entry, words: i..<(i + spelling.tokens.count))
                if seen.insert(match).inserted { out.append(match) }
            }
        }
    }
    return out
}

func firstIsUppercase(_ s: String) -> Bool { s.unicodeScalars.first?.properties.isUppercase ?? false }

// MARK: 1. The rule of the old app: the name without its last vowel, plus up to three letters (kept as a baseline for the benchmark)

public struct StemMatcher: NameMatcher {
    public init(entries: [NameEntry]) {
        stems = entries.flatMap { entry in entry.spellings.map { (entry.id, Words.split($0), entry.ignoresCapitals) } }
    }

    private let stems: [(String, [Word], Bool)]

    public func matches(in text: String) -> [NameMatch] {
        let words = Words.split(text)
        var out: [NameMatch] = []
        for (id, tokens, ignoresCapitals) in stems where !tokens.isEmpty {
            outer: for i in 0..<words.count where i + tokens.count <= words.count {
                for (k, token) in tokens.enumerated() {
                    let w = words[i + k]
                    if token.startsUppercase && !ignoresCapitals && !w.startsUppercase { continue outer }
                    let name = Array(token.folded)
                    let stem = name.last.map { "аяйьоеыиуюэ".contains($0) } == true ? String(name.dropLast()) : token.folded
                    let ok = w.folded == token.folded
                        || (stem.count >= 3 && w.folded.hasPrefix(stem) && w.folded.count - stem.count <= 3)
                    if !ok { continue outer }
                }
                out.append(NameMatch(entry: id, words: i..<(i + tokens.count)))
            }
        }
        return out
    }
}

// MARK: 2. The forms derived by rule

public struct ParadigmMatcher: NameMatcher {
    private let spellings: [Spelling]

    public init(entries: [NameEntry]) {
        var out: [Spelling] = []
        for entry in entries {
            for spelling in entry.spellings {
                let tokens = Words.split(spelling).map { word in (capital: word.startsUppercase && !entry.ignoresCapitals, accepts: Declension.forms(of: word.folded)) }
                if !tokens.isEmpty { out.append(Spelling(entry: entry.id, tokens: tokens)) }
            }
        }
        spellings = out
    }

    public func matches(in text: String) -> [NameMatch] { scan(text: text, spellings: spellings) }
}

// MARK: 3. Apple's lemmatizer

/// A word fits a name when the system gives both the same base form.
public struct LemmaMatcher: NameMatcher {
    private let spellings: [Spelling]

    public init(entries: [NameEntry]) {
        var out: [Spelling] = []
        for entry in entries {
            for spelling in entry.spellings {
                let tokens = Words.split(spelling).map { word -> (capital: Bool, accepts: Set<String>) in
                    var accepts: Set<String> = [word.folded]
                    if let lemma = LemmaMatcher.lemma(ofNominative: word.text) { accepts.insert("\u{1}" + lemma) }
                    return (word.startsUppercase && !entry.ignoresCapitals, accepts)
                }
                if !tokens.isEmpty { out.append(Spelling(entry: entry.id, tokens: tokens)) }
            }
        }
        spellings = out
    }

    static func lemma(ofNominative word: String) -> String? {
        let text = "Это \(word)."
        let lemmas = LemmaMatcher.lemmas(of: text, words: Words.split(text))
        return lemmas.count > 1 ? lemmas[1] : nil
    }

    /// The folded lemma of each word, or nil where the system gives none.
    static func lemmas(of text: String, words: [Word]) -> [String?] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.setLanguage(.russian, range: text.startIndex..<text.endIndex)
        var indexes: [String.Index] = []
        var position = text.unicodeScalars.startIndex
        while position < text.unicodeScalars.endIndex {
            indexes.append(position)
            position = text.unicodeScalars.index(after: position)
        }
        indexes.append(text.unicodeScalars.endIndex)
        return words.map { word in
            let at = indexes[word.scalars.lowerBound]
            guard let tag = tagger.tag(at: at, unit: .word, scheme: .lemma).0 else { return nil }
            return Words.fold(tag.rawValue)
        }
    }

    public func matches(in text: String) -> [NameMatch] {
        let words = Words.split(text)
        let lemmas = LemmaMatcher.lemmas(of: text, words: words)
        return scan(text: text, spellings: spellings, lemma: { $0 < lemmas.count ? lemmas[$0] : nil })
    }
}

// MARK: 4. Both

public struct HybridMatcher: NameMatcher {
    private let paradigm: ParadigmMatcher
    private let lemma: LemmaMatcher

    public init(entries: [NameEntry]) {
        paradigm = ParadigmMatcher(entries: entries)
        lemma = LemmaMatcher(entries: entries)
    }

    public func matches(in text: String) -> [NameMatch] {
        var seen = Set<NameMatch>()
        return (paradigm.matches(in: text) + lemma.matches(in: text)).filter { seen.insert($0).inserted }
    }
}
