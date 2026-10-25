import AppKit
import QuillandCore

/// Duplicates caught as the findings come in: one that repeats a row of the list joins it, one that is the same as a card of the book joins the card, and one that only
/// looks like something is marked.
extension AppSelfTest {
    func collectDuplicates() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard !scenes.isEmpty else { check(false, "a scene for the checks"); return 1 }
        let s0 = scenes[0].id
        let anna = try! main.characters.add(name: "Дубль-Анна"), lev = try! main.characters.add(name: "Дубль-Лев")
        let have = try! main.eventStore.add(title: "Ссора на станции")
        try! main.eventStore.update(have) { $0.links = [s0: ""]; $0.characters = [anna: "", lev: ""] }
        main.reloadStores(); main.collect.clear()
        let before = main.eventStore.events.count

        func event(_ title: String, at: Int) -> CollectedItem {
            var i = CollectedItem(kind: .events, name: title)
            i.members = ["Дубль-Анна", "Дубль-Лев"]
            i.evidence = [CollectedEvidence(scene: s0, quote: "Первая строка", range: NSRange(location: at, length: 3), note: "")]
            return i
        }
        let same = event("Ссора на станции вечером", at: 0), alike = event("Ссора на платформе", at: 10)
        let first = event("Расставание у ворот", at: 20), again = event("Расставание у ворот под дождём", at: 30)
        main.collect.inject([same, alike, first]); main.collect.inject([again])
        check(main.collect.items.count == 3 && main.collect.mergedOnTheFly == 1 && main.collect.items.first { $0.name == "Расставание у ворот" }?.evidence.count == 2, "a finding that repeats a row of the list, in other words, joins it as the list grows", "\(main.collect.items.map(\.name)) \(main.collect.mergedOnTheFly)")
        check(main.collect.existingMatch(same) == "Ссора на станции", "one that is the same as a card of the book (the same scene and people, and a title that says all its words) is that card", "\(String(describing: main.collect.existingMatch(same)))")
        check(main.collect.lookAlikes[same.id] == nil, "and is not marked as a look-alike")
        let mark = main.collect.lookAlikes[alike.id]
        check(mark?.title == "Ссора на станции" && mark?.isCard == true && main.collect.existingMatch(alike) == nil, "one that only looks like a card is marked with the card, and is not that card", "\(String(describing: mark))")
        main.showSearch(.suggestions); spin(0.3)
        let sv = main.searchPanel.suggestView
        check(sv.rowText(for: alike.id).contains("looks like the card “Ссора на станции”") && !sv.rowText(for: same.id).contains("looks like"), "the list shows the mark on that row alone", sv.rowText(for: alike.id))
        check(main.collect.duplicatesText.contains("found again") && main.collect.duplicatesText.contains("looks like something else"), "and a run says how many were joined and how many look alike", main.collect.duplicatesText)

        // Accepting: the same event joins its card (no duplicate is made); a look-alike is only a guess, so it is made.
        sv.checkAll()
        let report = sv.acceptChecked()!
        main.eventStore.reload()
        check(main.eventStore.events.count == before + 2, "accepting makes no second card for the same event: only the look-alike and the new one are made", "\(main.eventStore.events.map { $0.title ?? "" })")
        check(main.eventStore.events.filter { $0.title == "Ссора на станции" }.count == 1 && !main.eventStore.events.contains { $0.title == "Ссора на станции вечером" }, "no second card was made for the same event", "\(report)")

        // A finding that repeats a card and would add nothing (the scene and the people are there) is not listed; the status line says how many.
        main.collect.clear(); main.showSearch(.suggestions); spin(0.2)
        let nothing = event("Ссора на станции", at: 40)
        main.collect.inject([nothing]); spin(0.2)
        check(sv.itemCount == 0 && main.collect.items.count == 1 && main.collect.alreadyInBookCount == 1, "a finding that would add nothing to its card is not listed", "\(sv.itemCount)")
        check(sv.statusText.contains("1 finding already in the book"), "and the status line says so", sv.statusText)
        // One that adds a scene or a person is listed, and says what it adds.
        let vera = try! main.characters.add(name: "Дубль-Вера"); main.reloadStores()
        main.collect.clear()
        var more = event("Ссора на станции", at: 50)
        more.members = ["Дубль-Анна", "Дубль-Вера"]
        if scenes.count > 1 { more.evidence = [CollectedEvidence(scene: scenes[1].id, quote: "Вторая строка", range: NSRange(location: 5, length: 3), note: "")] }
        main.collect.inject([more]); spin(0.2)
        let text = sv.rowText(for: more.id)
        check(sv.itemCount == 1 && text.contains("already has a card: adds") && text.contains("people: Дубль-Вера") && (scenes.count < 2 || text.contains("the scene “")), "one that adds a scene or a person is listed, and says what it adds", text)
        try? BookIntegrity.deleteCharacter(vera, book: main.folder, snapshot: false)

        // A relationship the book has: found again with its scene already linked, it adds nothing and is not listed; a fact the card says in other words is not either.
        main.collect.clear()
        var friends = CollectedItem(kind: .relationships, name: ""); friends.members = ["Дубль-Анна", "Дубль-Лев"]; friends.type = "Дубль-друзья"; friends.when = "stated"
        friends.evidence = [CollectedEvidence(scene: s0, quote: "Первая строка", range: NSRange(location: 0, length: 3), note: "")]
        main.collect.inject([friends]); sv.checkAll(); _ = sv.acceptChecked()
        main.collect.inject([friends]); spin(0.2)
        check(sv.itemCount == 0 && main.collect.alreadyInBookCount == 1, "a relationship found again, with its scene linked, is not listed", "\(sv.itemCount)")
        try! main.characters.setProfile(anna, "Тихая девочка живёт в открытом космосе.")
        var fact = CollectedItem(kind: .observations, name: ""); fact.about = "Дубль-Анна"; fact.detail = "живёт как девочка в открытом космосе"; fact.evidence = friends.evidence
        main.collect.clear(); main.collect.inject([fact]); spin(0.2)
        check(sv.itemCount == 0, "a fact the card says in other words is not listed", "\(sv.itemCount)")
        fact.detail = "Хромает после аварии"; main.collect.clear(); main.collect.inject([fact]); spin(0.2)
        check(sv.itemCount == 1, "a fact that is new is", "\(sv.itemCount)")
        for r in main.relationships.relationships where r.kind == "Дубль-друзья" { if let id = r.id { try? BookIntegrity.deleteRelationship(id, book: main.folder, snapshot: false) } }
        main.reloadStores()

        // A change that names an event the book has (and a lone one in the same scene) goes to that event: no second event of the same title is made.
        if scenes.count > 1 {
            func change(_ who: String, _ detail: String, event: String) -> CollectedItem {
                var c = CollectedItem(kind: .changes, name: who); c.field = "profile"; c.detail = detail; c.eventTitle = event
                c.evidence = [CollectedEvidence(scene: scenes[1].id, quote: "Вторая строка", range: NSRange(location: 5, length: 3), note: "")]
                return c
            }
            main.collect.clear()
            main.collect.inject([change("Дубль-Анна", "Стала смелой.", event: "Ссора на станции"), change("Дубль-Лев", "Хмурый.", event: "")])
            sv.checkAll()
            _ = sv.acceptChecked()
            main.eventStore.reload()
            let named = main.eventStore.events.filter { $0.title == "Ссора на станции" }
            check(named.count == 1 && named.first?.effectText(.profile, of: anna) == "Стала смелой." && named.first?.effectText(.profile, of: lev) == "Хмурый." && !main.eventStore.events.contains { $0.title?.hasPrefix("Changes in") == true }, "changes that name an event the book has go to it, and no event of the same title is made", "\(main.eventStore.events.map { $0.title ?? "" })")
            // Found again (in other words): the event already changes it, so accepting could only refuse it: it is not listed.
            main.collect.clear()
            main.collect.inject([change("Дубль-Анна", "Совсем осмелела.", event: "Ссора на станции")]); spin(0.2)
            check(sv.itemCount == 0 && main.collect.alreadyInBookCount == 1, "a change the named event already makes is not listed", "\(sv.itemCount)")
        }

        main.searchPanel.onClose?(); spin(0.2)
        main.collect.clear()
        for e in main.eventStore.events where ["Ссора на станции", "Ссора на станции вечером", "Ссора на платформе", "Расставание у ворот", "Расставание у ворот под дождём"].contains(e.title ?? "") { if let id = e.id { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) } }
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
