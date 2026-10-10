import Foundation

/// Positions on the Plan canvas are whole numbers on an abstract axis (`start`), as on the timeline. Nothing here is a date.
/// A card or an event dropped between two others gets a number between theirs; when two neighbours have no room left, everything is renumbered.
public enum PlanPositions {
    public static let step = 100

    /// A number strictly between `a` and `b` (either may be missing: before the first, after the last), or nil when there is no room.
    public static func between(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case (nil, nil): return step
        case (let a?, nil): return a + step
        case (nil, let b?): return b > step ? b - step : (b >= 2 ? b / 2 : nil)
        case (let a?, let b?): return b - a >= 2 ? a + (b - a) / 2 : nil
        }
    }

    /// The old distinct positions in order, mapped to 100, 200, 300…
    public static func renumber(_ starts: [Int]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        for (i, s) in Set(starts).sorted().enumerated() { map[s] = (i + 1) * step }
        return map
    }
}
