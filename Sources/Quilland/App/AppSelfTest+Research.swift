import AppKit
import QuillandCore

/// The Research view: documents with typed text, a file, or both.
extension AppSelfTest {
    func research() -> Int32? {
        let main = self.main!
        let folder = self.folder!
        let before = main.mode
        app.modeResearch(); spin(0.5)
        guard let rv = main.researchView else { check(false, "View ▸ Research shows the view"); return 1 }
        check(main.mode == .research && rv.shownTitles.isEmpty && main.localState().mode == "research", "View ▸ Research opens an empty list and is remembered as the view")
        check(rv.addDocument(titled: "   ") == nil, "a blank title makes nothing")
        let id = rv.addDocument(titled: "Музыкальное образование в США")!
        check(rv.shownTitles == ["Музыкальное образование в США"] && rv.selected == id && rv.titleField.stringValue == "Музыкальное образование в США", "a typed title makes a document and opens its card")
        check(rv.fileText.hasPrefix("No file"), "a document may have no file: its text is the whole document", rv.fileText)

        // Typed text and the source, saved when the view is left before the timer fires.
        rv.textView.string = "Лоуэлл Мейсон ввёл пение в школы Бостона в 1838 году."
        rv.textDidChange(Notification(name: NSText.didChangeNotification, object: rv.textView))
        rv.sourceField.stringValue = "Mark, A History of American Music Education"
        rv.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: rv.sourceField))
        app.modeBook(); spin(0.3)
        check(ResearchStore(book: folder).text(id).contains("Лоуэлл Мейсон") && ResearchStore(book: folder).document(id)?.source.hasPrefix("Mark") == true, "the text and the source are saved")

        // A file: copied into the book, then replaced by a link to a file left outside.
        let outside = temp.appendingPathComponent("hearings.txt")
        try? Data("материал".utf8).write(to: outside)
        app.modeResearch(); spin(0.4)
        let rv2 = main.researchView!
        check(rv2.attachFile(outside, embed: true) && rv2.fileText.contains("hearings.txt") && rv2.fileText.contains("copied into the book"), "a file can be copied into the book", rv2.fileText)
        check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("research/\(id).file/hearings.txt").path), "and lies in the research folder under its own name")
        check(ResearchStore(book: folder).text(id).contains("Лоуэлл Мейсон"), "the typed text is still there beside the file")
        check(rv2.attachFile(outside, embed: false) && !FileManager.default.fileExists(atPath: folder.appendingPathComponent("research/\(id).file/hearings.txt").path), "a link replaces the copy, which goes to the trash")
        try? FileManager.default.removeItem(at: outside)
        rv2.reload()
        check(rv2.fileText.contains("missing"), "a linked file that is gone is shown as missing, not dropped", rv2.fileText)
        check(ResearchStore(book: folder).document(id)?.file?.name == "hearings.txt", "and the document keeps what it knew about it")
        rv2.takeFileOff()
        check(ResearchStore(book: folder).document(id)?.file == nil && ResearchStore(book: folder).text(id).contains("Лоуэлл Мейсон"), "taking the file off keeps the text")

        // A large copy is asked about; refusing changes nothing.
        let big = temp.appendingPathComponent("big.bin")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: big) { try? h.truncate(atOffset: UInt64(ResearchStore.embedWarningBytes + 1)); try? h.close() }
        var asked = false
        rv2.confirmLargeEmbed = { _ in asked = true; return false }
        check(!rv2.attachFile(big, embed: true) && asked && ResearchStore(book: folder).document(id)?.file == nil, "a copy over 20 MB is asked about, and refusing adds nothing")
        check(rv2.attachFile(big, embed: false), "while a link to the same file needs no question")
        try? FileManager.default.removeItem(at: big)
        rv2.takeFileOff()

        // Links.
        let scene = main.session.structure.scenes[0]
        let character = main.characters.characters[0]
        rv2.addLink(scene.id)
        rv2.addLink(character.id!)
        if let bookID = rv2.bookID() { rv2.addLink(bookID) }
        check(rv2.links.map(\.kind.rawValue) == ["Book", "Scene", "Character"] && rv2.links.allSatisfy { !$0.missing }, "a document links to the book, a scene and a character", "\(rv2.links.map(\.kind.rawValue))")
        rv2.setLinkText(row: 1, "урок пения")
        check(ResearchStore(book: folder).document(id)?.links[scene.id] == "урок пения", "the remark is saved")
        check(ResearchStore(book: folder).linked(to: scene.id).count == 1, "and the scene finds the document by its link")
        rv2.removeLink(row: 2)
        check(rv2.links.count == 2, "a link can be taken away")
        var openedScene: String?
        rv2.onOpenScene = { openedScene = $0 }
        rv2.onOpenScene?(scene.id)
        check(openedScene == scene.id, "a link can open its scene")

        // The right panel's tab shows what is linked to the scene, and its text can be changed there.
        let panel = main.rightPanel
        _ = panel.view
        panel.setVisibleTabs([.section, .characters, .research]); panel.showTab(.research)
        panel.researchTab.refresh(scene: scene.id)
        check(panel.researchTab.rowIDs == [id] && panel.researchTab.detail.stringValue.contains("урок пения"), "the Research tab lists the documents linked to the scene, with the remark", "\(panel.researchTab.rowIDs) \(panel.researchTab.detail.stringValue)")
        panel.researchTab.notes.string = "Дополнено на вкладке."
        panel.researchTab.textDidChange(Notification(name: NSText.didChangeNotification, object: panel.researchTab.notes))
        panel.researchTab.commitEdits()
        check(ResearchStore(book: folder).text(id) == "Дополнено на вкладке.", "and the text is changed there")
        panel.researchTab.selectedID = id
        panel.researchTab.refresh(scene: scene.id)
        check(panel.researchTab.fileLink.isHidden, "a document with no file shows no file link")
        let linkedFile = temp.appendingPathComponent("link-me.txt")
        try? Data("x".utf8).write(to: linkedFile)
        rv2.attachFile(linkedFile, embed: true)
        panel.researchTab.refresh(scene: scene.id)
        var opened: URL?
        panel.researchTab.openURL = { opened = $0 }
        check(!panel.researchTab.fileLink.isHidden && panel.researchTab.fileLink.attributedTitle.string == "link-me.txt" && panel.researchTab.fileLink.isEnabled, "the file of the chosen document is shown as a link")
        panel.researchTab.fileLink.performClick(nil)
        check(opened?.path == main.researchStore.fileURL(id)?.path, "a click opens the file with the system's program for it", "\(String(describing: opened))")
        rv2.takeFileOff()
        try? FileManager.default.removeItem(at: linkedFile)
        panel.researchTab.refresh(scene: scene.id)
        check(panel.researchTab.fileLink.isHidden, "and the link goes when the file is taken off")
        let quick = panel.researchTab.addDocument(titled: "  Заметка из панели ")!
        check(panel.researchTab.rowIDs.contains(quick) && panel.researchTab.selectedID == quick && ResearchStore(book: folder).linked(to: scene.id).contains { $0.id == quick }, "a title typed in the tab makes a document linked to the scene, and selects it")
        check(panel.researchTab.addDocument(titled: "   ") == nil, "a blank title makes nothing")
        let withFile = temp.appendingPathComponent("Конспект.txt")
        try? Data("файл".utf8).write(to: withFile)
        let fromFile = panel.researchTab.addDocument(titled: "Конспект", file: withFile)!
        check(ResearchStore(book: folder).document(fromFile)?.file?.embedded == true && ResearchStore(book: folder).document(fromFile)?.links[scene.id] != nil, "a document made from a file has the file copied in and is linked to the scene")
        try? FileManager.default.removeItem(at: withFile)
        for extra in [quick, fromFile] { try? main.researchStore.delete(extra) }
        panel.researchTab.refresh(scene: scene.id)
        panel.researchTab.refresh(scene: "no-such-scene")
        check(panel.researchTab.rowIDs.isEmpty, "a scene with no links shows none")
        panel.setVisibleTabs([.section, .characters])
        rv2.reload(); rv2.select(id)
        rv2.textView.string = "Лоуэлл Мейсон ввёл пение в школы Бостона в 1838 году."
        rv2.textDidChange(Notification(name: NSText.didChangeNotification, object: rv2.textView)); rv2.commitEdits()

        // The filter looks in the text too.
        rv2.filterField.stringValue = "бостон"
        rv2.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: rv2.filterField))
        check(rv2.shownTitles.count == 1, "the filter finds a word in the typed text", "\(rv2.shownTitles)")
        rv2.filterField.stringValue = "ничего-такого"
        rv2.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: rv2.filterField))
        check(rv2.shownTitles.isEmpty, "and shows nothing when there is none")
        rv2.filterField.stringValue = ""
        rv2.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: rv2.filterField))

        // Undo of the structure and the snapshots read the files again, so a restored book shows the right documents.
        main.reloadStores()
        check(main.researchStore.document(id) != nil, "reading the data files again keeps the documents")

        rv2.deleteSelected(confirm: false)
        check(ResearchStore(book: folder).documents.isEmpty && main.researchStore.problems.isEmpty, "a deleted document leaves the book")
        let trash = (try? FileManager.default.subpathsOfDirectory(atPath: folder.appendingPathComponent(".quilland/trash").path)) ?? []
        check(trash.contains { $0.hasSuffix("research/\(id).json") } && trash.contains { $0.hasSuffix("research/\(id).md") }, "and goes to the trash folder with its text")

        // Opening the view writes nothing by itself.
        let listing = { (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("research").path)) ?? [] }
        let filesBefore = listing()
        app.modeBook(); spin(0.2); app.modeResearch(); spin(0.3); app.modeBook(); spin(0.2)
        check(listing() == filesBefore, "looking at the Research view changes no file")
        if before != .research { main.setMode(before == .research ? main.writingMode : before) }
        spin(0.2)
        return nil
    }
}
