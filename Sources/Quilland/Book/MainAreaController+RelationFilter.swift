import AppKit
import QuillandCore

extension MainAreaController {
    /// What the "Filter by…" menus of the Characters, World and Events views offer, and the index they ask.
    func relationFilterSource() -> RelationFilterSource {
        RelationFilterSource(
            sections: { [weak self] in self?.planSectionChoices() ?? [] },
            events: { [weak self] in
                guard let self else { return [] }
                return self.eventStore.ordered(sceneOrder: self.session.structure.scenes.map(\.id)).compactMap { e in e.id.map { ($0, e.title ?? "") } }
            },
            characters: { [weak self] in
                (self?.characters.characters ?? []).compactMap { c in c.id.map { ($0, c.name ?? "") } }.sorted { $0.1.localizedLowercase < $1.1.localizedLowercase }
            },
            places: { [weak self] in
                guard let self else { return [] }
                return self.worlds.entries.compactMap { p in p.id.map { ($0, self.worlds.path(of: $0).dropFirst().joined(separator: " › ")) } }
                    .sorted { $0.1.localizedLowercase < $1.1.localizedLowercase }
            },
            index: { [weak self] in
                guard let self else { fatalError("the book is gone") }
                return RelationIndex(characters: self.characters, worlds: self.worlds, events: self.eventStore, structure: self.session.structure,
                                     sceneText: { [weak self] in self?.session.document($0)?.storage.string ?? "" })
            })
    }
}
