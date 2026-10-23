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
        check(report.updated >= 1 && main.eventStore.events.filter { $0.title == "Ссора на станции" }.count == 1 && !main.eventStore.events.contains { $0.title == "Ссора на станции вечером" }, "the same event added its scene to the card it repeats", "\(report)")

        main.searchPanel.onClose?(); spin(0.2)
        main.collect.clear()
        for e in main.eventStore.events where ["Ссора на станции", "Ссора на станции вечером", "Ссора на платформе", "Расставание у ворот", "Расставание у ворот под дождём"].contains(e.title ?? "") { if let id = e.id { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) } }
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
