import Foundation

/// The typing corrections: what the author's rules say should replace what was just typed (quilland-settings.md, `autocorrect.json`).
/// Quotes follow the book's language («» for Russian), " - " becomes a dash with a non-breaking space before it, "- " at the start of a
/// paragraph is a dialogue dash. The ellipsis correction is off by default: the author keeps three dots.
public struct AutocorrectSettings: Equatable, Sendable {
    public var enabled = true
    public var smartQuotes = true
    public var dashes = true
    public var dialogueDash = true
    public var ellipsis = false
    /// `auto` (the book's language), `ru` («»), `en` (“”).
    public var quoteStyle = "auto"
    public init() {}

    // MARK: The file

    public static func load(directory: URL) -> (settings: AutocorrectSettings, damaged: Bool) {
        let url = directory.appendingPathComponent("autocorrect.json")
        guard let data = try? Data(contentsOf: url) else { return (AutocorrectSettings(), false) }
        guard let o = try? JSONParser.parseObject(data) else {
            // A damaged file is kept aside and defaults are used; it is never overwritten silently.
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("autocorrect.json.bad"))
            try? FileManager.default.moveItem(at: url, to: directory.appendingPathComponent("autocorrect.json.bad"))
            return (AutocorrectSettings(), true)
        }
        var s = AutocorrectSettings()
        s.enabled = o.bool("enabled") ?? s.enabled
        s.smartQuotes = o.bool("smart_quotes") ?? s.smartQuotes
        s.dashes = o.bool("dashes") ?? s.dashes
        s.dialogueDash = o.bool("dialogue_dash") ?? s.dialogueDash
        s.ellipsis = o.bool("ellipsis") ?? s.ellipsis
        s.quoteStyle = o.string("quote_style") ?? s.quoteStyle
        return (s, false)
    }

    /// Writes the file, keeping any keys this version does not know.
    public func save(directory: URL) {
        let url = directory.appendingPathComponent("autocorrect.json")
        var o: JSONObject = (try? JSONParser.parseObject(Data(contentsOf: url))) ?? [:]
        o["format"] = .int(1)
        o["enabled"] = .bool(enabled)
        o["smart_quotes"] = .bool(smartQuotes)
        o["dashes"] = .bool(dashes)
        o["dialogue_dash"] = .bool(dialogueDash)
        o["ellipsis"] = .bool(ellipsis)
        o["quote_style"] = .string(quoteStyle)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: url)
    }
}

public enum Autocorrect {
    /// What to put instead: `back` characters before the caret are replaced by `text` (which includes the character just typed).
    public struct Edit: Equatable, Sendable {
        public var back: Int
        public var text: String
        public init(back: Int, text: String) { self.back = back; self.text = text }
    }

    /// The quotes of a style: opening and closing.
    public static func quotes(style: String, language: String) -> (open: String, close: String) {
        let resolved = style == "auto" ? (language.lowercased().hasPrefix("ru") ? "ru" : "en") : style
        return resolved == "ru" ? ("«", "»") : ("“", "”")
    }

    private static let openers: Set<Character> = ["(", "[", "{", "—", "–", "-", "«", "“", "‘", "/"]

    private static func isSpaceLike(_ c: Character) -> Bool { c.isWhitespace || c == "\u{00A0}" || c == "\u{202F}" }

    /// The edit for a typed character, given the text before the caret in its paragraph (nil: leave the typing alone).
    public static func edit(typed: String, before: String, settings: AutocorrectSettings, language: String) -> Edit? {
        guard settings.enabled, typed.count == 1 else { return nil }
        let last = before.last
        switch typed {
        case "\"":
            guard settings.smartQuotes else { return nil }
            let q = quotes(style: settings.quoteStyle, language: language)
            let opening = last == nil || isSpaceLike(last!) || openers.contains(last!)
            return Edit(back: 0, text: opening ? q.open : q.close)
        case "-":
            // "--" is a dash.
            guard settings.dashes, last == "-" else { return nil }
            return Edit(back: 1, text: "—")
        case " ":
            if settings.dialogueDash, before == "-" { return Edit(back: 1, text: "— ") }
            // "word - " is a dash with a non-breaking space before it.
            if settings.dashes, before.count >= 3, last == "-" {
                let chars = Array(before)
                if chars[chars.count - 2] == " ", !isSpaceLike(chars[chars.count - 3]) { return Edit(back: 2, text: "\u{00A0}— ") }
            }
            return nil
        case ".":
            guard settings.ellipsis, before.hasSuffix("..") else { return nil }
            return Edit(back: 2, text: "…")
        default:
            return nil
        }
    }
}
