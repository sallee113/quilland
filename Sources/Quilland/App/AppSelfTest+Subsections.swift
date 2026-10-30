import AppKit
import QuillandCore

/// Subsections of a scene: dividing at the cursor, the rows in the tree, a title and a narrator, joining with the previous one, and Undo.
extension AppSelfTest {
    func subsections() -> Int32? {
        let main = self.main!
        guard let scene = main.session.structure.scenes.first?.id else { check(false, "a scene for the checks"); return 1 }
        let original = text(scene)
        let anna = try! main.characters.add(name: "Подраздел-Анна")
        main.setMode(.panels); spin(0.4)
        setText(scene, "Первый абзац сцены.\nВторой абзац сцены.\nТретий абзац сцены.")
        main.reveal(scene: scene, range: NSRange(location: 0, length: 0)); spin(0.3)
        check(main.subsections(of: scene).isEmpty && main.subsectionCut(in: scene, caret: 0) == nil, "a scene with no markers has no subsections, and cannot be divided at its very top")

        // Divide at the paragraph the cursor is in.
        let secondStart = (text(scene) as NSString).range(of: "Второй").location
        main.reveal(scene: scene, range: NSRange(location: secondStart + 3, length: 0)); spin(0.3)
        check(main.subsectionCut(in: scene, caret: secondStart + 3) == secondStart, "the cut is at the start of the paragraph the cursor is in")
        main.divideIntoSubsections(); spin(0.5)
        let subs = main.subsections(of: scene)
        check(subs.count == 2 && subs.allSatisfy { $0.isMarked } && subs[0].derivedTitle.hasPrefix("Первый") && subs[1].derivedTitle.hasPrefix("Второй"), "dividing makes two subsections (the first part gets its marker too), titled by their first words", "\(subs.map(\.shownTitle))")
        let file = (try? String(contentsOf: main.session.structure.markdownURL(for: main.session.structure.scenes[0].node), encoding: .utf8)) ?? ""
        check(file.components(separatedBy: "<!-- fragment: ").count == 3 && file.hasPrefix("<!-- fragment: "), "the scene's file has a marker at the top and one at the cut", String(file.prefix(120)))
        check(main.session.structure.subsections[scene]?.count == 2 && SceneLinks.isSubsection(subs[1].id), "the structure knows them, and a link to one resolves to the scene")
        main.tree?.select(subs[1].id, notify: false); spin(0.2)
        check(main.tree?.visibleTitles.contains(subs[1].derivedTitle) == true, "the tree shows the subsections under their scene", "\(main.tree?.visibleTitles ?? [])")

        // Dividing again at a later paragraph adds one; a paragraph that begins a subsection cannot begin another.
        let thirdStart = (text(scene) as NSString).range(of: "Третий").location
        main.reveal(scene: scene, range: NSRange(location: thirdStart + 2, length: 0)); spin(0.3)
        main.divideIntoSubsections(); spin(0.5)
        check(main.subsections(of: scene).count == 3, "dividing again adds a subsection")
        let againAt = (text(scene) as NSString).range(of: "Третий").location
        check(main.subsectionCut(in: scene, caret: againAt) == nil, "a paragraph that begins a subsection cannot begin another")

        // A title typed, a narrator, and a link of a card to a subsection.
        let middle = main.subsections(of: scene)[1].id
        main.renameSubsection(scene: scene, id: middle, to: "Вечер"); spin(0.3)
        check(main.subsections(of: scene)[1].shownTitle == "Вечер" && main.subsections(of: scene)[1].title == "Вечер", "a title typed is kept (in the scene's data file) and shown")
        main.renameSubsection(scene: scene, id: middle, to: ""); spin(0.2)
        check(main.subsections(of: scene)[1].title.isEmpty && main.subsections(of: scene)[1].shownTitle.hasPrefix("Второй"), "and an empty one brings the first words back")
        try! main.characters.setNarrator(true, of: middle, character: anna)
        try! main.characters.update(anna) { var l = $0.links; l[middle] = "в середине"; $0.links = l }
        main.reloadStores()
        check(main.characters.narrators(of: middle).count == 1 && SceneMembers.linkedCharacters(inScene: scene, store: main.characters).contains(anna), "a narrator of a subsection, and a link to it, count for the scene")

        // The right panel's Section tab shows the subsection the cursor is in: a title (the first words stand in) and a narrator.
        main.setMode(.panels); spin(0.3)
        let panel = main.rightPanel
        _ = panel.view
        panel.showTab(.section); panel.show(scene)
        let inMiddle = (text(scene) as NSString).range(of: "Второй").location + 2
        main.reveal(scene: scene, range: NSRange(location: inMiddle, length: 0)); spin(0.4)
        panel.updateSubsectionRow()
        check(panel.shownSubsection?.id == middle && panel.subsectionNarrator.scene == middle && panel.subsectionNarrator.tickedTitles == ["Подраздел-Анна"], "the Section tab shows the subsection the cursor is in, with its narrator", "\(String(describing: panel.shownSubsection?.shownTitle)) \(panel.subsectionNarrator.tickedTitles)")
        panel.subsectionTitle.stringValue = "Вечер"
        panel.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: panel.subsectionTitle)); spin(0.3)
        check(main.subsections(of: scene)[1].title == "Вечер", "a title typed there is kept")
        main.renameSubsection(scene: scene, id: middle, to: "")

        // The cards: a link to a subsection is a row "Scene › Subsection", the Add menus list the subsections, and the scene still lists the character.
        app.modeCharacters(); spin(0.4)
        if let cv = main.charactersView {
            cv.select(anna); spin(0.2)
            check(cv.rows.contains { $0.sceneID == middle && $0.title.contains(" › ") && $0.title.contains("Второй") && $0.pov }, "the character's card lists the subsection it is linked to, with the point of view", "\(cv.rows.map(\.title))")
            check(!cv.addableScenes.contains { $0.contains(" › ") && $0.contains("Второй") } && cv.addableScenes.contains { $0.contains("Первый") }, "and the Add a Scene menu offers the other subsections")
        } else { check(false, "the Characters view shows") }
        // An event linked to a subsection: its row names the subsection.
        let event = try! main.eventStore.add(title: "Подраздел: событие")
        app.modeEvents(); spin(0.4)
        if let ev = main.eventsView {
            ev.reload(); ev.select(event); spin(0.2)
            ev.addScene(middle); spin(0.3)
            check(ev.connections.contains { $0.kind == .scene && $0.refID == middle && $0.name.contains(" › ") }, "an event linked to a subsection shows it by its place, scene and subsection", "\(ev.connections.map(\.name))")
            check(SceneLinks.has(main.eventStore.event(event)?.links ?? [:], scene: scene), "and counts for the scene")
        } else { check(false, "the Events view shows") }
        try? BookIntegrity.deleteEvent(event, book: main.folder, started: .deleteThem, snapshot: false)
        // Collect tells the model who "I" is in each subsection: its own narrator, else the scene's.
        try! main.characters.setNarrator(true, of: scene, character: anna)
        let narration = main.narration(of: scene)
        check(narration.narrators == ["Подраздел-Анна"] && narration.parts.count == 3 && narration.parts.allSatisfy { $0.narrators == ["Подраздел-Анна"] } && narration.parts[0].start == 0, "Collect reads each subsection with its narrators (the scene's where it has none of its own)", "\(narration)")
        try! main.characters.setNarrator(false, of: scene, character: anna)
        main.setMode(.panels); spin(0.4)

        // Join with the previous one: the boundary goes, and what was linked moves.
        main.joinSubsection(scene: scene, id: middle); spin(0.5)
        let joined = main.subsections(of: scene)
        check(joined.count == 2 && !joined.contains { $0.id == middle }, "joining takes a boundary away", "\(joined.map(\.shownTitle))")
        check(main.characters.character(anna)?.links[middle] == nil && main.characters.character(anna)?.links[joined[0].id] == "в середине" && main.characters.character(anna)?.povScenes == [joined[0].id], "what was linked to the joined one is linked to the one it joined")
        main.undoStructure(confirm: false); spin(0.6)
        check(main.subsections(of: scene).count == 3 && main.characters.character(anna)?.links[middle] == "в середине", "one Undo brings it back")
        main.joinSubsection(scene: scene, id: middle); spin(0.5)
        let last = main.subsections(of: scene)
        main.joinSubsection(scene: scene, id: last[1].id); spin(0.5)
        check(main.subsections(of: scene).isEmpty && !(((try? String(contentsOf: main.session.structure.markdownURL(for: main.session.structure.scenes[0].node), encoding: .utf8)) ?? "").contains("<!-- fragment")), "when one subsection is left the scene has no markers again")
        check(main.characters.character(anna)?.links[scene] == "в середине", "and what was linked to the subsections is linked to the scene")

        try? BookIntegrity.deleteCharacter(anna, book: main.folder, snapshot: false)
        setText(scene, original)
        main.reloadStores(); spin(0.3)
        return nil
    }
}
