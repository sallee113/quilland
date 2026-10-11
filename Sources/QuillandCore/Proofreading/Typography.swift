import Foundation

/// One thing the typography rules would change: where, what is there now, and what it would become.
public struct TypographyFinding: Equatable, Sendable {
    public enum Rule: String, CaseIterable, Sendable { case dash, dialogue, quotes, ellipsis, spaces, nbsp
        /// Found by the application with the system's spell checker, not by `Typography.check`.
        case spelling
        /// Found by the application with the local model (Check Grammar), not by `Typography.check`.
        case grammar }
    public var rule: Rule
    /// In UTF-16 units of the text that was checked.
    public var range: NSRange
    public var before: String
    public var after: String
    /// A little of the text on each side, for showing the finding.
    public var contextBefore: String
    public var contextAfter: String

    public init(rule: Rule, range: NSRange, before: String, after: String, contextBefore: String, contextAfter: String) {
        self.rule = rule; self.range = range; self.before = before; self.after = after; self.contextBefore = contextBefore; self.contextAfter = contextAfter
    }

    /// What a dismissal is remembered by: the rule and the text around, not the place, so that it survives edits elsewhere.
    public var key: String { "\(rule.rawValue)|\(contextBefore.suffix(8))|\(before)|\(contextAfter.prefix(8))" }
}

/// The rule-based layer of proofreading (quilland-spec.md, "proofreading"): dashes, dialogue dashes, quotes, ellipses, stray spaces and
/// non-breaking spaces after short words. Pure functions of the text; nothing here changes the text.
public enum Typography {
    static let nbsp = "\u{00A0}"
    private static let shortWords = "в|во|к|ко|с|со|у|о|об|и|а|но|на|не|ни|по|за|из|от|до|да|или|для|без|при|про|над|под"

    public static func check(_ text: String, language: String, rules: Set<TypographyFinding.Rule> = Set(TypographyFinding.Rule.allCases)) -> [TypographyFinding] {
        let ns = text as NSString
        let russian = language.lowercased().hasPrefix("ru")
        var out: [TypographyFinding] = []

        func add(_ rule: TypographyFinding.Rule, _ range: NSRange, _ after: String) {
            let before = ns.substring(with: range)
            guard before != after else { return }
            let from = max(0, range.location - 24), to = min(ns.length, NSMaxRange(range) + 24)
            var cb = ns.substring(with: NSRange(location: from, length: range.location - from))
            var ca = ns.substring(with: NSRange(location: NSMaxRange(range), length: to - NSMaxRange(range)))
            if let i = cb.lastIndex(of: "\n") { cb = String(cb[cb.index(after: i)...]) }
            if let i = ca.firstIndex(of: "\n") { ca = String(ca[..<i]) }
            out.append(TypographyFinding(rule: rule, range: range, before: before, after: after, contextBefore: cb, contextAfter: ca))
        }
        func each(_ pattern: String, _ options: NSRegularExpression.Options = [], _ body: (NSTextCheckingResult) -> Void) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in if let m { body(m) } }
        }

        if rules.contains(.dash) {
            // A dash between words: a non-breaking space before it, a plain one after it.
            each("(?<=\\S)[ \u{00A0}\u{202F}]+([-\u{2013}\u{2014}])[ \u{00A0}]+(?=\\S)") { m in
                add(.dash, m.range, russian ? nbsp + "\u{2014} " : "\u{2014}")
            }
        }
        if rules.contains(.dialogue) && russian {
            each("^[-\u{2013}\u{2014}][ \u{00A0}]?(?=[^\\s\\-\u{2013}\u{2014}*])", .anchorsMatchLines) { m in add(.dialogue, m.range, "\u{2014} ") }
        }
        if rules.contains(.quotes) {
            let (open, close) = russian || language.lowercased().hasPrefix("fr") ? ("\u{00AB}", "\u{00BB}") : ("\u{201C}", "\u{201D}")
            for paragraph in paragraphs(of: ns) {
                var isOpen = false
                var i = paragraph.location
                while i < NSMaxRange(paragraph) {
                    if ns.character(at: i) == 0x22 {
                        let previous = i > paragraph.location ? ns.character(at: i - 1) : 0x0A
                        let opens = !isOpen && (isSpace(previous) || "([{\u{2014}\u{2013}-".utf16.contains(previous) || previous == 0x0A)
                        add(.quotes, NSRange(location: i, length: 1), opens ? open : close)
                        isOpen = opens
                    }
                    i += 1
                }
            }
        }
        if rules.contains(.ellipsis) {
            each("(?<!\\.)\\.{3}(?!\\.)") { m in add(.ellipsis, m.range, "\u{2026}") }
        }
        if rules.contains(.spaces) {
            each("(?<=\\S) {2,}(?=\\S)") { m in add(.spaces, m.range, " ") }
            each("(?<=[^\\s(\\[{\u{00AB}\u{201C}]) +(?=[,.;:!?\u{2026}])(?![.]{2})") { m in add(.spaces, m.range, "") }
        }
        if rules.contains(.nbsp) && russian {
            each("(?<![\\p{L}\\p{N}])(" + shortWords + ") (?=[\\p{L}\\p{N}\u{00AB}\u{201C}(])", .caseInsensitive) { m in
                add(.nbsp, m.range, ns.substring(with: m.range(at: 1)) + nbsp)
            }
        }
        return out.sorted { $0.range.location < $1.range.location }
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0xA0 || c == 0x202F || c == 0x09 }

    private static func paragraphs(of ns: NSString) -> [NSRange] {
        var out: [NSRange] = []
        var i = 0
        while i < ns.length {
            let r = ns.paragraphRange(for: NSRange(location: i, length: 0))
            out.append(r)
            i = NSMaxRange(r)
        }
        return out
    }
}

/// The findings the author dismissed, kept on this machine in `.quilland/proofreading.json` (never in the book's own files).
public struct ProofreadingDismissals: Equatable, Sendable {
    public private(set) var keys: Set<String>
    /// Rules switched off for this book on this machine. The non-breaking space is off at first: its changes cannot be seen in the text, and there are many.
    public var rulesOff: Set<String>
    public init(keys: Set<String> = [], rulesOff: Set<String> = [TypographyFinding.Rule.nbsp.rawValue]) { self.keys = keys; self.rulesOff = rulesOff }
    public var rules: Set<TypographyFinding.Rule> { Set(TypographyFinding.Rule.allCases.filter { !rulesOff.contains($0.rawValue) }) }

    static func url(_ book: URL) -> URL { book.appendingPathComponent(".quilland/proofreading.json") }

    public static func load(book: URL) -> ProofreadingDismissals {
        guard let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data) else { return ProofreadingDismissals() }
        return ProofreadingDismissals(keys: Set(o.strings("dismissed") ?? []), rulesOff: o.strings("rules_off").map(Set.init) ?? [TypographyFinding.Rule.nbsp.rawValue])
    }

    public mutating func dismiss(_ finding: TypographyFinding) { keys.insert(finding.key) }
    public func isDismissed(_ finding: TypographyFinding) -> Bool { keys.contains(finding.key) }
    public mutating func forgetAll() { keys = [] }

    public func save(book: URL) {
        var o: JSONObject = (try? JSONParser.parseObject(Data(contentsOf: Self.url(book)))) ?? [:]
        o["format"] = .int(1)
        o["dismissed"] = .array(keys.sorted().map { .string($0) })
        o["rules_off"] = .array(rulesOff.sorted().map { .string($0) })
        try? FileManager.default.createDirectory(at: Self.url(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: Self.url(book))
    }
}
