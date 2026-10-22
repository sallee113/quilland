import AppKit
import QuillandCore

/// What events change, and the relationships, in the Events view: the changes button and window, the relationship rows and menus, "Book starts", the Δ.
extension AppSelfTest {
    func eventChanges() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes.map(\.id)
        guard scenes.count >= 3 else { check(false, "three scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "Изм-Анна"), lev = try! main.characters.add(name: "Изм-Лев")
        try! main.characters.setProfile(anna, "Тихая девочка.")
        let world = main.worlds.worlds[0].id!
        let place = try! main.worlds.addEntry(name: "Изм-Усадьба", world: world)
        try! main.worlds.setText(place, "Цветущий дом.")
        let e1 = try! main.eventStore.add(title: "Изм: первое"), e2 = try! main.eventStore.add(title: "Изм: второе"), loose = try! main.eventStore.add(title: "Изм: без сцены")
        try! main.eventStore.update(e1) { $0.links = [scenes[0]: ""]; $0.characters = [anna: "", lev: ""]; $0.places = [place: ""] }
        try! main.eventStore.update(e2) { $0.links = [scenes[1]: ""]; $0.characters = [anna: ""] }
        try! main.eventStore.update(loose) { $0.characters = [anna: ""] }
        let startID = main.eventStore.startEvent!.id!

        main.setMode(.events); spin(0.5)
        guard let ev = main.eventsView else { check(false, "the Events view shows"); return 1 }
        ev.reload(); spin(0.2)

        // "Book starts".
        ev.select(startID); spin(0.3)
        check(ev.listTitles.first == "— At the start of the book" && ev.shownTitles.allSatisfy { $0 != "Начало книги" }, "Book starts is at the top under its own heading, and is not one of the events of the story", "\(ev.listTitles)")
        check(ev.deleteHidden && ev.addMenuTitles == ["Add…", "Relationship"] && ev.connections.allSatisfy { $0.kind == .relationship }, "it cannot be deleted, and it holds relationships only", "\(ev.addMenuTitles)")

        // The changes window: a character's profile.
        ev.select(e1); spin(0.3)
        let annaRow = ev.connections.firstIndex { $0.kind == .character && $0.refID == anna }!
        check(ev.connections[annaRow].changes == 0 && ev.deltaShown(forEvent: e1) == false, "no change yet: the button is hollow and the event has no Δ")
        ev.changeTapped(row: annaRow); spin(0.3)
        guard let w = ev.changesWindow(forRow: annaRow) else { check(false, "the changes window opens"); return 1 }
        check(w.text(.profile) == "" && w.ghost(.profile) == "Тихая девочка." && w.window?.title.contains("Изм-Анна") == true && w.window?.title.contains("Изм: первое") == true, "the field is empty and shows the card's profile in grey", w.window?.title ?? "")
        w.pressTab(in: .profile)
        check(w.text(.profile) == "Тихая девочка.", "Tab accepts the ghost")
        w.setText(.profile, "Тихая девочка, теперь капитан.")
        w.pressTab(in: .aliases)
        check(w.text(.aliases) == "" && w.ghost(.aliases) == "", "Tab does not accept the ghost of the names")
        w.setText(.aliases, "Вильгельм, Билл")
        w.setMain(true)
        w.window?.close(); spin(0.3)
        let saved = main.eventStore.event(e1)
        check(saved?.effectText(.profile, of: anna) == "Тихая девочка, теперь капитан." && saved?.effectList(.aliases, of: anna) == ["Вильгельм", "Билл"] && saved?.effectFlag(of: anna) == true, "closing saves what was typed", "\(String(describing: saved?.effect(of: anna)))")
        check(main.characters.profile(anna) == "Тихая девочка." && main.characters.character(anna)?.aliases.isEmpty == true, "the card itself is not changed")
        let annaRow2 = ev.connections.firstIndex { $0.kind == .character && $0.refID == anna }!
        check(ev.connections[annaRow2].changes == 3 && ev.deltaShown(forEvent: e1) == true, "the button is filled with the number of fields, and the event has the Δ")

        // Emptying a field takes the change away; the banner offers Undo.
        ev.changeTapped(row: annaRow2); spin(0.2)
        let again = ev.changesWindow(forRow: annaRow2)!
        check(again.text(.profile) == "Тихая девочка, теперь капитан.", "opened again the field shows what the change says")
        again.setText(.profile, "")
        again.window?.close(); spin(0.3)
        check(main.eventStore.event(e1)?.effectText(.profile, of: anna) == nil && main.eventStore.event(e1)?.effectCount(of: anna) == 2, "emptying a field removes that change")
        check(main.banner.isShowing && main.banner.text == "Change removed.", "the banner says so", main.banner.text)
        main.undoStructure(); spin(0.3)
        check(main.eventStore.event(e1)?.effectText(.profile, of: anna) == "Тихая девочка, теперь капитан.", "and Undo puts it back")

        // Opened with nothing typed, nothing is saved.
        let levRow = ev.connections.firstIndex { $0.kind == .character && $0.refID == lev }!
        ev.changeTapped(row: levRow); spin(0.2)
        ev.changesWindow(forRow: levRow)?.window?.close(); spin(0.3)
        check(main.eventStore.event(e1)?.effects[lev] == nil, "a window closed with nothing typed saves nothing")

        // A place: its description.
        let placeRow = ev.connections.firstIndex { $0.kind == .place }!
        ev.changeTapped(row: placeRow); spin(0.2)
        let pw = ev.changesWindow(forRow: placeRow)!
        check(pw.ghost(.description) == "Цветущий дом.", "a place shows its description in grey")
        pw.setText(.description, "Сгорела.")
        pw.window?.close(); spin(0.3)
        check(main.eventStore.event(e1)?.effectText(.description, of: place) == "Сгорела." && main.worlds.text(place) == "Цветущий дом.", "and the change is the event's, not the card's")

        // Relationships: start a new one, change it, end it; refused moves.
        let rid = ev.createRelationship(between: anna, and: lev, kind: "изм-друзья")
        check(rid != nil && main.eventStore.event(e1)?.relationships[rid ?? ""] == "starts" && ev.connections.contains { $0.kind == .relationship && $0.marker == "starts" }, "a relationship starts here, and its row says so")
        let relRow = ev.connections.firstIndex { $0.kind == .relationship }!
        ev.changeTapped(row: relRow); spin(0.2)
        let rw = ev.changesWindow(forRow: relRow)!
        check(rw.text(.kind) == "изм-друзья" && rw.ghost(.kind) == "", "for a relationship that starts here, its own fields are plain fields")
        rw.setText(.kind, "изм-друзья детства")
        rw.window?.close(); spin(0.3)
        check(main.relationships.relationship(rid!)?.kind == "изм-друзья детства", "edited directly")
        ev.select(e2); spin(0.3)
        ev.endExisting(rid!); spin(0.2)
        check(main.eventStore.event(e2)?.relationships[rid!] == "ends" && ev.connections.contains { $0.kind == .relationship && $0.marker == "ends" }, "it ends in a later event")
        check(!ev.moveStart(of: rid!, to: e2) && ev.lastWarning?.title == "It cannot start there", "a start that would come after its end is refused", "\(String(describing: ev.lastWarning))")
        check(!ev.moveEnd(of: rid!, to: startID) && main.eventStore.event(e2)?.relationships[rid!] == "ends", "an end before its start is refused, and nothing changes")
        check(ev.moveStart(of: rid!, to: startID) && main.eventStore.startEvent?.relationships[rid!] == "starts" && main.eventStore.event(e1)?.relationships[rid!] == nil, "the start can move to Book starts")
        ev.keepActive(rid!); spin(0.2)
        check(main.eventStore.event(e2)?.relationships[rid!] == nil && main.relationships.relationship(rid!) != nil, "Keep It Active takes the end away")

        // An event with changes and no scene does not apply, and says so.
        ev.select(loose); spin(0.3)
        try! main.eventStore.update(loose) { $0.setEffect(.profile, of: anna, text: "Где-то.") }
        ev.select(e1); ev.select(loose); spin(0.3)
        check(ev.warningText.contains("no scene"), "it says so", ev.warningText)

        // Clean up.
        for id in [e1, e2, loose] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        try? BookIntegrity.deleteRelationship(rid!, book: main.folder, snapshot: false)
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        try? BookIntegrity.deletePlace(place, book: main.folder, snapshot: false)
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
