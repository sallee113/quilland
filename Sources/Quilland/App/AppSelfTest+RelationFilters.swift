import AppKit
import QuillandCore

/// "Filter by…" in the Characters, World and Events views: a section, an event, a character or a place, in either direction of a link.
extension AppSelfTest {
    func relationFilters() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes.map(\.id)
        guard scenes.count >= 3 else { check(false, "the book has three scenes for the checks"); return 1 }
        let (first, last) = (scenes[0], scenes[scenes.count - 1])
        setText(first, "Фёкла вошла в комнату.")
        setText(last, "Борислав жил в Сорренто.")
        let fekla = try! main.characters.add(name: "Фёкла"), borislav = try! main.characters.add(name: "Борислав")
        let world = main.worlds.worlds[0].id!
        let sorrento = try! main.worlds.addEntry(name: "Сорренто", world: world), elsewhere = try! main.worlds.addEntry(name: "Нигдевия", world: world)
        let arrival = try! main.eventStore.add(title: "Фильтр: приезд"), farewell = try! main.eventStore.add(title: "Фильтр: прощание")
        try! main.eventStore.update(arrival) { $0.links = [first: ""] }
        try! main.eventStore.update(farewell) { $0.links = [last: ""]; $0.places = [sorrento: "здесь"] }
        // The link between a character and an event is kept in the event's own file.
        try! main.eventStore.update(farewell) { $0.characters = [borislav: "уезжает"] }

        // Characters.
        app.modeCharacters(); spin(0.4)
        guard let cv = main.charactersView else { check(false, "the Characters view shows"); return 1 }
        cv.reload()
        check(cv.shownNames.contains("Фёкла") && cv.shownNames.contains("Борислав"), "with no filter all the characters are listed")
        check(cv.relationFilter.menuKinds == ["Section", "Event", "Place"], "the Characters view offers a section, an event or a place", "\(cv.relationFilter.menuKinds)")
        cv.view.window?.layoutIfNeeded(); cv.view.layoutSubtreeIfNeeded()
        let bar = cv.relationFilter.view.frame
        check(bar.width > 60 && bar.height > 12 && bar.minY > cv.filterField.frame.minY - 200, "the filter row has room under the word filter", "\(bar)")
        cv.relationFilter.set(.section(first)); spin(0.2)
        check(cv.shownNames.contains("Фёкла") && !cv.shownNames.contains("Борислав"), "filtered by a scene: the characters in it", "\(cv.shownNames)")
        check(cv.relationFilter.chipTexts.count == 1 && cv.relationFilter.noteText.contains("of"), "the filter is shown as a chip, with how many of how many", "\(cv.relationFilter.chipTexts) \(cv.relationFilter.noteText)")
        cv.relationFilter.set(.event(farewell)); spin(0.2)
        check(cv.shownNames.isEmpty || !cv.shownNames.contains("Фёкла"), "two filters must both match: in that scene AND in that event")
        cv.relationFilter.remove(.section(first)); spin(0.2)
        check(cv.shownNames == ["Борислав"], "filtered by an event: the characters the event lists", "\(cv.shownNames)")
        cv.relationFilter.set(.place(sorrento)); spin(0.2)
        check(cv.shownNames == ["Борислав"], "and by a place: the characters in the scenes where it is", "\(cv.shownNames)")
        cv.filterField.stringValue = "бор"
        cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField))
        check(cv.shownNames == ["Борислав"], "the word filter works on top of the others")
        cv.filterField.stringValue = "фёк"
        cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField))
        check(cv.shownNames.isEmpty, "and a word that matches nothing in them shows nothing")
        cv.filterField.stringValue = ""
        cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField))
        // Sharing a scene with a place is not having been there: only the events held there count.
        try! main.worlds.updateEntry(elsewhere) { $0.links = [first: ""] }
        cv.relationFilter.set(.place(elsewhere)); spin(0.2)
        check(cv.shownNames.isEmpty, "a character who is in a scene where the place has a line is not at the place", "\(cv.shownNames)")
        check(cv.relationFilter.noteText == "No character is linked to an event held at this place.", "and the list says why it is empty", cv.relationFilter.noteText)
        check(cv.relationFilter.chipTexts.count == 2 || cv.relationFilter.chipTexts.count == 1, "the chip is there to take off")
        cv.relationFilter.clear(); spin(0.2)
        check(cv.shownNames.contains("Фёкла") && cv.shownNames.contains("Борислав") && cv.relationFilter.chipTexts.isEmpty, "taking the filters off lists everyone again")

        // Events.
        app.modeEvents(); spin(0.4)
        guard let ev = main.eventsView else { check(false, "the Events view shows"); return 1 }
        ev.reload()
        check(ev.relationFilter.menuKinds == ["Section", "Character", "Place"], "the Events view offers a section, a character or a place")
        ev.relationFilter.set(.character(borislav)); spin(0.2)
        check(ev.shownTitles == ["Фильтр: прощание"], "the events of a character, though the event's own file does not name him", "\(ev.shownTitles)")
        ev.relationFilter.clear()
        ev.relationFilter.set(.place(sorrento)); spin(0.2)
        check(ev.shownTitles == ["Фильтр: прощание"], "the events at a place")
        ev.relationFilter.clear()
        ev.relationFilter.set(.section(first)); spin(0.2)
        check(ev.shownTitles.contains("Фильтр: приезд") && !ev.shownTitles.contains("Фильтр: прощание"), "the events of a section")
        ev.relationFilter.clear()

        // World.
        app.modeWorld(); spin(0.4)
        guard let wv = main.worldView else { check(false, "the World view shows"); return 1 }
        wv.reload()
        check(wv.relationFilter.menuKinds == ["Section", "Event", "Character"], "the World view offers a section, an event or a character")
        wv.relationFilter.set(.event(farewell)); spin(0.2)
        check(wv.visibleTitles.contains { $0.trimmingCharacters(in: .whitespaces) == "Сорренто" } && !wv.visibleTitles.contains { $0.contains("Нигдевия") }, "the places of an event (the world stays as their container)", "\(wv.visibleTitles)")
        wv.relationFilter.clear()
        wv.relationFilter.set(.character(borislav)); spin(0.2)
        check(wv.visibleTitles.contains { $0.contains("Сорренто") } && !wv.visibleTitles.contains { $0.contains("Нигдевия") }, "the places of a character, by the scenes they share")
        wv.relationFilter.clear(); spin(0.2)
        check(wv.visibleTitles.contains { $0.contains("Нигдевия") }, "and everything again without a filter")

        // A filter whose item is deleted is taken off by itself.
        app.modeEvents(); spin(0.3)
        main.eventsView?.relationFilter.set(.character(fekla))
        try? main.characters.delete(fekla)
        main.eventsView?.reload(); spin(0.2)
        check(main.eventsView?.relationFilter.chipTexts.isEmpty == true, "a filter on something that was deleted goes away")

        for id in [borislav] { try? main.characters.delete(id) }
        for id in [arrival, farewell] { try? main.eventStore.delete(id) }
        for id in [sorrento, elsewhere] { try? main.worlds.deleteEntry(id) }
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
