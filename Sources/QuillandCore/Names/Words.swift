import Foundation

/// A word of a text: where it is, and the forms of it that matching uses.
public struct Word: Equatable, Sendable {
    /// Offsets in the text's Unicode scalars.
    public var scalars: Range<Int>
    public var text: String
    /// Lowercase, ё as е, stress marks removed: what names are compared by.
    public var folded: String
    public var startsUppercase: Bool
}

public enum Words {
    /// The words of `text`: letters (with stress marks), and a hyphen or apostrophe between letters
    /// (`Нью-Йорка`, `O'Neil`). Digits and punctuation are not words.
    public static func split(_ text: String) -> [Word] {
        let scalars = Array(text.unicodeScalars)
        var words: [Word] = []
        var i = 0
        func isLetter(_ s: Unicode.Scalar) -> Bool {
            switch s.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .nonspacingMark: return true
            default: return false
            }
        }
        func isJoiner(_ s: Unicode.Scalar) -> Bool { s == "-" || s == "\u{2010}" || s == "\u{2019}" || s == "'" }
        while i < scalars.count {
            guard isLetter(scalars[i]), scalars[i].properties.generalCategory != .nonspacingMark else {
                i += 1
                continue
            }
            var j = i + 1
            while j < scalars.count {
                if isLetter(scalars[j]) { j += 1 }
                else if isJoiner(scalars[j]), j + 1 < scalars.count, isLetter(scalars[j + 1]) { j += 2 }
                else { break }
            }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars[i..<j])
            let word = String(view)
            words.append(Word(scalars: i..<j, text: word, folded: fold(word), startsUppercase: scalars[i].properties.isUppercase))
            i = j
        }
        return words
    }

    /// Lowercase, ё as е, stress marks (acute and grave accents) removed.
    public static func fold(_ word: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in word.unicodeScalars {
            if scalar == "\u{0301}" || scalar == "\u{0300}" { continue }
            if scalar == "ё" || scalar == "Ё" { out.append("е"); continue }
            out.append(contentsOf: String(scalar).lowercased().unicodeScalars)
        }
        return String(out)
    }
}
