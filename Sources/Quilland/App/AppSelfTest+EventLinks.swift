import AppKit
import QuillandCore

/// Events in the cards: a character's list of scenes holds the events it takes part in, and a place has its own list of the events held there.
extension AppSelfTest {
    func eventLinks() -> Int32? {
        let main = self.main!
        let scene = main.session.structure.scenes[0].id
        let gleb = try! main.characters.add(name: "Глеб-связи")
        let world = main.worlds.worlds[0].id!
        let port = try! main.worlds.addEntry(name: "Порт-связи", world: world)
        let storm = try! main.eventStore.add(title: "Связи: шторм"), calm = try! main.eventStore.add(title: "Связи: штиль")
        try! main.eventStore.update(storm) { $0.links = [scene: ""] }

        // The character's card.
        app.modeCharacters(); spin(0.4)
        guard let cv = main.charactersView else { check(false, "the Characters view shows"); return 1 }
        cv.reload(); cv.select(gleb); spin(0.2)
        check(cv.addableEvents.contains(storm) && cv.addableEvents.contains(calm), "the card offers the events to add", "\(cv.addableEvents)")
        check(!cv.addableScenes.contains { $0.hasPrefix("◆") }, "the scenes in the menu are not mixed with the events")
        check(!cv.removeLinkEnabled, "Remove Link is off while no row of the character's list is chosen")
        cv.addEvent(storm); spin(0.2)
        cv.view.window?.makeFirstResponder(nil)
        cv.selectLinkRow(nil); spin(0.1)
        check(!cv.removeLinkEnabled, "and stays off with nothing chosen")
        cv.selectLinkRow(0); spin(0.1)
        check(cv.removeLinkEnabled, "and works once a row is chosen")
        cv.selectLinkRow(nil); spin(0.1)
        cv.view.window?.makeFirstResponder(nil)  // (the cursor is in the new row's text cell, as the author would have it; leave it before using the API)
        check(cv.eventRowIDs == [storm], "the event is in the card's list", "\(cv.eventRowIDs)")
        check(main.eventStore.event(storm)?.characters[gleb] == "" && main.characters.character(gleb)?.links[storm] == nil, "and the link is kept in the event's file")
        check(!cv.addableEvents.contains(storm), "an event in the list is not offered again")
        cv.setSceneLine(row: cv.rows.firstIndex { $0.sceneID == storm } ?? 0, "борется со штормом")
        check(main.eventStore.event(storm)?.characters[gleb] == "борется со штормом", "what the character does in the event is saved")
        check(main.eventStore.event(storm)?.links[scene] == "" && main.eventStore.event(storm)?.places.isEmpty == true, "the event's scenes and places are not touched")
        app.modeEvents(); spin(0.3)
        main.eventsView?.select(storm); spin(0.2)
        check(main.eventsView?.connections.contains { $0.name == "Глеб-связи" } == true, "the Events view shows the same link")
        check(main.eventsView?.removeLinkEnabled == false, "Remove Link is off while no connection of the event is chosen")
        main.eventsView?.selectConnectionRow(0); spin(0.1)
        check(main.eventsView?.removeLinkEnabled == true, "and works once one is chosen")
        app.modeCharacters(); spin(0.3)
        main.charactersView?.select(gleb); spin(0.2)
        main.charactersView?.removeSceneLink(row: main.charactersView?.rows.firstIndex { $0.sceneID == storm } ?? 0); spin(0.2)
        check(main.eventStore.event(storm)?.characters[gleb] == nil && main.charactersView?.eventRowIDs.isEmpty == true, "removing the link takes the event out of the list")

        // The place's card.
        app.modeWorld(); spin(0.4)
        guard let wv = main.worldView else { check(false, "the World view shows"); return 1 }
        wv.reload(); wv.select(port); spin(0.2)
        check(wv.addableEvents.contains(storm) && wv.addableEvents.contains(calm), "the place offers the events to add")
        check(!wv.removeLinkEnabled, "Remove Link is off while no row of the place's list is chosen")
        wv.addEvent(calm); spin(0.2)
        wv.view.window?.makeFirstResponder(nil)
        wv.selectLinkRow(wv.rows.firstIndex { $0.sceneID == calm }); spin(0.1)
        check(wv.removeLinkEnabled, "and works once a row is chosen")
        wv.selectLinkRow(nil); spin(0.1)
        check(!wv.removeLinkEnabled, "and is off again when the row is let go")
        check(wv.eventRowIDs == [calm], "the event is in the place's list", "\(wv.eventRowIDs)")
        check(main.eventStore.event(calm)?.places[port] == "", "and the link is kept in the event's file")
        check(main.worlds.entry(port)?.links.isEmpty == true, "the place's own file is not touched")
        wv.setSceneLine(row: wv.rows.firstIndex { $0.sceneID == calm } ?? 0, "стоит на причале")
        check(main.eventStore.event(calm)?.places[port] == "стоит на причале", "what happens there is saved")
        wv.removeSceneLink(row: wv.rows.firstIndex { $0.sceneID == calm } ?? 0); spin(0.2)
        check(main.eventStore.event(calm)?.places[port] == nil && wv.eventRowIDs.isEmpty, "removing the link takes the place away from the event")

        // The "Add…" menus are off when there is nothing left to add.
        let sceneIDs = main.session.structure.scenes.map(\.id)
        let eventIDs = main.eventStore.events.compactMap(\.id)
        app.modeCharacters(); spin(0.3)
        if let cv = main.charactersView {
            cv.reload(); cv.select(gleb); spin(0.2)
            check(cv.addLinkEnabled, "the character's Add menu is on while scenes or events can be added")
            try! main.characters.update(gleb) { r in var l = r.links; for id in sceneIDs { l[id] = "" }; r.links = l }
            for id in eventIDs { try! main.eventStore.update(id) { var l = $0.characters; l[gleb] = ""; $0.characters = l } }
            cv.reload(); cv.select(gleb); spin(0.2)
            check(!cv.addLinkEnabled, "and off when every scene and event is in the list")
        }
        app.modeWorld(); spin(0.3)
        if let wv = main.worldView {
            wv.reload(); wv.select(port); spin(0.2)
            check(wv.addLinkEnabled, "the place's Add menu is on while scenes or events can be added")
            try! main.worlds.updateEntry(port) { r in var l = r.links; for id in sceneIDs { l[id] = "" }; r.links = l }
            for id in eventIDs { try! main.eventStore.update(id) { var p = $0.places; p[port] = ""; $0.places = p } }
            wv.reload(); wv.select(port); spin(0.2)
            check(!wv.addLinkEnabled, "and off when every scene and event is in the list")
        }
        app.modeEvents(); spin(0.3)
        main.eventsView?.select(storm); spin(0.2)
        check(main.eventsView?.addLinkEnabled == true, "the event's Add menu is on while something can be linked")

        // The window's title carries the view's name.
        main.setMode(.characters); spin(0.3)
        check(again.window.title.hasSuffix(" — World Bible ▸ Characters"), "the window title names the view (a kind of the World Bible, with the Bible)", again.window.title)
        main.setMode(.plan); spin(0.3)
        check(again.window.title.hasSuffix(" — Plan"), "and follows it to another view", again.window.title)

        // The Plan's zoom buttons are off where they would do nothing.
        app.modePlan(); spin(0.4)
        if let plan = main.planController, plan.showsControls {
            plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); plan.zoomIn(); spin(0.2)
            check(plan.zoomButtonsEnabled.in == false && plan.zoomButtonsEnabled.out, "at the largest zoom the + is off and the − is on", "\(plan.zoom) \(plan.zoomButtonsEnabled)")
            for _ in 0..<20 { plan.zoomOut() }
            spin(0.2)
            check(plan.zoomButtonsEnabled.out == false && plan.zoomButtonsEnabled.in, "at the smallest zoom the − is off and the + is on", "\(plan.zoom) \(plan.zoomButtonsEnabled)")
            plan.zoomToFit(); spin(0.2)
        } else { check(false, "the Plan has its controls") }

        for id in eventIDs { try? main.eventStore.update(id) { var l = $0.characters; l.removeValue(forKey: gleb); $0.characters = l } }
        try? main.characters.delete(gleb)
        for id in [storm, calm] { try? main.eventStore.delete(id) }
        for id in eventIDs { try? main.eventStore.update(id) { var p = $0.places; p.removeValue(forKey: port); $0.places = p } }
        try? main.worlds.deleteEntry(port)
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}

/// The Place part of the "Add…" menus lists the places under the name of their world.
extension AppSelfTest {
    func placeMenus() -> Int32? {
        let main = self.main!
        let w1 = main.worlds.worlds[0], w1name = main.worlds.worlds[0].name ?? ""
        let w2 = try! main.worlds.addWorld(name: "ТМП-Яблоня")
        let b = try! main.worlds.addEntry(name: "Б-место", world: w2), a = try! main.worlds.addEntry(name: "А-место", world: w2)
        let inner = try! main.worlds.addEntry(name: "внутри", world: w2, parent: a)
        let ev = try! main.eventStore.add(title: "ТМП меню мест")
        let doc = try! main.researchStore.add(title: "ТМП документ")

        func check(_ items: [(title: String, heading: Bool)], _ what: String) {
            let headings = items.filter(\.heading).map(\.title)
            self.check(headings.contains("ТМП-Яблоня") && headings.contains(w1name), "\(what): the places are under the names of their worlds", "\(headings)")
            self.check(headings == headings.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "\(what): the worlds are in alphabetical order", "\(headings)")
            if let i = items.firstIndex(where: { $0.title == "ТМП-Яблоня" && $0.heading }) {
                let rest = items[(i + 1)...].prefix { !$0.heading }.map(\.title)
                self.check(rest == ["А-место", "А-место › внутри", "Б-место"], "\(what): a world's places are sorted, a nested one shown inside its parent", "\(rest)")
            } else { self.check(false, "\(what): the heading of the second world is there") }
        }
        main.setMode(.events); spin(0.4)
        main.eventsView?.select(ev); spin(0.3)
        check(main.eventsView?.placeMenuItems ?? [], "Events")
        main.setMode(.research); spin(0.4)
        main.researchView?.select(doc); spin(0.3)
        check(main.researchView?.placeMenuItems ?? [], "Research")

        for id in [inner, a, b] { try? main.worlds.deleteEntry(id) }
        try? main.worlds.deleteWorld(w2)
        try? main.eventStore.delete(ev)
        try? main.researchStore.delete(doc)
        _ = w1
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
