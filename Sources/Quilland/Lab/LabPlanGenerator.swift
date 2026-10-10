import Foundation
import QuillandCore

/// A made-up plan for trying the canvas: three plot lines, cards on them, three floating cards, and real events beside some of them.
enum LabPlanGenerator {
    static func generate(into folder: URL, cardsPerLine: Int = 5) throws {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("plan"))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("bible/events"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bible/events"), withIntermediateDirectories: true)
        let store = try PlanStore(folder: folder)
        let captain = try store.addLine(name: "The captain", color: "teal")
        let girl = try store.addLine(name: "The girl", color: "pink")
        let parents = try store.addLine(name: "The parents' secret", color: "green")
        let captainCards = ["Captain wakes on the yacht", "He leaves the bay", "The storm hits", "He finds the letter", "He turns back"]
        let girlCards = ["The girl sees the yacht leave", "She reads the old logbook", "She follows the coast"]
        let parentCards = ["The letter from his mother", "The harbour master's lie"]
        for i in 0..<min(cardsPerLine, captainCards.count) { _ = try store.addCard(title: captainCards[i], text: "What happens: step \(i + 1).", line: captain, start: (i + 1) * 100, color: "teal") }
        for (i, t) in girlCards.enumerated() { _ = try store.addCard(title: t, text: "From the pier.", line: girl, start: [100, 300, 450][i], color: "pink") }
        for (i, t) in parentCards.enumerated() { _ = try store.addCard(title: t, text: "Older than the book.", line: parents, start: [200, 500][i], color: "green") }
        _ = try store.addCard(title: "What if the yacht is stolen?", x: 760, y: 90, color: "amber")
        _ = try store.addCard(title: "Old harbour master", x: 780, y: 230, color: "purple")
        _ = try store.addCard(title: "A dog on board?", x: 800, y: 360, color: "blue")
        // Real events of the book, placed on the lines (some level with cards, some not).
        let events: [(String, String, Int)] = [("Анна находит ключ", captain, 100), ("Он уходит из бухты", captain, 200), ("Вера уходит с пирса", girl, 100),
                                               ("Письмо находит Анну", parents, 300), ("Шторм у берега", captain, 350)]
        for (title, line, start) in events {
            let id = UUID().uuidString.lowercased()
            try JSONWriter.data(["id": .string(id), "title": .string(title)]).write(to: folder.appendingPathComponent("bible/events/\(id).json"))
            try store.placeEvent(id, onLine: line, start: start)
        }
    }
}
