import Foundation

/// Points the links of the book's data at another scene (when two scenes are merged, the second one's id disappears).
/// Links live on the owners (characters, places, events…) as `links` (scene id → description) and `pov_scenes`; everything else in a
/// file is kept as it is.
public enum BookRelinker {
    /// Moves every link to `old` over to `new`. When an owner already has a link to `new`, the two descriptions are joined.
    /// Returns how many files were changed.
    @discardableResult
    public static func retarget(book: URL, from old: String, to new: String) throws -> Int {
        let fm = FileManager.default
        var changed = 0
        for kind in ["characters", "places", "events", "relationships", "things"] {
            let dir = book.appendingPathComponent("bible/\(kind)")
            for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where name.hasSuffix(".json") {
                let url = dir.appendingPathComponent(name)
                guard var object = try? JSONParser.parseObject(Data(contentsOf: url)) else { continue }
                var touched = false
                var links = object.stringMap("links") ?? [:]
                if let text = links.removeValue(forKey: old) {
                    if let existing = links[new], !existing.isEmpty, !text.isEmpty { links[new] = existing + " " + text }
                    else if (links[new] ?? "").isEmpty { links[new] = text }
                    object.setStringMap("links", links)
                    touched = true
                }
                var pov = object.strings("pov_scenes") ?? []
                if pov.contains(old) {
                    pov = pov.filter { $0 != old }
                    if !pov.contains(new) { pov.append(new) }
                    object.setStrings("pov_scenes", pov)
                    touched = true
                }
                if touched {
                    try AtomicFile.write(JSONWriter.data(object), to: url)
                    changed += 1
                }
            }
        }
        return changed
    }
}
