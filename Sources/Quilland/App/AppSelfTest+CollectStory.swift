import AppKit
import QuillandCore

/// Accepting what the second pass of Collect found: changes go into events (never into a card), relationships begin with the book or at an event, and what would
/// break the order of a relationship is skipped with the reason.
extension AppSelfTest {
    func collectStory() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard scenes.count >= 3 else { check(false, "three scenes for the checks"); return 1 }
        let s0 = scenes[0].id, s1 = scenes[1].id, s2 = scenes[2].id
        let anna = try! main.characters.add(name: "Кол-Анна"), lev = try! main.characters.add(name: "Кол-Лев")
        try! main.characters.setProfile(anna, "Тихая девочка.")
        try! main.characters.update(anna) { $0.notes = ["Заметка автора."] }
        let world = main.worlds.worlds[0].id!
        let manor = try! main.worlds.addEntry(name: "Кол-Усадьба", world: world)
        try! main.worlds.setText(manor, "Цветущий дом.")
        func ev(_ scene: String, _ quote: String = "Первая строка") -> [CollectedEvidence] { [CollectedEvidence(scene: scene, quote: quote, range: NSRange(location: 0, length: 6), note: "")] }
        func change(_ about: String, _ field: String, _ value: String, scene: String, event: String = "", aliases: [String] = []) -> CollectedItem {
            var c = CollectedItem(kind: .changes, name: about); c.field = field; c.detail = value; c.aliases = aliases; c.eventTitle = event; c.evidence = ev(scene); return c
        }
        func rel(_ kind: String, _ when: String, scene: String) -> CollectedItem {
            var r = CollectedItem(kind: .relationships, name: ""); r.members = ["Кол-Анна", "Кол-Лев"]; r.type = kind; r.when = when; r.evidence = ev(scene); return r
        }
        var arrival = CollectedItem(kind: .events, name: "Кол-Приезд"); arrival.members = ["Кол-Анна"]; arrival.evidence = ev(s1)
        let a1 = change("Кол-Анна", "profile", "Теперь капитан.", scene: s0)
        let a2 = change("Кол-Усадьба", "description", "Сгорела.", scene: s0)
        let a3 = change("Кол-Анна", "aliases", "", scene: s1, aliases: ["Кол-Билл"])
        let a4 = change("Кол-Усадьба", "description", "Руины.", scene: s1, event: "Кол-Приезд")
        let a5 = change("Кол-Лев", "profile", "Ранен.", scene: s2)
        let a6 = change("Кол-Лев", "main", "true", scene: s2)
        let a8 = change("Кол-Анна", "description", "Стала тише.", scene: s1)
        let a7 = change("Кол-Анна", "profile", "Тихая девочка.", scene: s1)
        let stated = rel("друзья", "stated", scene: s0), turns = rel("враги", "changes", scene: s1), starts = rel("соседи", "starts", scene: s1), endsEarly = rel("соседи", "ends", scene: s0)
        var fact = CollectedItem(kind: .observations, name: ""); fact.about = "Кол-Лев"; fact.detail = "Хромает."; fact.evidence = ev(s0)
        let items = [arrival, stated, turns, starts, endsEarly, a1, a2, a3, a4, a5, a7, a8, fact]
        _ = a6

        main.collect.inject(items)
        main.showSearch(.suggestions); spin(0.3)
        let sv = main.searchPanel.suggestView
        sv.checkAll()
        let report = sv.acceptChecked()!
        main.eventStore.reload(); main.relationships.reload()
        let start = main.eventStore.startEvent!.id!
        let events = main.eventStore.events

        let made0 = events.first { $0.links.keys.contains(s0) && $0.title?.hasPrefix("Changes in") == true }
        check(made0 != nil && made0?.effectText(.profile, of: anna) == "Теперь капитан." && made0?.effectText(.description, of: manor) == "Сгорела.", "two changes in one scene make one event for the scene, with both changes", "\(events.map { $0.title ?? "" })")
        check(made0?.characters[anna] == "" && made0?.places[manor] == "", "the event shows what it changes as rows")
        let real = events.first { $0.title == "Кол-Приезд" }
        check(real?.effectList(.aliases, of: anna) == ["Кол-Билл"] && real?.effectText(.description, of: manor) == "Руины.", "changes found in the scene of an event of the story, or naming it, go to that event")
        check(real?.effectText(.profile, of: anna) == "Стала тише." && main.collect.skipReason(for: a8.id) == nil, "a character's change the model called a description is the profile")
        check(!events.contains { $0.title == "Кол-Анна: also called" }, "and no second event is made for that scene")
        let single = events.first { $0.title == "Кол-Лев: profile" }
        check(single?.links.keys.contains(s2) == true && single?.effectText(.profile, of: lev) == "Ранен.", "a lone change with no event makes one titled with what it changes", "\(events.map { $0.title ?? "" })")
        check(main.characters.profile(anna) == "Тихая девочка." && main.characters.character(anna)?.notes == ["Заметка автора."] && main.worlds.text(manor) == "Цветущий дом." && main.characters.character(anna)?.aliases.isEmpty == true, "the cards themselves, and the author's notes, are not changed")
        check(main.collect.skipReason(for: a7.id)?.contains("already says this") == true, "a change that says what the card says is skipped, with the reason", "\(String(describing: main.collect.skipReason(for: a7.id)))")

        let friends = main.relationships.relationships.first { $0.kind == "друзья" }?.id ?? ""
        check(main.eventStore.startEvent?.relationships[friends] == "starts", "a relationship that is simply so starts with the book (Book starts)")
        check(real?.relationships[friends] == "" && real?.effectText(.kind, of: friends) == "враги", "one that changes is a change in the event of its scene")
        let neighbours = main.relationships.relationships.first { $0.kind == "соседи" }?.id ?? ""
        check(!neighbours.isEmpty && real?.relationships[neighbours] == "starts", "one that begins starts in the event of its scene")
        check(main.eventStore.events.allSatisfy { $0.relationships[neighbours] != "ends" } && main.collect.skipReason(for: endsEarly.id)?.contains("end before it starts") == true, "an end that comes before the start is not applied, and the row says why", "\(String(describing: main.collect.skipReason(for: endsEarly.id)))")
        check(main.characters.profile(lev) == "Хромает.", "a fact that was always so is a new paragraph of the card's text")
        check(report.created[.changes] != nil && main.collect.message.contains("recorded in"), "the report counts the changes", main.collect.message)
        check(main.characters.character(lev)?.notes.isEmpty == true, "a fact is not written into the notes")
        check(RelationshipTimeline(events: main.eventStore, sceneOrder: scenes.map(\.id)).broken(friends).isEmpty, "the order of the relationship is sound")

        // Clean up.
        main.searchPanel.onClose?(); spin(0.2)
        main.collect.clear()
        let mine = Set(main.eventStore.events.filter { ($0.links.keys.contains(s0) || $0.links.keys.contains(s1) || $0.links.keys.contains(s2)) && ($0.title?.hasPrefix("Кол-") == true || $0.title?.hasPrefix("Changes in") == true) }.compactMap(\.id))
        for id in mine { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        for r in main.relationships.relationships where Set(r.characters) == Set([anna, lev]) { if let id = r.id { try? BookIntegrity.deleteRelationship(id, book: main.folder, snapshot: false) } }
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        try? BookIntegrity.deletePlace(manor, book: main.folder, snapshot: false)
        main.reloadStores(); main.collectedCardsChanged(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
