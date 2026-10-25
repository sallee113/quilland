import AppKit
import QuillandCore

/// What accepting a finding would add to the card it repeats (so that a finding that would add nothing is not shown).
struct CardAddition: Equatable {
    /// Scenes the card is not linked to yet (ids).
    var scenes: [String] = []
    /// People who take part (an event): names not in the event yet.
    var people: [String] = []
    /// Other names the card does not have yet.
    var names: [String] = []
    var isEmpty: Bool { scenes.isEmpty && people.isEmpty && names.isEmpty }
}

extension CollectSession {
    /// The findings that need no change in the book: they repeat a card that already has everything they would add. They are not listed.
    var visibleItems: [CollectedItem] { collected.items.filter { additions[$0.id]?.isEmpty != true } }
    var alreadyInBookCount: Int { collected.items.filter { additions[$0.id]?.isEmpty == true }.count }

    /// Looks again at what each finding would add to the card it repeats; the book is read as it is now.
    func refreshAdditions() {
        guard let main else { additions = [:]; return }
        func normal(_ names: [String]) -> [String] { names.map(Names.normalize) }
        func newScenes(_ item: CollectedItem, _ links: [String: String]) -> [String] {
            var seen = Set<String>()
            return item.evidence.map(\.scene).filter { links[$0] == nil && seen.insert($0).inserted }
        }
        var characterIDs: [String: String] = [:]
        for c in main.characters.characters { for n in [c.name ?? ""] + c.aliases { if let id = c.id { characterIDs[Names.normalize(n)] = id } } }
        var entryIDs: [String: String] = [:]
        for e in main.worlds.entries { for n in [e.name ?? ""] + e.aliases { if let id = e.id { entryIDs[Names.normalize(n)] = id } } }
        var out: [UUID: CardAddition] = [:]
        // The characters first: an event may name someone whose card is made in the same accepting.
        var pending = Set<String>()
        for item in collected.items where item.kind == .characters {
            let wanted = Set(normal([item.name] + item.aliases))
            let card = main.characters.characters.first { c in !wanted.isDisjoint(with: Set(normal([c.name ?? ""] + c.aliases))) } ?? sameCard(item).flatMap { main.characters.character($0.id) }
            guard let card else { pending.formUnion(wanted); continue }
            let known = Set(normal([card.name ?? ""] + card.aliases))
            out[item.id] = CardAddition(scenes: newScenes(item, card.links), people: [], names: ([item.name] + item.aliases).filter { !known.contains(Names.normalize($0)) })
        }
        for item in collected.items where item.kind == .places {
            let wanted = Set(normal([item.name] + item.aliases))
            guard let card = main.worlds.entries.first(where: { e in !wanted.isDisjoint(with: Set(normal([e.name ?? ""] + e.aliases))) }) ?? sameCard(item).flatMap({ main.worlds.entry($0.id) }) else { continue }
            out[item.id] = CardAddition(scenes: newScenes(item, card.links))   // (a place gets the scenes only)
        }
        for item in collected.items where item.kind == .events {
            guard let card = main.eventStore.events.first(where: { Names.normalize($0.title ?? "") == Names.normalize(item.name) }) ?? sameCard(item).flatMap({ main.eventStore.event($0.id) }) else { continue }
            let people = item.members.filter { name in
                let n = Names.normalize(name)
                if let id = characterIDs[n] { return card.characters[id] == nil }
                return pending.contains(n)
            }
            out[item.id] = CardAddition(scenes: newScenes(item, card.links), people: people)
        }
        // A fact that is in the card's text already, and a change that says what the card says (or names it already has): nothing to add.
        for item in collected.items where item.kind == .observations {
            let key = Names.normalize(item.about)
            let base = characterIDs[key].map { main.characters.profile($0) } ?? entryIDs[key].map { main.worlds.text($0) }
            if let base, DuplicateFinder.says(base, item.detail) { out[item.id] = CardAddition() }
        }
        for item in collected.items where item.kind == .changes {
            let key = Names.normalize(item.name)
            let character = characterIDs[key]
            guard let target = character ?? entryIDs[key] else { continue }
            // The event the finding names, when the book has it: if it already changes this very thing, accepting would only be refused.
            let record = item.eventTitle.isEmpty ? nil : main.eventStore.events.first { Names.normalize($0.title ?? "") == Names.normalize(item.eventTitle) }
            if let character = character.flatMap({ main.characters.character($0) }), item.field == "aliases" {
                let have = Set(normal([character.name ?? ""] + character.aliases + (record?.effectList(.aliases, of: target) ?? [])))
                if !item.aliases.isEmpty, item.aliases.allSatisfy({ have.contains(Names.normalize($0)) }) { out[item.id] = CardAddition() }
                continue
            }
            guard ["profile", "description"].contains(item.field) else { continue }
            let base = character != nil ? main.characters.profile(target) : main.worlds.text(target)
            let field: EffectField = character != nil ? .profile : .description
            if DuplicateFinder.says(base, item.detail) || record?.effectText(field, of: target) != nil { out[item.id] = CardAddition() }
        }
        // A relationship the book has already between them (of that kind): it adds nothing when its scenes are linked, or when it has ended already.
        let timeline = RelationshipTimeline(events: main.eventStore, sceneOrder: main.session.structure.scenes.map(\.id))
        for item in collected.items where item.kind == .relationships {
            let ids = item.members.compactMap { characterIDs[Names.normalize($0)] }
            guard Set(ids).count >= 2 else { continue }
            let same = main.relationships.relationships.filter { Set($0.characters) == Set(ids) }
            guard let r = StoryAccept.existing(item, among: same, main: main), let id = r.id else { continue }
            switch item.when {
            case "changes": continue
            case "ends": if timeline.marks(of: id).end != nil { out[item.id] = CardAddition() }
            default: if item.evidence.allSatisfy({ r.links[$0.scene] != nil }) { out[item.id] = CardAddition() }
            }
        }
        additions = out
    }
}
