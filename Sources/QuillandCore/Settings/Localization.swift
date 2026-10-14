import Foundation

// The language of the interface (not of the book).
//
// English is the language of the source: every text in the code is its own English text, `L("Open Book…")`, so the code stays readable and a
// text with no translation shows in English. A language is one JSON file:
//
//   { "format": 1, "code": "ru", "name": "Русский", "plural_rule": "ru",
//     "strings": { "Open Book…": "Открыть книгу…", "Delete “{title}”?": "Удалить «{title}»?" },
//     "plurals": { "{n} scenes": { "one": "{n} сцена", "few": "{n} сцены", "many": "{n} сцен", "other": "{n} сцены" } } }
//
// `{name}` marks a place the program fills in. A plural text is found by its English plural form; the language gives one text per category its
// rule has. Files in the app's own folder and in the user's folder (`~/Library/Application Support/Quilland/Languages/`) are all offered;
// a user's file replaces a bundled one with the same code.

/// How a language counts: which category a number belongs to (`one`, `few`, `many`…).
public enum PluralRule: String, Sendable, CaseIterable {
    /// One for 1, other for the rest (English, German, Spanish, Italian, Dutch, Portuguese…).
    case en
    /// One for 0 and 1 (French).
    case fr
    /// One, few, many, other (Russian, Ukrainian, Belarusian).
    case ru
    /// One, few, many, other (Polish).
    case pl
    /// One, few, many, other (Czech, Slovak).
    case cs
    /// Zero, one, two, few, many, other (Arabic).
    case ar
    /// No plural (Japanese, Chinese, Korean, Vietnamese, Turkish for nouns after a number…).
    case none

    public func category(_ n: Int) -> String {
        let i = abs(n)
        switch self {
        case .en: return i == 1 ? "one" : "other"
        case .fr: return i == 0 || i == 1 ? "one" : "other"
        case .ru:
            if i % 10 == 1 && i % 100 != 11 { return "one" }
            if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return "few" }
            return "many"
        case .pl:
            if i == 1 { return "one" }
            if (2...4).contains(i % 10) && !(12...14).contains(i % 100) { return "few" }
            return "many"
        case .cs:
            if i == 1 { return "one" }
            if (2...4).contains(i) { return "few" }
            return "other"
        case .ar:
            if i == 0 { return "zero" }
            if i == 1 { return "one" }
            if i == 2 { return "two" }
            if (3...10).contains(i % 100) { return "few" }
            if (11...99).contains(i % 100) { return "many" }
            return "other"
        case .none: return "other"
        }
    }

    /// The categories a translator must give a text for.
    public var categories: [String] {
        switch self {
        case .en, .fr: return ["one", "other"]
        case .ru, .pl: return ["one", "few", "many", "other"]
        case .cs: return ["one", "few", "other"]
        case .ar: return ["zero", "one", "two", "few", "many", "other"]
        case .none: return ["other"]
        }
    }
}

public struct Language: Equatable, Sendable {
    public var code: String
    public var name: String
    public var rule: PluralRule
    public var strings: [String: String]
    public var plurals: [String: [String: String]]
    /// A file that came with the app (not the user's).
    public var isBundled = false
    public var url: URL?

    /// Reads a language file; a message says what is wrong when it cannot be used.
    public static func load(_ url: URL) -> (language: Language?, problem: String?) {
        guard let data = try? Data(contentsOf: url) else { return (nil, L("The file could not be read.")) }
        let object: JSONObject
        do { object = try JSONParser.parseObject(data) } catch { return (nil, L("It is not valid JSON: {error}", ["error": "\(error)"])) }
        guard let code = object.string("code"), !code.isEmpty, code.range(of: "^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})*$", options: .regularExpression) != nil else {
            return (nil, L("It has no language code (\"code\": \"ru\")."))
        }
        guard let name = object.string("name"), !name.isEmpty else { return (nil, L("It has no name of the language (\"name\": \"Русский\").")) }
        let rule = object.string("plural_rule").flatMap(PluralRule.init(rawValue:)) ?? .en
        var plurals: [String: [String: String]] = [:]
        for (key, value) in object.object("plurals") ?? [:] {
            if case .object(let forms) = value { plurals[key] = forms.compactMapValues { if case .string(let s) = $0 { return s }; return nil } }
        }
        var language = Language(code: code, name: name, rule: rule, strings: object.stringMap("strings") ?? [:], plurals: plurals)
        language.url = url
        return (language, nil)
    }

    /// How many of the texts of the template this language has translated (empty translations do not count).
    public func translated(of template: Template) -> Int {
        template.strings.filter { !(strings[$0] ?? "").isEmpty }.count + template.plurals.filter { forms in
            guard let have = plurals[forms] else { return false }
            return rule.categories.allSatisfy { !(have[$0] ?? "").isEmpty }
        }.count
    }
}

/// The list of texts to translate (made from the program's source by `make-languages.py`; bundled as `template.json`).
public struct Template: Equatable, Sendable {
    public var strings: [String] = []
    /// The English plural forms, by the English plural text.
    public var plurals: [String] = []
    public var total: Int { strings.count + plurals.count }

    public init() {}

    public static func load(_ url: URL) -> Template? {
        guard let data = try? Data(contentsOf: url), let o = try? JSONParser.parseObject(data) else { return nil }
        var t = Template()
        t.strings = (o.object("strings") ?? [:]).keys.sorted()
        t.plurals = (o.object("plurals") ?? [:]).keys.sorted()
        return t
    }
}

public final class Localizer: @unchecked Sendable {
    public static let shared = Localizer()

    public private(set) var current: Language?
    /// Folders that hold language files: the app's own, then the user's (a later one wins).
    public var directories: [URL] = []

    public init() {}

    // MARK: Which language

    /// Chooses the language by its code (`nil`, `en` or an unknown code: English). Returns whether a translation is now in use.
    @discardableResult
    public func use(code: String?) -> Bool {
        guard let code, code != "en" else { current = nil; return false }
        current = available().first { $0.code.lowercased() == code.lowercased() }
        return current != nil
    }

    /// The language of the system, when one is installed (`nil`: English).
    public func systemCode() -> String? {
        let installed = Set(available().map { $0.code.lowercased() })
        for preferred in Locale.preferredLanguages {
            let code = preferred.lowercased().replacingOccurrences(of: "_", with: "-")
            if installed.contains(code) { return code }
            if let base = code.split(separator: "-").first.map(String.init), installed.contains(base) { return base }
            if code.hasPrefix("en") { return nil }
        }
        return nil
    }

    /// Every language that can be used, bundled ones first; the user's file replaces a bundled one with the same code.
    public func available() -> [Language] {
        var byCode: [String: Language] = [:]
        var order: [String] = []
        for (i, dir) in directories.enumerated() {
            for name in ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where name.hasSuffix(".json") && name != "template.json" {
                guard var language = Language.load(dir.appendingPathComponent(name)).language else { continue }
                language.isBundled = i == 0
                if byCode[language.code.lowercased()] == nil { order.append(language.code.lowercased()) }
                byCode[language.code.lowercased()] = language
            }
        }
        return order.compactMap { byCode[$0] }
    }

    // MARK: Texts

    /// The text in the chosen language, with `{name}` places filled; English when there is no translation.
    public func text(_ english: String, _ args: [String: Any] = [:]) -> String {
        Self.fill(current?.strings[english].flatMap { $0.isEmpty ? nil : $0 } ?? Self.shown(english), args)
    }

    /// A key may end with `||context` ("{n} characters||text"): the translator sees what the word means; English shows only the text before it.
    static func shown(_ key: String) -> String {
        guard let range = key.range(of: "||") else { return key }
        return String(key[..<range.lowerBound])
    }

    /// A text that depends on a number: `plural("{n} scene", "{n} scenes", n)`.
    public func plural(_ one: String, _ other: String, _ n: Int, _ args: [String: Any] = [:]) -> String {
        var all = args
        all["n"] = n
        if let language = current, let forms = language.plurals[other] {
            let wanted = language.rule.category(n)
            if let text = forms[wanted] ?? forms["other"], !text.isEmpty { return Self.fill(text, all) }
        }
        return Self.fill(Self.shown(n == 1 ? one : other), all)
    }

    static func fill(_ text: String, _ args: [String: Any]) -> String {
        guard !args.isEmpty, text.contains("{") else { return text }
        var out = text
        for (key, value) in args { out = out.replacingOccurrences(of: "{\(key)}", with: Self.format(value)) }
        return out
    }

    private static func format(_ value: Any) -> String {
        if let n = value as? Int { return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
        return "\(value)"
    }
}

/// A text of the interface, in the language chosen. The English text is the key.
public func L(_ english: String, _ args: [String: Any] = [:]) -> String { Localizer.shared.text(english, args) }

/// A text with a number: `Lp("{n} scene", "{n} scenes", count)`.
public func Lp(_ one: String, _ other: String, _ n: Int, _ args: [String: Any] = [:]) -> String { Localizer.shared.plural(one, other, n, args) }
