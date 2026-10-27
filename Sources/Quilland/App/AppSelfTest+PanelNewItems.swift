import AppKit
import QuillandCore

/// The tabs of the right panel follow one rule: *All …* and a New button on top (a new item is linked to the scene and its name is ready to be typed), the field under the card
/// is the description, and a double-click opens the item in its own view.
extension AppSelfTest {
    func panelNewItems() -> Int32? {
        let main = self.main!
        guard let scene = main.session.structure.scenes.first?.id else { check(false, "a scene for the checks"); return 1 }
        main.setMode(.panels); spin(0.4)
        let panel = main.rightPanel
        _ = panel.view
        panel.setVisibleTabs([.section, .characters, .world, .events, .research])
        panel.show(scene); spin(0.2)
        func note(_ s: String) -> NSNotification.Name { Notification.Name(s) }
        func typed(_ tv: NSTextView, _ text: String, into tab: PanelListTab) {
            tv.string = text
            tab.textDidChange(Notification(name: NSText.didChangeNotification, object: tv))
            tab.commitEdits()
        }
        func renamed(_ tab: PanelListTab, _ name: String) {
            tab.heading.stringValue = name
            tab.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: tab.heading))
        }

        // Characters.
        panel.showTab(.characters); panel.setShowsAllCharacters(false); spin(0.2)
        var opened: String?
        panel.onOpenCharacter = { opened = $0 }
        panel.addNewCharacter(); spin(0.2)
        let anna = main.characters.characters.first { $0.name == "New character" }
        check(anna != nil && anna?.links[scene] == "" && !panel.showsAllCharacters && panel.listedCharacterIDs.contains(anna?.id ?? ""), "New Character links the character to the scene, so it is in the list and All characters is left as it was", "\(panel.showsAllCharacters) \(panel.listedCharacterIDs)")
        panel.characterDescription.string = "Тихая девочка."
        panel.textDidChange(Notification(name: NSText.didChangeNotification, object: panel.characterDescription))
        panel.commitEdits()
        check(main.characters.profile(anna?.id ?? "") == "Тихая девочка." && main.characters.character(anna?.id ?? "")?.notes.isEmpty == true, "the field under the card is the description (the profile text), and the notes are not touched")
        panel.openSelectedCharacter()
        check(opened == anna?.id, "a double-click opens the character in its own view")

        // World.
        panel.showTab(.world); panel.worldTab.allBox.state = .off; panel.refresh()
        let world = main.worlds.worlds[0].id!
        panel.worldTab.chooseWorld = { world }
        var openedPlace: String?
        panel.worldTab.onOpen = { openedPlace = $0 }
        let place = panel.worldTab.addNew(); spin(0.2)
        check(place != nil && main.worlds.entry(place ?? "")?.name == "New place" && main.worlds.entry(place ?? "")?.links[scene] == "" && panel.worldTab.rowIDs.contains(place ?? "") && panel.worldTab.allBox.state == .off, "New Place makes a place in a world, linked to the scene and listed, with All left as it was")
        renamed(panel.worldTab, "Новый двор")
        check(main.worlds.entry(place ?? "")?.name == "Новый двор" && panel.worldTab.heading.isEditable, "the name is typed in the card's heading")
        typed(panel.worldTab.descriptionView, "Двор за домом.", into: panel.worldTab)
        check(main.worlds.text(place ?? "") == "Двор за домом.", "the description is the place's text")
        panel.worldTab.openSelected()
        check(openedPlace == place, "a double-click opens the place")

        // Events.
        panel.showTab(.events); panel.eventsTab.allBox.state = .off; panel.refresh()
        var openedEvent: String?
        panel.eventsTab.onOpen = { openedEvent = $0 }
        let event = panel.eventsTab.addNew(); spin(0.2)
        check(event != nil && main.eventStore.event(event ?? "")?.title == "New event" && main.eventStore.event(event ?? "")?.links[scene] == "" && panel.eventsTab.rowIDs.contains(event ?? ""), "New Event makes an event linked to the scene")
        renamed(panel.eventsTab, "Новая встреча")
        typed(panel.eventsTab.descriptionView, "Они встретились.", into: panel.eventsTab)
        check(main.eventStore.event(event ?? "")?.title == "Новая встреча" && main.eventStore.text(event ?? "") == "Они встретились.", "its name and its description are saved")
        panel.eventsTab.openSelected()
        check(openedEvent == event, "a double-click opens the event")

        // Research.
        panel.showTab(.research); panel.researchTab.allBox.state = .off; panel.refresh()
        var openedDoc: String?
        panel.researchTab.onOpen = { openedDoc = $0 }
        let doc = panel.researchTab.addNew(); spin(0.2)
        check(doc != nil && main.researchStore.document(doc ?? "")?.title == "New document" && main.researchStore.document(doc ?? "")?.links[scene] == "" && panel.researchTab.rowIDs.contains(doc ?? ""), "New Document makes a document linked to the scene")
        typed(panel.researchTab.descriptionView, "Краткое описание.", into: panel.researchTab)
        check(main.researchStore.text(doc ?? "") == "Краткое описание.", "the field is its text")
        panel.researchTab.openSelected()
        check(openedDoc == doc, "a double-click opens the document")
        check(panel.researchTab.newButton.title == "New Document" && panel.worldTab.newButton.title == "New Place" && panel.eventsTab.newButton.title == "New Event", "every tab has its New button")

        if let id = anna?.id { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        if let id = place { try? BookIntegrity.deletePlace(id, book: main.folder, snapshot: false) }
        for id in [event].compactMap({ $0 }) { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        if let id = doc { try? main.researchStore.delete(id) }
        main.reloadStores(); panel.show(scene); panel.showTab(.section); panel.setVisibleTabs([.section, .characters]); spin(0.3)
        return nil
    }
}
