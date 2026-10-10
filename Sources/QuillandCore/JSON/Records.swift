import Foundation

// Typed views of the data files (quilland-format.md, sections 6, 7, 14, 16).
//
// A record holds the whole JSON object it was read from. Its properties read and
// write single fields of that object, so every field the app does not know, at any
// depth, stays exactly where it was and is written back. A field of the wrong type
// reads as nil but is never removed; `problems` reports it.

/// What a field of a record should hold.
enum FieldKind {
    case string, int, bool, strings, stringMap, objects, object

    func matches(_ value: JSONValue) -> Bool {
        switch (self, value) {
        case (.string, .string), (.bool, .bool), (.object, .object): return true
        case (.int, .number(let n)): return Int(n) != nil
        case (.strings, .array(let items)): return items.allSatisfy { if case .string = $0 { return true } else { return false } }
        case (.stringMap, .object(let o)): return o.values.allSatisfy { if case .string = $0 { return true } else { return false } }
        case (.objects, .array(let items)): return items.allSatisfy { if case .object = $0 { return true } else { return false } }
        default: return false
        }
    }
}

func checkFields(_ object: JSONObject, required: [String], kinds: [String: FieldKind]) -> [String] {
    var problems: [String] = []
    for key in required where object[key] == nil { problems.append("\"\(key)\" is missing") }
    for (key, kind) in kinds.sorted(by: { $0.key < $1.key }) {
        if let value = object[key], !kind.matches(value) { problems.append("\"\(key)\" has the wrong kind of value") }
    }
    return problems
}

// MARK: Scene, chapter, part, title page

public struct SceneRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }
    public init(id: String, title: String) { object = ["id": .string(id), "title": .string(title)] }

    public static let knownStatuses = ["idea", "draft", "revised", "done"]

    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var title: String? { get { object.string("title") } set { object.setString("title", newValue) } }
    /// As written; a value outside `knownStatuses` is kept and reported, never changed.
    public var status: String? { get { object.string("status") } set { object.setString("status", newValue) } }
    public var synopsis: String? { get { object.string("synopsis") } set { object.setString("synopsis", newValue) } }
    public var note: String? { get { object.string("note") } set { object.setString("note", newValue) } }
    public var tags: [String] { get { object.strings("tags") ?? [] } set { object.setStrings("tags", newValue) } }
    public var targetCharacters: Int? { get { object.int("target_characters") } set { object.setInt("target_characters", newValue) } }

    public var problems: [String] {
        var out = checkFields(object, required: ["id", "title"], kinds: [
            "id": .string, "title": .string, "status": .string, "synopsis": .string, "note": .string,
            "tags": .strings, "target_characters": .int,
        ])
        if let status, !Self.knownStatuses.contains(status) { out.append("unknown status \"\(status)\" (kept)") }
        return out
    }
}

// MARK: Character

public struct CharacterRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }

    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var name: String? { get { object.string("name") } set { object.setString("name", newValue) } }
    public var aliases: [String] { get { object.strings("aliases") ?? [] } set { object.setStrings("aliases", newValue) } }
    public var main: Bool { get { object.bool("main") ?? false } set { object.setBool("main", newValue ? true : nil) } }
    public var notes: [String] { get { object.strings("notes") ?? [] } set { object.setStrings("notes", newValue) } }
    public var povScenes: [String] { get { object.strings("pov_scenes") ?? [] } set { object.setStrings("pov_scenes", newValue) } }
    public var worlds: [String] { get { object.strings("worlds") ?? [] } set { object.setStrings("worlds", newValue) } }
    /// Target id to description. An empty description is a link with no text.
    public var links: [String: String] { get { object.stringMap("links") ?? [:] } set { object.setStringMap("links", newValue) } }
    public var images: [String: String] { get { object.stringMap("images") ?? [:] } set { object.setStringMap("images", newValue) } }

    public var problems: [String] {
        checkFields(object, required: ["id", "name"], kinds: [
            "id": .string, "name": .string, "aliases": .strings, "main": .bool, "notes": .strings,
            "pov_scenes": .strings, "worlds": .strings, "links": .stringMap, "images": .stringMap,
        ])
    }
}

// MARK: Timeline

public struct TimelineFile: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }

    public struct Entry: Equatable, Sendable {
        public var object: JSONObject
        public var event: String? { get { object.string("event") } set { object.setString("event", newValue) } }
        public var lane: String? { get { object.string("lane") } set { object.setString("lane", newValue) } }
        public var start: Int? { get { object.int("start") } set { object.setInt("start", newValue) } }
        public var end: Int? { get { object.int("end") } set { object.setInt("end", newValue) } }
        public var label: String? { get { object.string("label") } set { object.setString("label", newValue) } }
    }

    public struct Lane: Equatable, Sendable {
        public var object: JSONObject
        public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
        public var name: String? { get { object.string("name") } set { object.setString("name", newValue) } }
        public var world: String? { get { object.string("world") } set { object.setString("world", newValue) } }
        public var color: String? { get { object.string("color") } set { object.setString("color", newValue) } }
        /// A short note on what the line is about, shown under its name.
        public var summary: String? { get { object.string("description") } set { object.setString("description", newValue?.isEmpty == true ? nil : newValue) } }
        /// Switched off on the canvas: the line and what stands on it are not shown. Nothing is deleted.
        public var isHidden: Bool { get { object.bool("hidden") ?? false } set { object.setBool("hidden", newValue ? true : nil) } }
    }

    public var entries: [Entry] {
        get { (object.objects("entries") ?? []).map { Entry(object: $0) } }
        set { object.setObjects("entries", newValue.map(\.object)) }
    }

    public var lanes: [Lane] {
        get { (object.objects("lanes") ?? []).map { Lane(object: $0) } }
        set { object.setObjects("lanes", newValue.map(\.object)) }
    }

    /// Drags one event: only its own entry changes.
    public mutating func move(event: String, toStart start: Int, end: Int?) {
        var all = entries
        guard let i = all.firstIndex(where: { $0.event == event }) else { return }
        all[i].start = start
        all[i].end = end
        entries = all
    }

    public var problems: [String] {
        var out = checkFields(object, required: [], kinds: ["entries": .objects, "lanes": .objects])
        for (i, entry) in entries.enumerated() {
            out += checkFields(entry.object, required: ["event", "lane", "start"],
                               kinds: ["event": .string, "lane": .string, "start": .int, "end": .int, "label": .string])
                .map { "entry \(i): \($0)" }
            if let s = entry.start, let e = entry.end, e < s { out.append("entry \(i): the end is before the start") }
        }
        return out
    }
}

// MARK: Export profiles

public struct ExportFile: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }

    public struct HeadingRule: Equatable, Sendable {
        public var print: String
        public var template: String?
        public var newPage: Bool?
        public init(print: String, template: String? = nil, newPage: Bool? = nil) {
            self.print = print
            self.template = template
            self.newPage = newPage
        }
    }

    public struct Profile: Equatable, Sendable {
        public var object: JSONObject
        public var name: String? { get { object.string("name") } set { object.setString("name", newValue) } }
        public var format: String? { get { object.string("format") } set { object.setString("format", newValue) } }
        public var toc: Bool? { get { object.bool("toc") } set { object.setBool("toc", newValue) } }
        public var cover: Bool? { get { object.bool("cover") } set { object.setBool("cover", newValue) } }
        public var footnotes: String? { get { object.string("footnotes") } set { object.setString("footnotes", newValue) } }
        public var sceneBreak: String? { get { object.string("scene_break") } set { object.setString("scene_break", newValue) } }
        public var titlePage: String? { get { object.string("title_page") } set { object.setString("title_page", newValue) } }
        public var tocScenes: Bool? { get { object.bool("toc_scenes") } set { object.setBool("toc_scenes", newValue) } }
        public var numbering: String? { get { object.string("numbering") } set { object.setString("numbering", newValue) } }
        public var restartInParts: Bool? { get { object.bool("restart_in_parts") } set { object.setBool("restart_in_parts", newValue) } }
        public init(object: JSONObject = [:]) { self.object = object }
        public var statuses: [String] { object.object("filters")?.strings("statuses") ?? [] }
        public var tags: [String] { object.object("filters")?.strings("tags") ?? [] }

        public mutating func setFilters(statuses: [String], tags: [String]) {
            var filters = object.object("filters") ?? [:]
            filters.setStrings("statuses", statuses)
            filters.setStrings("tags", tags)
            object["filters"] = .object(filters)
        }

        /// The rule for "part", "chapter" or "scene"; unknown keys inside it stay when it is changed.
        public func headingRule(_ level: String) -> HeadingRule? {
            guard let rule = object.object("headings")?.object(level), let print = rule.string("print") else { return nil }
            return HeadingRule(print: print, template: rule.string("template"), newPage: rule.bool("new_page"))
        }

        public mutating func setHeadingRule(_ level: String, _ rule: HeadingRule) {
            var headings = object.object("headings") ?? [:]
            var entry = headings.object(level) ?? [:]
            entry.setString("print", rule.print)
            entry.setString("template", rule.template)
            entry.setBool("new_page", rule.newPage)
            headings[level] = .object(entry)
            object["headings"] = .object(headings)
        }
    }

    public var profiles: [Profile] {
        get { (object.objects("profiles") ?? []).map { Profile(object: $0) } }
        set { object.setObjects("profiles", newValue.map(\.object)) }
    }
}

// MARK: Plan cards (quilland-format.md, section 20)

/// A card of the plan: on a line (`line` and `start`) or floating (`x` and `y`), never both.
public struct PlanCardRecord: Equatable, Sendable {
    public var object: JSONObject
    public init(object: JSONObject) { self.object = object }

    public var id: String? { get { object.string("id") } set { object.setString("id", newValue) } }
    public var title: String? { get { object.string("title") } set { object.setString("title", newValue) } }
    public var text: String? { get { object.string("text") } set { object.setString("text", newValue) } }
    public var color: String? { get { object.string("color") } set { object.setString("color", newValue) } }
    public var line: String? { get { object.string("line") } set { object.setString("line", newValue) } }
    public var start: Int? { get { object.int("start") } set { object.setInt("start", newValue) } }
    public var x: Int? { get { object.int("x") } set { object.setInt("x", newValue) } }
    public var y: Int? { get { object.int("y") } set { object.setInt("y", newValue) } }
    public var links: [String: String] { get { object.stringMap("links") ?? [:] } set { object.setStringMap("links", newValue) } }

    public var isFloating: Bool { line == nil }

    public struct Spans: Equatable, Sendable {
        public var from: Int
        public var to: Int?
        /// `chapters` or `scenes`.
        public var unit: String
        public init(from: Int, to: Int? = nil, unit: String) {
            self.from = from
            self.to = to
            self.unit = unit
        }
    }

    public var spans: Spans? {
        get {
            guard let o = object.object("spans"), let from = o.int("from"), let unit = o.string("unit") else { return nil }
            return Spans(from: from, to: o.int("to"), unit: unit)
        }
        set {
            guard let v = newValue else { object.removeValue(forKey: "spans"); return }
            var o = object.object("spans") ?? [:]
            o.setInt("from", v.from)
            o.setInt("to", v.to)
            o.setString("unit", v.unit)
            object["spans"] = .object(o)
        }
    }

    /// Puts the card on a line; its floating position is forgotten.
    public mutating func place(onLine line: String, start: Int) {
        self.line = line
        self.start = start
        object.removeValue(forKey: "x")
        object.removeValue(forKey: "y")
    }

    /// Lets the card float; its line and position on it are forgotten.
    public mutating func float(x: Int, y: Int) {
        self.x = x
        self.y = y
        object.removeValue(forKey: "line")
        object.removeValue(forKey: "start")
    }

    public var problems: [String] {
        var out = checkFields(object, required: ["id", "title"], kinds: [
            "id": .string, "title": .string, "text": .string, "color": .string, "line": .string, "start": .int, "x": .int, "y": .int,
            "links": .stringMap, "spans": .object,
        ])
        if line != nil, start == nil { out.append("\"line\" needs \"start\"") }
        if line != nil, x != nil || y != nil { out.append("a card is either on a line or floating, not both") }
        if let s = spans {
            if !["chapters", "scenes"].contains(s.unit) { out.append("\"spans\" has an unknown unit") }
            if let to = s.to, to < s.from { out.append("\"spans\": the end is before the start") }
        }
        return out
    }
}
