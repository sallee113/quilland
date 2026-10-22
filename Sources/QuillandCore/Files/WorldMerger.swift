import Foundation

/// Two entries that are one place, two worlds that are one, a place that is really a world, a world that is really a place.
/// Like `CharacterMerger`, each writes the kept side first and trashes the removed card last, so a stop half way loses nothing.
public enum WorldMerger {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    public struct Report: Equatable, Sendable {
        public var aliasesAdded: [String] = []
        /// Files of other things (characters, events, plan cards…) whose links to the removed place or world were pointed at the other one.
        public var linksRepointed = 0
        /// Places that moved: the children of a merged place, the entries of a merged or converted world.
        public var placesMoved = 0
    }

    private static func union(_ first: [String], _ second: [String]) -> [String] {
        var out = first
        for item in second where !out.contains(item) { out.append(item) }
        return out
    }

    private static func names(into aliases: inout [String], keep: String, add: [String], report: inout Report) {
        for name in add {
            let t = name.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.lowercased() != keep.lowercased(), !aliases.contains(where: { $0.lowercased() == t.lowercased() }) else { continue }
            aliases.append(t)
            report.aliasesAdded.append(t)
        }
    }

    /// Points what refers to `old` at `new`: the `links` and `places` maps of characters, events, things and plan cards (the descriptions of one target are joined),
    /// and the `worlds` list of a character.
    @discardableResult
    static func repoint(book: URL, from old: String, to new: String) throws -> Int {
        let fm = FileManager.default
        var changed = 0
        for relative in ["bible/characters", "bible/events", "bible/things", "plan/cards", "research"] {
            let dir = book.appendingPathComponent(relative)
            for name in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where name.hasSuffix(".json") {
                let url = dir.appendingPathComponent(name)
                guard var object = try? JSONParser.parseObject(Data(contentsOf: url)) else { continue }
                var touched = false
                for key in ["links", "places"] {
                    var map = object.stringMap(key) ?? [:]
                    if let text = map.removeValue(forKey: old) {
                        object.setStringMap(key, CharacterMerger.joined(map, [new: text]))
                        touched = true
                    }
                }
                // What an event changes in a place follows the place that is kept.
                if relative == "bible/events", var effects = object.object("effects"), let moved = effects.removeValue(forKey: old) {
                    if effects[new] == nil { effects[new] = moved }
                    if effects.isEmpty { object.removeValue(forKey: "effects") } else { object["effects"] = .object(effects) }
                    touched = true
                }
                if var worlds = object.strings("worlds"), worlds.contains(old) {
                    worlds = worlds.map { $0 == old ? new : $0 }
                    var seen: [String] = []
                    for w in worlds where !seen.contains(w) { seen.append(w) }
                    object.setStrings("worlds", seen)
                    touched = true
                }
                if touched { try AtomicFile.write(JSONWriter.data(object), to: url); changed += 1 }
            }
        }
        return changed
    }

    /// The text of the removed card is added under a bold line with its name.
    private static func appendText(_ store: WorldStore, from source: String, to target: String, name: String) throws {
        let extra = store.text(source)
        guard !extra.isEmpty else { return }
        let base = store.text(target)
        try store.setText(target, base.isEmpty ? extra : base + "\n\n**" + name + "**\n\n" + extra)
    }

    // MARK: Two places

    @discardableResult
    public static func mergePlaces(_ source: String, into target: String, book: URL) throws -> Report {
        guard source != target else { throw Failure(L("A place cannot be merged into itself.")) }
        let store = WorldStore(book: book)
        guard let from = store.entry(source), let into = store.entry(target) else { throw Failure(L("No such place.")) }
        let below = store.descendants(of: source)
        guard !below.contains(where: { $0.id == target }) else { throw Failure(L("A place cannot be merged into a place inside it.")) }
        var report = Report()
        let fromName = (from.name ?? "").trimmingCharacters(in: .whitespaces)
        var aliases = into.aliases
        names(into: &aliases, keep: into.name ?? "", add: [fromName] + from.aliases, report: &report)
        try store.updateEntry(target) { r in
            r.aliases = aliases
            r.notes = union(r.notes, from.notes)
            r.links = CharacterMerger.joined(r.links, from.links)
        }
        try appendText(store, from: source, to: target, name: fromName)
        // What was inside the removed place is inside the kept one (in its world).
        for d in below where from.world != into.world { if let id = d.id { try store.updateEntry(id) { $0.world = into.world } } }
        for child in store.entries.filter({ $0.parent == source }) {
            guard let id = child.id else { continue }
            try store.updateEntry(id) { $0.parent = target; $0.world = into.world }
            report.placesMoved += 1
        }
        report.linksRepointed = try repoint(book: book, from: source, to: target)
        try store.deleteEntry(source)
        return report
    }

    // MARK: Two worlds

    @discardableResult
    public static func mergeWorlds(_ source: String, into target: String, book: URL) throws -> Report {
        guard source != target else { throw Failure(L("A world cannot be merged into itself.")) }
        let store = WorldStore(book: book)
        guard let from = store.world(source), let into = store.world(target) else { throw Failure(L("No such world.")) }
        var report = Report()
        let fromName = (from.name ?? "").trimmingCharacters(in: .whitespaces)
        var aliases = into.aliases
        names(into: &aliases, keep: into.name ?? "", add: [fromName] + from.aliases, report: &report)
        try store.updateWorld(target) { r in
            r.aliases = aliases
            r.notes = union(r.notes, from.notes)
        }
        try appendText(store, from: source, to: target, name: fromName)
        for e in store.entries.filter({ $0.world == source }) {
            guard let id = e.id else { continue }
            try store.updateEntry(id) { $0.world = target }
            report.placesMoved += 1
        }
        report.linksRepointed = try repoint(book: book, from: source, to: target)
        try store.deleteWorld(source)
        return report
    }

    // MARK: A place that is a world

    /// The place becomes a world of its own, and what was inside it is at the top of that world. Returns the new world's id.
    @discardableResult
    public static func placeToWorld(_ entry: String, book: URL) throws -> (world: String, report: Report) {
        let store = WorldStore(book: book)
        guard let from = store.entry(entry) else { throw Failure(L("No such place.")) }
        var report = Report()
        let world = try store.addWorld(name: from.name ?? "")
        try store.updateWorld(world) { r in
            r.aliases = from.aliases
            r.notes = from.notes
            // The scenes it had links to stay with it (kept in the record, which keeps fields it does not know).
            if !from.links.isEmpty { r.object.setStringMap("links", from.links) }
        }
        let text = store.text(entry)
        if !text.isEmpty { try store.setText(world, text) }
        let below = store.descendants(of: entry)
        for d in below { if let id = d.id { try store.updateEntry(id) { $0.world = world; if $0.parent == entry { $0.parent = nil } }; report.placesMoved += 1 } }
        report.linksRepointed = try repoint(book: book, from: entry, to: world)
        try store.deleteEntry(entry)
        return (world, report)
    }

    // MARK: A world that is a place

    /// The world becomes a place inside another world (inside `parent`, or at the top of `intoWorld`), and its entries are inside that place. Returns the new place's id.
    @discardableResult
    public static func worldToPlace(_ world: String, intoWorld: String, parent: String?, book: URL) throws -> (entry: String, report: Report) {
        guard world != intoWorld else { throw Failure(L("A world cannot be merged into itself.")) }
        let store = WorldStore(book: book)
        guard let from = store.world(world) else { throw Failure(L("No such world.")) }
        guard store.world(intoWorld) != nil else { throw Failure(L("No such world.")) }
        var report = Report()
        let entry = try store.addEntry(name: from.name ?? "", world: intoWorld, parent: parent)
        try store.updateEntry(entry) { r in
            r.aliases = from.aliases
            r.notes = from.notes
            if let links = from.object.stringMap("links") { r.links = links }
        }
        let text = store.text(world)
        if !text.isEmpty { try store.setText(entry, text) }
        for e in store.entries.filter({ $0.world == world }) {
            guard let id = e.id else { continue }
            try store.updateEntry(id) { $0.world = intoWorld; if $0.parent == nil { $0.parent = entry } }
            report.placesMoved += 1
        }
        report.linksRepointed = try repoint(book: book, from: world, to: entry)
        try store.deleteWorld(world)
        return (entry, report)
    }
}
