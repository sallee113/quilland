import Foundation

/// The forms a Russian name takes in the six cases, derived from its nominative by rule.
///
/// Works on folded words (lowercase, ё as е, no stress marks), so `Пётр` gives `петра`.
/// It does not know which of two possible patterns a name follows (a name ending in -ь may be
/// masculine, Игорь, or feminine, Любовь; a name in -ин may be a surname, Пушкин, or a city,
/// Берлин), so it gives the forms of both: a few forms that nobody writes do no harm.
/// What it cannot derive (the vanishing vowel of Лев → Льва) is in a short list; a name that
/// follows no rule gets an alias in its card.
public enum Declension {
    private static let sibilants: Set<Character> = ["ж", "ч", "ш", "щ"]
    private static let velars: Set<Character> = ["г", "к", "х"]
    private static let vowels: Set<Character> = ["а", "е", "и", "о", "у", "ы", "э", "ю", "я"]
    /// Names whose stem changes in a way no rule shows.
    static let irregularStems: [String: [String]] = ["лев": ["льв"]]
    /// A hyphenated name that begins with one of these declines only its last part (Нью-Йорка).
    private static let fixedPrefixes: Set<String> = ["нью", "сан", "санкт", "ла", "эль", "ал", "фон", "де", "ван", "ди", "да", "дель", "ле"]

    public static func forms(of word: String) -> Set<String> {
        if word.contains("-") { return hyphenated(word) }
        var out: Set<String> = [word]
        let chars = Array(word)
        guard let last = chars.last, chars.count >= 2 else { return out }
        func add(_ stem: String, _ endings: [String]) { for e in endings { out.insert(stem + e) } }
        let dropped = String(chars.dropLast())

        // Surnames that are adjectives: Достоевский, Толстой, Белый; and their feminine forms.
        // -кий, -гий, -хий and -ший, -жий, -чий, -щий are adjectives (Горький, Хороший); other -ий are names (Дмитрий, Юрий).
        let adjectiveIY = ["кий", "гий", "хий", "ший", "жий", "чий", "щий"].contains(where: { word.hasSuffix($0) })
        if chars.count > 4, word.hasSuffix("ский") || word.hasSuffix("цкий") || word.hasSuffix("ой") || word.hasSuffix("ый") || adjectiveIY {
            add(String(chars.dropLast(2)), ["ого", "ому", "им", "ым", "ом"])
            return out
        }
        if chars.count > 4, word.hasSuffix("ая") {
            add(String(chars.dropLast(2)), ["ой", "ую"])
            return out
        }

        switch last {
        case "а":
            let stemLast = chars[chars.count - 2]
            let surname = ["ова", "ева", "ина", "ына"].contains(where: { word.hasSuffix($0) }) && chars.count > 4
            // A woman's surname (Иванова, Ивановой, Иванову) ...
            if surname { add(dropped, ["ой", "у"]) }
            // ... and an ordinary name. Only -ова and -ева are surnames for certain; -ина and -ына may be
            // either (Екатерина, Ирина; Пушкина), so they get both patterns.
            if !(surname && (word.hasSuffix("ова") || word.hasSuffix("ева"))) {
                add(dropped, [velars.contains(stemLast) || sibilants.contains(stemLast) ? "и" : "ы", "е", "у", "ой", "ою"])
                if sibilants.contains(stemLast) || stemLast == "ц" { add(dropped, ["ей"]) }
            }
        case "я":
            let stemLast = chars[chars.count - 2]
            if stemLast == "и" {
                add(dropped, ["и", "ю", "ей"]) // Мария: Марии, Марию, Марией
            } else {
                add(dropped, ["и", "е", "ю", "ей"]) // Зоя, Катя, Наталья, Илья
            }
        case "ь":
            add(dropped, ["я", "ю", "ем", "е", "и", "ью"]) // masculine (Игорь) and feminine (Любовь)
        case "й":
            add(dropped, ["я", "ю", "ем", "е", "и"]) // Сергей, Николай, Дмитрий
        default:
            if vowels.contains(last) { return out } // Мэри, Анри, Ли: not declined
            for stem in stemVariants(word) {
                add(stem, ["а", "у", "е"])
                add(stem, [sibilants.contains(last) || last == "ц" ? "ем" : "ом"])
                if ["ов", "ев", "ин", "ын"].contains(where: { word.hasSuffix($0) }) { add(stem, ["ым", "ом"]) }
            }
        }
        return out
    }

    /// The word itself, and the stem it has once an ending is added (a vanishing vowel).
    static func stemVariants(_ word: String) -> [String] {
        var out = [word]
        out += irregularStems[word] ?? []
        if word.hasSuffix("ел"), word.count >= 4 { out.append(String(word.dropLast(2)) + "л") } // Павел -> Павла
        return out
    }

    private static func hyphenated(_ word: String) -> Set<String> {
        let parts = word.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return [word] }
        if fixedPrefixes.contains(parts[0]) {
            return Set(forms(of: parts[parts.count - 1]).map { (parts.dropLast() + [$0]).joined(separator: "-") })
        }
        var combos: [[String]] = [[]]
        for part in parts {
            let options = Array(forms(of: part))
            combos = combos.flatMap { prefix in options.map { prefix + [$0] } }
            if combos.count > 400 { break }
        }
        return Set(combos.map { $0.joined(separator: "-") })
    }
}
