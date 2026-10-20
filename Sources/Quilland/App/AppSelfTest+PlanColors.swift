import AppKit
import QuillandCore

/// Colours on the Plan: the events' files are read again by the book after a change (the Events view must not write the old colour back over it).
extension AppSelfTest {
    func planColors() -> Int32? {
        let main = self.main!
        let event = try! main.eventStore.add(title: "Событие для цвета")
        app.modePlan(); spin(0.5)
        guard let plan = main.planController else { check(false, "the Plan shows"); return 1 }
        let line = plan.store.lines.first?.id ?? (try! plan.store.addLine(name: "Линия"))
        try! plan.store.placeEvent(event, onLine: line, start: 100)
        try! plan.store.reload()
        plan.reload(); spin(0.3)
        plan.setMode(.events)
        guard let view = plan.canvas.itemViews.first(where: { $0.item.id == event }) else { check(false, "the event is on the canvas"); return 1 }
        plan.click(view, extending: false)
        plan.setColor("purple", for: plan.selection); spin(0.3)
        check(main.eventStore.event(event)?.color == "purple", "the book's event store knows the colour at once", "\(String(describing: main.eventStore.event(event)?.color))")
        // The Events view saves its own edits without losing the colour.
        try? main.eventStore.update(event) { $0.date = "осень" }
        check(EventStore(book: main.folder).event(event)?.color == "purple" && EventStore(book: main.folder).event(event)?.date == "осень", "and a later edit of the event keeps the colour")
        plan.undo(); spin(0.3)
        check(main.eventStore.event(event)?.color == nil && EventStore(book: main.folder).event(event)?.date == "осень", "Undo on the Plan takes the colour back and keeps the edit")
        try? plan.store.removeEntry(forEvent: event)
        try? main.eventStore.delete(event)
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
