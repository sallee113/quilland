import Foundation
import Testing
@testable import QuillandCore

@Suite("The plan: cards, lines and positions")
struct PlanTests {
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a position between two others, and renumbering when there is no room")
    func positions() {
        #expect(PlanPositions.between(nil, nil) == 100)
        #expect(PlanPositions.between(100, 300) == 200)
        #expect(PlanPositions.between(100, 101) == nil)
        #expect(PlanPositions.between(100, nil) == 200)
        #expect(PlanPositions.between(nil, 300) == 200)
        #expect(PlanPositions.between(nil, 100) == 50)
        #expect(PlanPositions.between(nil, 1) == nil, "no room before 1: renumber")
        #expect(PlanPositions.between(nil, 80) == 40)
        #expect(PlanPositions.renumber([300, 100, 100, 7]) == [7: 100, 100: 200, 300: 300])
    }

    @Test("a card is on a line or floating, never both; its other fields stay")
    func cardRecord() {
        var card = PlanCardRecord(object: ["id": .string("c1"), "title": .string("T"), "x_future": .object(["a": .int(1)])])
        card.float(x: 120, y: 40)
        #expect(card.isFloating && card.x == 120 && card.y == 40 && card.problems.isEmpty)
        card.place(onLine: "L1", start: 300)
        #expect(!card.isFloating && card.x == nil && card.y == nil && card.start == 300 && card.problems.isEmpty)
        card.float(x: 5, y: 6)
        #expect(card.line == nil && card.start == nil)
        #expect(card.object["x_future"] == .object(["a": .int(1)]), "unknown fields stay")
        card.spans = PlanCardRecord.Spans(from: 2, to: 3, unit: "chapters")
        #expect(card.spans == PlanCardRecord.Spans(from: 2, to: 3, unit: "chapters") && card.problems.isEmpty)
        card.spans = PlanCardRecord.Spans(from: 3, to: 2, unit: "pages")
        #expect(card.problems.count == 2)
        let both = PlanCardRecord(object: ["id": .string("c"), "title": .string("t"), "line": .string("L"), "start": .int(1), "x": .int(2)])
        #expect(both.problems.contains("a card is either on a line or floating, not both"))
        #expect(PlanCardRecord(object: ["id": .string("c"), "title": .string("t"), "line": .string("L")]).problems == ["\"line\" needs \"start\""])
    }

    @Test("lines, cards and events are written at once and read back the same")
    func persistence() throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try PlanStore(folder: dir)
        let captain = try store.addLine(name: "The captain", color: "teal")
        let girl = try store.addLine(name: "The girl", color: "pink")
        let a = try store.addCard(title: "Wakes on the yacht", text: "Storm warning.", line: captain, start: 100, color: "teal")
        let b = try store.addCard(title: "Sees it leave", line: girl, start: 200)
        let loose = try store.addCard(title: "What if it is stolen?", x: 600, y: 80)
        try store.placeEvent("e1", onLine: captain, start: 100)
        let again = try PlanStore(folder: dir)
        #expect(again.problems.isEmpty, "\(again.problems)")
        #expect(again.lines.map { $0.name } == ["The captain", "The girl"] && again.lines[0].color == "teal")
        #expect(again.cards.count == 3)
        #expect(again.cards[a]?.line == captain && again.cards[a]?.start == 100 && again.cards[a]?.text == "Storm warning.")
        #expect(again.cards[b]?.start == 200)
        #expect(again.cards[loose]?.isFloating == true && again.cards[loose]?.x == 600 && again.cards[loose]?.y == 80)
        #expect(again.entry(forEvent: "e1")?.start == 100)
        #expect(again.rowStarts == [100, 200])
        // The files are the ones of the format.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("plan/canvas.json").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("plan/cards/\(a).json").path))
        let text = try String(contentsOf: dir.appendingPathComponent("plan/cards/\(loose).json"), encoding: .utf8)
        #expect(!text.contains("\"line\"") && text.contains("\"x\": 600"))
    }

    @Test("dropping level with a row, between two rows, and with no room: renumbering keeps the order")
    func drops() throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try PlanStore(folder: dir)
        let line = try store.addLine(name: "L")
        let first = try store.addCard(title: "first", line: line, start: 100)
        let second = try store.addCard(title: "second", line: line, start: 101)
        let third = try store.addCard(title: "third", line: line, start: 300)
        #expect(try store.resolve(.row(100)) == 100)
        #expect(try store.resolve(.between(101, 300)) == 200)
        // 100 and 101 have no room between them: all are renumbered, and the new one still lands between.
        let n = try store.resolve(.between(100, 101))
        #expect(store.cards[first]?.start == 100 && store.cards[second]?.start == 200 && store.cards[third]?.start == 300)
        #expect(n == 150)
        #expect(try PlanStore(folder: dir).cards[second]?.start == 200, "the renumbering is on disk")
    }

    @Test("deleting a line: its cards float, its events go to the first other line")
    func deleteLine() throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try PlanStore(folder: dir)
        let one = try store.addLine(name: "one"), two = try store.addLine(name: "two")
        let card = try store.addCard(title: "c", line: two, start: 100)
        try store.placeEvent("ev", onLine: two, start: 200)
        try store.deleteLine(two, floatingAt: [card: (x: 300, y: 40)])
        #expect(store.lines.map { $0.id } == [one])
        #expect(store.cards[card]?.isFloating == true && store.cards[card]?.x == 300 && store.cards[card]?.y == 40)
        #expect(store.entry(forEvent: "ev")?.lane == one && store.entry(forEvent: "ev")?.start == 200)
        let again = try PlanStore(folder: dir)
        #expect(again.lines.count == 1 && again.cards[card]?.isFloating == true)
        try store.deleteCard(card)
        #expect(try PlanStore(folder: dir).cards.isEmpty)
    }

    @Test("a damaged card file is reported and the rest is read")
    func damaged() throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try PlanStore(folder: dir)
        _ = try store.addCard(title: "fine", x: 1, y: 2)
        try Data("{ nope".utf8).write(to: dir.appendingPathComponent("plan/cards/bad.json"))
        let again = try PlanStore(folder: dir)
        #expect(again.cards.count == 1 && again.problems.count == 1)
    }

    @Test("the plan can be put back as it was: a deleted card, a deleted line, a moved card")
    func undo() throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try PlanStore(folder: dir)
        let line = try store.addLine(name: "L")
        let card = try store.addCard(title: "keep me", text: "text", line: line, start: 100)
        let other = try store.addCard(title: "floater", x: 5, y: 6)
        let before = store.captureState()
        try store.deleteCard(card)
        try store.deleteLine(line, floatingAt: [:])
        try store.updateCard(other) { $0.place(onLine: "nowhere", start: 9) }
        #expect(store.cards.count == 1 && store.lines.isEmpty)
        try store.restore(before)
        let again = try PlanStore(folder: dir)
        #expect(again.cards.count == 2 && again.cards[card]?.title == "keep me" && again.cards[card]?.text == "text")
        #expect(again.lines.count == 1 && again.cards[other]?.isFloating == true)
        // And restoring removes what did not exist then.
        let extra = try store.addCard(title: "new", x: 1, y: 1)
        try store.restore(before)
        #expect(try PlanStore(folder: dir).cards[extra] == nil)
    }
}

@Suite("Room on a line")
struct PlanRoomTests {
    @Test("two cards, or two events, never share a line and a row; other lines and the other kind may")
    func noStacking() throws {
        let folder = try PlanTests.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plan = try PlanStore(folder: folder)
        let a = try plan.addLine(name: "A"), b = try plan.addLine(name: "B")
        // Two cards: the second asks for the first one's place and goes to a new row after it.
        let c1 = try plan.addCard(title: "один", line: a, start: 100)
        let c2 = try plan.addCard(title: "два", line: a, start: 300)
        let c3 = try plan.addCard(title: "три", line: b, start: 100)
        try plan.placeCard(c3, onLine: a, start: 100)
        #expect(plan.cards[c3]?.line == a && plan.cards[c3]?.start == 200, "between 100 and the next row, 300")
        #expect(plan.cards[c1]?.start == 100 && plan.cards[c2]?.start == 300, "nothing else moved")
        // The same row on another line is fine: it is the same moment.
        let c4 = try plan.addCard(title: "четыре", line: b, start: 300)
        try plan.placeCard(c4, onLine: b, start: 100)
        #expect(plan.cards[c4]?.start == 100 && plan.cards[c3]?.line == a, "a different line may use the row")
        // A card may stand where an event stands, and the other way round.
        let events = EventStore(book: folder)
        let e1 = try events.add(title: "событие 1"), e2 = try events.add(title: "событие 2")
        try plan.reload()
        try plan.placeEvent(e1, onLine: a, start: 100)
        #expect(plan.entry(forEvent: e1)?.start == 100, "an event under a card is two layers")
        try plan.placeEvent(e2, onLine: a, start: 100)
        #expect(plan.entry(forEvent: e2)?.start == 150 && plan.entry(forEvent: e1)?.start == 100, "a second event on the line goes to a new row just after the first (the next row is 200)")
        try plan.placeEvent(e2, onLine: a, start: 150)
        #expect(plan.entry(forEvent: e2)?.start == 150, "an item put where it already is stays")
        try plan.placeCard(c1, onLine: a, start: 100)
        #expect(plan.cards[c1]?.start == 100, "a card is not its own neighbour")
        // After the last row there is room too.
        let c6 = try plan.addCard(title: "шесть", line: b, start: 500)
        try plan.placeCard(c6, onLine: a, start: 300)
        #expect(plan.cards[c6]?.line == a && plan.cards[c6]?.start == 400, "between 300 and the next row, 500")
    }

    @Test("when there is no room between two rows everything is renumbered, and the item still gets its own row")
    func noRoom() throws {
        let folder = try PlanTests.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plan = try PlanStore(folder: folder)
        let a = try plan.addLine(name: "A")
        let first = try plan.addCard(title: "один", line: a, start: 100)
        let second = try plan.addCard(title: "два", line: a, start: 101)
        let third = try plan.addCard(title: "три", line: a, start: 500)
        try plan.placeCard(third, onLine: a, start: 100)
        let starts = [first, second, third].map { plan.cards[$0]?.start ?? -1 }
        #expect(Set(starts).count == 3 && starts[0] < starts[2] && starts[2] < starts[1], "three distinct rows in the order one, three, two")
    }
}
