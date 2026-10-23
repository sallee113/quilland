import Foundation

/// What two things are compared by to tell whether they are the same thing written twice: a finding of Collect, or a card of the book (`id` is whatever the caller knows it by).
/// Everything is worked out by the app from the facts it has (names, scenes, who takes part, where): no model is asked.
public struct DupeFacet: Sendable {
    public var kind: CollectKind
    public var id: String
    /// A title, or a name with its other names.
    public var names: [String]
    public var scenes: Set<String>
    /// Each person who takes part (a relationship's characters, an event's participants), as the normalized names the person goes by.
    public var people: [Set<String>]
    /// Each place of an event, the same way.
    public var places: [Set<String>]
    /// A relationship's kind, a change's new text, an observation's words.
    public var text: String
    /// A change's field, or when a relationship begins (stated, starts, changes, ends).
    public var field: String

    public init(kind: CollectKind, id: String, names: [String], scenes: Set<String> = [], people: [Set<String>] = [], places: [Set<String>] = [], text: String = "", field: String = "") {
        self.kind = kind; self.id = id; self.names = names; self.scenes = scenes; self.people = people; self.places = places; self.text = text; self.field = field
    }
}

public enum DupeLevel: Int, Comparable, Sendable {
    /// Probably the same: shown, never merged by itself.
    case probably = 1
    /// The same: merged (a finding joins the card or the row it repeats).
    case same = 2
    public static func < (a: DupeLevel, b: DupeLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct DupeVerdict: Equatable, Sendable {
    public var level: DupeLevel
    /// In words, for the person who decides.
    public var reason: String
}

public enum DuplicateFinder {
    // MARK: Words

    /// The words that tell what a title is about (not the little ones).
    static func words(_ text: String) -> [String] { Names.normalize(text).split(separator: " ").map(String.init).filter { $0.count >= 3 } }

    /// The same word in another case form or number (приезд, приезда; станции, станция).
    static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shortest = min(a.count, b.count)
        var common = 0
        for (x, y) in zip(a, b) { if x == y { common += 1 } else { break } }
        if shortest >= 4, common >= max(4, shortest - 2), abs(a.count - b.count) <= 3 { return true }
        return Declension.forms(of: a).contains(b) || Declension.forms(of: b).contains(a)
    }

    /// How many words of the shorter list are in the longer one, and how many there are in the shorter.
    static func shared(_ a: [String], _ b: [String]) -> (count: Int, shorter: Int) {
        let (small, large) = a.count <= b.count ? (a, b) : (b, a)
        var used = Set<Int>()
        var n = 0
        for w in small { if let i = large.indices.first(where: { !used.contains($0) && sameWord(w, large[$0]) }) { used.insert(i); n += 1 } }
        return (n, small.count)
    }

    /// One name is the other, or one is the other with a letter wrong (a typo): for names of five letters and more.
    static func nearlyEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard a.count >= 5, b.count >= 5, abs(a.count - b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var i = 0
        while i < min(x.count, y.count), x[i] == y[i] { i += 1 }
        if x.count == y.count { return Array(x[(i + 1)...]) == Array(y[(i + 1)...]) }
        let (long, short) = x.count > y.count ? (x, y) : (y, x)
        return Array(long[(i + 1)...]) == Array(short[i...])
    }

    /// How many persons of `a` are among those of `b` (a person is the same when any name they go by is).
    static func overlap(_ a: [Set<String>], _ b: [Set<String>]) -> Int { a.filter { p in b.contains { !p.isDisjoint(with: $0) } }.count }

    // MARK: Comparing

    /// Is `a` the same thing as `b`, or does it look so? Only things of one kind are compared.
    public static func compare(_ a: DupeFacet, _ b: DupeFacet) -> DupeVerdict? {
        guard a.kind == b.kind, a.id != b.id else { return nil }
        switch a.kind {
        case .characters, .places: return compareNamed(a, b)
        case .events: return compareEvents(a, b)
        case .relationships: return compareRelationships(a, b)
        case .changes: return compareChanges(a, b)
        case .observations: return compareFacts(a, b)
        }
    }

    private static func compareNamed(_ a: DupeFacet, _ b: DupeFacet) -> DupeVerdict? {
        let x = Set(a.names.map(Names.normalize).filter { !$0.isEmpty }), y = Set(b.names.map(Names.normalize).filter { !$0.isEmpty })
        if !x.isDisjoint(with: y) { return DupeVerdict(level: .same, reason: L("they share a name")) }
        for p in x { for q in y where nearlyEqual(p, q) { return DupeVerdict(level: .probably, reason: L("“{a}” and “{b}” differ by a letter", ["a": p, "b": q])) } }
        // One name is a word of the other (Вера, Тётя Вера, Вера Павловна): the same person for a character, a guess for a place.
        for p in x { for q in y {
            let pw = p.split(separator: " ").map(String.init), qw = q.split(separator: " ").map(String.init)
            if (pw.count == 1 && pw[0].count >= 4 && qw.count > 1 && qw.contains { sameWord(pw[0], $0) }) || (qw.count == 1 && qw[0].count >= 4 && pw.count > 1 && pw.contains { sameWord(qw[0], $0) }) {
                return DupeVerdict(level: a.kind == .characters && !a.scenes.isDisjoint(with: b.scenes) ? .same : .probably, reason: L("one name is a word of the other: “{a}” and “{b}”", ["a": p, "b": q]))
            }
        } }
        return nil
    }

    private static func compareEvents(_ a: DupeFacet, _ b: DupeFacet) -> DupeVerdict? {
        let titleA = a.names.first ?? "", titleB = b.names.first ?? ""
        if Names.normalize(titleA) == Names.normalize(titleB), !Names.normalize(titleA).isEmpty { return DupeVerdict(level: .same, reason: L("the same title")) }
        let wa = words(titleA), wb = words(titleB)
        let s = shared(wa, wb)
        guard s.shorter > 0, s.count > 0 else {
            // No word in common: the same scene and the same people are not enough to say the two are one event.
            return nil
        }
        let share = Double(s.count) / Double(s.shorter)
        let sameScene = !a.scenes.isDisjoint(with: b.scenes)
        let people = overlap(a.people, b.people)
        let fewer = max(1, min(a.people.count, b.people.count))
        let together = Double(people) / Double(fewer)
        if share >= 0.99, sameScene, people > 0 || a.people.isEmpty || b.people.isEmpty { return DupeVerdict(level: .same, reason: L("the same scene, and one title says all the words of the other")) }
        if share >= 0.99, sameScene { return DupeVerdict(level: .probably, reason: L("the same scene, and one title says all the words of the other")) }
        if share >= 0.5, sameScene, together >= 0.5, people > 0 { return DupeVerdict(level: .probably, reason: L("the same scene, the same people, and the titles share words")) }
        if share >= 0.99, s.shorter >= 3, a.scenes.isEmpty || b.scenes.isEmpty { return DupeVerdict(level: .probably, reason: L("one title says all the words of the other")) }
        return nil
    }

    private static func compareRelationships(_ a: DupeFacet, _ b: DupeFacet) -> DupeVerdict? {
        // (A relationship that starts and one that ends are not the same finding, whatever their kind: `field` says when.)
        guard a.field == b.field, a.people.count >= 2, b.people.count >= 2, overlap(a.people, b.people) == min(a.people.count, b.people.count), a.people.count == b.people.count else { return nil }
        let x = Names.normalize(a.text), y = Names.normalize(b.text)
        if x == y { return DupeVerdict(level: .same, reason: L("the same two characters and the same kind")) }
        let s = shared(words(a.text), words(b.text))
        if s.shorter > 0, s.count == s.shorter { return DupeVerdict(level: .probably, reason: L("the same two characters, and one kind says all the words of the other")) }
        if nearlyEqual(x, y) { return DupeVerdict(level: .same, reason: L("the same two characters and the same kind")) }
        return nil
    }

    private static func compareChanges(_ a: DupeFacet, _ b: DupeFacet) -> DupeVerdict? {
        guard a.field == b.field, !a.field.isEmpty else { return nil }
        let target = Set(a.names.map(Names.normalize)).isDisjoint(with: Set(b.names.map(Names.normalize))) ? false : true
        guard target else { return nil }
        let x = Names.normalize(a.text), y = Names.normalize(b.text)
        if x == y { return DupeVerdict(level: .same, reason: L("the same change of the same thing")) }
        let s = shared(words(a.text), words(b.text))
        if s.shorter >= 2, Double(s.count) / Double(s.shorter) >= 0.75 { return DupeVerdict(level: .probably, reason: L("the same thing changes, in almost the same words")) }
        return nil
    }

    private static func compareFacts(_ a: DupeFacet, _ b: DupeFacet) -> DupeVerdict? {
        guard !Set(a.names.map(Names.normalize)).isDisjoint(with: Set(b.names.map(Names.normalize))) else { return nil }
        let x = Names.normalize(a.text), y = Names.normalize(b.text)
        if x == y || x.contains(y) || y.contains(x), !x.isEmpty, !y.isEmpty { return DupeVerdict(level: .same, reason: L("the same fact about the same thing")) }
        let s = shared(words(a.text), words(b.text))
        if s.shorter >= 2, Double(s.count) / Double(s.shorter) >= 0.75 { return DupeVerdict(level: .probably, reason: L("the same thing, in almost the same words")) }
        return nil
    }

    /// The best match of `facet` among `others` (the stronger level first, then the first found), or nil.
    public static func best(for facet: DupeFacet, among others: [DupeFacet]) -> (other: DupeFacet, verdict: DupeVerdict)? {
        var best: (DupeFacet, DupeVerdict)?
        for o in others {
            guard let v = compare(facet, o) else { continue }
            if best == nil || v.level > best!.1.level { best = (o, v) }
        }
        return best.map { (other: $0.0, verdict: $0.1) }
    }
}
