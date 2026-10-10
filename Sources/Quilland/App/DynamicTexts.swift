import QuillandCore

/// Texts that are looked up by a computed key (`L(status)`, `L(kind.rawValue)`), so they never stand as a literal where they are used.
/// They are listed here so that the list of texts to translate has them. (Nothing calls this.)
enum DynamicTexts {
    static var all: [String] {
        [
            // The statuses of a scene.
            L("idea"), L("draft"), L("revised"), L("done"),
            // The levels of the book.
            L("scene"), L("chapter"), L("part"), L("Scene"), L("Chapter"), L("Part"),
            // The sources of a search.
            L("Text"), L("Synopses"), L("Notes"),
        ]
    }
}
