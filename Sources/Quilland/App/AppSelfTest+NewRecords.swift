import AppKit
import QuillandCore

/// A character or a place made from a name in the text, another name for a card, and the Right panel's buttons that link a character or a place to the scene.
extension AppSelfTest {
    private func fire(_ item: NSMenuItem?) { if let item, let action = item.action { _ = NSApp.sendAction(action, to: item.target, from: item) } }

    func newRecords() -> Int32? {
        let main = self.main!
        main.setMode(main.writingMode); spin(0.3)
        let scene = main.session.structure.scenes[0].id
        setText(scene, "Он увидел Тихона у костра. Потом заглянул в Старую Гавань. Я смотрел.")
        main.setRightPanel(true); spin(0.4)
        let panel = main.rightPanel
        _ = panel.view
        panel.setVisibleTabs([.section, .characters, .world])
        main.reveal(scene: scene, range: nil); spin(0.3)
        panel.show(scene)
        guard let tv = main.controllers.first(where: { $0.currentSceneID == scene })?.currentSheet?.textView else { check(false, "the text view of the scene is there"); return 1 }
        let text = tv.string as NSString

        // Names in the text.
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        check(tv.recordItems().isEmpty, "with nothing selected the menu offers nothing about names")
        tv.setSelectedRange(text.range(of: "Он увидел Тихона у костра. Потом заглянул"))
        check(tv.recordItems().isEmpty, "a whole sentence is not taken for a name")
        tv.setSelectedRange(text.range(of: "Тихона"))
        let titles = tv.recordItems().map(\.title)
        check(titles.count == 3 && titles[0].contains("Тихона") && titles[0].lowercased().contains("character") && titles[1].lowercased().contains("place") && titles[2].lowercased().contains("name"), "a name selected in the text offers a character, a place, or another name", "\(titles)")
        let before = main.characters.characters.count
        fire(tv.recordItems().first)
        spin(0.3)
        let tikhon = main.characters.characters.first { $0.name == "Тихона" }
        check(main.characters.characters.count == before + 1 && tikhon?.links[scene] == "", "Make a Character makes the card with the selection as its name and links the scene")
        check(panel.listedCharacterIDs.contains(tikhon?.id ?? "-") && panel.inSceneText.contains("Тихона"), "and the Right panel shows it at once", panel.inSceneText)
        // Now it is a name: the character item is no longer offered for it.
        tv.setSelectedRange(text.range(of: "Тихона"))
        check(!tv.recordItems().contains { $0.title.lowercased().contains("character") }, "a name that is a character already is not offered again")

        tv.setSelectedRange(text.range(of: "Старую Гавань"))
        fire(tv.recordItems().first { $0.title.lowercased().contains("place") })
        spin(0.3)
        let harbour = main.worlds.entries.first { $0.name == "Старую Гавань" }
        check(harbour != nil && harbour?.links[scene] == "" && panel.currentTab == .world && panel.worldTab.selectedID == harbour?.id, "Make a Place makes it in the first world, links the scene and shows it")

        // Another name for a card.
        setText(scene, "Он увидел Тихона у костра. Я смотрел. Старик молчал.")
        let elder = (tv.string as NSString).range(of: "Старик")
        tv.setSelectedRange(elder)
        let addName = tv.recordItems().first { $0.submenu != nil }
        let characterEntry = addName?.submenu?.items.first?.submenu?.items.first { $0.title == "Тихона" }
        fire(characterEntry)
        check(main.characters.character(tikhon?.id ?? "-")?.aliases.contains("Старик") == true, "Add as a Name of… gives a character one more name")
        check(SceneMembers.named(entries: main.characters.entries, in: "Пришёл Старик.").contains(tikhon?.id ?? "-"), "and the matching knows it")

        // The Right panel's buttons.
        let unlinked = try! main.characters.add(name: "Прохожий")
        panel.show(scene)
        panel.showTab(.characters)
        panel.selectCharacter(unlinked)
        check(panel.sceneLinkTitle == "Add to This Scene", "a character who is not in the scene gets Add to This Scene", "\(String(describing: panel.sceneLinkTitle))")
        panel.perform(NSSelectorFromString("sceneLinkPressed"))
        check(main.characters.character(unlinked)?.links[scene] == "" && panel.found.contains(unlinked) && panel.sceneLinkTitle == "Remove from This Scene", "pressing it links the scene, and the button turns into Remove")
        panel.perform(NSSelectorFromString("sceneLinkPressed"))
        check(main.characters.character(unlinked)?.links[scene] == nil && !panel.found.contains(unlinked), "and Remove takes the link away again")
        let named = try! main.characters.add(name: "Старик")
        _ = named
        panel.refresh(); panel.selectCharacter(tikhon?.id ?? "-")
        check(panel.sceneLinkTitle == nil, "a character whose name is in the text has no button: nothing to add", "\(String(describing: panel.sceneLinkTitle))")

        panel.showTab(.world)
        panel.worldTab.refresh(scene: scene)
        let other = try! main.worlds.addEntry(name: "Дальний лес", world: main.worlds.worlds[0].id!)
        panel.worldTab.allBox.state = .on
        panel.worldTab.selectedID = other
        panel.worldTab.refresh(scene: scene)
        check(panel.worldTab.sceneLinkTitle == "Add to This Scene", "the same button for a place that is not in the scene", "\(String(describing: panel.worldTab.sceneLinkTitle))")
        panel.worldTab.perform(NSSelectorFromString("sceneLinkPressed"))
        check(main.worlds.entry(other)?.links[scene] == "" && panel.worldTab.sceneLinkTitle == "Remove from This Scene", "pressing it links the scene to the place")

        // Clean up.
        panel.worldTab.allBox.state = .off
        for id in [unlinked, named, tikhon?.id ?? ""] where !id.isEmpty { try? main.characters.delete(id) }
        for id in [other, harbour?.id ?? ""] where !id.isEmpty { try? main.worlds.deleteEntry(id) }
        panel.setVisibleTabs([.section, .characters])
        main.setRightPanel(false); spin(0.3)
        return nil
    }
}
