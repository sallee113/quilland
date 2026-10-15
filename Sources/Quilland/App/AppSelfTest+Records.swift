import AppKit
import QuillandCore

/// The Characters view and relationships.
extension AppSelfTest {
    func records() -> Int32? {
        let main = self.main!
        let sc = self.sc!
        let folder = self.folder!
        // The Characters view.
        app.modeCharacters(); spin(0.5)
        guard let cv = main.charactersView else { check(false, "View ▸ Characters shows the view"); return 1 }
        check(main.mode == .characters && cv.shownNames == ["Анна Петровна"], "View ▸ Characters lists the characters of the book", "\(cv.shownNames)")
        check(main.localState().mode == "characters", "and it is the view remembered for the book")
        let petr = cv.addCharacter(named: "  Пётр ")!
        check(cv.shownNames.contains("Пётр") && cv.selected == petr && cv.nameField.stringValue == "Пётр", "a typed name makes a character and opens its card")
        check(cv.addCharacter(named: "   ") == nil, "a blank name makes nothing")
        cv.profile.string = "Высокий, молчаливый."
        cv.textDidChange(Notification(name: NSText.didChangeNotification, object: cv.profile))
        cv.commitEdits()
        check(main.characters.profile(petr) == "Высокий, молчаливый.", "the profile is written to the character's text file")
        cv.aliasField.stringValue = "Петя, Петруша"
        cv.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: cv.aliasField))
        check(main.characters.character(petr)?.aliases == ["Петя", "Петруша"], "other names are split at commas")
        cv.mainBox.performClick(nil)
        check(main.characters.character(petr)?.main == true && cv.shownNames.first == "Пётр", "a main character goes to the top of the list")
        cv.nameField.stringValue = "Пётр Иванович"
        cv.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: cv.nameField))
        check(main.characters.character(petr)?.name == "Пётр Иванович" && cv.shownNames.first == "Пётр Иванович", "renaming changes the card and the list")
        setText(sc[0].id, "Петя вошёл. Пётр Иванович сел. Анне Петровне стало легче.")
        cv.select(petr)
        check(cv.rows.count == 1 && cv.rows[0].sceneID == sc[0].id && cv.rows[0].mentions == 2, "the card lists the scenes where the name is, with how often", "\(cv.rows)")
        cv.setSceneLine(row: 0, "Входит и садится.")
        cv.setScenePOV(row: 0, true)
        check(main.characters.character(petr)?.links[sc[0].id] == "Входит и садится." && main.characters.character(petr)?.povScenes == [sc[0].id], "what the character does and the point of view are saved")
        setText(sc[0].id, "Здесь никого.")
        cv.select(petr)
        check(cv.rows.count == 1 && cv.rows[0].mentions == 0 && cv.rows[0].pov, "a scene with a line or the point of view stays in the list although the name is gone")
        cv.filterField.stringValue = "анна"
        cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField))
        check(cv.shownNames == ["Анна Петровна"], "the filter narrows the list")
        cv.filterField.stringValue = ""
        cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField))
        // Relationships.
        setText(sc[0].id, "Петя вошёл. Анне Петровне стало легче.")
        let relAnna = main.characters.characters.first { $0.name == "Анна Петровна" }!.id!
        let rel = cv.addRelationship([relAnna, petr], kind: "друзья")!
        check(cv.relationshipTitles == ["Анна Петровна, Пётр Иванович — друзья"] && cv.selectedRelationship == rel && cv.relCard.shownID == rel, "New Relationship makes one and opens its card")
        check(cv.relCard.sceneRows.contains { $0.sceneID == sc[0].id && $0.mentions > 0 }, "its card lists the scenes where both characters are named")
        cv.relCard.setSceneLine(row: 0, "спорят о доме")
        check(main.relationships.relationship(rel)?.links[sc[0].id] == "спорят о доме", "and what the relationship does there is saved")
        cv.relCard.kindField.stringValue = "соседи"
        cv.relCard.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: cv.relCard.kindField))
        check(main.relationships.relationship(rel)?.kind == "соседи" && cv.relationshipTitles == ["Анна Петровна, Пётр Иванович — соседи"], "the kind can be changed, and the list follows")
        // A relationship's notes typed a moment ago (its own save waits for a timer) are saved when the book saves everything (before a merge, a close).
        cv.relCard.notes.string = "Соседи по лестнице."
        cv.relCard.textDidChange(Notification(name: NSText.didChangeNotification, object: cv.relCard.notes))
        let waiting = RelationshipStore(book: main.folder).relationship(rel)?.notes != ["Соседи по лестнице."]
        main.saveAll()
        check(waiting && RelationshipStore(book: main.folder).relationship(rel)?.notes == ["Соседи по лестнице."], "what was typed in a relationship's card is saved by Save All, not left to its timer")
        check(cv.addRelationship([relAnna], kind: "один") == nil, "a relationship needs two characters")
        cv.select(petr)
        check(cv.selectedRelationship == nil && main.relationships.relationships(of: petr).count == 1, "choosing a character shows the character again")
        for ext in ["json", "md"] { try? FileManager.default.removeItem(at: main.folder.appendingPathComponent("bible/relationships/\(rel).\(ext)")) }
        cv.reloadRelationships()
        cv.onOpenScene?(sc[0].id); spin(0.5)
        check(main.mode == main.writingMode && main.currentSceneID == sc[0].id, "opening a scene from the card goes to the text")
        app.modeCharacters(); spin(0.4)
        let cv2 = main.charactersView!
        cv2.select(petr)
        cv2.deleteSelected(confirm: false)
        check(main.characters.character(petr) == nil && cv2.shownNames == ["Анна Петровна"], "deleting a character takes it out of the list")
        check(!(((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(".quilland/trash").path)) ?? []).isEmpty), "and into the trash folder")
        self.cv2 = cv2
        return nil
    }
}
