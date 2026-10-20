import Foundation
import Testing
@testable import QuillandCore

@Suite("Events")
struct EventStoreTests {
    @Test("an event is made, edited, ordered by the book, and keeps what the app does not know")
    func basics() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let scenes = try BookStructure.load(folder: book).scenes.map(\.id)
        let store = EventStore(book: book)
        let late = try store.add(title: "Конец")
        let early = try store.add(title: "Начало")
        let loose = try store.add(title: "Без сцены")
        try store.update(early) { $0.date = "весна, год 214"; $0.links = [scenes[0]: "Она выходит из корабля."]; $0.places = ["p1": "Посадочная площадка."]; $0.notes = ["не знает"] }
        let s2 = try BookEditorTests.editor(book).add(.scene, relativeTo: scenes[0], title: "Вторая")
        try store.update(late) { $0.links = [s2: "Прощание."] }
        let order = [scenes[0], s2]
        #expect(store.ordered(sceneOrder: order).compactMap(\.id) == [early, late, loose])
        // A hand-written field survives the next edit.
        let file = book.appendingPathComponent("bible/events/\(early).json")
        var raw = try JSONParser.parseObject(Data(contentsOf: file))
        raw["future"] = .string("kept")
        try AtomicFile.write(JSONWriter.data(raw), to: file)
        let again = EventStore(book: book)
        try again.update(early) { $0.date = "осень" }
        #expect(try JSONParser.parseObject(Data(contentsOf: file)).string("future") == "kept")
        let back = EventStore(book: book)
        #expect(back.events.count == 3 && back.problems.isEmpty && back.event(early)?.date == "осень" && back.event(early)?.places["p1"] == "Посадочная площадка.")
        try back.setText(early, "Описание.")
        #expect(EventStore(book: book).text(early) == "Описание.")
    }

    @Test("deleting moves the files to the trash; an event can be taken off the canvas")
    func deleting() throws {
        let (parent, book) = try BookEditorTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = EventStore(book: book)
        let id = try store.add(title: "Событие")
        try store.setText(id, "Текст.")
        let plan = try PlanStore(folder: book)
        let line = try plan.addLine(name: "Линия")
        try plan.placeEvent(id, onLine: line, start: 100)
        #expect(try PlanStore(folder: book).entry(forEvent: id) != nil)
        try plan.removeEntry(forEvent: id)
        #expect(try PlanStore(folder: book).entry(forEvent: id) == nil)
        try store.delete(id)
        #expect(EventStore(book: book).events.isEmpty)
        let trash = book.appendingPathComponent(".quilland/trash")
        let stamps = try FileManager.default.contentsOfDirectory(atPath: trash.path)
        let files = try FileManager.default.contentsOfDirectory(atPath: trash.appendingPathComponent(stamps[0] + "/bible/events").path)
        #expect(files.sorted() == ["\(id).json", "\(id).md"])
    }
}

@Suite("Colours of events on the Plan")
struct EventColorTests {
    @Test("a colour is kept in the event's own file with everything else there, read again, and put back or taken away with the plan's state")
    func colors() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let events = EventStore(book: book)
        let a = try events.add(title: "Приезд"), b = try events.add(title: "Отъезд")
        try events.update(a) { $0.date = "весна"; $0.notes = ["важно"] }
        let plan = try PlanStore(folder: book)
        #expect(plan.eventColors.isEmpty)
        let before = plan.captureState()
        try plan.setEventColor(a, to: "teal")
        try plan.setEventColor(b, to: "red")
        #expect(plan.eventColors == [a: "teal", b: "red"])
        // Read again, with the rest of the event untouched.
        let again = try PlanStore(folder: book)
        #expect(again.eventColors == [a: "teal", b: "red"])
        let reloaded = EventStore(book: book)
        #expect(reloaded.event(a)?.color == "teal" && reloaded.event(a)?.date == "весна" && reloaded.event(a)?.notes == ["важно"])
        // Undo: the state before brings back no colours; the one after brings them again.
        let after = plan.captureState()
        try plan.restore(before)
        #expect(plan.eventColors.isEmpty && EventStore(book: book).event(a)?.color == nil && EventStore(book: book).event(a)?.date == "весна")
        try plan.restore(after)
        #expect(plan.eventColors == [a: "teal", b: "red"])
        try plan.setEventColor(a, to: nil)
        #expect(plan.eventColors == [b: "red"] && EventStore(book: book).event(a)?.color == nil)
        // An event that does not exist is left alone.
        try plan.setEventColor("no-such-event", to: "pink")
        #expect(plan.eventColors == [b: "red"])
    }
}

@Suite("The order of events")
struct EventOrderTests {
    static func book() throws -> (URL, URL) {
        let parent = try NewBookTests.folder()
        return (parent, try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent)))
    }

    @Test("the scenes decide, and within a scene the author's order, then the title; only the scene's events are numbered")
    func withinAScene() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = EventStore(book: book)
        let a = try store.add(title: "Арест"), b = try store.add(title: "Бегство"), c = try store.add(title: "Встреча"), d = try store.add(title: "Годы спустя")
        let scenes = ["s1", "s2", "s3"]
        try store.update(a) { $0.links = ["s1": ""] }
        try store.update(b) { $0.links = ["s1": ""] }
        try store.update(c) { $0.links = ["s2": ""] }
        #expect(store.ordered(sceneOrder: scenes).compactMap(\.title) == ["Арест", "Бегство", "Встреча", "Годы спустя"], "by title inside a scene until put in order; no scene last")
        let groups = store.groups(sceneOrder: scenes)
        #expect(groups.map(\.scene) == ["s1", "s2", nil] && groups[0].events.count == 2)
        // Put the two events of the first scene in the other order.
        try store.reorder([b, a])
        #expect(store.ordered(sceneOrder: scenes).compactMap(\.title) == ["Бегство", "Арест", "Встреча", "Годы спустя"])
        #expect(EventStore(book: book).ordered(sceneOrder: scenes).compactMap(\.title) == ["Бегство", "Арест", "Встреча", "Годы спустя"], "and it is on disk")
        #expect(store.event(b)?.order == 100 && store.event(a)?.order == 200, "the two were numbered in the new order")
        #expect(store.event(c)?.order == nil && store.event(d)?.order == nil, "the events of other scenes were not touched")
        // Back again: they swap the numbers they have, and nothing else is written.
        try store.reorder([a, b])
        #expect(store.event(a)?.order == 100 && store.event(b)?.order == 200)
        #expect(store.ordered(sceneOrder: scenes).compactMap(\.title) == ["Арест", "Бегство", "Встреча", "Годы спустя"])
        // A new event has no number: last in its group.
        let e = try store.add(title: "Бой")
        try store.update(e) { $0.links = ["s1": ""] }
        #expect(store.ordered(sceneOrder: scenes).compactMap(\.title) == ["Арест", "Бегство", "Бой", "Встреча", "Годы спустя"])
        // Put in order again with the new one among them: all three are numbered anew.
        try store.reorder([e, a, b])
        #expect(store.ordered(sceneOrder: scenes).compactMap(\.title) == ["Бой", "Арест", "Бегство", "Встреча", "Годы спустя"] && store.event(e)?.order == 100)
        // An event that does not exist is left out.
        try store.reorder(["no-such-event", b, a])
        #expect(store.ordered(sceneOrder: scenes).compactMap(\.title) == ["Бой", "Бегство", "Арест", "Встреча", "Годы спустя"] && store.events.count == 5)
    }
}
