import Foundation

/// A change an event makes in one character, place or relationship, for the cards that show it.
public struct EntityChange: Equatable, Sendable {
    public var event: String
    public var eventTitle: String
    /// The scene that gives the event its place in the book (the first of its scenes, in the order of the book); nil: the event has no scene, so the change does not apply.
    public var scene: String?
    /// The fields the event filled in.
    public var effect: JSONObject
    public var applies: Bool { scene != nil }

    public func text(_ field: EffectField) -> String? { effect.string(field.rawValue) }
    public func list(_ field: EffectField) -> [String] { effect.strings(field.rawValue) ?? [] }
    public var flag: Bool? { effect.bool(EffectField.main.rawValue) }
}

public extension EventStore {
    /// The changes the events make in a character, place or relationship: those with a scene in the order of the book (then by the event's order in its scene), and
    /// after them the ones of events with no scene, which do not apply.
    func changes(of target: String, sceneOrder: [String]) -> [EntityChange] {
        let position = Dictionary(uniqueKeysWithValues: sceneOrder.enumerated().map { ($1, $0) })
        var placed: [EntityChange] = [], loose: [EntityChange] = []
        for e in ordered(sceneOrder: sceneOrder) {
            guard let id = e.id, !e.effect(of: target).isEmpty else { continue }
            let scene = sceneOrder.first { SceneLinks.has(e.links, scene: $0) }
            let change = EntityChange(event: id, eventTitle: e.title ?? "", scene: scene, effect: e.effect(of: target))
            if scene != nil, position[scene!] != nil { placed.append(change) } else { loose.append(change) }
        }
        return placed + loose
    }

    /// The new names events give a character (all of them, in the order of the book): the matcher finds the character under them too.
    func addedAliases(of character: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for e in events { for name in e.effectList(.aliases, of: character) where seen.insert(name.lowercased()).inserted { out.append(name) } }
        return out
    }
}
