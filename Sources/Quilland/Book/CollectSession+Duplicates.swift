import AppKit
import QuillandCore

/// What a finding looks like in the book: the same as a card (it joins it), or only like something (it is marked, and the writer decides). The comparison is made by the
/// app's own finder (`DuplicateFinder`), as the findings come in; no model is asked.
struct LookAlike: Equatable {
    var title: String
    var reason: String
    /// A card of the book (else another row of the list).
    var isCard: Bool
}

extension MainAreaController {
    /// The cards of the book as the finder compares them, by kind, each with the name to show for it.
    func dupeFacets() -> [CollectKind: [(facet: DupeFacet, title: String)]] {
        func person(_ id: String) -> Set<String>? {
            guard let c = characters.character(id) else { return nil }
            return Set(([c.name ?? ""] + c.aliases).map(Names.normalize).filter { !$0.isEmpty })
        }
        func place(_ id: String) -> Set<String>? {
            guard let p = worlds.entry(id) else { return nil }
            return Set(([p.name ?? ""] + p.aliases).map(Names.normalize).filter { !$0.isEmpty })
        }
        var out: [CollectKind: [(DupeFacet, String)]] = [:]
        out[.characters] = characters.characters.compactMap { c in c.id.map { (DupeFacet(kind: .characters, id: $0, names: [c.name ?? ""] + c.aliases, scenes: Set(c.links.keys).union(c.povScenes)), c.name ?? "") } }
        out[.places] = worlds.entries.compactMap { p in p.id.map { (DupeFacet(kind: .places, id: $0, names: [p.name ?? ""] + p.aliases, scenes: Set(p.links.keys)), p.name ?? "") } }
        out[.events] = eventStore.events.compactMap { e in e.id.map { (DupeFacet(kind: .events, id: $0, names: [e.title ?? ""], scenes: Set(e.links.keys), people: e.characters.keys.compactMap(person), places: e.places.keys.compactMap(place)), e.title ?? "") } }
        out[.relationships] = relationships.relationships.compactMap { r in r.id.map { id in
            (DupeFacet(kind: .relationships, id: id, names: [], people: r.characters.compactMap(person), text: r.kind ?? ""), r.characters.compactMap { characters.character($0)?.name }.joined(separator: " — ") + " (" + (r.kind ?? "") + ")") } }
        return out
    }
}

extension CollectSession {
    /// The card a finding repeats for sure (the finder says "the same"), with what it is: its id and its name to show.
    func sameCard(_ item: CollectedItem) -> (id: String, title: String)? {
        guard let main else { return nil }
        let facet = item.facet
        var found: (id: String, title: String)?
        for (candidate, title) in cardFacets(main)[item.kind] ?? [] where DuplicateFinder.compare(facet, candidate)?.level == .same { found = (candidate.id, title); break }
        return found
    }

    func cardFacets(_ main: MainAreaController) -> [CollectKind: [(facet: DupeFacet, title: String)]] {
        // (Made again when the book has more or fewer cards than when it was made.)
        let signature = "\(main.characters.characters.count)-\(main.worlds.entries.count)-\(main.eventStore.events.count)-\(main.relationships.relationships.count)"
        if let cached = cardFacetCache, cardFacetSignature == signature { return cached }
        let fresh = main.dupeFacets()
        cardFacetCache = fresh
        cardFacetSignature = signature
        return fresh
    }

    /// The findings that look like a card or like another row without being the same for sure: marked in the list, with the reason.
    func refreshLookAlikes() {
        guard let main else { return }
        var marks: [UUID: LookAlike] = [:]
        let facets = cardFacets(main)
        let all = collected.items
        for item in all {
            if sameCard(item) != nil { continue }   // (it joins that card: "already has a card" says so)
            let facet = item.facet
            // A card it is the same as is shown by "already has a card"; a guess at one is shown here.
            if let (other, verdict) = DuplicateFinder.best(for: facet, among: (facets[item.kind] ?? []).map(\.facet)), verdict.level == .probably,
               let title = facets[item.kind]?.first(where: { $0.facet.id == other.id })?.title {
                marks[item.id] = LookAlike(title: title, reason: verdict.reason, isCard: true)
                continue
            }
            if let other = all.first(where: { $0.id != item.id && $0.kind == item.kind && DuplicateFinder.compare(facet, $0.facet)?.level == .probably }), let verdict = DuplicateFinder.compare(facet, other.facet) {
                marks[item.id] = LookAlike(title: other.title, reason: verdict.reason, isCard: false)
            }
        }
        lookAlikes = marks
    }

    /// The book changed (cards were made): what the findings are compared with is made again.
    func forgetCardFacets() { cardFacetCache = nil }

    /// How a run ended, said of what the finder did on the way.
    var duplicatesText: String {
        var parts: [String] = []
        if mergedOnTheFly > 0 { parts.append(Lp("{n} found again and joined to its row", "{n} found again and joined to their rows", mergedOnTheFly)) }
        if !lookAlikes.isEmpty { parts.append(Lp("{n} looks like something else", "{n} look like something else", lookAlikes.count)) }
        return parts.joined(separator: " · ")
    }
}
