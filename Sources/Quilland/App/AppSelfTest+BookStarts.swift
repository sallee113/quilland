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
        check(ev.removeButtonTitle == "Delete from the Book", "the button there says it deletes from the book", ev.removeButtonTitle)
        let before = main.relationships.relationships.count
        ev.deleteRelationships(rows: rows); spin(0.4)
        main.relationships.reload(); main.eventStore.reload()
        check(main.relationships.relationship(r1) == nil && main.relationships.relationship(r2) == nil && main.relationships.relationship(r3) != nil && main.relationships.relationships.count == before - 2, "two of them are deleted at once and the third stays")
        check(main.eventStore.startEvent?.relationships[r1] == nil && main.eventStore.startEvent?.relationships[r3] == "starts", "and are gone from Book starts")
        check(main.banner.isShowing, "with a banner offering Undo instead of a question", main.banner.text)
        main.undoStructure(); spin(0.5)
        main.relationships.reload(); main.eventStore.reload()
        check(main.relationships.relationship(r1) != nil && main.relationships.relationship(r2) != nil && main.eventStore.startEvent?.relationships[r1] == "starts", "one Undo brings both back")
        // A relationship that ends in another event goes with its end mark.
        ev.reload(); ev.select(startID); spin(0.3)
        if let row = ev.connections.firstIndex(where: { $0.refID == r3 }) { ev.deleteRelationships(rows: [row]); spin(0.4) }
        main.eventStore.reload(); main.relationships.reload()
        check(main.relationships.relationship(r3) == nil && main.eventStore.event(other)?.relationships[r3] == nil, "a relationship that ends elsewhere leaves that event too")
        main.undoStructure(); spin(0.5)

        for r in [r1, r2, r3] { try? BookIntegrity.deleteRelationship(r, book: main.folder, snapshot: false) }
        try? BookIntegrity.deleteEvent(other, book: main.folder, started: .deleteThem, snapshot: false)
        for id in [anna, lev, vera] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
