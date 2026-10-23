import AppKit
import QuillandCore

/// The cards show what events change: a place's description rows, a character's profile rows, new names and worlds as bricks, relationships as bricks (read-only).
extension AppSelfTest {
    func cardChanges() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes.map(\.id)
        guard scenes.count >= 3 else { check(false, "three scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "Карт-Анна"), lev = try! main.characters.add(name: "Карт-Лев")
        try! main.characters.setProfile(anna, "Тихая девочка.")
        let worlds = main.worlds.worlds
        let home = worlds[0].id!
        let place = try! main.worlds.addEntry(name: "Карт-Усадьба", world: home)
        try! main.worlds.setText(place, "Цветущий дом.")
        let e1 = try! main.eventStore.add(title: "Карт: первое"), e2 = try! main.eventStore.add(title: "Карт: второе"), loose = try! main.eventStore.add(title: "Карт: без сцены")
        try! main.eventStore.update(e1) { $0.links = [scenes[0]: ""]; $0.characters = [anna: "", lev: ""]; $0.places = [place: ""] }
        try! main.eventStore.update(e2) { $0.links = [scenes[1]: ""]; $0.characters = [anna: ""] }
        try! main.eventStore.update(loose) { $0.characters = [anna: ""]; $0.places = [place: ""] }
        // Written in the order e2, e1, loose on purpose: the card follows the book, not the order of writing.
        try! main.eventStore.update(e2) { $0.setEffect(.profile, of: anna, text: "Капитан."); $0.setEffect(.aliases, of: anna, list: ["Вильгельм"]); $0.setEffect(.description, of: place, text: "Руины.") }
        try! main.eventStore.update(e1) { $0.setEffect(.profile, of: anna, text: "Девочка на корабле."); $0.setEffect(.aliases, of: anna, list: ["Билл", "Вильгельм"]); $0.setEffect(.description, of: place, text: "Сгорела.") }
        try! main.eventStore.update(loose) { $0.setEffect(.profile, of: anna, text: "Где-то."); $0.setEffect(.description, of: place, text: "Нигде.") }
        if worlds.count > 1 { try! main.eventStore.update(e2) { $0.setEffect(.worlds, of: anna, list: [worlds[1].id!]) } }
        main.reloadStores(); spin(0.3)

        // A place.
        main.setMode(.world); spin(0.4)
        guard let wv = main.worldView else { check(false, "the Places view shows"); return 1 }
        wv.reload(); wv.select(place); spin(0.3)
        check(wv.changeRowTexts == ["Сгорела.", "Руины.", "Нигде."], "the place card lists the changes in the order of the book, the event with no scene last", "\(wv.changeRowTexts)")
        check(wv.changeRowTooltips[0].hasPrefix("Карт: первое · ") && wv.changeRowTooltips[2].hasPrefix("Карт: без сцены"), "each row has the event and the scene in its tooltip", "\(wv.changeRowTooltips)")
        check(wv.changeRowsDimmed == [false, false, true], "the row of an event with no scene is greyed")
        check(main.worlds.text(place) == "Цветущий дом.", "the base description is not changed")
        let placeRows = wv.rowTitles
        check(zip(wv.eventRowFlags, wv.changesButtonTitles).allSatisfy { $0 == ($1 != nil) } && wv.changesButtonTitles.compactMap { $0 }.count == 2, "the place's list has a Changes button on its event rows only", "\(wv.changesButtonTitles) \(placeRows)")
        check(wv.changesButtonTitles.compactMap { $0 }.contains("Changes: 1"), "and it shows how many fields the event changes", "\(wv.changesButtonTitles)")
        if let row = wv.eventRowFlags.firstIndex(of: true) { wv.openChangesOfRow(row); spin(0.3) }
        check(main.changeWindows.values.contains { $0.window?.isVisible == true }, "the button opens the window of that change")
        for w in main.changeWindows.values { w.window?.close() }; spin(0.3)
        wv.clickChangeRow(1); spin(0.3)
        check(main.changeWindows[e2 + "|" + place]?.window?.isVisible == true, "a click on a row opens the window of that change")
        main.changeWindows[e2 + "|" + place]?.window?.close(); spin(0.3)

        // A character.
        main.setMode(.characters); spin(0.4)
        guard let cv = main.charactersView else { check(false, "the Characters view shows"); return 1 }
        cv.reload(); cv.select(anna); spin(0.3)
        check(zip(cv.eventRowFlags, cv.changesButtonTitles).allSatisfy { $0 == ($1 != nil) } && cv.changesButtonTitles.compactMap { $0 }.count == 3, "the character's list has a Changes button on its event rows only", "\(cv.changesButtonTitles)")
        if let row = cv.eventRowFlags.firstIndex(of: true) { cv.openChangesOfRow(row); spin(0.3) }
        check(main.changeWindows.values.contains { $0.window?.isVisible == true }, "the button opens the window of that change")
        for w in main.changeWindows.values { w.window?.close() }; spin(0.3)
        check(cv.profileRowTexts == ["Девочка на корабле.", "Капитан.", "Где-то."], "the profile shows the changes in the order of the book", "\(cv.profileRowTexts)")
        check(cv.aliasBrickTitles == ["Билл", "Вильгельм"], "the names events add are bricks after the field, each once", "\(cv.aliasBrickTitles)")
        if worlds.count > 1 { check(cv.worldBrickTitles.contains(worlds[1].name ?? ""), "a world an event adds is a brick", "\(cv.worldBrickTitles)") }
        check(main.characters.character(anna)?.aliases.isEmpty == true && main.characters.profile(anna) == "Тихая девочка.", "the card itself is not changed")
        cv.clickAliasBrick(0); spin(0.3)
        check(main.changeWindows[e1 + "|" + anna]?.window?.isVisible == true, "a click on a name opens the window of its change")
        main.changeWindows[e1 + "|" + anna]?.window?.close(); spin(0.3)

        // The matcher knows the added names.
        setText(scenes[2], "Вильгельм вошёл в каюту.")
        check(main.mentions(ofCharacter: anna)[scenes[2]] == 1, "the text matcher finds the character under a name an event added", "\(main.mentions(ofCharacter: anna))")
        check(main.characters.entries.first { $0.id == anna }?.aliases.contains("Вильгельм") == true, "and the list of names has it")
        setText(scenes[2], "")

        // Relationships: bricks, and not edited here.
        let rid = try! main.relationships.add(characters: [anna, lev], kind: "друзья")
        try! main.eventStore.update(e1) { var r = $0.relationships; r[rid] = "starts"; $0.relationships = r }
        try! main.eventStore.update(e2) { $0.setEffect(.kind, of: rid, text: "враги") }
        main.reloadStores(); cv.reload(); cv.select(anna); spin(0.3)
        check(cv.relationshipBrickTitles == ["Карт-Лев — друзья → враги"], "a relationship is a brick with the other character and the chain of kinds", "\(cv.relationshipBrickTitles)")
        cv.clickRelationshipBrick(0); spin(0.4)
        check(main.mode == .events && main.eventsView?.selected == e1, "a click opens the event that holds the relationship")
        try! main.eventStore.update(e2) { var r = $0.relationships; r[rid] = "ends"; $0.relationships = r }
        main.reloadStores(); main.setMode(.characters); spin(0.4)
        main.charactersView?.select(anna); spin(0.2)
        check(main.relationshipBricks(of: anna).first?.dimmed == true && main.relationshipBricks(of: anna).first?.tooltip.contains("Карт: второе") == true, "an ended relationship is greyed, and the tooltip says where it ends")

        // Clean up.
        for id in [e1, e2, loose] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        try? BookIntegrity.deleteRelationship(rid, book: main.folder, snapshot: false)
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        try? BookIntegrity.deletePlace(place, book: main.folder, snapshot: false)
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
