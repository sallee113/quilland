import Foundation

/// Which parts of the plan are left out when the author works on a later part of the book: everything before a chosen scene.
public enum PlanFilter {
    /// The ids of the events and cards to hide. An event is hidden when every scene it is linked to comes before `scene` (an event linked to no
    /// scene, or to scenes this order does not know, is never hidden). A card on a line is hidden when it is at or before the last hidden event
    /// of that line; a line with no hidden event keeps all its cards, and so do cards that lie on no line.
    public static func hidden(store: PlanStore, sceneOrder: [String], from scene: String) -> Set<String> {
        guard let cut = sceneOrder.firstIndex(of: scene) else { return [] }
        let position = Dictionary(uniqueKeysWithValues: sceneOrder.enumerated().map { ($1, $0) })
        var hidden: Set<String> = []
        var lastHidden: [String: Int] = [:]
        for entry in store.entries {
            guard let event = entry.event else { continue }
            let known = (store.eventLinks[event] ?? []).compactMap { position[$0] }
            guard let latest = known.max(), latest < cut else { continue }
            hidden.insert(event)
            if let line = entry.lane, let start = entry.start { lastHidden[line] = max(lastHidden[line] ?? start, start) }
        }
        for (id, card) in store.cards {
            if let line = card.line, let start = card.start, let last = lastHidden[line], start <= last { hidden.insert(id) }
        }
        return hidden
    }
}
