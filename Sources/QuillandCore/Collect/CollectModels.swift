import Foundation

/// What the author may ask the model to look for in the book (AI ▸ Collect from the Book…).
public enum CollectKind: String, CaseIterable, Sendable {
    case characters, places, events, relationships, observations
}

/// Where a finding comes from: the scene, the words of the text that show it, and what the model says about it there.
public struct CollectedEvidence: Equatable, Sendable {
    public var scene: String
    /// As the text has it (taken from the scene, not from the model's copy of it).
    public var quote: String
    /// Where the quote is in the scene's text, in UTF-16 units.
    public var range: NSRange
    public var note: String
    public init(scene: String, quote: String, range: NSRange, note: String) {
        self.scene = scene; self.quote = quote; self.range = range; self.note = note
    }
}

/// One thing the model found, from one or several scenes. Nothing is stored in the book until the author accepts it.
public struct CollectedItem: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: CollectKind
    /// A character's or place's name (in its base form), an event's title; empty for a relationship (see `type` and `members`) and an observation.
    public var name: String
    public var aliases: [String] = []
    /// The model's overall description (it goes into the card's free text).
    public var detail: String = ""
    /// A place's type (`place`, `people`, `thing`, `term`); a relationship's kind ("sisters").
    public var type: String = ""
    /// A relationship's characters, by name.
    public var members: [String] = []
    /// An observation: who or what it is about, by name.
    public var about: String = ""
    /// A place's parent, by name (inside which place it is).
    public var parent: String = ""
    /// An event's date, as the text says it, and its places by name.
    public var date: String = ""
    public var places: [String] = []
    public var evidence: [CollectedEvidence] = []

    public init(kind: CollectKind, name: String) { self.kind = kind; self.name = name }

    /// What two findings are the same by: the kind and the name (a relationship by its members and kind, an observation by its subject and words).
    public var key: String {
        switch kind {
        case .relationships: return "r|" + members.map(Names.normalize).sorted().joined(separator: "+") + "|" + Names.normalize(type)
        case .observations: return "o|" + Names.normalize(about) + "|" + Names.normalize(detail)
        default: return kind.rawValue + "|" + Names.normalize(name)
        }
    }

    /// A line to show: the name, or "A — B (sisters)".
    public var title: String {
        switch kind {
        case .relationships: return members.joined(separator: " — ") + (type.isEmpty ? "" : " (\(type))")
        case .observations: return about
        default: return name
        }
    }
}

public enum Names {
    /// For comparing names and quotes: lower case, ё as е, no quotation marks or dashes, single spaces.
    public static func normalize(_ text: String) -> String {
        var out = ""
        var space = false
        for ch in text.lowercased() {
            let c: Character = ch == "ё" ? "е" : ch
            if c.isLetter || c.isNumber { out.append(c); space = false }
            else if !space, !out.isEmpty { out.append(" "); space = true }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}

/// The findings of a run, merged: one item for one thing, with the evidence from every scene.
public struct CollectedSet: Equatable, Sendable {
    public private(set) var items: [CollectedItem] = []
    public init() {}

    public mutating func merge(_ new: [CollectedItem]) {
        for item in new {
            if let i = items.firstIndex(where: { $0.key == item.key || $0.kind == item.kind && $0.kind != .relationships && $0.kind != .observations && $0.matches(aliasOf: item) }) {
                var e = items[i]
                // The fuller name is the name; the shorter one is another name of the same person.
                if item.kind == .characters || item.kind == .places, item.name.count > e.name.count, Names.normalize(item.name).contains(Names.normalize(e.name)) {
                    e.aliases.append(e.name); e.name = item.name
                }
                for a in ([item.name] + item.aliases) where !a.isEmpty && !e.aliases.contains(where: { Names.normalize($0) == Names.normalize(a) }) && Names.normalize(a) != Names.normalize(e.name) { e.aliases.append(a) }
                if e.detail.isEmpty || (item.detail.count > e.detail.count && item.kind != .observations) { e.detail = item.detail }
                if e.date.isEmpty { e.date = item.date }
                if e.parent.isEmpty { e.parent = item.parent }
                for p in item.places where !e.places.contains(p) { e.places.append(p) }
                for ev in item.evidence where !e.evidence.contains(where: { $0.scene == ev.scene && $0.range == ev.range }) { e.evidence.append(ev) }
                items[i] = e
            } else {
                items.append(item)
            }
        }
    }

    public mutating func remove(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) } }
}

extension CollectedItem {
    /// The same character or place under another of its names.
    func matches(aliasOf other: CollectedItem) -> Bool {
        let mine = Set(([name] + aliases).map(Names.normalize)), theirs = Set(([other.name] + other.aliases).map(Names.normalize))
        if !mine.isDisjoint(with: theirs) { return true }
        // A character found as "Вера", "Тётя Вера" and "Вера Павловна" is one person: a one-word name that is a word of another name.
        guard kind == .characters else { return false }
        func words(_ names: Set<String>) -> Set<String> { Set(names.flatMap { $0.split(separator: " ").map(String.init) }) }
        let single = { (names: Set<String>) in names.filter { !$0.contains(" ") && $0.count >= 3 } }
        return !single(mine).isDisjoint(with: words(theirs)) || !single(theirs).isDisjoint(with: words(mine))
    }
}
