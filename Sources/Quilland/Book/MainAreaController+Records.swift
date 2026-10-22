import AppKit
import QuillandCore

/// What is known of the book's characters, places and worlds, and what can be done with it: mentions in the scenes, and merging and converting the records.
extension MainAreaController {
    /// How many times a character's name is in each scene (only the scenes where it is).
    func mentions(ofCharacter id: String) -> [String: Int] {
        guard let record = characters.character(id), let name = record.name else { return [:] }
        return mentions(of: NameEntry(id: id, name: name, aliases: record.aliases))
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
