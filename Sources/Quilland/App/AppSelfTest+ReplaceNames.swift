import AppKit
import QuillandCore

/// Suggestions ▸ Replace a Name…: a name the model made up is replaced by a card, in the suggestions only.
extension AppSelfTest {
    func replaceNames() -> Int32? {
        let main = self.main!
        guard let scene = main.session.structure.scenes.first?.id else { check(false, "a scene for the checks"); return 1 }
        let villi = try! main.characters.add(name: "Замена-Вилли"), elli = try! main.characters.add(name: "Замена-Элли")
        main.reloadStores(); main.collect.clear()
        let evidence = [CollectedEvidence(scene: scene, quote: "Первая строка", range: NSRange(location: 0, length: 3), note: "")]
        func rel(_ a: String, _ b: String, _ kind: String) -> CollectedItem {
            var r = CollectedItem(kind: .relationships, name: ""); r.members = [a, b]; r.type = kind; r.when = "stated"; r.evidence = evidence; return r
        }
        let hero1 = rel("Замена-Герой", "Замена-Элли", "дружба"), hero2 = rel("Замена-Герой (рассказчик)", "Замена-Элли", "дружба"), other = rel("Замена-Герой", "Замена-Вилли", "общение")
        var place = CollectedItem(kind: .places, name: "Замена-Герой"); place.evidence = evidence
        main.collect.inject([hero1, hero2, other, place])
        main.showSearch(.suggestions); spin(0.3)
        let sv = main.searchPanel.suggestView
        sv.selectItemRow(hero1.id)
        check(sv.replaceNameEnabled && sv.nameSlots(of: hero1.id).map(\.name) == ["Замена-Герой", "Замена-Элли"], "Replace a Name… is on for a suggestion that has names, and lists them")
        let accepted = { main.collect.accept([hero1.id]) }
        let tried = accepted()
        check(tried.skipped.count == 1 && main.collect.skipReason(for: hero1.id) != nil, "a suggestion whose name has no card cannot be accepted", "\(tried)")

        // One suggestion alone.
        let one = sv.replaceName(in: other.id, slot: NameSlot(role: .character, name: "Замена-Герой"), with: "Замена-Вилли", inAll: false)
        check(one == 1 && main.collect.items.first { $0.id == other.id }?.members == ["Замена-Вилли", "Замена-Вилли"] && main.collect.items.first { $0.id == hero1.id }?.members.first == "Замена-Герой", "with In all suggestions off only that suggestion changes")
        // All of them.
        let all = sv.replaceName(in: hero1.id, slot: NameSlot(role: .character, name: "Замена-Герой"), with: "Замена-Вилли", inAll: true)
        check(all >= 1, "in all suggestions, the same name is replaced")
        sv.replaceName(in: hero2.id, slot: NameSlot(role: .character, name: "Замена-Герой (рассказчик)"), with: "Замена-Вилли", inAll: true)
        let friends = main.collect.items.filter { $0.kind == .relationships && $0.type == "дружба" }
        check(friends.count == 1 && Set(friends[0].members) == ["Замена-Вилли", "Замена-Элли"] && friends[0].evidence.count >= 1, "and when the other way the model wrote the name is replaced too, the two that are now one relationship join", "\(main.collect.items.map(\.members))")
        check(main.collect.skipReason(for: hero1.id) == nil && main.collect.items.first { $0.kind == .places }?.name == "Замена-Герой", "the old reason is gone, and a place of the same name is not touched")
        check(main.collect.message.contains("Replaced “Замена-Герой (рассказчик)” with “Замена-Вилли” in 1 suggestion"), "and the status says what was done", main.collect.message)
        // The replaced one can now be accepted: both names have cards.
        let keep = friends[0].id
        let report = main.collect.accept([keep])
        main.relationships.reload()
        check(report.skipped.isEmpty && main.relationships.relationships.contains { Set($0.characters) == [villi, elli] && $0.kind == "дружба" }, "the relationship is made between the cards that were chosen")
        check(main.characters.character(villi)?.aliases.contains { $0.contains("Герой") } != true, "and the made-up name is not put on the card")

        for r in main.relationships.relationships where r.kind == "дружба" || r.kind == "общение" { if let id = r.id { try? BookIntegrity.deleteRelationship(id, book: main.folder, snapshot: false) } }
        for id in [villi, elli] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.collect.clear(); main.reloadStores()
        return nil
    }
}
