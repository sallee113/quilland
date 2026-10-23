import Foundation
import QuillandCore

/// The words of the marks on the graph: what an event changes, and the life of a relationship.
enum GraphTexts {
    private static func word(_ field: EffectField, main: Bool?) -> String {
        switch field {
        case .aliases: return L("also called")
        case .main: return main == true ? L("main: on") : L("main: off")
        case .profile: return L("profile")
        case .worlds: return L("worlds")
        case .description: return L("description")
        case .kind: return L("kind")
        }
    }

    /// "Вилли: profile, main: on · Усадьба: description", one line for each thing an event changes.
    static func summary(_ changes: [GraphChange]) -> String {
        changes.map { c in
            var parts = c.fields.map { word($0, main: c.main) }
            if let marker = c.marker { parts.append(marker == "starts" ? L("starts here") : L("ends here")) }
            return c.target + ": " + parts.joined(separator: ", ")
        }.joined(separator: "\n")
    }

    /// What is out of order in a relationship, as a warning (the Events view's wording says what a move *would* do; this says what *is*).
    static func warning(_ problem: RelationshipTimeline.Problem) -> String {
        switch problem {
        case .noScene: return L("A start, change or end of it is in an event with no scene.")
        case .endsBeforeStart(let t): return L("It ends (in “{title}”) before it starts.", ["title": t])
        case .startsAfterEnd(let t): return L("It starts after it ends (in “{title}”).", ["title": t])
        case .startsAfterChange(let t): return L("A change in “{title}” comes before it starts.", ["title": t])
        case .endsBeforeChange(let t): return L("A change in “{title}” comes after it ends.", ["title": t])
        case .endsWhereItStarts: return L("It ends in the event where it starts.")
        }
    }

    static func eventWarningLines(_ problems: [RelationshipTimeline.Problem]) -> String { problems.map { "⚠ " + warning($0) }.joined(separator: "\n") }

    static let eventWarning = L("This event changes something but has no scene, so its changes do not apply.")

    /// "friends → enemies · from “A” to “B”" for each relationship a line stands for (only what has something to tell).
    static func periods(_ periods: [GraphPeriod]) -> String {
        periods.compactMap { p in
            guard p.kinds.count > 1 || p.from != nil || p.to != nil else { return nil }
            var line = p.kinds.filter { !$0.isEmpty }.joined(separator: " → ")
            if let from = p.from { line += " · " + L("from “{event}”", ["event": from]) }
            if let to = p.to { line += (p.from == nil ? " · " : " ") + L("to “{event}”", ["event": to]) }
            return line
        }.joined(separator: "\n")
    }
}
