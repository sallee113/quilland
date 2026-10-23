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
