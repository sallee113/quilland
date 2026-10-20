import Foundation

/// The plan of a book on disk (quilland-format.md, sections 14 and 20): the plot lines and the places of the real events in `plan/canvas.json`,
/// and one file per card in `plan/cards/`. Every change is written at once, atomically, to the one file it concerns.
public final class PlanStore {
    public enum Drop {
        /// Level with an existing row: the same position, so simultaneous.
        case row(Int)
        /// A new row between two existing positions (nil: before the first, or after the last).
        case between(Int?, Int?)
    }

    public let folder: URL
    public private(set) var canvas = TimelineFile(object: ["format": .int(1)])
    public private(set) var cards: [String: PlanCardRecord] = [:]
    /// The real events (their titles), read from `bible/events/`.
    public private(set) var events: [String: String] = [:]
    /// The colour of each real event that has one (kept in the event's own file).
    public private(set) var eventColors: [String: String] = [:]
    /// The scenes (and fragments) each event is linked to.
    public private(set) var eventLinks: [String: [String]] = [:]
    public private(set) var problems: [String] = []

    private var canvasURL: URL { folder.appendingPathComponent("plan/canvas.json") }
    private var cardsFolder: URL { folder.appendingPathComponent("plan/cards") }

    public init(folder: URL) throws {
        self.folder = folder
        try reload()
    }

    public func reload() throws {
        problems = []
        cards = [:]
        events = [:]
        eventColors = [:]
        eventLinks = [:]
        canvas = TimelineFile(object: ["format": .int(1)])
        let fm = FileManager.default
        if let data = try? Data(contentsOf: canvasURL) {
            do {
                canvas = TimelineFile(object: try JSONParser.parseObject(data))
                problems += canvas.problems.map { "canvas.json: \($0)" }
            } catch { problems.append("canvas.json: \(error)") }
        }
        for name in ((try? fm.contentsOfDirectory(atPath: cardsFolder.path)) ?? []).sorted() where name.hasSuffix(".json") {
            do {
                let record = PlanCardRecord(object: try JSONParser.parseObject(Data(contentsOf: cardsFolder.appendingPathComponent(name))))
                if let id = record.id { cards[id] = record }
                problems += record.problems.map { "\(name): \($0)" }
            } catch { problems.append("\(name): \(error)") }
        }
        let eventsFolder = folder.appendingPathComponent("bible/events")
        for name in ((try? fm.contentsOfDirectory(atPath: eventsFolder.path)) ?? []).sorted() where name.hasSuffix(".json") {
            if let data = try? Data(contentsOf: eventsFolder.appendingPathComponent(name)), let o = try? JSONParser.parseObject(data), let id = o.string("id") {
                events[id] = o.string("title") ?? ""
                if let color = o.string("color") { eventColors[id] = color }
                eventLinks[id] = Array((o.stringMap("links") ?? [:]).keys)
            }
        }
    }

    // MARK: Undo

    /// Everything the plan holds, for undoing an operation: put back with `restore`.
    public struct State: Sendable {
        var canvas: JSONObject
        var cards: [String: JSONObject]
        var eventColors: [String: String]
    }

    public func captureState() -> State { State(canvas: canvas.object, cards: cards.mapValues(\.object), eventColors: eventColors) }

    /// Puts the plan back as it was: the canvas file is rewritten, cards that are gone are written again, cards that did not exist are removed.
    public func restore(_ state: State) throws {
        let now = Set(cards.keys)
        canvas = TimelineFile(object: state.canvas)
        cards = state.cards.mapValues { PlanCardRecord(object: $0) }
        try saveCanvas()
        for id in now.subtracting(state.cards.keys) { try? FileManager.default.removeItem(at: cardURL(id)) }
        for id in state.cards.keys { try saveCard(id) }
        for id in Set(eventColors.keys).union(state.eventColors.keys) where eventColors[id] != state.eventColors[id] { try setEventColor(id, to: state.eventColors[id]) }
    }

    // MARK: Colours of real events

    /// Gives a real event a colour on the Plan, or takes it away (nil). It is written in the event's own file (`bible/events/<id>.json`), everything else there kept.
    public func setEventColor(_ id: String, to color: String?) throws {
        guard events[id] != nil else { return }
        let url = folder.appendingPathComponent("bible/events/\(id).json")
        var object = try JSONParser.parseObject(Data(contentsOf: url))
        object.setString("color", color)
        try AtomicFile.write(JSONWriter.data(object), to: url)
        if let color { eventColors[id] = color } else { eventColors.removeValue(forKey: id) }
    }

    // MARK: Lines

    public var lines: [TimelineFile.Lane] { canvas.lanes }
    public var entries: [TimelineFile.Entry] { canvas.entries }

    private func saveCanvas() throws {
        try FileManager.default.createDirectory(at: canvasURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(canvas.object), to: canvasURL)
    }

    @discardableResult
    public func addLine(name: String, color: String? = nil) throws -> String {
        let id = UUID().uuidString.lowercased()
        var lane = TimelineFile.Lane(object: [:])
        lane.id = id
        lane.name = name
        lane.color = color
        canvas.lanes = canvas.lanes + [lane]
        try saveCanvas()
        return id
    }

    /// The lines that are shown, in order: the columns of the canvas.
    public var visibleLines: [TimelineFile.Lane] { canvas.lanes.filter { !$0.isHidden } }

    private func changeLine(_ id: String, _ change: (inout TimelineFile.Lane) -> Void) throws {
        var all = canvas.lanes
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        let before = all[i]
        change(&all[i])
        guard all[i] != before else { return }
        canvas.lanes = all
        try saveCanvas()
    }

    public func setLineColor(_ id: String, to color: String?) throws { try changeLine(id) { $0.color = color } }
    public func setLineDescription(_ id: String, to text: String?) throws { try changeLine(id) { $0.summary = text } }
    public func setLine(_ id: String, visible: Bool) throws { try changeLine(id) { $0.isHidden = !visible } }

    /// Moves a line one place left (-1) or right (1) among all the lines, hidden ones too. False at the end of the row.
    @discardableResult
    public func moveLine(_ id: String, by step: Int) throws -> Bool {
        var all = canvas.lanes
        guard let i = all.firstIndex(where: { $0.id == id }), all.indices.contains(i + step) else { return false }
        all.swapAt(i, i + step)
        canvas.lanes = all
        try saveCanvas()
        return true
    }

    public func renameLine(_ id: String, to name: String) throws {
        var all = canvas.lanes
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].name = name
        canvas.lanes = all
        try saveCanvas()
    }

    /// Removes a line. Its cards become floating at the places given (the interface knows where they were drawn); its events move to
    /// the first remaining line, keeping their positions. Without another line the events' entries are dropped (an event with no entry is still an event).
    public func deleteLine(_ id: String, floatingAt places: [String: (x: Int, y: Int)]) throws {
        for (cardID, place) in places where cards[cardID]?.line == id { try updateCard(cardID) { $0.float(x: place.x, y: place.y) } }
        for (cardID, card) in cards where card.line == id && places[cardID] == nil { try updateCard(cardID) { $0.float(x: 0, y: 0) } }
        let remaining = canvas.lanes.filter { $0.id != id }
        var entries = canvas.entries
        if let first = remaining.first?.id {
            for i in entries.indices where entries[i].lane == id { entries[i].lane = first }
        } else {
            entries.removeAll { $0.lane == id }
        }
        canvas.entries = entries
        canvas.lanes = remaining
        try saveCanvas()
    }

    // MARK: Cards

    private func cardURL(_ id: String) -> URL { cardsFolder.appendingPathComponent("\(id).json") }

    private func saveCard(_ id: String) throws {
        guard let card = cards[id] else { return }
        try FileManager.default.createDirectory(at: cardsFolder, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(card.object), to: cardURL(id))
    }

    @discardableResult
    public func addCard(title: String, text: String = "", line: String? = nil, start: Int? = nil, x: Int = 0, y: Int = 0, color: String? = nil) throws -> String {
        let id = UUID().uuidString.lowercased()
        var card = PlanCardRecord(object: [:])
        card.id = id
        card.title = title
        if !text.isEmpty { card.text = text }
        card.color = color
        if let line, let start { card.place(onLine: line, start: start) } else { card.float(x: x, y: y) }
        cards[id] = card
        try saveCard(id)
        return id
    }

    public func updateCard(_ id: String, _ change: (inout PlanCardRecord) -> Void) throws {
        guard var card = cards[id] else { return }
        change(&card)
        cards[id] = card
        try saveCard(id)
    }

    public func deleteCard(_ id: String) throws {
        guard cards.removeValue(forKey: id) != nil else { return }
        try? FileManager.default.removeItem(at: cardURL(id))
    }

    // MARK: Real events on the canvas

    public func entry(forEvent id: String) -> TimelineFile.Entry? { canvas.entries.first { $0.event == id } }

    /// Takes an event off the canvas (the event itself is not touched).
    public func removeEntry(forEvent id: String) throws {
        guard canvas.entries.contains(where: { $0.event == id }) else { return }
        canvas.entries = canvas.entries.filter { $0.event != id }
        try saveCanvas()
    }

    /// Places a real event on a line at a position (its own entry changes, nothing else).
    public func placeEvent(_ id: String, onLine line: String, start: Int) throws {
        let start = try freeStart(forEvent: id, onLine: line, wanted: start)
        var all = canvas.entries
        if let i = all.firstIndex(where: { $0.event == id }) {
            all[i].lane = line
            all[i].start = start
        } else {
            var e = TimelineFile.Entry(object: [:])
            e.event = id; e.lane = line; e.start = start
            all.append(e)
        }
        canvas.entries = all
        try saveCanvas()
    }

    // MARK: Room on a line

    /// Two events, or two cards, never share a line and a row: one that is wanted where another of its kind already stands goes to a new row just after
    /// that place (between it and the next row, so nothing else moves). A card and an event may share a cell (two layers), and so may items of
    /// different lines (the same row there means the same moment).
    func freeStart(forEvent id: String, onLine line: String, wanted start: Int) throws -> Int {
        let taken = Set(canvas.entries.filter { $0.lane == line && $0.event != id }.compactMap(\.start))
        return try nextFree(from: start, taken: taken)
    }

    func freeStart(forCard id: String, onLine line: String, wanted start: Int) throws -> Int {
        let taken = Set(cards.values.filter { $0.line == line && $0.id != id }.compactMap(\.start))
        return try nextFree(from: start, taken: taken)
    }

    private func nextFree(from start: Int, taken: Set<Int>) throws -> Int {
        guard taken.contains(start) else { return start }
        return try resolve(.between(start, rowStarts.first { $0 > start }))
    }

    /// Puts a card on a line at a position; if that place is taken by another card of the line, at a new row just after it.
    public func placeCard(_ id: String, onLine line: String, start: Int) throws {
        let start = try freeStart(forCard: id, onLine: line, wanted: start)
        try updateCard(id) { $0.place(onLine: line, start: start) }
    }

    // MARK: Positions

    /// The distinct positions of everything that sits on a line, in order: the rows of the canvas.
    public var rowStarts: [Int] {
        var all = Set(canvas.entries.compactMap(\.start))
        for card in cards.values { if card.line != nil, let s = card.start { all.insert(s) } }
        return all.sorted()
    }

    /// The position a drop means. If two neighbours have no room between them, every position is renumbered first.
    public func resolve(_ drop: Drop) throws -> Int {
        switch drop {
        case .row(let start): return start
        case .between(let a, let b):
            if let n = PlanPositions.between(a, b) { return n }
            let map = try renumberAll()
            guard let n = PlanPositions.between(a.flatMap { map[$0] }, b.flatMap { map[$0] }) else { return PlanPositions.step }
            return n
        }
    }

    /// Positions become 100, 200, 300… in the same order; returns old → new.
    @discardableResult
    public func renumberAll() throws -> [Int: Int] {
        let map = PlanPositions.renumber(rowStarts)
        var entries = canvas.entries
        for i in entries.indices {
            if let s = entries[i].start, let n = map[s] { entries[i].start = n }
            if let e = entries[i].end, let n = map[e] { entries[i].end = n }
        }
        canvas.entries = entries
        try saveCanvas()
        for (id, card) in cards { if card.line != nil, let s = card.start, let n = map[s] { try updateCard(id) { $0.start = n } } }
        return map
    }
}
