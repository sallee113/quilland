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
