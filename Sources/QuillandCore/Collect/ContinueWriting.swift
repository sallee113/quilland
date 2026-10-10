import Foundation

/// What Continue Writing sent, in a line for the status bar ("scene text, 3 cards, the plan: 2,300 of 40,960 tokens").
public struct ContinueSummary: Equatable, Sendable {
    public var textCharacters: Int
    public var cards: Int
    public var hasPlan: Bool
    public var hasDirection: Bool
    public var tokens: Int
    public var context: Int
}

public enum ContinuePrompt {
    /// About how many tokens a text takes (Russian and English: two to three characters each).
    public static func tokens(_ characters: Int) -> Int { Int((Double(characters) / 2.4).rounded(.up)) }

    public static func system(language: String) -> String {
        AIPrompts.resolve("continue", language: language, builtIn: builtIn(CollectPrompt.languageName(language) ?? "the language of the text"))
    }

    static func builtIn(_ name: String) -> String {
        """
        You are a co-author continuing a novel. Write the continuation of the text, directly after its last word.
        Write in \(name), in the same style, tense and point of view as the text before. Plain prose only: no markup, no headings, no quotation marks around the whole, no comments.
        Write ONE paragraph and stop at its end. If the text already ends a paragraph, begin the next one. Do not end or summarize the scene, and do not start a new scene.
        Do not bring in new named characters unless the direction asks for them. Stay consistent with the reference material, if there is any.
        """
    }

    /// The request. `before` is the text up to the cursor (the oldest part is cut to fit), `after` what follows the cursor (a little of it is shown, so that the model
    /// does not repeat it).
    public static func messages(before: String, after: String, language: String, synopsis: String, note: String, sources: [ConsistencySource],
                                planCards: [(title: String, text: String)], direction: String?, context: Int) -> (messages: [ChatMessage], summary: ContinueSummary) {
        let reserve = 1100
        let available = max(1500, Int(Double(max(2048, context) - reserve) * 2.4))
        let textBudget = min(14000, max(1200, available * 6 / 10))
        let sourceBudget = min(7000, max(0, available - textBudget - 600))
        var chosen = String(before.suffix(textBudget))
        if chosen.count < before.count, let firstBreak = chosen.firstIndex(of: "\n") { chosen = String(chosen[chosen.index(after: firstBreak)...]) }

        var reference = ""
        var cards = 0
        var used = 0
        func add(_ line: String) -> Bool { guard used + line.count <= sourceBudget else { return false }; used += line.count; reference += line + "\n"; return true }
        if !synopsis.isEmpty { _ = add("This scene, in short: \(synopsis)") }
        if !note.isEmpty { _ = add("Author's note on this scene: \(note)") }
        for s in sources where s.kind != .scene { if add("[\(s.title)] \(s.text)") { cards += 1 } }
        let earlier = sources.filter { $0.kind == .scene }.reversed()
        if !earlier.isEmpty {
            var lines: [String] = []
            for s in earlier { lines.append("“\(s.title)”: \(s.text)") }
            _ = add("Earlier scenes: " + lines.joined(separator: " "))
        }
        var plan = false
        for card in planCards { if add("Plan for this part: \(card.title). \(card.text)") { plan = true } }

        var user = ""
        if !reference.isEmpty { user += "Reference material:\n\(reference)\n" }
        if let direction, !direction.trimmingCharacters(in: .whitespaces).isEmpty { user += "Direction for the continuation: \(direction.trimmingCharacters(in: .whitespaces))\n(The paragraph you write must start moving the story this way.)\n\n" }
        user += "Text so far (continue after its last word):\n\"\"\"\n\(chosen)"
        user += "\"\"\"\n"
        let following = after.trimmingCharacters(in: .whitespacesAndNewlines)
        if !following.isEmpty { user += "\nThe text that already follows the place where you continue (do not repeat it): \(String(following.prefix(300)))\n" }
        let summary = ContinueSummary(textCharacters: chosen.count, cards: cards, hasPlan: plan, hasDirection: direction?.isEmpty == false,
                                      tokens: tokens(system(language: language).count + user.count), context: context)
        return ([ChatMessage("system", system(language: language)), ChatMessage("user", user)], summary)
    }
}

/// Cleans the model's continuation as it streams in: no leading blank, a single newline between paragraphs, no markup, a space after the text before when the
/// continuation goes on in the same paragraph.
public struct ContinuationFilter {
    private var atStart = true
    private var lastWasNewline = false
    private let before: String
    /// One paragraph is asked for: the first line break after some text ends it, and what comes after is not shown.
    public private(set) var isFinished = false

    public init(before: String) { self.before = before }

    public mutating func feed(_ piece: String) -> String {
        var out = ""
        for ch in piece {
            if isFinished { break }
            if ch == "*" { continue }
            if ch == "\n" || ch == "\r" {
                if atStart { continue }
                isFinished = true
                break
            }
            if atStart {
                if ch == " " || ch == "\t" { continue }
                atStart = false
                let last = before.last
                if let last, last != "\n", !last.isWhitespace { out.append(" ") }
            }
            lastWasNewline = false
            out.append(ch)
        }
        return out
    }
}
