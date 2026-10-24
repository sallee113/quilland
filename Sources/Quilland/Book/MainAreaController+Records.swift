import AppKit
import QuillandCore

/// What is known of the book's characters, places and worlds, and what can be done with it: mentions in the scenes, and merging and converting the records.
extension MainAreaController {
    /// How many times a character's name is in each scene (only the scenes where it is).
    func mentions(ofCharacter id: String) -> [String: Int] {
        guard let record = characters.character(id), let name = record.name else { return [:] }
        return mentions(of: NameEntry(id: id, name: name, aliases: record.aliases + eventStore.addedAliases(of: id)))
    }

    /// How many times a name (or one of its aliases) is in each scene (only the scenes where it is).
    func mentions(of entry: NameEntry) -> [String: Int] {
        let matcher = ParadigmMatcher(entries: [entry])
        var out: [String: Int] = [:]
        for e in session.structure.scenes {
            let n = matcher.matches(in: session.document(e.id)?.storage.string ?? "").count
            if n > 0 { out[e.id] = n }
        }
        return out
    }

    /// A character was added, renamed or changed in the Characters view: the right panel reads it again.
    /// Merge Into…: the second character leaves the book and the first one keeps what is known of both. Like the other changes that touch many files, a snapshot is
    /// taken before and after, so that Undo (the banner, ⌘Z) takes it back.
    func mergeCharacters(_ source: String, into target: String) {
        let sourceName = characters.character(source)?.name ?? "", targetName = characters.character(target)?.name ?? ""
        restructure(focusText: false, undoName: L("Merge “{from}” into “{to}”", ["from": sourceName, "to": targetName])) { editor in
            try CharacterMerger.merge(source, into: target, book: editor.folder)
            return nil
        }
        charactersView?.select(target)
    }

    // MARK: The changes of an event

    /// Opens the window of what an event changes in a character, a place or a relationship (one for each event and target), from the Events view or from a card.
    func openChanges(event: String, target: String, kind: EffectTarget) {
        let key = event + "|" + target
        if let open = changeWindows[key] { open.showWindow(nil); open.window?.makeKeyAndOrderFront(nil); return }
        let context = ChangesContext(events: eventStore, event: event, characters: characters, worlds: worlds, relationships: relationships)
        let w = ChangesWindowController(context: context, kind: kind, target: target, startsHere: kind == .relationship && eventStore.event(event)?.relationships[target] == "starts")
        w.onSaved = { [weak self] removed in self?.changesSaved(event: event, target: target, removed: removed) }
        w.onClosed = { [weak self] _ in self?.changeWindows[key] = nil }
        changeWindows[key] = w
        w.showWindow(nil)
        w.window?.makeKeyAndOrderFront(nil)
    }

    /// "Пожар в усадьбе · Сцена 4": the event and its scene, for the tooltip of a change on a card.
    func changeTooltip(_ c: EntityChange) -> String {
        guard let scene = c.scene, let entry = session.structure.scenes.first(where: { $0.id == scene }) else { return c.eventTitle + " · " + L("no scene") }
        return c.eventTitle + " · " + entry.node.title
    }


    /// The event that holds a relationship: where it starts (else where it ends or changes first), the one to open when the relationship is clicked.
    func eventHolding(relationship id: String) -> String? {
        let marks = RelationshipTimeline(events: eventStore, sceneOrder: session.structure.scenes.map(\.id)).marks(of: id)
        return marks.start ?? marks.end ?? marks.changes.first
    }

    /// The relationships of a character for its card, in the order they start: "Лев — friends → enemies" (the other characters, the kind, and each later kind),
    /// greyed when it has ended; the tooltip says where it starts and ends; a click opens the event that holds it (the start; else the first mark).
    func relationshipBricks(of character: String) -> [RelationshipBrick] {
        let order = session.structure.scenes.map(\.id)
        let timeline = RelationshipTimeline(events: eventStore, sceneOrder: order)
        func eventTitle(_ id: String?) -> String { id.flatMap { eventStore.event($0)?.title } ?? "" }
        var items: [(position: Int, brick: RelationshipBrick)] = []
        for r in relationships.relationships(of: character) {
            guard let id = r.id else { continue }
            let marks = timeline.marks(of: id)
            guard let holder = eventHolding(relationship: id) else { continue }
            var kinds = [r.kind ?? ""]
            for e in marks.changes { if let k = eventStore.event(e)?.effect(of: id).string("kind"), k != kinds.last { kinds.append(k) } }
            let others = r.characters.filter { $0 != character }.compactMap { characters.character($0)?.name }.joined(separator: ", ")
            let title = (others.isEmpty ? "" : others + " — ") + kinds.joined(separator: " → ")
            var lines: [String] = []
            if let s = marks.start { lines.append(L("Starts: {event}", ["event": eventTitle(s)])) }
            if let e = marks.end { lines.append(L("Ends: {event}", ["event": eventTitle(e)])) }
            items.append((timeline.order(of: marks.start ?? holder) ?? Int.max, RelationshipBrick(title: title, dimmed: marks.end != nil, tooltip: lines.joined(separator: "\n"), event: holder)))
        }
        return items.sorted { $0.position < $1.position }.map(\.brick)
    }

    /// A window of changes saved: the cards show it. A change that was emptied is gone: the banner says so and, for a moment, offers Undo.
    private func changesSaved(event: String, target: String, removed: [(field: EffectField, text: String)]) {
        NotificationCenter.default.post(name: .bookDataChanged, object: nil)
        onChange?()
        guard !removed.isEmpty else { return }
        effectUndo = (Date().addingTimeInterval(25), { [weak self] in
            guard let self else { return }
            try? self.eventStore.update(event) { r in
                for (field, text) in removed {
                    switch field {
                    case .aliases, .worlds: r.setEffect(field, of: target, list: text.split(separator: ",").map { String($0) })
                    case .main: r.setEffectFlag(of: target, text == "true")
                    default: r.setEffect(field, of: target, text: text)
                    }
                }
            }
            NotificationCenter.default.post(name: .bookDataChanged, object: nil)
        })
        banner.show(L("Change removed."), undoable: true)
    }

    // MARK: Deleting
    //
    // A deletion takes everything that refers to the item along (`BookIntegrity`, in the core), as one undoable change: the snapshots before and after are the ones
    // of `restructure`, and Undo (the banner, ⌘Z) brings back everything.

    func deleteCharacter(_ id: String) {
        let name = characters.character(id)?.name ?? ""
        restructure(focusText: false, undoName: L("Delete “{name}”", ["name": name])) { editor in
            try BookIntegrity.deleteCharacter(id, book: editor.folder, snapshot: false)
            return nil
        }
    }

    func deletePlace(_ id: String, isWorld: Bool) {
        let name = worldName(id)
        restructure(focusText: false, undoName: L("Delete “{name}”", ["name": name])) { editor in
            if isWorld { try BookIntegrity.deleteWorld(id, book: editor.folder, snapshot: false) } else { try BookIntegrity.deletePlace(id, book: editor.folder, snapshot: false) }
            return nil
        }
    }

    func deleteRelationship(_ id: String) {
        let kind = relationships.relationship(id)?.kind ?? ""
        restructure(focusText: false, undoName: L("Delete “{name}”", ["name": kind])) { editor in
            try BookIntegrity.deleteRelationship(id, book: editor.folder, snapshot: false)
            return nil
        }
    }

    /// Several relationships at once (the wrong ones that start with the book): one step, one Undo.
    func deleteRelationships(_ ids: [String]) {
        let name = ids.count == 1 ? (relationships.relationship(ids[0])?.kind ?? "") : Lp("{n} relationship", "{n} relationships", ids.count)
        restructure(focusText: false, undoName: L("Delete “{name}”", ["name": name])) { editor in
            for id in ids { try BookIntegrity.deleteRelationship(id, book: editor.folder, snapshot: false) }
            return nil
        }
    }

    func deleteEvent(_ id: String, started: BookIntegrity.StartedRelationships) {
        let title = eventStore.event(id)?.title ?? ""
        restructure(focusText: false, undoName: L("Delete “{name}”", ["name": title])) { editor in
            try BookIntegrity.deleteEvent(id, book: editor.folder, started: started, snapshot: false)
            return nil
        }
    }

    private func worldName(_ id: String) -> String { worlds.world(id)?.name ?? worlds.entry(id)?.name ?? "" }

    func mergePlaces(_ source: String, into target: String) {
        let names = ["from": worldName(source), "to": worldName(target)]
        restructure(focusText: false, undoName: L("Merge “{from}” into “{to}”", names)) { editor in
            try WorldMerger.mergePlaces(source, into: target, book: editor.folder)
            return nil
        }
        worldView?.select(target)
    }

    func mergeWorlds(_ source: String, into target: String) {
        let names = ["from": worldName(source), "to": worldName(target)]
        restructure(focusText: false, undoName: L("Merge “{from}” into “{to}”", names)) { editor in
            try WorldMerger.mergeWorlds(source, into: target, book: editor.folder)
            return nil
        }
        worldView?.select(target)
    }

    func placeToWorld(_ id: String) {
        var created: String?
        restructure(focusText: false, undoName: L("Turn “{name}” into a world", ["name": worldName(id)])) { editor in
            created = try WorldMerger.placeToWorld(id, book: editor.folder).world
            return nil
        }
        if let created { worldView?.select(created) }
    }

    func worldToPlace(_ world: String, intoWorld: String, parent: String?) {
        var created: String?
        restructure(focusText: false, undoName: L("Turn “{name}” into a place", ["name": worldName(world)])) { editor in
            created = try WorldMerger.worldToPlace(world, intoWorld: intoWorld, parent: parent, book: editor.folder).entry
            return nil
        }
        if let created { worldView?.select(created) }
    }

    func charactersChanged() {
        if showsRightPanel { rightPanel.refresh() }
        onChange?()
    }

    /// The events for the cards' "Add…" menus and rows, in the order of the book: the title and the title of the scene that decides where the event stands.
    func eventChoices() -> [EventChoice] {
        let scenes = session.structure.sceneChoices
        let titles = Dictionary(scenes.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        return eventStore.groups(sceneOrder: scenes.map(\.id)).flatMap { g in
            g.events.compactMap { e in e.id.map { EventChoice(id: $0, title: e.title ?? "", scene: g.scene.flatMap { titles[$0] }) } }
        }
    }
}

/// An event as the Character and Place cards list it.
struct EventChoice {
    var id: String
    var title: String
    var scene: String?
    /// "Title — Scene" (or the title alone when the event is linked to no scene).
    var label: String { scene.map { "\(title) — \($0)" } ?? title }
}
