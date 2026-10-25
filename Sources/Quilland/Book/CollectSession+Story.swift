import AppKit
import QuillandCore

/// Accepting what the second pass found (quilland-change-events.md): a change goes into an event, never into a card; a relationship starts with the book or at an event,
/// changes or ends at one. A change that comes with no event of the story gets an event made by the app, one for each scene, linked to the scene of the quote.
final class StoryAccept {
    enum Outcome: Equatable {
        case created(CollectKind)
        case updated
        case skipped(String)
    }

    private let main: MainAreaController
    var characterIDs: [String: String]
    var entryIDs: [String: String]
    /// The events of the story, by title (found in the book, or made in this accept), and the one proposed in a scene.
    var eventIDs: [String: String] = [:]
    private var sceneEvents: [String: String] = [:]
    /// The event the app made for the changes of a scene.
    private var madeEvents: [String: String] = [:]
    /// What the story findings of each scene are (to title the event the app makes).
    private let groups: [String: [CollectedItem]]
    private(set) var eventsMade = 0

    init(main: MainAreaController, characterIDs: [String: String], entryIDs: [String: String], story: [CollectedItem]) {
        self.main = main; self.characterIDs = characterIDs; self.entryIDs = entryIDs
        // The events the book has already: a change that names one goes to it, and no second event of that title is made.
        for e in main.eventStore.events { if let id = e.id, let title = e.title { eventIDs[Names.normalize(title)] = id } }
        groups = Dictionary(grouping: story.filter { $0.kind == .changes || ($0.kind == .relationships && $0.when != "stated") }, by: { $0.evidence.first?.scene ?? "" })
    }

    /// An event of the story was accepted (or was there): the changes of its scenes go to it.
    func noteEvent(_ id: String, title: String, scenes: [String]) {
        eventIDs[Names.normalize(title)] = id
        for s in scenes where sceneEvents[s] == nil { sceneEvents[s] = id }
    }

    private var timeline: RelationshipTimeline { RelationshipTimeline(events: main.eventStore, sceneOrder: main.session.structure.scenes.map(\.id)) }

    // MARK: The event

    private func fieldWord(_ field: String) -> String { field == "aliases" ? L("also called") : (field == "profile" ? L("profile") : L("description")) }

    private func title(of item: CollectedItem) -> String {
        item.kind == .changes ? item.name + ": " + fieldWord(item.field) : item.members.joined(separator: " — ") + ": " + item.type
    }

    /// The event a finding goes to: the one it names, the one proposed in its scene, or one made for its scene.
    private func event(for item: CollectedItem) -> String? {
        if !item.eventTitle.isEmpty, let id = eventIDs[Names.normalize(item.eventTitle)] { return id }
        guard let scene = item.evidence.first?.scene else { return nil }
        if let id = sceneEvents[scene] ?? madeEvents[scene] { return id }
        let group = groups[scene] ?? [item]
        let named = group.first { !$0.eventTitle.isEmpty }?.eventTitle
        let sceneTitle = main.session.structure.scenes.first { $0.id == scene }?.node.title ?? ""
        if let named, let id = eventIDs[Names.normalize(named)] { return id }   // (the event the scene's findings name is there already)
        let title = named ?? (group.count == 1 ? self.title(of: item) : L("Changes in “{scene}”", ["scene": sceneTitle]))
        guard let id = try? main.eventStore.add(title: title) else { return nil }
        try? main.eventStore.update(id) { $0.links = [scene: ""] }
        madeEvents[scene] = id
        eventsMade += 1
        return id
    }

    /// The event shows the character or place it changes as a row.
    private func addRow(_ event: String, character: String? = nil, place: String? = nil, relationship: [String] = []) {
        try? main.eventStore.update(event) { r in
            if let character { var l = r.characters; if l[character] == nil { l[character] = "" }; r.characters = l }
            if let place { var p = r.places; if p[place] == nil { p[place] = "" }; r.places = p }
            for c in relationship { var l = r.characters; if l[c] == nil { l[c] = "" }; r.characters = l }
        }
    }

    // MARK: A change

    /// An event the app made for a finding that was then skipped is not left behind empty.
    private func cleaned(_ item: CollectedItem, _ outcome: Outcome) -> Outcome {
        guard case .skipped = outcome, let scene = item.evidence.first?.scene, let id = madeEvents[scene], let e = main.eventStore.event(id) else { return outcome }
        if e.effects.isEmpty && e.relationships.isEmpty && e.characters.isEmpty && e.places.isEmpty {
            try? main.eventStore.delete(id)
            madeEvents[scene] = nil
            eventsMade -= 1
        }
        return outcome
    }

    func apply(change item: CollectedItem) -> Outcome { cleaned(item, applyChange(item)) }
    func apply(relationship item: CollectedItem, linkText: [String: String]) -> Outcome { cleaned(item, applyRelationship(item, linkText: linkText)) }

    private func applyChange(_ item: CollectedItem) -> Outcome {
        let key = Names.normalize(item.name)
        let character = characterIDs[key], place = character == nil ? entryIDs[key] : nil
        guard let target = character ?? place else { return .skipped(L("no card named “{name}” to attach it to", ["name": item.name])) }
        // A character's text is its profile and a place's its description, whichever word the model used for it.
        var item = item
        if character != nil, item.field == "description" { item.field = "profile" }
        if place != nil, item.field == "profile" { item.field = "description" }
        if character != nil, item.field != "profile", item.field != "aliases" { return .skipped(L("a character has no “{field}” to change", ["field": item.field])) }
        if place != nil, item.field != "description" { return .skipped(L("a place has no “{field}” to change", ["field": item.field])) }
        guard let event = event(for: item) else { return .skipped(L("the event could not be made")) }
        let record = main.eventStore.event(event)
        switch item.field {
        case "aliases":
            let card = character.flatMap { main.characters.character($0) }
            let have = Set(([card?.name ?? ""] + (card?.aliases ?? []) + (record?.effectList(.aliases, of: target) ?? [])).map(Names.normalize))
            let new = item.aliases.filter { !have.contains(Names.normalize($0)) }
            guard !new.isEmpty else { return .skipped(L("the card already has these names")) }
            try? main.eventStore.update(event) { $0.setEffect(.aliases, of: target, list: (record?.effectList(.aliases, of: target) ?? []) + new) }
        default:
            let field: EffectField = item.field == "profile" ? .profile : .description
            let base = character != nil ? main.characters.profile(target) : main.worlds.text(target)
            if Names.normalize(base) == Names.normalize(item.detail) { return .skipped(L("the card already says this")) }
            if record?.effectText(field, of: target) != nil { return .skipped(L("this event already changes it")) }
            try? main.eventStore.update(event) { $0.setEffect(field, of: target, text: item.detail) }
        }
        addRow(event, character: character, place: place)
        return .created(.changes)
    }

    // MARK: A relationship

    private func startsAtBook(_ relationship: String) {
        guard timeline.marks(of: relationship).start == nil else { return }
        guard let start = main.eventStore.startEvent?.id ?? (try? main.eventStore.ensureStartEvent(title: EventLinkMigration.startTitle(language: main.bookLanguage))) else { return }
        try? main.eventStore.update(start) { var m = $0.relationships; m[relationship] = "starts"; $0.relationships = m }
    }

    private func mark(_ relationship: String, _ mark: String, in event: String) {
        try? main.eventStore.update(event) { var m = $0.relationships; if m[relationship] == nil || !mark.isEmpty { m[relationship] = mark }; $0.relationships = m }
    }

    private func applyRelationship(_ item: CollectedItem, linkText: [String: String]) -> Outcome {
        let ids = item.members.compactMap { characterIDs[Names.normalize($0)] }
        guard Set(ids).count >= 2 else { return .skipped(L("it needs two characters that have cards")) }
        let members = Array(NSOrderedSet(array: ids)) as? [String] ?? ids
        let same = main.relationships.relationships.filter { Set($0.characters) == Set(ids) }
        // The relationship the book already has between them: of the same kind, or of a kind the finder says is the same worded otherwise.
        let wanted = item.facet
        let exact = same.first { Names.normalize($0.kind ?? "") == Names.normalize(item.type) } ?? same.first(where: { r in
            let people = r.characters.compactMap { id in main.characters.character(id).map { Set(([$0.name ?? ""] + $0.aliases).map(Names.normalize)) } }
            return DuplicateFinder.compare(wanted, DupeFacet(kind: .relationships, id: r.id ?? "", names: [], people: people, text: r.kind ?? ""))?.level == .same
        })
        let when = item.when.isEmpty ? "stated" : item.when
        func links(_ id: String) { try? main.relationships.update(id) { $0.links = $0.links.merging(linkText) { old, _ in old } } }
        switch when {
        case "stated":
            if let id = exact?.id { links(id); startsAtBook(id); return .updated }
            guard let id = try? main.relationships.add(characters: members, kind: item.type) else { return .skipped(L("it could not be made")) }
            try? main.relationships.update(id) { $0.links = linkText }
            startsAtBook(id)
            return .created(.relationships)
        case "starts":
            guard let event = event(for: item) else { return .skipped(L("the event could not be made")) }
            if timeline.order(of: event) == nil { return .skipped(RelationshipTimeline.Problem.noScene.sentence) }
            if let id = exact?.id { links(id); return .updated }
            guard let id = try? main.relationships.add(characters: members, kind: item.type) else { return .skipped(L("it could not be made")) }
            try? main.relationships.update(id) { $0.links = linkText }
            mark(id, "starts", in: event); addRow(event, relationship: members)
            return .created(.relationships)
        default:
            guard let event = event(for: item) else { return .skipped(L("the event could not be made")) }
            let t = timeline
            // The relationship between them that is active at the event (else the first there is).
            // The one of that kind, else the one that is active at the event, else the first there is.
            guard let r = same.first(where: { Names.normalize($0.kind ?? "") == Names.normalize(item.type) }) ?? same.first(where: { $0.id.map { t.isActive($0, at: event) } == true }) ?? same.first, let id = r.id else { return .skipped(L("there is no relationship between them to change")) }
            if when == "changes" {
                if let p = t.problem(changing: id, at: event) { return .skipped(p.sentence) }
                var current = r.kind ?? ""
                let here = t.order(of: event) ?? Int.max
                for c in t.marks(of: id).changes where (t.order(of: c) ?? Int.max) <= here { if let k = main.eventStore.event(c)?.effect(of: id).string(EffectField.kind.rawValue) { current = k } }
                if Names.normalize(current) == Names.normalize(item.type) { return .skipped(L("it already has this kind")) }
                try? main.eventStore.update(event) { $0.setEffect(.kind, of: id, text: item.type) }
                mark(id, "", in: event)
            } else {
                if t.marks(of: id).end != nil { return .skipped(L("it has already ended")) }
                if let p = t.problem(ending: id, at: event) { return .skipped(p.sentence) }
                mark(id, "ends", in: event)
            }
            addRow(event, relationship: members)
            return .created(.changes)
        }
    }
}

extension MainAreaController {
    /// The characters and places as the model is told what is known: the text on the card and the relationships of a character.
    func collectCards() -> [CollectCard] {
        var out: [CollectCard] = []
        let names = Dictionary(characters.characters.compactMap { c in c.id.flatMap { id in c.name.map { (id, $0) } } }, uniquingKeysWith: { a, _ in a })
        for c in characters.characters {
            guard let id = c.id, let name = c.name else { continue }
            let relations = relationships.relationships(of: id).compactMap { r -> String? in
                let others = r.characters.filter { $0 != id }.compactMap { names[$0] }.joined(separator: ", ")
                return others.isEmpty ? nil : others + ": " + (r.kind ?? "")
            }
            out.append(CollectCard(name: name, aliases: c.aliases, text: characters.profile(id), relations: relations))
        }
        for e in worlds.entries { if let id = e.id, let name = e.name { out.append(CollectCard(name: name, aliases: e.aliases, text: worlds.text(id), isPlace: true)) } }
        return out
    }
}
