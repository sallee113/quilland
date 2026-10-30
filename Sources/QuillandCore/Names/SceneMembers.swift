import Foundation

/// Who and what is "in" a scene. One rule for the Right panel and the cards, so that they cannot disagree about the same scene:
/// a character is in a scene if its name (or an alias) is in the text, or the scene has a line of its own for the character, or it is the character's
/// point of view; a place is in a scene if its name is in the text or the scene has a line of its own for it.
public enum SceneMembers {
    /// The ids of the characters in the scene, whose text is given.
    public static func characters(inScene scene: String, text: String, store: CharacterStore) -> Set<String> {
        named(entries: store.entries, in: text).union(linkedCharacters(inScene: scene, store: store))
    }

    /// The ids of the places (and worlds, by name) in the scene.
    public static func places(inScene scene: String, text: String, store: WorldStore) -> Set<String> {
        named(entries: store.nameEntries, in: text).union(linkedPlaces(inScene: scene, store: store))
    }

    /// Only by the name written in the text.
    public static func named(entries: [NameEntry], in text: String) -> Set<String> {
        Set(ParadigmMatcher(entries: entries).matches(in: text).map(\.entry))
    }

    /// Only by what is stored: a line for the scene, or the point of view.
    public static func linkedCharacters(inScene scene: String, store: CharacterStore) -> Set<String> {
        Set(store.characters.compactMap { c in
            guard let id = c.id, SceneLinks.has(c.links, scene: scene) || c.povScenes.contains(where: { SceneLinks.scene(of: $0) == scene }) else { return nil }
            return id
        })
    }

    public static func linkedPlaces(inScene scene: String, store: WorldStore) -> Set<String> {
        Set(store.entries.compactMap { e in
            guard let id = e.id, SceneLinks.has(e.links, scene: scene) else { return nil }
            return id
        })
    }
}
