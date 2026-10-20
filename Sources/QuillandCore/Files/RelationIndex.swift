import Foundation

/// What is related to what, in both directions (quilland-format.md, section 5: a link is stored once, on one side, and the other side is worked out).
///
/// It answers the filters of the Characters, World and Events views: "the characters in this chapter", "the events this character takes part in",
/// "the places where this event happens", and so on. Each answer is a set of ids of one kind, and several anchors combine: everything must match.
///
/// The relations it reads:
/// - a character is in a scene when its name is in the text, or the scene has a line for it, or it is its point of view (`SceneMembers`); a place when its
///   name is in the text or the scene has a line for it;
/// - an event is in a scene when the event is linked to it (stored on the event);
/// - a character takes part in an event when the character has a link to it (stored on the character);
/// - an event happens at a place when the place is in the event's list of places (stored on the event);
/// - a character and a place go together when they are in a scene together.
public final class RelationIndex {
    public enum Anchor: Hashable, Sendable {
        case section(String)
        case character(String)
        case place(String)
        case event(String)
    }

    public enum Kind: Sendable { case character, place, event }

    private let characters: CharacterStore
    private let worlds: WorldStore
    private let events: EventStore
    private let structure: BookStructure
    private let sceneText: (String) -> String
    private lazy var characterMatcher = ParadigmMatcher(entries: characters.entries)
    private lazy var placeMatcher = ParadigmMatcher(entries: worlds.nameEntries)
    private var members: [String: (characters: Set<String>, places: Set<String>)] = [:]

    public init(characters: CharacterStore, worlds: WorldStore, events: EventStore, structure: BookStructure, sceneText: @escaping (String) -> String) {
        self.characters = characters
        self.worlds = worlds
        self.events = events
        self.structure = structure
        self.sceneText = sceneText
    }

    // MARK: Scenes

    /// The scenes at or under a section (a part, a chapter or a scene), in book order.
    public func scenes(inSection id: String) -> [String] {
        structure.scenes.filter { $0.id == id || $0.chapterID == id || $0.partID == id }.map(\.id)
    }

    /// Who and what is in a scene (worked out once, and kept).
    private func members(of scene: String) -> (characters: Set<String>, places: Set<String>) {
        if let known = members[scene] { return known }
        let text = sceneText(scene)
        var people = Set(characterMatcher.matches(in: text).map(\.entry))
        var spots = Set(placeMatcher.matches(in: text).map(\.entry))
        people.formUnion(SceneMembers.linkedCharacters(inScene: scene, store: characters))
        spots.formUnion(SceneMembers.linkedPlaces(inScene: scene, store: worlds))
        members[scene] = (people, spots)
        return members[scene]!
    }

    private func charactersIn(_ scenes: [String]) -> Set<String> { scenes.reduce(into: Set<String>()) { $0.formUnion(members(of: $1).characters) } }
    private func placesIn(_ scenes: [String]) -> Set<String> { scenes.reduce(into: Set<String>()) { $0.formUnion(members(of: $1).places) } }

    private func scenes(ofCharacter id: String) -> [String] { structure.scenes.map(\.id).filter { members(of: $0).characters.contains(id) } }
    private func scenes(ofPlace id: String) -> [String] { structure.scenes.map(\.id).filter { members(of: $0).places.contains(id) } }

    // MARK: Answers

    /// The ids of the items of `kind` that match every anchor; nil when there are no anchors (nothing is filtered). An anchor of the same kind as the
    /// items asked for is not used (a character is not filtered by a character).
    public func matching(_ kind: Kind, anchors: [Anchor]) -> Set<String>? {
        var result: Set<String>?
        for anchor in anchors {
            guard let found = answer(kind, anchor) else { continue }
            result = result.map { $0.intersection(found) } ?? found
        }
        return result
    }

    private func answer(_ kind: Kind, _ anchor: Anchor) -> Set<String>? {
        switch (kind, anchor) {
        case (.character, .section(let s)): return charactersIn(scenes(inSection: s))
        case (.character, .event(let e)): return Set(characters.characters.compactMap { c in c.links[e] != nil ? c.id : nil })
        case (.character, .place(let p)): return charactersIn(scenes(ofPlace: p))
        case (.place, .section(let s)): return placesIn(scenes(inSection: s))
        case (.place, .event(let e)): return Set(events.event(e)?.places.keys.map { $0 } ?? [])
        case (.place, .character(let c)): return placesIn(scenes(ofCharacter: c))
        case (.event, .section(let s)):
            let inside = Set(scenes(inSection: s))
            return Set(events.events.compactMap { e in e.links.keys.contains { inside.contains($0) } ? e.id : nil })
        case (.event, .character(let c)): return Set((characters.character(c)?.links.keys.map { $0 } ?? []).filter { events.event($0) != nil })
        case (.event, .place(let p)): return Set(events.events.compactMap { $0.places[p] != nil ? $0.id : nil })
        default: return nil
        }
    }
}
