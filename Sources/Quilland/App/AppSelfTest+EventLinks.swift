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
        cv.addScene(storm); spin(0.2)
        cv.view.window?.makeFirstResponder(nil)  // (the cursor is in the new row's text cell, as the author would have it; leave it before using the API)
        check(cv.eventRowIDs == [storm], "the event is in the card's list", "\(cv.eventRowIDs)")
        check(main.characters.character(gleb)?.links[storm] == "", "and the link is kept in the character's file")
        check(!cv.addableEvents.contains(storm), "an event in the list is not offered again")
        cv.setSceneLine(row: cv.rows.firstIndex { $0.sceneID == storm } ?? 0, "борется со штормом")
        check(main.characters.character(gleb)?.links[storm] == "борется со штормом", "what the character does in the event is saved")
        check(main.eventStore.event(storm)?.links[scene] == "" && main.eventStore.event(storm)?.places.isEmpty == true, "the event's own file is not touched")
        app.modeEvents(); spin(0.3)
        main.eventsView?.select(storm); spin(0.2)
        check(main.eventsView?.connections.contains { $0.name == "Глеб-связи" } == true, "the Events view shows the same link")
        app.modeCharacters(); spin(0.3)
        main.charactersView?.select(gleb); spin(0.2)
        main.charactersView?.removeSceneLink(row: main.charactersView?.rows.firstIndex { $0.sceneID == storm } ?? 0); spin(0.2)
        check(main.characters.character(gleb)?.links[storm] == nil && main.charactersView?.eventRowIDs.isEmpty == true, "removing the link takes the event out of the list")

        // The place's card.
        app.modeWorld(); spin(0.4)
        guard let wv = main.worldView else { check(false, "the World view shows"); return 1 }
        wv.reload(); wv.select(port); spin(0.2)
        check(wv.addableEvents.contains(storm) && wv.addableEvents.contains(calm), "the place offers the events to add")
        wv.addEvent(calm); spin(0.2)
        check(wv.eventRowIDs == [calm], "the event is in the place's list", "\(wv.eventRowIDs)")
        check(main.eventStore.event(calm)?.places[port] == "", "and the link is kept in the event's file")
        check(main.worlds.entry(port)?.links.isEmpty == true, "the place's own file is not touched")
        wv.setEventLine(row: 0, "стоит на причале")
        check(main.eventStore.event(calm)?.places[port] == "стоит на причале", "what happens there is saved")
        wv.removeEventLink(row: 0); spin(0.2)
        check(main.eventStore.event(calm)?.places[port] == nil && wv.eventRowIDs.isEmpty, "removing the link takes the place away from the event")

        try? main.characters.delete(gleb)
        for id in [storm, calm] { try? main.eventStore.delete(id) }
        try? main.worlds.deleteEntry(port)
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
