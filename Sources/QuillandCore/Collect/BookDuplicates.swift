import Foundation

/// A set of cards of the book that look like one thing written more than once, found by the finder (no model): what they are, how sure, and why.
public struct DuplicateGroup: Identifiable, Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public var id: String
        public var title: String
        /// How much the book says of it (scenes, rows, links), to suggest which to keep.
        public var weight: Int
        /// When the app made the card (nil: it is older than the records, or made elsewhere).
        public var age: Date?
    }

    public var kind: CollectKind
    public var members: [Member]
    public var level: DupeLevel
    public var reasons: [String]
    public var key: String { members.map(\.id).sorted().joined(separator: "|") }
    public var id: String { key }
    /// The card that is already there: the first (members are in order, the oldest first).
    public var existing: Member { members[0] }
    /// The others, which are the new ones: what Merge puts into the existing card and Delete removes.
    public var newer: [Member] { Array(members.dropFirst()) }
}

public enum BookDuplicates {
    /// The cards of the book as the finder compares them, by kind, each with the name to show for it and how much it holds.
    public static func facets(characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore) -> [CollectKind: [(facet: DupeFacet, title: String, weight: Int)]] {
        func person(_ id: String) -> Set<String>? {
            guard let c = characters.character(id) else { return nil }
            return Set(([c.name ?? ""] + c.aliases).map(Names.normalize).filter { !$0.isEmpty })
        }
        func place(_ id: String) -> Set<String>? {
            guard let p = worlds.entry(id) else { return nil }
            return Set(([p.name ?? ""] + p.aliases).map(Names.normalize).filter { !$0.isEmpty })
        }
        var out: [CollectKind: [(DupeFacet, String, Int)]] = [:]
        out[.characters] = characters.characters.compactMap { c in
            c.id.map { (DupeFacet(kind: .characters, id: $0, names: [c.name ?? ""] + c.aliases, scenes: Set(c.links.keys).union(c.povScenes)), c.name ?? "", c.links.count + c.povScenes.count + c.notes.count + (c.aliases.count)) }
        }
        out[.places] = worlds.entries.compactMap { p in
            p.id.map { (DupeFacet(kind: .places, id: $0, names: [p.name ?? ""] + p.aliases, scenes: Set(p.links.keys), group: (p.world ?? "") + "/" + (p.parent ?? "")), p.name ?? "", p.links.count + p.notes.count + p.aliases.count) }
        }
        out[.events] = events.events.compactMap { e in
            e.id.map { (DupeFacet(kind: .events, id: $0, names: [e.title ?? ""], scenes: Set(e.links.keys), people: e.characters.keys.compactMap(person), places: e.places.keys.compactMap(place)), e.title ?? "",
                        e.links.count + e.characters.count + e.places.count + e.effects.count + e.relationships.count) }
        }
        out[.relationships] = relationships.relationships.compactMap { r in
            r.id.map { id in
                (DupeFacet(kind: .relationships, id: id, names: [], people: r.characters.compactMap(person), text: r.kind ?? "", field: "stated"),
                 r.characters.compactMap { characters.character($0)?.name }.joined(separator: " — ") + " (" + (r.kind ?? "") + ")", r.links.count + r.notes.count)
            }
        }
        return out
    }

    /// The groups of cards that look like one: in a kind, cards joined by a verdict of the finder, however many. `dismissed` are the groups the writer said are not the same.
    public static func find(characters: CharacterStore, worlds: WorldStore, events: EventStore, relationships: RelationshipStore, dismissed: Set<String> = [], ages: [String: Date] = [:]) -> [DuplicateGroup] {
        let all = facets(characters: characters, worlds: worlds, events: events, relationships: relationships)
        var groups: [DuplicateGroup] = []
        for kind in [CollectKind.characters, .places, .events, .relationships] {
            let items = all[kind] ?? []
            var parent = Array(0..<items.count)
            func root(_ i: Int) -> Int { var r = i; while parent[r] != r { r = parent[r] }; return r }
            var verdicts: [Int: [DupeVerdict]] = [:]   // by the root of the group, filled in after the groups are known
            var pairs: [(Int, Int, DupeVerdict)] = []
            for i in 0..<items.count {
                for j in (i + 1)..<max(items.count, i + 1) {
                    guard let v = DuplicateFinder.compare(items[i].facet, items[j].facet) else { continue }
                    pairs.append((i, j, v))
                    let a = root(i), b = root(j)
                    if a != b { parent[a] = b }
                }
            }
            for (i, _, v) in pairs { verdicts[root(i), default: []].append(v) }
            var byRoot: [Int: [Int]] = [:]
            for i in 0..<items.count { byRoot[root(i), default: []].append(i) }
            for (r, indices) in byRoot where indices.count > 1 {
                // The oldest first: cards with no time noted (the most in them first), then the ones with a time, earliest first.
                let members = indices.map { DuplicateGroup.Member(id: items[$0].facet.id, title: items[$0].title, weight: items[$0].weight, age: ages[items[$0].facet.id]) }.sorted { a, b in
                    switch (a.age, b.age) {
                    case (nil, nil): return a.weight != b.weight ? a.weight > b.weight : a.title.localizedLowercase < b.title.localizedLowercase
                    case (nil, _?): return true
                    case (_?, nil): return false
                    case let (x?, y?): return x != y ? x < y : a.weight > b.weight
                    }
                }
                let vs = verdicts[r] ?? []
                var reasons: [String] = []
                for v in vs where !reasons.contains(v.reason) { reasons.append(v.reason) }
                let group = DuplicateGroup(kind: kind, members: members, level: vs.map(\.level).max() ?? .probably, reasons: Array(reasons.prefix(3)))
                if !dismissed.contains(group.key) { groups.append(group) }
            }
        }
        let order: [CollectKind] = [.characters, .places, .events, .relationships]
        return groups.sorted { a, b in
            if a.kind != b.kind { return order.firstIndex(of: a.kind)! < order.firstIndex(of: b.kind)! }
            if a.level != b.level { return a.level > b.level }
            return (a.members.first?.title ?? "").localizedLowercase < (b.members.first?.title ?? "").localizedLowercase
        }
    }

    // MARK: "Not the same"

    private static func dismissalsURL(_ book: URL) -> URL { book.appendingPathComponent(".quilland/duplicates-dismissed.json") }

    /// The groups the writer said are not the same, kept on this machine (not in Git).
    public static func dismissed(book: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: dismissalsURL(book)), let o = try? JSONParser.parseObject(data) else { return [] }
        return Set(o.strings("dismissed") ?? [])
    }

    public static func dismiss(_ keys: [String], book: URL) {
        var all = dismissed(book: book)
        all.formUnion(keys)
        var o: JSONObject = ["format": .int(1)]
        o["dismissed"] = .array(all.sorted().map { .string($0) })
        try? FileManager.default.createDirectory(at: dismissalsURL(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: dismissalsURL(book))
    }

    public static func forgetDismissed(book: URL) { try? FileManager.default.removeItem(at: dismissalsURL(book)) }
}
