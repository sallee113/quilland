import QuillandCore

extension BookStructure.SceneEntry {
    /// "Part › Chapter › Scene": where a scene is and what it is called, for lists and pickers.
    var fullPath: String { [partTitle, chapterTitle, node.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › ") }
    /// "Part › Chapter": the place of the scene, without its own title.
    var place: String { [partTitle, chapterTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › ") }
}

extension BookStructure {
    /// Every scene in the book's order with its path, for the pickers of the views.
    var sceneChoices: [(id: String, title: String)] { scenes.map { ($0.id, $0.fullPath) } }

    /// What a card can be linked to: every scene, and after it its subsections ("Part › Chapter › Scene › Subsection"), in the order of the book.
    var linkChoices: [(id: String, title: String)] {
        scenes.flatMap { entry -> [(id: String, title: String)] in
            let path = entry.fullPath
            return [(entry.id, path)] + (subsections[entry.id] ?? []).filter(\.isMarked).map { ($0.id, path + " › " + $0.shownTitle) }
        }
    }
}
