import AppKit
import QuillandCore

/// Merging and converting characters, places and worlds; the World and Events views.
extension AppSelfTest {
    func recordMerges() -> Int32? {
        let main = self.main!
        let sc = self.sc!
        let cv2 = self.cv2!
        let again = self.again!
        let folder = self.folder!
        // Merge Into…: the same person under two names.
        do {
            let keptID = main.characters.characters.first { $0.name == "Анна Петровна" }!.id!
            let dupID = try! main.characters.add(name: "Анечка")
            try! main.characters.update(dupID) { $0.notes = ["Младшая."]; $0.links = [sc[0].id: "спит"] }
            let menuHost = main.charactersView!
            _ = menuHost
            main.mergeCharacters(dupID, into: keptID); spin(0.8)
            let kept = main.characters.character(keptID)
            check(main.characters.character(dupID) == nil && kept?.aliases.contains("Анечка") == true && kept?.notes.contains("Младшая.") == true && kept?.links[sc[0].id] == "спит", "Merge Into… takes the second card out and gives its name, notes and links to the first", "\(String(describing: kept?.aliases)) \(String(describing: kept?.notes))")
            check(main.charactersView?.shownNames == ["Анна Петровна"] && main.charactersView?.selected == keptID, "the list shows the kept character, chosen")
            check(main.undoStack.last?.name.contains("Анечка") == true && main.banner.isShowing, "and the banner offers Undo")
            main.undoStructure(confirm: false); spin(0.8)
            check(main.characters.character(dupID) != nil && main.characters.character(keptID)?.aliases.contains("Анечка") != true, "Undo brings the second card back and takes its name off the first", "dup \(main.characters.character(dupID) != nil) aliases \(String(describing: main.characters.character(keptID)?.aliases)) stack \(main.undoStack.map(\.name))")
        }
        cv2.onEscape?(); spin(0.4)
        check(main.mode == main.writingMode, "Esc leaves the view")
        setText(sc[0].id, "Первая строка новой книги.")

        // The World view.
        app.modeWorld(); spin(0.5)
        guard let wv = main.worldView else { check(false, "View ▸ World shows the view"); return 1 }
        let defaultWorld = main.worlds.worlds[0].id!
        check(main.mode == .world && wv.visibleTitles == [main.worlds.worlds[0].name!], "View ▸ World shows the world a new book has", "\(wv.visibleTitles)")
        check(main.localState().mode == "world", "and it is the view remembered for the book")
        let germany = wv.addPlace(named: "Германия")!
        let frankfurt = wv.addPlace(named: "Франкфурт")!
        let berlin = wv.addPlace(named: "Берлин", inside: false)!
        check(wv.visibleTitles.dropFirst().sorted() == ["  Германия", "    Берлин", "    Франкфурт"].sorted() && main.worlds.entry(berlin)?.parent == germany && main.worlds.entry(frankfurt)?.parent == germany, "a typed name makes a place inside the chosen one, or beside it", "\(wv.visibleTitles)")
        check(wv.addPlace(named: "  ") == nil, "a blank name makes nothing")
        let north = wv.addWorld(named: "Север")!
        check(wv.visibleTitles.contains("Север") && main.worlds.worlds.count == 2, "New World adds a world")
        check(wv.movePlace(berlin, into: north) && main.worlds.entry(berlin)?.world == north && main.worlds.entry(berlin)?.parent == nil, "a place dropped on another world goes there")
        check(!wv.movePlace(germany, into: frankfurt) && main.worlds.entry(germany)?.parent == nil, "a place cannot be dropped into what is inside it")
        check(wv.movePlace(frankfurt, into: defaultWorld) && main.worlds.entry(frankfurt)?.parent == nil, "dropping on a world makes it a top-level place there")
        setText(sc[0].id, "Он приехал во Франкфурт из Германии.")
        wv.select(frankfurt)
        check(wv.rows.isEmpty, "a scene that only names the place is not a link: the card's list has none of them by default", "\(wv.rows)")
        wv.setShowsMentions(true)
        check(wv.rows.count == 1 && wv.rows[0].mentions == 1 && wv.mentionOnlyFlags == [true], "Also scenes that name it lists the scene where the name is, dimmed", "\(wv.rows)")
        wv.selectSceneRow(0)
        check(!wv.removeLinkEnabled && wv.removeLinkTip.contains("names the place"), "such a row cannot be taken away, and the tooltip says why", wv.removeLinkTip)
        wv.removeSceneLink(row: 0)
        check(wv.rows.count == 1, "and Remove Link does nothing to it")
        check(wv.memory.flags == ["mentions"], "the switch is kept with the view's state")
        wv.setSceneLine(row: 0, "Первая ночь Анны.")
        check(main.worlds.entry(frankfurt)?.links[sc[0].id] == "Первая ночь Анны.", "a line typed for it makes it a link, and what happens there is saved")
        wv.setShowsMentions(false)
        check(wv.rows.count == 1 && wv.mentionOnlyFlags == [false], "and it stays in the list when the switch is off, as a link")
        // A scene can be linked by hand, where the name is not written, and unlinked again.
        let other = sc[1].id
        let otherTitle = main.session.structure.sceneChoices.first { $0.id == other }!.title
        check(!wv.sceneRowIDs.contains(other) && wv.addableScenes.contains(otherTitle), "a scene without the place is offered by Add a Scene…", "\(wv.addableScenes)")
        wv.addScene(other)
        check(main.worlds.entry(frankfurt)?.links[other] == "" && wv.sceneRowIDs.contains(other) && !wv.addableScenes.contains(otherTitle), "adding a scene links it with an empty line, and it leaves the menu")
        wv.setSceneLine(row: wv.sceneRowIDs.firstIndex(of: other)!, "Пересадка.")
        check(main.worlds.entry(frankfurt)?.links[other] == "Пересадка.", "and the line for it can be typed")
        wv.removeSceneLink(row: wv.sceneRowIDs.firstIndex(of: other)!)
        check(main.worlds.entry(frankfurt)?.links[other] == nil && !wv.sceneRowIDs.contains(other) && main.worlds.entry(frankfurt)?.links[sc[0].id] == "Первая ночь Анны.", "Remove Link takes only that scene away")
        wv.descriptionView.string = "Большой город на реке."
        wv.textDidChange(Notification(name: NSText.didChangeNotification, object: wv.descriptionView))
        wv.commitEdits()
        check(main.worlds.text(frankfurt) == "Большой город на реке.", "the description is written to the place's text file")
        check(main.worlds.entry(frankfurt)?.type == "place", "a place is a place: the card has no kind of entry to choose")
        wv.select(north)
        wv.deleteSelected(confirm: false)
        check(main.worlds.world(north) != nil, "a world with places in it is not deleted")
        wv.select(germany)
        let child = main.worlds.addEntryForTest(germany)
        wv.reload()
        wv.deleteSelected(confirm: false)
        check(main.worlds.entry(germany) == nil && main.worlds.entry(child)?.parent == nil, "deleting a place lifts what was inside it")
        wv.onOpenScene?(sc[0].id); spin(0.5)
        check(main.mode == main.writingMode, "opening a scene from the card goes to the text")
        app.modeWorld(); spin(0.4)
        // Merging and converting places and worlds: each is one change with its own Undo.
        do {
            let home = main.worlds.worlds[0].id!
            let worldsBefore = main.worlds.worlds.count
            let planet = try! main.worlds.addEntry(name: "Тэра", world: home)
            let north = try! main.worlds.addEntry(name: "Север", world: home, parent: planet)
            let twin = try! main.worlds.addEntry(name: "Планета Тэра", world: home)
            try! main.worlds.updateEntry(twin) { $0.notes = ["Далёкая."] }
            main.mergePlaces(twin, into: planet); spin(0.8)
            check(main.worlds.entry(twin) == nil && main.worlds.entry(planet)?.aliases.contains("Планета Тэра") == true && main.worlds.entry(planet)?.notes.contains("Далёкая.") == true && main.worldView?.selected == planet, "Merge Into… on a place gives its name and notes to the other, and chooses it")
            main.undoStructure(confirm: false); spin(0.8)
            check(main.worlds.entry(twin) != nil && main.worlds.entry(planet)?.aliases.contains("Планета Тэра") != true, "and Undo brings the place back")
            main.placeToWorld(planet); spin(0.8)
            let made = main.worlds.worlds.first { $0.name == "Тэра" }
            check(made != nil && main.worlds.entry(planet) == nil && main.worlds.entry(north)?.world == made?.id && main.worlds.entry(north)?.parent == nil, "Turn Into a World makes a world of a place, with what was inside it at the top")
            if let made = made?.id {
                main.worldToPlace(made, intoWorld: home, parent: nil); spin(0.8)
                check(main.worlds.world(made) == nil && main.worlds.entries.contains { $0.name == "Тэра" && $0.world == home && $0.parent == nil } && main.worlds.entry(north)?.world == home, "and Turn Into a Place puts a world back as a place in another one")
            }
            main.undoStructure(confirm: false); spin(0.8)
            main.undoStructure(confirm: false); spin(0.8)
            check(main.worlds.entry(planet) != nil && main.worlds.entry(north)?.parent == planet && main.worlds.worlds.count == worldsBefore, "both can be undone", "planet \(main.worlds.entry(planet) != nil) parent \(String(describing: main.worlds.entry(north)?.parent)) worlds \(main.worlds.worlds.count) before \(worldsBefore)")
            for id in [north, twin, planet] { try? main.worlds.deleteEntry(id) }
        }
        main.worldView?.onEscape?(); spin(0.4)
        check(main.mode == main.writingMode, "Esc leaves the view")
        check(main.worlds.problems.isEmpty, "and the files of the worlds read without problems", "\(main.worlds.problems)")
        setText(sc[0].id, "Первая строка новой книги.")

        // The Events view.
        app.modeEvents(); spin(0.5)
        guard let ev = main.eventsView else { check(false, "View ▸ Events shows the view"); return 1 }
        check(main.mode == .events && ev.shownTitles.isEmpty, "View ▸ Events starts empty, inviting the first event")
        check(main.localState().mode == "events", "and it is the view remembered for the book")
        let arrival = ev.addEvent(titled: "  Анна приезжает ")!
        let farewell = ev.addEvent(titled: "Прощание")!
        let loose = ev.addEvent(titled: "Без сцены")!
        check(ev.addEvent(titled: "  ") == nil && main.eventStore.events.count == 3, "a typed title makes an event; a blank one makes nothing")
        let allScenes = main.session.structure.scenes
        ev.select(farewell)
        ev.addScene(allScenes[1].id)
        ev.select(arrival)
        ev.addScene(allScenes[0].id)
        spin(0.2)
        check(((again.window.firstResponder as? NSTextView)?.delegate as? NSTextField)?.placeholderString == "Type what happens here", "adding a connection puts the cursor in its What happens cell", "\(String(describing: again.window.firstResponder))")
        check(ev.shownTitles == ["Анна приезжает", "Прощание", "Без сцены"], "events are listed in the order of the book, those without a scene last", "\(ev.shownTitles)")
        ev.dateField.stringValue = "весна, год 214"
        ev.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: ev.dateField))
        check(main.eventStore.event(arrival)?.date == "весна, год 214", "the date is free text")
        ev.setConnectionText(row: 0, "Она выходит из корабля.")
        check(main.eventStore.event(arrival)?.links[allScenes[0].id] == "Она выходит из корабля." && ev.connections.count == 1, "what happens in a scene is saved")
        let annaID = main.characters.characters.first { $0.name == "Анна Петровна" }!.id!
        ev.addCharacter(annaID)
        ev.setConnectionText(row: ev.connections.firstIndex { $0.kind == .character }!, "Не знает, что станция пуста.")
        check(main.eventStore.event(arrival)?.characters[annaID] == "Не знает, что станция пуста." && main.characters.character(annaID)?.links[arrival] == nil, "a character who takes part is stored in the event's own file")
        let placeID = main.worlds.entries.first?.id ?? (try! main.worlds.addEntry(name: "Посадочная площадка", world: main.worlds.worlds[0].id!))
        ev.addPlace(placeID)
        check(!ev.doubleClickOpens(column: 2) && ev.doubleClickOpens(column: 1), "a double-click in the What happens column is for typing and does not open anything")
        check(ev.connections.map(\.kind.rawValue) == ["Scene", "Place", "Character"], "scenes, places and characters are listed together", "\(ev.connections.map(\.kind.rawValue))")
        ev.removeConnection(row: ev.connections.firstIndex { $0.kind == .place }!)
        check(main.eventStore.event(arrival)?.places.isEmpty == true && ev.connections.count == 2, "a connection is taken away")
        ev.descriptionView.string = "Корабль садится на площадку."
        ev.textDidChange(Notification(name: NSText.didChangeNotification, object: ev.descriptionView))
        ev.commitEdits()
        check(main.eventStore.text(arrival) == "Корабль садится на площадку.", "the description is written to the event's text file")
        check(ev.planText == "Not on the plan yet", "an event starts off the plan")
        let plan = try! PlanStore(folder: folder)
        let line = try! plan.addLine(name: "Анна")
        ev.select(arrival)
        ev.putOnPlanOrShow()
        check(ev.planText == "On the plan: line “Анна”" && (try? PlanStore(folder: folder))?.entry(forEvent: arrival) != nil, "an event is put on the first line of the plan", ev.planText)
        _ = line
        ev.select(loose)
        ev.deleteSelected(confirm: false); spin(0.8)   // (the views are made again after a deletion)
        check(main.eventStore.event(loose) == nil && main.eventsView?.shownTitles == ["Анна приезжает", "Прощание"], "deleting an event takes it out of the list")
        main.eventsView?.select(arrival)
        main.eventsView?.deleteSelected(confirm: false); spin(0.8)
        check((try? PlanStore(folder: folder))?.entry(forEvent: arrival) == nil && main.eventsView?.shownTitles == ["Прощание"], "and off the plan")
        ev.onOpenScene?(allScenes[0].id); spin(0.5)
        check(main.mode == main.writingMode, "opening a scene from the card goes to the text")
        app.modeEvents(); spin(0.4)
        main.eventsView?.onOpenCharacter?(annaID); spin(0.4)
        check(main.mode == .characters && main.charactersView?.selected == annaID, "opening a character from the card goes to the Characters view")
        main.charactersView?.onEscape?(); spin(0.4)
        check(main.eventStore.problems.isEmpty && main.mode == main.writingMode, "the files of the events read without problems")
        return nil
    }
}
