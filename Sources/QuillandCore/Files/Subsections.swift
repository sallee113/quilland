import Foundation

/// A subsection of a scene: a fragment of its text, between two markers (`<!-- fragment: <id> -->`, quilland-format.md section 4). It is not a file of its own: the scene's text
/// has the markers, and the scene's data file has the titles typed for the subsections (`fragment_titles`, id to title). Other things can be linked to it by its id.
public struct Subsection: Identifiable, Equatable, Sendable {
    public var id: String
    public var scene: String
    /// Its place among the subsections of the scene, from 0.
    public var index: Int
    /// The title the author typed ("" when none).
    public var title: String
    /// What stands for the title when none was typed: the heading the subsection begins with, or its first words.
    public var derivedTitle: String
    /// Characters with spaces.
    public var characters: Int
    /// False for the part of a scene before its first marker (a marker deleted by hand): it has no id of its own, so it stands under the scene's.
    public var isMarked: Bool

    public var shownTitle: String { title.isEmpty ? derivedTitle : title }
}

public enum Subsections {
    /// The subsections of a scene, in order, from its Markdown as it is on disk. A scene with no markers has none.
    public static func parse(scene: String, markdown: String, titles: [String: String] = [:]) -> [Subsection] {
        guard markdown.contains("<!-- fragment: ") else { return [] }
        let document = MarkdownParser.parse(markdown)
        var parts: [(id: String?, blocks: [Block])] = [(nil, [])]
        for block in document.blocks {
            if case .fragment(let id) = block { parts.append((id, [])) } else { parts[parts.count - 1].blocks.append(block) }
        }
        // (Text before the first marker is a part too, under the scene's id; an empty one is nothing.)
        if parts[0].blocks.isEmpty || TextStats.count(Document(parts[0].blocks)).characters == 0 { parts.removeFirst() }
        return parts.enumerated().map { i, part in
            let id = part.id ?? scene
            return Subsection(id: id, scene: scene, index: i, title: part.id == nil ? "" : (titles[id] ?? ""), derivedTitle: derivedTitle(of: part.blocks),
                              characters: TextStats.count(Document(part.blocks)).characters, isMarked: part.id != nil)
        }
    }

    /// The heading a subsection begins with, or its first words.
    public static func derivedTitle(of blocks: [Block]) -> String {
        for block in blocks {
            switch block {
            case .heading(_, let inlines): return plain(inlines)
            case .paragraph(let inlines):
                let text = plain(inlines).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                return firstWords(text)
            case .quote(let paragraphs):
                let text = paragraphs.map(plain).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return firstWords(text) }
            case .sceneBreak, .fragment, .emptyLine: continue
            }
        }
        return ""
    }

    /// About the first six words, at most 48 characters, with an ellipsis when something was left out.
    public static func firstWords(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var out = ""
        for (i, word) in words.enumerated() {
            let next = out.isEmpty ? word : out + " " + word
            if i >= 6 || next.count > 48 { return out.isEmpty ? String(word.prefix(48)) + "…" : out + "…" }
            out = next
        }
        return out
    }

    private static func plain(_ inlines: [Inline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .run(let run): return run.text
            case .note: return ""
            case .lineBreak: return " "
            }
        }.joined()
    }
}

/// Which scene a link stands for. A link can be to a scene or to one of its subsections; a subsection's id is not a scene's, so everything that asks "which scene is it linked to"
/// resolves the id here first. The ids of the subsections are known from the scene files (`BookStructure.load` keeps this current); ids are unique, so the books that are open
/// share one table.
public enum SceneLinks {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var byBook: [String: [String: String]] = [:]
    nonisolated(unsafe) private static var merged: [String: String] = [:]

    /// The scene a link key stands for: the scene it is a subsection of, or the key itself.
    public static func scene(of key: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return merged[key] ?? key
    }

    /// Is this key a subsection (not a scene)?
    public static func isSubsection(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return merged[key] != nil
    }

    /// The subsection ids of a scene, from the table.
    public static func subsections(of scene: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return merged.filter { $0.value == scene }.map(\.key).sorted()
    }

    /// Does an owner's `links` hold a link to this scene or to one of its subsections?
    public static func has(_ links: [String: String], scene: String) -> Bool {
        if links[scene] != nil { return true }
        lock.lock(); defer { lock.unlock() }
        return links.keys.contains { merged[$0] == scene }
    }

    /// The scenes (resolved) an owner's links are to.
    public static func scenes(of links: [String: String]) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(links.keys.map { merged[$0] ?? $0 })
    }

    /// Sets what is known of a book's subsections (subsection id to scene id); the earlier table of that book is replaced.
    public static func set(_ table: [String: String], forBook folder: URL) {
        lock.lock(); defer { lock.unlock() }
        byBook[folder.standardizedFileURL.path] = table
        merged = byBook.values.reduce(into: [:]) { $0.merge($1) { a, _ in a } }
    }
}
