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
        check(state.views["events"]?.selected == ids[30] && abs((state.views["events"]?.scroll ?? -1) - Double(before)) < 1, "the state kept for the book has the chosen event and the place in the list", "\(state.views)")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-state-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        state.save(book: tmp)
        let loaded = LocalBookState.load(book: tmp).views, kept = state.views.filter { $0.value != ViewMemory() }
        check(Set(loaded.keys) == Set(kept.keys) && loaded["events"]?.selected == kept["events"]?.selected && abs((loaded["events"]?.scroll ?? -9) - (kept["events"]?.scroll ?? 9)) <= 1, "and it is written to the book's local state and read back")
        try? FileManager.default.removeItem(at: tmp)

        // Another view and back (the views are made again): the same event, the same place.
        main.setMode(.characters); spin(0.3)
        main.setMode(.events); spin(0.5)
        check(main.eventsView?.selected == ids[30] && abs((main.eventsView?.listScroll ?? -1) - before) < 2, "after another view, the Events view is as it was", "\(String(describing: main.eventsView?.selected)) \(String(describing: main.eventsView?.listScroll)) vs \(before)")

        // Filters too: the word filter and the "Filter by…" chips come back, in each list view, with the chosen item.
        let who = try! main.characters.add(name: "Пам-Анна")
        for e in [ids[24], ids[25]] { try! main.eventStore.update(e) { $0.characters = [who: ""] } }
        main.reloadStores(); main.setMode(.events); spin(0.3)
        guard let ev2 = main.eventsView else { check(false, "the Events view shows again"); return 1 }
        ev2.relationFilter.set(.character(who)); spin(0.2)
        ev2.filterField.stringValue = "Поз-2"
        ev2.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: ev2.filterField)); spin(0.2)
        ev2.select(ids[24]); spin(0.1)
        ev2.filterField.stringValue = "Поз-2"; ev2.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: ev2.filterField)); spin(0.2)
        check(ev2.shownTitles.sorted() == ["Поз-25", "Поз-26"], "the events are filtered by a word and a person", "\(ev2.shownTitles)")
        main.setMode(.characters); spin(0.3)
        check(main.charactersView != nil, "another view is shown")
        main.setMode(.events); spin(0.5)
        let back = main.eventsView
        check(back?.filterField.stringValue == "Поз-2" && back?.relationFilter.memory == ["character:" + who] && back?.shownTitles.sorted() == ["Поз-25", "Поз-26"], "the Events view keeps its word filter and its chips when another view comes and goes", "\(String(describing: back?.filterField.stringValue)) \(String(describing: back?.relationFilter.memory)) \(String(describing: back?.shownTitles))")
        check(main.localState().views["events"]?.filter == "Поз-2" && main.localState().views["events"]?.anchors == ["character:" + who], "and they are in the state kept for the book")

        main.setMode(.characters); spin(0.3)
        guard let cv = main.charactersView else { check(false, "the Characters view shows"); return 1 }
        cv.filterField.stringValue = "Пам"; cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField)); spin(0.2)
        cv.select(who); spin(0.1)
        main.setMode(.events); spin(0.3)
        main.setMode(.characters); spin(0.4)
        check(main.charactersView?.filterField.stringValue == "Пам" && main.charactersView?.selected == who && main.charactersView?.shownNames == ["Пам-Анна"], "the Characters view comes back with its filter and its character", "\(String(describing: main.charactersView?.filterField.stringValue)) \(String(describing: main.charactersView?.shownNames))")

        main.setMode(.world); spin(0.3)
        guard let wv = main.worldView else { check(false, "the World view shows"); return 1 }
        wv.filterField.stringValue = "Пам"; wv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: wv.filterField)); spin(0.2)
        main.setMode(.events); spin(0.3)
        main.setMode(.world); spin(0.4)
        check(main.worldView?.filterField.stringValue == "Пам", "the World view comes back with its filter")
        main.worldView?.filterField.stringValue = ""; main.worldView?.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: main.worldView?.filterField))

        main.setMode(.research); spin(0.3)
        main.researchView?.filterField.stringValue = "ничего"
        main.researchView?.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: main.researchView?.filterField)); spin(0.2)
        main.setMode(.events); spin(0.3)
        main.setMode(.research); spin(0.4)
        check(main.researchView?.filterField.stringValue == "ничего", "the Research view comes back with its filter")
        main.researchView?.filterField.stringValue = ""; main.researchView?.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: main.researchView?.filterField))
        // The Plan keeps its zoom; the Outline keeps what was folded.
        main.setMode(.plan); spin(0.4)
        main.planController?.scrollView.magnification = 1.5
        main.setMode(.events); spin(0.3)
        main.setMode(.plan); spin(0.5)
        check(abs((main.planController?.scrollView.magnification ?? 0) - 1.5) < 0.01, "the Plan comes back at its zoom", "\(String(describing: main.planController?.scrollView.magnification))")
        main.setMode(.outline); spin(0.4)
        let allRows = main.tree?.visibleTitles.count ?? 0
        main.tree?.foldAll(); spin(0.2)
        let folded = main.tree?.visibleTitles.count ?? 0
        main.setMode(.events); spin(0.3)
        main.setMode(.outline); spin(0.5)
        check(folded < allRows && main.tree?.visibleTitles.count == folded, "the Outline comes back with the same parts and chapters folded", "\(allRows) \(folded) \(String(describing: main.tree?.visibleTitles.count))")
        main.tree?.foldAll(); spin(0.2)   // (open again)
        main.setMode(.events); spin(0.2)
        main.eventsView?.relationFilter.clear(); main.eventsView?.filterField.stringValue = ""
        main.eventsView.map { $0.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: $0.filterField)) }
        try? BookIntegrity.deleteCharacter(who, book: main.folder, snapshot: false)
        for id in ids { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
