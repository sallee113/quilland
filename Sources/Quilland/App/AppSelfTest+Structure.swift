import AppKit
import QuillandCore

/// Splitting, merging and grouping scenes, Undo of the structure, the scene header.
extension AppSelfTest {
    func structure() -> Int32? {
        let folder = self.folder!
        let again = self.again!
        // Quitting keeps the book as the one to open next time.
        _ = app.applicationShouldTerminate(NSApp)
        check(AppSettings(directory: app.settings.directory).lastOpened == folder.path, "quitting with a book open keeps it as the book to reopen")
        again.window.close(); spin(0.2)

        // Split, merge, group, and undo of structure (in a book of its own).
        guard let folder2 = create(title: "Structure Test", plan: false) else { check(false, "the book for the structure checks is made"); return 1 }
        spin(0.6)
        guard let win2 = app.bookWindows.last, win2.folder.standardizedFileURL == folder2.standardizedFileURL else { return 1 }
        win2.usesFullScreen = false
        let m2 = win2.main
        func scenesNow() -> [BookStructure.SceneEntry] { (try? BookStructure.load(folder: folder2).scenes) ?? [] }
        func plain(_ id: String) -> String { m2.session.document(id)?.storage.string ?? "" }
        let s0 = m2.session.structure.scenes[0].id
        let d0 = m2.session.document(s0)!
        d0.storage.replaceCharacters(in: NSRange(location: 0, length: d0.storage.length), with: "Первый абзац.\nВторой абзац.\nТретий абзац.")
        d0.textDidChange(); d0.updateCounts(); _ = d0.saveNow()
        m2.reveal(scene: s0, range: nil); spin(0.3)
        m2.controllers[0].currentSheet?.textView.setSelectedRange(NSRange(location: 14, length: 0))
        m2.splitSceneHere(); spin(0.6)
        var sc2 = scenesNow()
        check(sc2.count == 2 && sc2[0].id == s0, "Split Scene Here makes a second scene after the first")
        let splitFirstText = (try? String(contentsOf: m2.session.structure.markdownURL(for: m2.session.structure.scenes[0].node), encoding: .utf8)) ?? ""
        let splitSecondText = (try? String(contentsOf: m2.session.structure.markdownURL(for: m2.session.structure.scenes[1].node), encoding: .utf8)) ?? ""
        check(splitFirstText.contains("Первый абзац.") && !splitFirstText.contains("Второй") && splitSecondText.contains("Второй абзац.") && splitSecondText.contains("Третий абзац.") && !splitSecondText.contains("Первый"), "the text is cut between the paragraphs", "first \(splitFirstText.debugDescription) second \(splitSecondText.debugDescription)")
        check(sc2[1].node.title == "Сцена 1 2" && sc2[1].node.status == sc2[0].node.status && m2.currentSceneID == sc2[1].id, "the new scene has a title made from the old one, the same status, and the cursor is in it")
        check(m2.banner.isShowing && m2.undoStack.count == 1 && m2.tree?.canUndo() == true, "a banner offers Undo, and ⌘Z in the tree is ready")
        check(!SnapshotStore(bookFolder: folder2).changed(since: m2.undoStack[0].post!), "right after a change the book is the same as the snapshot taken after it, so Undo does not ask")
        m2.undoStructure(); spin(0.6)
        sc2 = scenesNow()
        let backText = (try? String(contentsOf: m2.session.structure.markdownURL(for: m2.session.structure.scenes[0].node), encoding: .utf8)) ?? ""
        check(sc2.count == 1 && backText.contains("Второй абзац.") && backText.contains("Третий абзац.") && m2.undoStack.isEmpty, "Undo puts the scene back whole")
        check(m2.redoStack.count == 1 && m2.tree?.canRedo() == true && m2.banner.text.hasPrefix("Undone"), "after Undo, Redo is ready (in the tree and on the banner)")
        check(!SnapshotStore(bookFolder: folder2).changed(since: m2.redoStack[0].pre), "and right after an Undo the book is the one Redo expects, so Redo does not ask")
        m2.redoStructure(); spin(0.6)
        sc2 = scenesNow()
        check(sc2.count == 2 && m2.undoStack.count == 1 && m2.redoStack.isEmpty, "Redo splits the scene again")
        m2.undoStructure(); spin(0.6)
        check(scenesNow().count == 1 && m2.redoStack.count == 1, "and Undo once more takes it back")
        m2.reveal(scene: s0, range: nil); spin(0.3)
        // Split again, then merge with links to move.
        m2.reveal(scene: s0, range: nil); spin(0.3)
        m2.controllers[0].currentSheet?.textView.setSelectedRange(NSRange(location: 14, length: 0))
        m2.splitSceneHere(); spin(0.6)
        sc2 = scenesNow()
        let anna2 = try! m2.characters.add(name: "Анна")
        try! m2.characters.update(anna2) { $0.links = [sc2[1].id: "приходит"] }
        m2.merge(sc2[0].id, direction: 1, confirm: false); spin(0.6)
        sc2 = scenesNow()
        let mergedText = (try? String(contentsOf: m2.session.structure.markdownURL(for: m2.session.structure.scenes[0].node), encoding: .utf8)) ?? ""
        check(sc2.count == 1 && mergedText.contains("Первый абзац.") && mergedText.contains("Третий абзац."), "Merge with Next joins two scenes into the first")
        check(m2.characters.character(anna2)?.links.keys.contains(sc2[0].id) == true && m2.characters.character(anna2)?.links.count == 1, "and the links to the second scene now point at the first")
        m2.undoStructure(confirm: false); spin(0.6)
        sc2 = scenesNow()
        check(sc2.count == 2 && m2.characters.character(anna2)?.links.keys.contains(sc2[1].id) == true, "Undo brings back the second scene and its link")
        m2.undoStructure(confirm: false); spin(0.6)
        check(scenesNow().count == 1, "and a second Undo goes one change further back")
        // Group and ungroup.
        m2.add(.chapter); spin(0.5)
        let chapters = m2.session.structure.roots.map(\.id)
        check(chapters.count == 2, "a second chapter")
        m2.groupChapters(chapters, titled: "Часть первая"); spin(0.6)
        var roots2 = (try? BookStructure.load(folder: folder2).roots) ?? []
        check(roots2.count == 1 && roots2[0].kind == .part && roots2[0].children.map(\.id) == chapters, "Group into a New Part puts the chapters in a part")
        m2.ungroupPart(roots2[0].id, confirm: false); spin(0.6)
        roots2 = (try? BookStructure.load(folder: folder2).roots) ?? []
        check(roots2.map(\.id) == chapters, "Ungroup Part gives the chapters back")
        m2.undoStructure(confirm: false); spin(0.6)
        roots2 = (try? BookStructure.load(folder: folder2).roots) ?? []
        check(roots2.count == 1 && roots2[0].kind == .part, "and Undo brings the part back")
        check(BookStructure.problemsFree(folder2), "the book on disk reads without problems")
        // The scene header: a click on the title renames, a click on the dot chooses the status.
        m2.setMode(.book); spin(0.5)
        let headers: [SceneHeaderView] = m2.controllers[0].stack.rows.compactMap { if case .header(let h) = $0 { return h }; return nil }
        if let hdr = headers.first {
            let sceneID = hdr.document.id
            hdr.titleField.stringValue = "Новое название"
            hdr.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: hdr.titleField))
            spin(0.3)
            check(m2.session.document(sceneID)?.title == "Новое название" && scenesNow().first { $0.id == sceneID }?.node.title == "Новое название", "typing in the title of a scene header renames the scene, in the file too")
            hdr.titleField.stringValue = "   "
            hdr.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: hdr.titleField))
            check(hdr.titleField.stringValue == "Новое название", "a blank title is refused and the old one comes back")
            hdr.chooseStatus("done")
            spin(0.3)
            check(m2.session.document(sceneID)?.status == "done" && scenesNow().first { $0.id == sceneID }?.node.status == "done", "the status chosen from the dot's menu is saved")
        } else { check(false, "Book mode has scene headers") }
        win2.window.close(); spin(0.3)
        return nil
    }
}
