import Foundation

public struct SearchOptions: Equatable, Sendable {
    public var matchCase = false
    public var wholeWords = false
    /// Word endings: the query's words are found in every case form (Russian, by the same rule that finds names).
    public var endings = false
    /// ё and е are the same letter.
    public var yoAsYe = true
    public init(matchCase: Bool = false, wholeWords: Bool = false, endings: Bool = false, yoAsYe: Bool = true) {
        self.matchCase = matchCase
        self.wholeWords = wholeWords
        self.endings = endings
        self.yoAsYe = yoAsYe
    }
}

/// Finding a phrase in a text, for Search and Replace. Offsets are UTF-16 (what the text views use).
public enum TextSearch {
    /// One UTF-16 unit as it is compared: lowercase unless the case matters, ё as е when asked. The length never changes.
    @inline(__always)
    static func fold(_ u: UInt16, _ o: SearchOptions) -> UInt16 {
        if u < 0x80 {
            if !o.matchCase, u >= 0x41, u <= 0x5A { return u + 32 }
            return u
        }
        if o.yoAsYe {
            if u == 0x0451 { return 0x0435 }
            if u == 0x0401 { return o.matchCase ? 0x0415 : 0x0435 }
        }
        if o.matchCase || (u >= 0xD800 && u <= 0xDFFF) { return u }
        if let scalar = Unicode.Scalar(u) {
            let lower = scalar.properties.lowercaseMapping.utf16
            if lower.count == 1, let first = lower.first { return first }
        }
        return u
    }

    private static func isWordUnit(_ u: UInt16) -> Bool {
        if u >= 0xD800 && u <= 0xDFFF { return true }
        guard let scalar = Unicode.Scalar(u) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    /// Where `query` is in `text`, in order, not overlapping. `within` limits the search to a part of the text.
    public static func ranges(of query: String, in text: String, options: SearchOptions = SearchOptions(), within: NSRange? = nil, limit: Int = 10_000) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let units = Array(text.utf16)
        let area = within.map { NSIntersectionRange($0, NSRange(location: 0, length: units.count)) } ?? NSRange(location: 0, length: units.count)
        guard area.length > 0 else { return [] }
        if options.endings { return endingRanges(query, text: text, units: units, area: area, options: options, limit: limit) }
        let needle = query.utf16.map { fold($0, options) }
        guard needle.count <= area.length else { return [] }
        let hay = units[area.location..<area.location + area.length].map { fold($0, options) }
        var found: [NSRange] = []
        var i = 0
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == needle[0] {
                var k = 1
                while k < needle.count && hay[i + k] == needle[k] { k += 1 }
                if k == needle.count {
                    let start = area.location + i
                    var ok = true
                    if options.wholeWords {
                        if start > 0, isWordUnit(units[start - 1]), isWordUnit(units[start]) { ok = false }
                        let end = start + needle.count
                        if ok, end < units.count, isWordUnit(units[end]), isWordUnit(units[end - 1]) { ok = false }
                    }
                    if ok {
                        found.append(NSRange(location: start, length: needle.count))
                        if found.count >= limit { break }
                        i += needle.count
                        continue
                    }
                }
            }
            i += 1
        }
        return found
    }

    private static func endingRanges(_ query: String, text: String, units: [UInt16], area: NSRange, options: SearchOptions, limit: Int) -> [NSRange] {
        let matcher = ParadigmMatcher(entries: [NameEntry(id: "q", name: query)])
        let words = Words.split(text)
        // Offsets of the scalars in UTF-16 units.
        var offsets: [Int] = []
        offsets.reserveCapacity(text.unicodeScalars.count + 1)
        var at = 0
        for s in text.unicodeScalars { offsets.append(at); at += s.utf16.count }
        offsets.append(at)
        var out: [NSRange] = []
        for m in matcher.matches(in: text) {
            guard let first = words[safe: m.words.lowerBound], let last = words[safe: m.words.upperBound - 1] else { continue }
            let start = offsets[first.scalars.lowerBound], end = offsets[last.scalars.upperBound]
            let r = NSRange(location: start, length: end - start)
            if r.location >= area.location, NSMaxRange(r) <= NSMaxRange(area) { out.append(r) }
            if out.count >= limit { break }
        }
        return out
    }

    /// A short stretch of text before and after a range, on one line, for showing a result.
    public static func context(of range: NSRange, in text: String, radius: Int = 40) -> (before: String, after: String) {
        let ns = text as NSString
        let from = max(0, range.location - radius), to = min(ns.length, NSMaxRange(range) + radius)
        func clean(_ s: String) -> String { s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\u{2029}", with: " ") }
        var before = clean(ns.substring(with: NSRange(location: from, length: range.location - from)))
        var after = clean(ns.substring(with: NSRange(location: NSMaxRange(range), length: to - NSMaxRange(range))))
        if from > 0 { before = "…" + before }
        if to < ns.length { after += "…" }
        return (before, after)
    }

    /// The text with the ranges replaced, and where the replacements are in the new text (for undoing).
    public static func replace(_ ranges: [NSRange], in text: String, with replacement: String) -> (text: String, replaced: [NSRange]) {
        let out = NSMutableString(string: text)
        var delta = 0
        var replaced: [NSRange] = []
        let length = (replacement as NSString).length
        for r in ranges.sorted(by: { $0.location < $1.location }) {
            out.replaceCharacters(in: NSRange(location: r.location + delta, length: r.length), with: replacement)
            replaced.append(NSRange(location: r.location + delta, length: length))
            delta += length - r.length
        }
        return (out as String, replaced)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
