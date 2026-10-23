import Foundation

/// The settings of the person, per machine (`~/Library/Application Support/Quilland/settings.json`; quilland-settings.md).
/// Only the library (the books the app knows) is here for now. A damaged file is kept as `settings.json.bad` and never overwritten silently;
/// unknown keys are kept when the file is written.
public final class AppSettings {
    public struct KnownBook: Equatable, Sendable {
        public var name: String
        public var path: String
    }

    public static let recentLimit = 10
    /// How many recent books are kept (Settings ▸ General).
    public var recentCap = AppSettings.recentLimit

    public let directory: URL
    private var object: JSONObject = ["format": .int(1)]
    /// Set when the file could not be read (it was moved aside).
    public private(set) var damaged = false

    public init(directory: URL) {
        self.directory = directory
        let url = directory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url) else { return }
        do { object = try JSONParser.parseObject(data) } catch {
            damaged = true
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("settings.json.bad"))
            try? FileManager.default.moveItem(at: url, to: directory.appendingPathComponent("settings.json.bad"))
        }
    }

    public static var standardDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Quilland")
    }

    private var library: JSONObject { object.object("library") ?? [:] }

    public var knownBooks: [KnownBook] {
        (library.objects("known_books") ?? []).compactMap { o in
            guard let path = o.string("path") else { return nil }
            return KnownBook(name: o.string("name") ?? URL(fileURLWithPath: path).lastPathComponent, path: path)
        }
    }

    public var lastOpened: String? { library.string("last_opened") }

    /// A book was opened or created: it goes to the front of the recent list and becomes the last opened.
    public func noteOpened(folder: URL, name: String) {
        var books = knownBooks.filter { $0.path != folder.path }
        books.insert(KnownBook(name: name, path: folder.path), at: 0)
        if books.count > recentCap { books = Array(books.prefix(recentCap)) }
        var lib = library
        lib.setObjects("known_books", books.map { ["name": .string($0.name), "path": .string($0.path)] })
        lib.setString("last_opened", folder.path)
        object["library"] = .object(lib)
        save()
    }

    /// A book was renamed (Book Settings): the list of recent books shows the new name, in its place.
    public func noteTitle(folder: URL, name: String) {
        var lib = library
        let books = knownBooks.map { $0.path == folder.path ? KnownBook(name: name, path: $0.path) : $0 }
        lib.setObjects("known_books", books.map { ["name": .string($0.name), "path": .string($0.path)] })
        object["library"] = .object(lib)
        save()
    }

    /// Closing the last book: the next start shows the Welcome window.
    public func clearLastOpened() {
        var lib = library
        lib.setString("last_opened", nil)
        object["library"] = .object(lib)
        save()
    }

    public func forget(path: String) {
        var lib = library
        lib.setObjects("known_books", knownBooks.filter { $0.path != path }.map { ["name": .string($0.name), "path": .string($0.path)] })
        if lastOpened == path { lib.setString("last_opened", nil) }
        object["library"] = .object(lib)
        save()
    }

    /// The whole settings object, for the typed groups kept in it (see `Preferences`).
    var objectValue: JSONObject { object }

    func replaceObject(_ new: JSONObject) {
        object = new
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(object), to: directory.appendingPathComponent("settings.json"))
    }
}

/// What the Graph view was set to and where it was looking, kept for the book on this machine (inside `LocalBookState`).
public struct GraphViewMemory: Equatable, Sendable {
    /// `whole`, `social` or `neighbourhood`.
    public var look = "whole"
    /// Kinds shown: `character`, `place`, `event`, `scene`.
    public var kinds: [String] = ["character", "place", "event"]
    public var showUnlinked = true
    /// Draw the relationships that have ended, and keep only the events that change something.
    public var showEnded = true
    public var changesOnly = false
    /// The scene the graph is as of (nil: the whole book).
    public var asOf: String?
    public var section: String?
    public var focus: String?
    public var depth = 1
    /// The zoom, and the middle of what was in view, in the layout's own coordinates; nil: fit everything.
    public var zoom: Double?
    public var centerX: Double?
    public var centerY: Double?

    public init() {}

    init?(object o: JSONObject) {
        look = o.string("look") ?? "whole"
        kinds = o.strings("kinds") ?? ["character", "place", "event"]
        showUnlinked = o.bool("show_unlinked") ?? true
        showEnded = o.bool("show_ended") ?? true
        changesOnly = o.bool("changes_only") ?? false
        asOf = o.string("as_of")
        section = o.string("section")
        focus = o.string("focus")
        depth = o.int("depth") ?? 1
        if let z = o.string("zoom"), let v = Double(z) { zoom = v }
        centerX = o.int("center_x").map(Double.init)
        centerY = o.int("center_y").map(Double.init)
    }

    var object: JSONObject {
        var o: JSONObject = ["look": .string(look), "show_unlinked": .bool(showUnlinked), "show_ended": .bool(showEnded), "changes_only": .bool(changesOnly), "depth": .int(depth)]
        o.setStrings("kinds", kinds)
        o.setString("section", section)
        o.setString("focus", focus)
        o.setString("as_of", asOf)
        if let zoom { o["zoom"] = .string(String(format: "%.3f", zoom)) }
        if let centerX, let centerY { o["center_x"] = .int(Int(centerX.rounded())); o["center_y"] = .int(Int(centerY.rounded())) }
        return o
    }
}

/// Where the author left off in one book (`<book>/.quilland/state.json`, ignored by Git): the scene and the place in it, and the view.
public struct LocalBookState: Equatable, Sendable {
    public var scene: String?
    public var position: Int = 0
    /// `panels`, `book` or `plan` (others come with their views). An old `compare` is the Book view with the split.
    public var mode: String = "panels"
    /// Is the right panel open?
    public var rightPanel: Bool = false
    /// The day the count of "today" started (`2026-10-06`) and the size of the book at its start.
    public var dayDate: String?
    public var dayBaseline: Int?
    /// Where this book was last exported (kept on this machine only, not in the book).
    public var exportFolder: String?
    /// The section (part, chapter or scene) the Plan view starts from; what comes before it is hidden. Nil: the whole book.
    public var planFrom: String?
    /// Is the Book view split into two panes?
    public var split: Bool = false
    /// The Graph view's settings and place.
    public var graph: GraphViewMemory?

    public init(scene: String? = nil, position: Int = 0, mode: String = "panels", rightPanel: Bool = false, dayDate: String? = nil, dayBaseline: Int? = nil, exportFolder: String? = nil, planFrom: String? = nil, split: Bool = false, graph: GraphViewMemory? = nil) {
        self.split = split
        self.graph = graph
        self.exportFolder = exportFolder
        self.planFrom = planFrom
        self.rightPanel = rightPanel
        self.dayDate = dayDate
        self.dayBaseline = dayBaseline
        self.scene = scene
        self.position = position
        self.mode = mode
    }

    /// Starts a new day's count when the date is not the one kept: `total` is the size of the book now. Returns the characters written today.
    public mutating func written(today date: String, total: Int) -> Int {
        if dayDate != date || dayBaseline == nil { dayDate = date; dayBaseline = total }
        return total - (dayBaseline ?? total)
    }

    static func url(_ book: URL) -> URL { book.appendingPathComponent(".quilland/state.json") }

    public static func load(book: URL) -> LocalBookState {
        guard let data = try? Data(contentsOf: url(book)), let o = try? JSONParser.parseObject(data) else { return LocalBookState() }
        let cursor = o.object("cursor") ?? [:]
        return LocalBookState(scene: cursor.string("scene"), position: cursor.int("position") ?? 0, mode: o.string("mode") ?? "panels", rightPanel: o.bool("right_panel") ?? false, dayDate: o.object("today")?.string("date"), dayBaseline: o.object("today")?.int("baseline"), exportFolder: o.string("export_folder"), planFrom: o.string("plan_from"), split: o.bool("split") ?? false, graph: o.object("graph").flatMap(GraphViewMemory.init(object:)))
    }

    /// Keeps the keys it does not know (other parts of the state).
    public func save(book: URL) {
        var o: JSONObject = (try? JSONParser.parseObject(Data(contentsOf: Self.url(book)))) ?? [:]
        o["format"] = .int(1)
        o["mode"] = .string(mode)
        o["right_panel"] = .bool(rightPanel)
        o["split"] = .bool(split)
        if let graph { o["graph"] = .object(graph.object) } else { o.removeValue(forKey: "graph") }
        if let exportFolder { o["export_folder"] = .string(exportFolder) }
        if let planFrom { o["plan_from"] = .string(planFrom) } else { o.removeValue(forKey: "plan_from") }
        if let dayDate, let dayBaseline { o["today"] = .object(["baseline": .int(dayBaseline), "date": .string(dayDate)]) }
        if let scene { o["cursor"] = .object(["position": .int(position), "scene": .string(scene)]) } else { o.removeValue(forKey: "cursor") }
        try? FileManager.default.createDirectory(at: Self.url(book).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? AtomicFile.write(JSONWriter.data(o), to: Self.url(book))
    }
}
