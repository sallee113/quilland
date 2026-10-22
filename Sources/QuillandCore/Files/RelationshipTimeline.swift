import Foundation

/// When the relationships of a book are active (quilland-change-events.md): a relationship starts at an event (the default event "Book starts" or any), may change
/// its fields in later events and ends at one. Everything is read from the events, in the order of the book (the event's first scene, then its order in the
/// scene; "Book starts" comes before everything). An event with no scene has no place in the book: it can neither start, change nor end a relationship.
public struct RelationshipTimeline {
    public enum Problem: Equatable, Sendable {
        /// The event has no scene, so it has no place in the book.
        case noScene
        /// The relationship cannot end before it starts, nor change before its start, nor after its end: the event that is in the way.
        case endsBeforeStart(eventTitle: String)
        case startsAfterEnd(eventTitle: String)
        case startsAfterChange(eventTitle: String)
        case endsBeforeChange(eventTitle: String)
        case endsWhereItStarts
    }

    public let events: EventStore
    private let position: [String: Int]
    private let titles: [String: String]

    public init(events: EventStore, sceneOrder: [String]) {
        self.events = events
        var position: [String: Int] = [:]
        var titles: [String: String] = [:]
        if let start = events.startEvent, let id = start.id { position[id] = -1; titles[id] = start.title ?? "" }
        let ordered = events.ordered(sceneOrder: sceneOrder)
        let scenes = Set(sceneOrder)
        for (i, e) in ordered.enumerated() {
            guard let id = e.id else { continue }
            titles[id] = e.title ?? ""
            // (An event linked to no scene of the book has no place in it.)
            if e.links.keys.contains(where: scenes.contains) { position[id] = i }
        }
        self.position = position
        self.titles = titles
    }

    /// Where an event stands in the book (nil: it has no scene).
    public func order(of event: String) -> Int? { position[event] }

    /// The events where a relationship starts, changes and ends (an event with no scene is left out of nothing: it is listed, and its marker is reported by `broken`).
    public func marks(of relationship: String) -> (start: String?, end: String?, changes: [String]) {
        var start: String?, end: String?
        var changes: [String] = []
        for e in events.allEvents {
            guard let id = e.id else { continue }
            switch e.relationships[relationship] {
            case "starts"?: if start == nil || (position[id] ?? Int.max) < (position[start!] ?? Int.max) { start = id }
            case "ends"?: if end == nil || (position[id] ?? Int.max) < (position[end!] ?? Int.max) { end = id }
            default: break
            }
            if e.effects[relationship] != nil { changes.append(id) }
        }
        return (start, end, changes.sorted { (position[$0] ?? Int.max) < (position[$1] ?? Int.max) })
    }

    /// Is the relationship active at an event: it started at or before it, and has not ended before it?
    public func isActive(_ relationship: String, at event: String) -> Bool {
        guard let here = position[event] else { return false }
        let m = marks(of: relationship)
        guard let s = m.start, let started = position[s], started <= here else { return false }
        if let e = m.end, let ended = position[e], ended < here { return false }
        return true
    }

    /// The relationships of `all` that are active at an event.
    public func active(at event: String, among all: [String]) -> [String] { all.filter { isActive($0, at: event) } }

    // MARK: What may be set

    private func title(_ id: String) -> String { titles[id] ?? "" }

    public func problem(starting relationship: String, at event: String) -> Problem? {
        guard let here = position[event] else { return .noScene }
        let m = marks(of: relationship)
        if let e = m.end, let p = position[e], p <= here { return .startsAfterEnd(eventTitle: title(e)) }
        if let c = m.changes.first(where: { (position[$0] ?? Int.max) < here }) { return .startsAfterChange(eventTitle: title(c)) }
        return nil
    }

    public func problem(ending relationship: String, at event: String) -> Problem? {
        guard let here = position[event] else { return .noScene }
        let m = marks(of: relationship)
        if let s = m.start, let p = position[s] {
            if s == event { return .endsWhereItStarts }
            if here < p { return .endsBeforeStart(eventTitle: title(s)) }
        }
        if let c = m.changes.last(where: { (position[$0] ?? -2) > here }) { return .endsBeforeChange(eventTitle: title(c)) }
        return nil
    }

    /// May the event change the relationship's fields (it is active there: started at or before it, not ended before it)?
    public func problem(changing relationship: String, at event: String) -> Problem? {
        guard let here = position[event] else { return .noScene }
        let m = marks(of: relationship)
        if let s = m.start, let p = position[s], here < p { return .endsBeforeStart(eventTitle: title(s)) }
        if let e = m.end, let p = position[e], here > p { return .startsAfterEnd(eventTitle: title(e)) }
        return nil
    }

    /// Relationships whose order is broken (a start, a change or an end out of order, or an event with no scene that has a mark): for a warning on the row.
    public func broken(_ relationship: String) -> [Problem] {
        let m = marks(of: relationship)
        var out: [Problem] = []
        for id in [m.start, m.end].compactMap({ $0 }) + m.changes where position[id] == nil { out.append(.noScene) }
        if let s = m.start, let e = m.end, let ps = position[s], let pe = position[e], pe < ps { out.append(.endsBeforeStart(eventTitle: title(e))) }
        for c in m.changes {
            guard let pc = position[c] else { continue }
            if let s = m.start, let ps = position[s], pc < ps { out.append(.startsAfterChange(eventTitle: title(c))) }
            if let e = m.end, let pe = position[e], pc > pe { out.append(.endsBeforeChange(eventTitle: title(c))) }
        }
        return out
    }
}
