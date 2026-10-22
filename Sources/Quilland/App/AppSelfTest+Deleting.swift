import AppKit
import QuillandCore

/// Deleting from the views takes everything that refers to the item along, as one undoable change, and the screens are told.
extension AppSelfTest {
    func deleting() -> Int32? {
        let main = self.main!
        let anna = try! main.characters.add(name: "Уд-Анна"), lev = try! main.characters.add(name: "Уд-Лев")
        let world = main.worlds.worlds[0].id!
        let place = try! main.worlds.addEntry(name: "Уд-Место", world: world)
        let event = try! main.eventStore.add(title: "Уд: событие")
        let rel = try! main.relationships.add(characters: [anna, lev], kind: "уд-друзья")
        let doc = try! main.researchStore.add(title: "Уд-документ")
        try! main.researchStore.update(doc) { $0.links = [anna: "о ней", place: "о месте"] }
        try! main.eventStore.update(event) { r in
            r.characters = [anna: "", lev: ""]; r.places = [place: ""]; r.relationships = [rel: "starts"]
            r.effects = [anna: .object(["profile": .string("Новое.")]), place: .object(["description": .string("Сгорело.")])]
        }
        var told = 0
        let hear = subscribe(to: .bookDataChanged) { told += 1 }
        defer { _ = hear }

        // A character: the card, its rows and effects, its relationships and its links go together; one Undo brings them back.
        main.setMode(.characters); spin(0.4)
        guard let cv = main.charactersView else { check(false, "the Characters view shows"); return 1 }
        cv.reload(); cv.select(anna); spin(0.2)
        cv.deleteSelected(confirm: false); spin(0.8)
        check(main.characters.character(anna) == nil && main.eventStore.event(event)?.characters.keys.contains(anna) == false && main.eventStore.event(event)?.effects[anna] == nil, "a deleted character goes from the events, with what they changed in it")
        check(main.relationships.relationship(rel) == nil && main.eventStore.event(event)?.relationships.isEmpty == true, "and its relationships go, with their place in the events")
        check(main.researchStore.document(doc)?.links[anna] == nil && main.researchStore.document(doc)?.links[place] != nil, "and its links in research documents, not the others")
        check(main.banner.isShowing && main.banner.text.contains("Уд-Анна") && told >= 1, "one banner offers Undo, and the screens were told", "\(main.banner.text) \(told)")
        main.undoStructure(); spin(0.8)
        check(main.characters.character(anna) != nil && main.eventStore.event(event)?.characters[anna] == "" && main.relationships.relationship(rel) != nil && main.researchStore.document(doc)?.links[anna] == "о ней", "one Undo brings everything back")
        check(main.eventStore.event(event)?.relationships[rel] == "starts" && main.eventStore.event(event)?.effects[anna] != nil, "with the markers and the effects")

        // An event with a relationship that starts in it: deleted with it (the question is asked only when the author is asked).
        main.setMode(.events); spin(0.4)
        guard let ev = main.eventsView else { check(false, "the Events view shows"); return 1 }
        ev.reload(); ev.select(event); spin(0.2)
        check(BookIntegrity.relationshipsStarting(in: event, book: main.folder) == [rel], "the relationship starts in the event")
        ev.deleteSelected(confirm: false); spin(0.8)
        check(main.eventStore.event(event) == nil && main.relationships.relationship(rel) == nil, "deleting the event deletes the relationships that start in it, when no question is asked")
        main.undoStructure(); spin(0.8)
        check(main.eventStore.event(event)?.relationships[rel] == "starts" && main.relationships.relationship(rel) != nil, "and Undo brings them back")

        // A place.
        main.setMode(.world); spin(0.4)
        guard let wv = main.worldView else { check(false, "the World view shows"); return 1 }
        wv.reload(); wv.select(place); spin(0.2)
        wv.deleteSelected(confirm: false); spin(0.8)
        check(main.worlds.entry(place) == nil && main.eventStore.event(event)?.places.isEmpty == true && main.eventStore.event(event)?.effects[place] == nil && main.researchStore.document(doc)?.links[place] == nil, "a deleted place goes from the events and the documents")
        main.undoStructure(); spin(0.8)

        // Nothing is left dangling after it all.
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        try? BookIntegrity.deleteEvent(event, book: main.folder, snapshot: false)
        try? BookIntegrity.deletePlace(place, book: main.folder, snapshot: false)
        try? main.researchStore.delete(doc)
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        check(LooseEnds(book: main.folder).scan().filter { $0.target.isEmpty == false && [anna, lev, place, event, rel].contains($0.target) }.isEmpty, "no loose end points at what was deleted")
        return nil
    }
}
