import AppKit
import QuillandCore

/// "Book starts": the relationships that start there can be deleted from the book, one or several at once, with no question and one Undo.
extension AppSelfTest {
    func bookStartsDelete() -> Int32? {
        let main = self.main!
        let anna = try! main.characters.add(name: "Начало-Анна"), lev = try! main.characters.add(name: "Начало-Лев"), vera = try! main.characters.add(name: "Начало-Вера")
        let r1 = try! main.relationships.add(characters: [anna, lev], kind: "начало-друзья"), r2 = try! main.relationships.add(characters: [anna, vera], kind: "начало-соседи"), r3 = try! main.relationships.add(characters: [lev, vera], kind: "начало-враги")
        let startID = main.eventStore.startEvent!.id!
        try! main.eventStore.update(startID) { var m = $0.relationships; for r in [r1, r2, r3] { m[r] = "starts" }; $0.relationships = m }
        let other = try! main.eventStore.add(title: "Начало: другое")
        try! main.eventStore.update(other) { var m = $0.relationships; m[r3] = "ends"; $0.relationships = m }
        main.reloadStores()
        main.setMode(.events); spin(0.4)
        guard let ev = main.eventsView else { check(false, "the Events view shows"); return 1 }
        ev.reload(); ev.select(startID); spin(0.3)
        let rows = ev.connections.indices.filter { ev.connections[$0].kind == .relationship && [r1, r2].contains(ev.connections[$0].refID) }
        check(rows.count == 2, "the relationships that start with the book are listed in Book starts", "\(ev.connections.map(\.name))")
        ev.selectConnectionRow(rows[0])
        check(ev.removeButtonTitle == "Delete from the Book", "with one of them chosen, the button says it deletes from the book", ev.removeButtonTitle)
        let before = main.relationships.relationships.count
        ev.deleteRelationships(rows: rows); spin(0.4)
        main.relationships.reload(); main.eventStore.reload()
        check(main.relationships.relationship(r1) == nil && main.relationships.relationship(r2) == nil && main.relationships.relationship(r3) != nil && main.relationships.relationships.count == before - 2, "two of them are deleted at once and the third stays")
        check(main.eventStore.startEvent?.relationships[r1] == nil && main.eventStore.startEvent?.relationships[r3] == "starts", "and are gone from Book starts")
        check(main.banner.isShowing, "with a banner offering Undo instead of a question", main.banner.text)
        check(main.eventsView?.selected == startID, "Book starts is still the chosen event afterwards, not the first of the story", "\(String(describing: main.eventsView?.selected))")
        main.undoStructure(); spin(0.5)
        check(main.eventsView?.selected == startID, "and after Undo")
        main.relationships.reload(); main.eventStore.reload()
        check(main.relationships.relationship(r1) != nil && main.relationships.relationship(r2) != nil && main.eventStore.startEvent?.relationships[r1] == "starts", "one Undo brings both back")
        // A relationship that ends in another event goes with its end mark.
        ev.reload(); ev.select(startID); spin(0.3)
        if let row = ev.connections.firstIndex(where: { $0.refID == r3 }) { ev.deleteRelationships(rows: [row]); spin(0.4) }
        main.eventStore.reload(); main.relationships.reload()
        check(main.relationships.relationship(r3) == nil && main.eventStore.event(other)?.relationships[r3] == nil, "a relationship that ends elsewhere leaves that event too")
        main.undoStructure(); spin(0.5)

        // Taking a link away from an ordinary event keeps that event chosen, in the list and on the card (whichever kind of link, and wherever it stands in its group).
        if let scenes = Optional(main.session.structure.scenes), scenes.count > 1 {
            let place = try! main.worlds.addEntry(name: "Начало-Место", world: main.worlds.worlds[0].id!)
            let e1 = try! main.eventStore.add(title: "Начало: один"), e2 = try! main.eventStore.add(title: "Начало: два"), e3 = try! main.eventStore.add(title: "Начало: три"), e4 = try! main.eventStore.add(title: "Начало: четыре")
            for (i, e) in [e1, e2, e3].enumerated() { try! main.eventStore.update(e) { $0.links = [scenes[0].id: "", scenes[1].id: ""]; $0.order = (i + 1) * 100; $0.characters = [anna: "", lev: ""]; $0.places = [place: ""]; $0.relationships = [r1: ""] } }
            try! main.eventStore.update(e4) { $0.links = [scenes[1].id: ""]; $0.order = 50 }
            main.reloadStores(); ev.reload(); spin(0.2)
            for kind in [EventConnection.Kind.scene, .place, .character, .relationship, .scene] {
                ev.select(e2); spin(0.2)
                guard let row = ev.connections.firstIndex(where: { $0.kind == kind && ($0.marker != "starts") }) else { check(false, "a \(kind) link to take away"); continue }
                ev.removeConnection(row: row); spin(0.3)
                check(ev.selected == e2 && ev.chosenListTitle == "Начало: два" && ev.cardTitle == "Начало: два", "taking a \(kind) link away keeps the event chosen, in the list and on the card", "\(String(describing: ev.selected)) \(String(describing: ev.chosenListTitle)) \(ev.cardTitle)")
            }
            // A relationship that starts in an ordinary event is deleted from the book by the same button: no refusal, one Undo.
            let wrong = try! main.relationships.add(characters: [anna, vera], kind: "начало-ошибка")
            try! main.eventStore.update(e4) { var m = $0.relationships; m[wrong] = "starts"; $0.relationships = m }
            main.reloadStores(); ev.reload(); ev.select(e4); spin(0.3)
            if let row = ev.connections.firstIndex(where: { $0.refID == wrong }) {
                ev.selectConnectionRow(row)
                check(ev.removeButtonTitle == "Delete from the Book", "on a relationship that starts here, the button says it deletes from the book", ev.removeButtonTitle)
                ev.removeConnection(row: row); spin(0.4)
                main.relationships.reload()
                check(main.relationships.relationship(wrong) == nil && ev.lastWarning == nil && ev.selected == e4 && ev.cardTitle == "Начало: четыре", "it is deleted with no refusal, and the event stays chosen")
                main.undoStructure(); spin(0.5); main.relationships.reload()
                check(main.relationships.relationship(wrong) != nil, "and one Undo brings it back")
            }
            try? BookIntegrity.deleteRelationship(wrong, book: main.folder, snapshot: false)
            main.reloadStores(); ev.reload(); ev.select(e4); spin(0.2)
            // With the list filtered by a character, taking that character away from the chosen event takes the event out of the list: the choice is then the same event
            // still (the card), or nothing, never another event.
            ev.select(e3); spin(0.2)
            try! main.eventStore.update(e3) { $0.characters = [lev: ""] }; main.reloadStores(); ev.reload()
            ev.relationFilter.set(.character(lev)); spin(0.3)
            ev.select(e3); spin(0.2)
            if let row = ev.connections.firstIndex(where: { $0.kind == .character && $0.refID == lev }) {
                ev.removeConnection(row: row); spin(0.3)
                check(ev.chosenListTitle == nil || ev.chosenListTitle == ev.cardTitle, "with the list filtered, the list never shows one event chosen and the card another", "\(String(describing: ev.chosenListTitle)) | \(ev.cardTitle) | \(String(describing: ev.selected))")
            }
            ev.relationFilter.clear(); spin(0.2)
            for e in [e1, e2, e3, e4] { try? BookIntegrity.deleteEvent(e, book: main.folder, started: .deleteThem, snapshot: false) }
            try? BookIntegrity.deletePlace(place, book: main.folder, snapshot: false)
            main.reloadStores(); ev.reload(); ev.select(startID); spin(0.2)
        }

        // The same for a character and a place: an unrelated change does not move the choice.
        main.setMode(.characters); spin(0.3)
        main.charactersView?.select(lev); spin(0.2)
        main.deleteRelationships([r1]); spin(0.4)
        check(main.charactersView?.selected == lev, "a character stays chosen after a change elsewhere", "\(String(describing: main.charactersView?.selected))")
        main.undoStructure(); spin(0.5)
        check(main.charactersView?.selected == lev, "and after Undo")

        for r in [r1, r2, r3] { try? BookIntegrity.deleteRelationship(r, book: main.folder, snapshot: false) }
        try? BookIntegrity.deleteEvent(other, book: main.folder, started: .deleteThem, snapshot: false)
        for id in [anna, lev, vera] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
