import Foundation

/// AI ▸ Write Synopsis: a scene's synopsis from its text, a chapter's from the synopses of its scenes, a part's from those of its chapters.
public enum SynopsisPrompt {
    public static func system(kind: BookStructure.Kind, language: String) -> String {
        let key = "synopsis." + (kind == .scene ? "scene" : kind == .chapter ? "chapter" : "part")
        return AIPrompts.resolve(key, language: language, builtIn: builtIn(kind: kind, name: CollectPrompt.languageName(language) ?? "the language of the text"))
    }

    static func builtIn(kind: BookStructure.Kind, name: String) -> String {
        switch kind {
        case .scene, .subsection:   // (a subsection has no synopsis; the scene's words are used if one is ever asked for)
            return """
            You write the synopsis of one scene of a novel, to be kept on its card. Two to four sentences, in the present tense, neutral and concrete: what happens, who takes part, where, and what changes.
            Write in \(name). One paragraph of plain prose: no title, no list, no quotation marks, no comment, no opinion about the writing. Use only what the text says. Retell it in your own words: never copy sentences from the text, and never quote it.
            """
        case .chapter:
            return """
            You write the synopsis of a chapter of a novel from the synopses of its scenes. Three to five sentences, in the present tense, neutral and concrete: how the chapter moves, who takes part, and what has changed by its end.
            Write in \(name). One paragraph of plain prose: no title, no list, no quotation marks, no comment. Use only what the scene synopses say. Retell it in your own words: do not copy the synopses one after another.
            """
        case .part:
            return """
            You write the synopsis of a part of a novel from the synopses of its chapters. Three to six sentences, in the present tense, neutral and concrete: the main movement of the part, who takes part, and what has changed by its end.
            Write in \(name). One paragraph of plain prose: no title, no list, no quotation marks, no comment. Use only what the chapter synopses say. Retell it in your own words: do not copy the synopses one after another.
            """
        }
    }

    public static func userForScene(title: String, text: String) -> String { "Scene “\(title)”:\n\"\"\"\n\(text)\n\"\"\"\n\nNow write the synopsis of this scene: two to four sentences in your own words, not a copy of the text." }

    /// A chapter's or a part's input: its children with their synopses, in order.
    public static func userForSection(kind: BookStructure.Kind, title: String, children: [(title: String, synopsis: String)]) -> String {
        let label = kind == .part ? "Chapters" : "Scenes"
        var s = "\(kind == .part ? "Part" : "Chapter") “\(title)”. \(label) with their synopses:\n"
        for (i, c) in children.enumerated() { s += "\(i + 1). “\(c.title)”: \(c.synopsis.isEmpty ? "(no synopsis)" : c.synopsis)\n" }
        return s + "\nNow write the synopsis of the \(kind == .part ? "part" : "chapter") in your own words."
    }

    /// Prompt for a long text that does not fit: each piece is summarised in a few sentences first.
    public static let pieceSystem = """
    You summarise a piece of a scene of a novel in two or three plain sentences, in the language of the piece: what happens, who takes part, where. Use only what the piece says. No comment.
    """
    public static func pieceUser(title: String, index: Int, of count: Int, text: String) -> String { "Piece \(index) of \(count) of the scene “\(title)”:\n\"\"\"\n\(text)\n\"\"\"" }
}
