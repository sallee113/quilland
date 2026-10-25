import AppKit
import QuillandCore

/// The Events view is where it was left: the chosen event and the place in the list are kept for the book, and come back when the view is shown again.
extension AppSelfTest {
    func eventsPosition() -> Int32? {
        let main = self.main!
        let ids = (1...40).map { try! main.eventStore.add(title: String(format: "Поз-%02d", $0)) }
        main.reloadStores(); main.setMode(.events); spin(0.4)
        guard let ev = main.eventsView else { check(false, "the Events view shows"); return 1 }
        ev.reload(); ev.select(ids[30]); spin(0.2)
        ev.scrollList(to: 300); spin(0.2)
        let before = ev.listScroll
        check(before > 0, "the list can be scrolled", "\(before)")
        let state = main.localState()
        check(state.events?.selected == ids[30] && abs((state.events?.scroll ?? -1) - Double(before)) < 1, "the state kept for the book has the chosen event and the place in the list", "\(String(describing: state.events))")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-state-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        state.save(book: tmp)
        check(LocalBookState.load(book: tmp).events == state.events, "and it is written to the book's local state and read back")
        try? FileManager.default.removeItem(at: tmp)

        // Another view and back (the views are made again): the same event, the same place.
        main.setMode(.characters); spin(0.3)
        main.setMode(.events); spin(0.5)
        check(main.eventsView?.selected == ids[30] && abs((main.eventsView?.listScroll ?? -1) - before) < 2, "after another view, the Events view is as it was", "\(String(describing: main.eventsView?.selected)) \(String(describing: main.eventsView?.listScroll)) vs \(before)")

        for id in ids { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
