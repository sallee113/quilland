import AppKit
import QuillandCore

/// The Duplicates tab: cards that look like one are listed; the new one is merged into the one that is already there, or deleted (one Undo takes it back), or they are said to be not the same.
extension AppSelfTest {
    func duplicatesTab() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard !scenes.isEmpty else { check(false, "a scene for the checks"); return 1 }
        let s0 = scenes[0].id
        let anna = try! main.characters.add(name: "Двойн-Анна"), lev = try! main.characters.add(name: "Двойн-Лев")
        let a = try! main.eventStore.add(title: "Встреча у озера"), b = try! main.eventStore.add(title: "Встреча у озера вечером"), other = try! main.eventStore.add(title: "Пожар в амбаре")
        try! main.eventStore.update(a) { $0.links = [s0: ""]; $0.characters = [anna: ""] }
        try! main.eventStore.update(b) { $0.links = [s0: ""]; $0.characters = [anna: "", lev: ""] }
        try! main.eventStore.update(other) { $0.links = [s0: ""] }
        main.reloadStores()

        main.showSearch(.duplicates); spin(0.4)
        let dv = main.searchPanel.duplicatesView
        guard let group = dv.groups.first(where: { $0.kind == .events && Set($0.members.map(\.id)) == [a, b] }) else { check(false, "the two events are listed as a group", "\(dv.groups.map { $0.members.map(\.title) })"); return 1 }
        check(main.searchPanel.mode == .duplicates && group.level == .same && !dv.groups.contains { $0.members.contains { $0.id == other } }, "the tab lists the cards that look like one, and not the one that is different")
        dv.select { $0.key == group.key }
        check(dv.selectedGroup?.key == group.key, "a group can be chosen")

        // The card made first is the one that is already there; Merge puts the new one into it: one step, with the new one's rows added.
        check(group.existing.id == a && group.newer.map(\.id) == [b], "the card made first is the existing one, and the other is new")
        let eventsBefore = main.eventStore.events.count
        let keeper = a
        check(dv.merge(group), "Merge merges the new card into the existing one, with no question asked")
        main.eventStore.reload()
        let gone = b
        check(main.eventStore.event(gone) == nil && main.eventStore.events.count == eventsBefore - 1 && main.eventStore.event(keeper)?.characters.keys.contains(anna) == true && main.eventStore.event(keeper)?.characters.keys.contains(lev) == true, "the other is gone, and the kept one has the people of both")
        check(!dv.groups.contains { $0.key == group.key }, "and the group is no longer listed")
        check(main.banner.isShowing && main.banner.text.contains("Merge into"), "the banner says what was done, with Undo, instead of asking first", main.banner.text)
        main.undoStructure(); spin(0.5)
        main.eventStore.reload()
        check(main.eventStore.event(a) != nil && main.eventStore.event(b) != nil, "one Undo brings both events back")

        // Delete one card of a group: no question, one Undo, and a relationship that started in it starts in the one that is kept.
        main.showSearch(.duplicates); spin(0.3); dv.refresh()
        guard let again = dv.groups.first(where: { $0.kind == .events && Set($0.members.map(\.id)) == [a, b] }) else { check(false, "the group is back after the Undo"); return 1 }
        let rel = try! main.relationships.add(characters: [anna, lev], kind: "Двойн-друзья")
        try! main.eventStore.update(b) { var m = $0.relationships; m[rel] = "starts"; $0.relationships = m }
        main.reloadStores()
        let keeper2 = again.existing.id
        check(again.newer.map(\.id) == [b] && dv.delete(again), "Delete removes the new card of the group")
        main.eventStore.reload()
        check(main.eventStore.event(b) == nil && main.eventStore.event(a) != nil && main.eventStore.event(keeper2)?.relationships[rel] == "starts", "the other card stays, and the relationship that started in the deleted one starts in it", "\(String(describing: main.eventStore.event(keeper2)?.relationships))")
        main.undoStructure(); spin(0.5)
        main.eventStore.reload()
        check(main.eventStore.event(b) != nil && main.eventStore.event(b)?.relationships[rel] == "starts", "one Undo brings it back as it was")
        try? BookIntegrity.deleteRelationship(rel, book: main.folder, snapshot: false); main.reloadStores()

        // Not the Same: remembered.
        main.showSearch(.duplicates); spin(0.3)
        dv.refresh()
        dv.select { $0.kind == .events && Set($0.members.map(\.id)) == [a, b] }
        dv.notSame()
        check(!dv.groups.contains { $0.kind == .events && Set($0.members.map(\.id)) == [a, b] } && BookDuplicates.dismissed(book: main.folder).contains(group.key), "Not the Same takes the group off the list for good")
        BookDuplicates.forgetDismissed(book: main.folder)

        main.searchPanel.onClose?(); spin(0.2)
        for id in [a, b, other] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
