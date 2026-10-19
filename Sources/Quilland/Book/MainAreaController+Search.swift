import AppKit
import QuillandCore

enum SearchScope: Int, CaseIterable {
    case selection, scene, chapter, part, book
    var title: String { [L("Selection"), L("Scene"), L("Chapter"), L("Part"), L("Book")][rawValue] }
}

enum SearchSource: String, CaseIterable {
    case text = "Text", synopsis = "Synopses", note = "Notes"
}

struct SearchQuery: Equatable {
    var text = ""
    var options = SearchOptions()
    var sources: Set<SearchSource> = [.text]
    var scope: SearchScope = .book
}

/// A place where the query was found.
struct SearchHit {
    let id = UUID()
    var source: SearchSource
    /// A scene's id for text; the section's id for a synopsis or a note.
    var owner: String
    var range: NSRange
    var groupTitle: String
    var before: String
    var match: String
    var after: String
}

/// What a replacement did, so that it can be undone: the pieces now in the text and what they replaced.
struct ReplaceRecord {
    var source: SearchSource
    var owner: String
    var places: [NSRange]
    var old: [String]
    var new: String
}

extension MainAreaController {
    // MARK: Scope

    /// The scenes and sections the scope covers, and the narrowed range for "Selection".
    func searchTargets(_ scope: SearchScope) -> (scenes: [String], sections: [String], selection: (scene: String, range: NSRange)?) {
        let structure = session.structure
        var everything: [String] = structure.scenes.map(\.id)
        for root in structure.roots {
            everything.append(root.id)
            for child in root.children { everything.append(child.id) }
        }
        var seen = Set<String>()
        everything = everything.filter { seen.insert($0).inserted }
        let allScenes: [String] = structure.scenes.map(\.id)
        let none: (scene: String, range: NSRange)? = nil
        guard let current = currentSceneID, let entry = structure.scenes.first(where: { $0.id == current }) else {
            if scope == .book { return (allScenes, everything, none) }
            return ([], [], none)
        }
        switch scope {
        case .selection:
            let area = activeArea
            if let tv = area?.currentSheet?.textView, tv.selectedRange().length > 0 {
                return ([current], [], (current, tv.selectedRange()))
            }
            return ([current], [current], none)
        case .scene:
            return ([current], [current], none)
        case .chapter:
            let ids: [String] = structure.scenes.filter { $0.chapterID == entry.chapterID }.map(\.id)
            var sections = ids
            if let chapter = entry.chapterID { sections.append(chapter) }
            return (ids, sections, none)
        case .part:
            guard let part = entry.partID else { return searchTargets(.chapter) }
            let list = structure.scenes.filter { $0.partID == part }
            let ids: [String] = list.map(\.id)
            var sections = ids
            sections.append(contentsOf: Set(list.compactMap(\.chapterID)).sorted())
            sections.append(part)
            return (ids, sections, none)
        case .book:
            return (allScenes, everything, none)
        }
    }

    private func groupTitle(for id: String) -> String {
        if let e = session.structure.scenes.first(where: { $0.id == id }) {
            return e.fullPath
        }
        return findNode(id).map { "\(L($0.kind.rawValue.capitalized)): \($0.title)" } ?? ""
    }

    // MARK: Searching

    func search(_ query: SearchQuery) -> [SearchHit] {
        guard !query.text.isEmpty else { return [] }
        let targets = searchTargets(query.scope)
        var hits: [SearchHit] = []
        func add(_ source: SearchSource, owner: String, text: String, within: NSRange?) {
            for r in TextSearch.ranges(of: query.text, in: text, options: query.options, within: within, limit: 2000) {
                let (before, after) = TextSearch.context(of: r, in: text)
                hits.append(SearchHit(source: source, owner: owner, range: r, groupTitle: groupTitle(for: owner), before: before, match: (text as NSString).substring(with: r), after: after))
            }
        }
        if query.sources.contains(.text) {
            for id in targets.scenes {
                guard let doc = session.document(id) else { continue }
                add(.text, owner: id, text: doc.storage.string, within: targets.selection?.scene == id ? targets.selection?.range : nil)
            }
        }
        let editor = BookEditor(structure: session.structure)
        for (source, key) in [(SearchSource.synopsis, "synopsis"), (.note, "note")] where query.sources.contains(source) && targets.selection == nil {
            for id in targets.sections {
                if let text = editor.record(id)?.string(key), !text.isEmpty { add(source, owner: id, text: text, within: nil) }
            }
        }
        return hits
    }

    // MARK: Replacing

    /// Replaces the given hits (a snapshot is taken first). Returns what was done, to undo it, and how many hits were stale and skipped.
    func replace(_ hits: [SearchHit], with replacement: String) -> (records: [ReplaceRecord], skipped: Int)? {
        saveAll()
        do { _ = try SnapshotStore(bookFolder: folder).take(.beforeOperation, reason: L("Replace")) } catch { reportError(error); return nil }
        var records: [ReplaceRecord] = []
        var skipped = 0
        let editor = BookEditor(structure: session.structure)
        var groups: [(key: String, source: SearchSource, owner: String, hits: [SearchHit])] = []
        for hit in hits {
            let key = "\(hit.source.rawValue)/\(hit.owner)"
            if let i = groups.firstIndex(where: { $0.key == key }) { groups[i].hits.append(hit) } else { groups.append((key, hit.source, hit.owner, [hit])) }
        }
        for group in groups {
            let field = group.source == .synopsis ? "synopsis" : "note"
            let current: String
            if group.source == .text { current = session.document(group.owner)?.storage.string ?? "" } else { current = editor.record(group.owner)?.string(field) ?? "" }
            let ns = current as NSString
            // Only the pieces that are still what the result said (the text may have been typed in since).
            let live = group.hits.filter { NSMaxRange($0.range) <= ns.length && ns.substring(with: $0.range) == $0.match }
            skipped += group.hits.count - live.count
            guard !live.isEmpty else { continue }
            let ranges = live.map(\.range)
            let (new, places) = TextSearch.replace(ranges, in: current, with: replacement)
            let old = ranges.sorted { $0.location < $1.location }.map { ns.substring(with: $0) }
            if group.source == .text, let doc = session.document(group.owner) {
                for r in ranges.sorted(by: { $0.location > $1.location }) { doc.storage.replaceCharacters(in: r, with: replacement) }
                doc.textDidChange()
                doc.updateCounts()
                _ = doc.saveNow()
            } else {
                do { try editor.setText(group.owner, key: field, to: new) } catch { reportError(error); continue }
            }
            records.append(ReplaceRecord(source: group.source, owner: group.owner, places: places, old: old, new: replacement))
        }
        didChangeSectionTexts()
        return (records, skipped)
    }

    /// Puts back what a replacement changed, piece by piece, where the text is still what the replacement wrote.
    func undoReplace(_ records: [ReplaceRecord]) -> Int {
        var left = 0
        let editor = BookEditor(structure: session.structure)
        for rec in records {
            let field = rec.source == .synopsis ? "synopsis" : "note"
            var text = rec.source == .text ? (session.document(rec.owner)?.storage.string ?? "") : (editor.record(rec.owner)?.string(field) ?? "")
            let ns = NSMutableString(string: text)
            let doc = rec.source == .text ? session.document(rec.owner) : nil
            for (i, place) in rec.places.enumerated().reversed() {
                guard NSMaxRange(place) <= ns.length, ns.substring(with: place) == rec.new else { left += 1; continue }
                if let doc { doc.storage.replaceCharacters(in: place, with: rec.old[i]) } else { ns.replaceCharacters(in: place, with: rec.old[i]) }
            }
            if let doc { doc.textDidChange(); doc.updateCounts(); _ = doc.saveNow() } else {
                text = ns as String
                try? editor.setText(rec.owner, key: field, to: text)
            }
        }
        didChangeSectionTexts()
        return left
    }

    func reportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("That could not be done")
        alert.informativeText = "\(error)"
        alert.runModal()
    }
}

extension WorldStore {
    /// For the checks: a place inside another one.
    func addEntryForTest(_ parent: String) -> String {
        let world = entry(parent)?.world ?? worlds[0].id ?? ""
        return (try? addEntry(name: "Внутри", world: world, parent: parent)) ?? ""
    }
}
