import Foundation

/// A kind of book and the length it usually has. The target size of a book is kept in characters (with spaces); a kind is a way to choose it:
/// its usual length in words is turned into characters by the language of the book.
public struct BookKind: Equatable, Sendable {
    public let id: String
    /// English name; the application translates it.
    public let name: String
    /// The length that is filled in when the kind is chosen.
    public let typicalWords: Int
    /// The range the kind covers (nil: no limit on that side).
    public let minWords: Int?
    public let maxWords: Int?
}

public enum BookKinds {
    public static let all: [BookKind] = [
        BookKind(id: "flash", name: "Flash fiction", typicalWords: 1_000, minWords: nil, maxWords: 1_500),
        BookKind(id: "short_story", name: "Short story", typicalWords: 5_000, minWords: 1_500, maxWords: 7_500),
        BookKind(id: "novelette", name: "Novelette", typicalWords: 12_000, minWords: 7_500, maxWords: 17_500),
        BookKind(id: "novella", name: "Novella", typicalWords: 30_000, minWords: 17_500, maxWords: 40_000),
        BookKind(id: "short_novel", name: "Short novel", typicalWords: 55_000, minWords: 40_000, maxWords: 70_000),
        BookKind(id: "novel", name: "Novel", typicalWords: 90_000, minWords: 70_000, maxWords: 110_000),
        BookKind(id: "epic", name: "Epic or saga", typicalWords: 130_000, minWords: 110_000, maxWords: nil),
    ]

    public static func kind(_ id: String?) -> BookKind? { all.first { $0.id == id } }

    /// How many characters (spaces included) a word takes on average in the language, the space after it too.
    public static func charactersPerWord(_ language: String) -> Double {
        ["en": 6.0, "es": 6.0, "it": 6.0, "fr": 6.3, "ru": 7.0, "uk": 7.0, "pl": 7.0, "de": 7.5][language.lowercased()] ?? 6.0
    }

    /// The target in characters a kind gives in a language, to the nearest thousand.
    public static func characters(of kind: BookKind, language: String) -> Int {
        Int((Double(kind.typicalWords) * charactersPerWord(language) / 1000).rounded()) * 1000
    }

    /// About how many words a number of characters is in the language.
    public static func words(fromCharacters characters: Int, language: String) -> Int {
        Int((Double(characters) / charactersPerWord(language)).rounded())
    }

    /// The Russian publishing unit: 40,000 characters with spaces.
    public static let charactersPerAuthorSheet = 40_000

    public static func authorSheets(fromCharacters characters: Int) -> Double { Double(characters) / Double(charactersPerAuthorSheet) }

    /// Languages whose books are counted in author's sheets.
    public static func usesAuthorSheets(_ language: String) -> Bool { ["ru", "uk", "be"].contains(language.lowercased()) }

    /// How far a book is from its target, in whole percent (nil without a target); it may pass 100.
    public static func percent(characters: Int, target: Int?) -> Int? {
        guard let target, target > 0 else { return nil }
        return Int((Double(characters) / Double(target) * 100).rounded())
    }
}
