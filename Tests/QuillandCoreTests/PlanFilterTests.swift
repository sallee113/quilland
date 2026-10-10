import Foundation
import Testing
@testable import QuillandCore

@Suite("The plan filter: working on a later part")
struct PlanFilterTests {
    @Test("events before the chosen scene are hidden, and the cards before them on the same line")
    func hides() throws {
        let book = try PlanTests.folder()
        let events = book.appendingPathComponent("bible/events")
        try FileManager.default.createDirectory(at: events, withIntermediateDirectories: true)
        func event(_ id: String, links: [String]) throws {
            let links = links.map { "\"\($0)\": \"x\"" }.joined(separator: ",")
            try Data("{\"id\":\"\(id)\",\"title\":\"\(id)\",\"links\":{\(links)}}".utf8).write(to: events.appendingPathComponent("\(id).json"))
        }
        try event("old", links: ["s1"])
        try event("spans", links: ["s2", "s4"])
        try event("new", links: ["s4"])
        try event("free", links: [])
        let store = try PlanStore(folder: book)
        let a = try store.addLine(name: "A"), b = try store.addLine(name: "B")
        try store.placeEvent("old", onLine: a, start: 300)
        try store.placeEvent("spans", onLine: a, start: 500)
        try store.placeEvent("new", onLine: a, start: 700)
        try store.placeEvent("free", onLine: b, start: 100)
        let early = try store.addCard(title: "early", line: a, start: 100)
        let level = try store.addCard(title: "level", line: a, start: 300)
        let between = try store.addCard(title: "between", line: a, start: 400)
        let late = try store.addCard(title: "late", line: a, start: 600)
        let other = try store.addCard(title: "other line", line: b, start: 100)
        let loose = try store.addCard(title: "loose", x: 5, y: 5)
        let order = ["s1", "s2", "s3", "s4"]

        let hidden = PlanFilter.hidden(store: store, sceneOrder: order, from: "s3")
        #expect(hidden == ["old", early, level])
        #expect(!hidden.contains(between) && !hidden.contains(late) && !hidden.contains(other) && !hidden.contains(loose))
        #expect(!hidden.contains("spans") && !hidden.contains("free"), "an event that reaches the chosen scene stays, and one linked to nothing too")
        #expect(PlanFilter.hidden(store: store, sceneOrder: order, from: "s1").isEmpty, "from the first scene nothing is hidden")
        #expect(PlanFilter.hidden(store: store, sceneOrder: order, from: "gone").isEmpty, "an unknown scene hides nothing")
    }

    @Test("where the plan starts is kept on this machine only, and can be cleared")
    func kept() throws {
        let book = try PlanTests.folder()
        var state = LocalBookState(planFrom: "chapter-2")
        state.save(book: book)
        #expect(LocalBookState.load(book: book).planFrom == "chapter-2")
        state.planFrom = nil
        state.save(book: book)
        #expect(LocalBookState.load(book: book).planFrom == nil)
    }

    @Test("a line can be recolored, described, moved and switched off; nothing on it is lost")
    func lines() throws {
        let store = try PlanStore(folder: try PlanTests.folder())
        let a = try store.addLine(name: "A", color: "teal"), b = try store.addLine(name: "B"), c = try store.addLine(name: "C")
        let card = try store.addCard(title: "on B", line: b, start: 100)
        try store.setLineColor(a, to: "red")
        try store.setLineDescription(b, to: "Short note")
        #expect(store.lines[0].color == "red" && store.lines[1].summary == "Short note")
        #expect(try store.moveLine(a, by: 1) && store.lines.compactMap(\.id) == [b, a, c])
        #expect(try store.moveLine(a, by: 1) && !(try store.moveLine(a, by: 1)), "at the end it stays")
        try store.setLine(b, visible: false)
        #expect(store.visibleLines.compactMap(\.id) == [c, a])
        #expect(store.cards[card]?.line == b, "a hidden line keeps its cards")
        try store.setLineDescription(b, to: "")
        let again = try PlanStore(folder: store.folder)
        #expect(again.lines.first { $0.id == b }?.isHidden == true && again.lines.first { $0.id == b }?.summary == nil, "kept on disk; an empty description is removed")
        try again.setLine(b, visible: true)
        #expect(again.lines.first { $0.id == b }?.object.bool("hidden") == nil, "shown again: the key is gone")
    }
}
