import AppKit
import QuillandCore

/// The Narrator field in the settings of a scene (the Outline's detail, the right panel's Section tab): the same data as the point of view on the character's card, which Collect
/// tells the model. And the Target field says what it is.
extension AppSelfTest {
    func narratorField() -> Int32? {
        let main = self.main!
        guard let scene = main.session.structure.scenes.first?.id else { check(false, "a scene for the checks"); return 1 }
        let anna = try! main.characters.add(name: "Рассказ-Анна"), lev = try! main.characters.add(name: "Рассказ-Лев")
        main.reloadStores()

        main.setMode(.outline); spin(0.4)
        guard let detail = main.outlineDetail else { check(false, "the Outline shows"); return 1 }
        detail.show([scene]); spin(0.3)
        check(detail.narratorRowShown && detail.narratorButton.scene == scene && detail.narratorButton.tickedTitles.isEmpty, "a scene's settings have a Narrator field, with no one ticked at first")
        check(detail.targetPlaceholder == "for example 5000", "the Target field has a hint that says what goes there", detail.targetPlaceholder)
        // Ticking a narrator is the point of view on the card.
        detail.narratorButton.personItem("Рассказ-Анна").map { _ = $0.target?.perform($0.action, with: $0) }
        spin(0.2)
        check(main.characters.character(anna)?.povScenes == [scene] && detail.narratorButton.tickedTitles == ["Рассказ-Анна"], "choosing a character in the scene's Narrator field makes the scene their point of view", "\(String(describing: main.characters.character(anna)?.povScenes))")
        try! main.characters.setNarrator(true, of: scene, character: lev)
        detail.narratorButton.show(scene: scene)
        check(Set(detail.narratorButton.tickedTitles) == ["Рассказ-Анна", "Рассказ-Лев"] && main.characters.narratorNames()[scene]?.sorted() == ["Рассказ-Анна", "Рассказ-Лев"], "a scene can have several narrators, and the names are what Collect tells the model")
        detail.narratorButton.personItem("Рассказ-Лев").map { _ = $0.target?.perform($0.action, with: $0) }
        spin(0.2)
        check(main.characters.character(lev)?.povScenes.isEmpty == true && main.characters.narrators(of: scene).count == 1, "choosing a ticked one again takes it away")

        // Through the menu itself (as a click does): choosing a ticked name takes it away, and the title says None again.
        let items = detail.narratorButton.menu?.items ?? []
        let idx = detail.narratorButton.personItem("Рассказ-Анна").flatMap { items.firstIndex(of: $0) } ?? -1   // (the first entry of a pull-down is its title, which can read the same)
        check(idx > 0 && detail.narratorButton.tickedTitles == ["Рассказ-Анна"] && detail.narratorButton.title == "Рассказ-Анна" && detail.narratorButton.noneItem?.state == .off, "the title of the Narrator button names the narrator", "\(detail.narratorButton.title)")
        detail.narratorButton.menu?.performActionForItem(at: idx); spin(0.2)
        check(main.characters.narrators(of: scene).isEmpty && detail.narratorButton.tickedTitles.isEmpty && detail.narratorButton.title == "None" && detail.narratorButton.noneItem?.state == .on, "choosing the ticked narrator through the menu takes it away, and the button says None", "\(detail.narratorButton.title) \(main.characters.narrators(of: scene).count)")
        detail.narratorButton.menu?.performActionForItem(at: idx); spin(0.2)
        check(main.characters.narrators(of: scene).count == 1, "and choosing it again makes it the narrator")
        // The None entry takes them all away at once.
        try! main.characters.setNarrator(true, of: scene, character: lev)
        detail.narratorButton.show(scene: scene)
        check(Set(detail.narratorButton.tickedTitles) == ["Рассказ-Анна", "Рассказ-Лев"], "two narrators are ticked")
        let noneAt = detail.narratorButton.noneItem.flatMap { detail.narratorButton.menu?.items.firstIndex(of: $0) } ?? -1
        detail.narratorButton.menu?.performActionForItem(at: noneAt); spin(0.3)
        check(main.characters.narrators(of: scene).isEmpty && detail.narratorButton.title == "None", "None takes every narrator away at once", "\(main.characters.narrators(of: scene).count)")
        try! main.characters.setNarrator(true, of: scene, character: anna)
        detail.narratorButton.show(scene: scene)

        // The Target field: what the size line says once there is a target.
        main.setTarget(scene, 5000); detail.show([scene]); spin(0.2)
        check(detail.countsText.contains(" of ") && detail.countsText.contains("5") && detail.countsText.hasSuffix("%)"), "with a target, the size line says how far the scene is: size of target and the percent", detail.countsText)
        main.setTarget(scene, nil); detail.show([scene]); spin(0.2)

        // The right panel's Section tab has it too.
        main.setMode(.panels); spin(0.4)
        let panel = main.rightPanel
        _ = panel.view
        panel.showTab(.section); panel.show(scene); spin(0.2)
        check(panel.narratorButton.scene == scene && panel.narratorButton.tickedTitles == ["Рассказ-Анна"], "the Section tab of the right panel shows the narrator too", "\(panel.narratorButton.tickedTitles)")
        // ...and there too the narrator can be taken away through the menu, and the button says None.
        let panelItems = panel.narratorButton.menu?.items ?? []
        let at = panel.narratorButton.personItem("Рассказ-Анна").flatMap { panelItems.firstIndex(of: $0) } ?? -1
        panel.narratorButton.menu?.performActionForItem(at: at); spin(0.3)
        check(main.characters.narrators(of: scene).isEmpty && panel.narratorButton.tickedTitles.isEmpty && panel.narratorButton.title == "None", "the right panel's Narrator takes a narrator away and returns None", "\(panel.narratorButton.title) \(main.characters.narrators(of: scene).count)")

        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); spin(0.3)
        return nil
    }
}
