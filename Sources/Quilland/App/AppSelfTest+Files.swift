import AppKit
import QuillandCore

/// Export, import, snapshots.
extension AppSelfTest {
    func files() -> Int32? {
        // Export.
        app.booksParent = temp
        guard let exFolder = create(title: "Export Test", plan: false) else { check(false, "the book for the export checks is made"); return 1 }
        spin(0.6)
        guard let exWin = app.bookWindows.last else { return 1 }
        exWin.usesFullScreen = false
        let exMain = exWin.main
        let exScenes = exMain.session.structure.scenes
        let exDoc = exMain.session.document(exScenes[0].id)!
        exDoc.storage.replaceCharacters(in: NSRange(location: 0, length: exDoc.storage.length), with: "Первый абзац главы.\nВторой абзац.")
        exDoc.textDidChange(); _ = exDoc.saveNow()
        _ = exMain.add(.scene) as Void
        spin(0.5)
        exMain.add(.chapter); spin(0.5)
        let exMore = try! BookStructure.load(folder: exFolder)
        let secondDoc = exMore.scenes[1]
        try! Data("Текст второй сцены.\n".utf8).write(to: exMore.markdownURL(for: secondDoc.node))
        guard let ex = try? ExportWindowController(folder: exFolder) else { check(false, "the Export window opens"); return 1 }
        ex.show(); spin(0.3)
        check(ex.profileNames == ["Manuscript DOCX"] && ex.format == .docx && !ex.isEdited, "Export starts with a profile and nothing edited")
        ex.setFormat(.epub)
        check(ex.isEdited && ex.format == .epub, "a changed choice shows the profile as edited")
        ex.revertCurrent()
        check(!ex.isEdited && ex.format == .docx, "Revert goes back to the saved profile")
        ex.setFormat(.epub); ex.setTOC(false)
        ex.saveCurrent()
        check(!ex.isEdited && ExportStore(book: exFolder).profile(named: "Manuscript DOCX")?.format == "epub" && ExportStore(book: exFolder).profile(named: "Manuscript DOCX")?.toc == false, "Save writes the profile into export.json")
        ex.addProfile(ExportStore.defaultProfile(name: "Для читалки", format: .fb2))
        check(ex.profileNames == ["Manuscript DOCX", "Для читалки"] && ex.format == .fb2 && ExportStore(book: exFolder).lastProfile == "Для читалки", "a new profile is added and becomes the last used")
        ex.removeProfile("Для читалки")
        check(ex.profileNames == ["Manuscript DOCX"], "a profile can be deleted")
        let exBefore = ex.summary
        check(exBefore.scenes == 3 && ex.titlesText.contains("1. Глава 1"), "the titles of the book are listed from the plan", ex.titlesText)
        ex.setHeading("chapter", print: "title")
        check(ex.titlesText.contains("Глава 1") && !ex.titlesText.contains("1. Глава 1") && ex.isEdited, "headings follow the profile's choice")
        ex.setHeading("chapter", print: "number_and_title", template: "Chapter {number}: {title}")
        check(ex.titlesText.contains("Chapter 1: Глава 1"), "and its template")
        ex.setIncluded(Array(ex.sceneIDs.prefix(2)), false)
        check(ex.summary.scenes == 1 && ex.summaryText.hasPrefix("1 scene,"), "unticked scenes leave the book", ex.summaryText)
        ex.setIncluded(ex.sceneIDs, true)
        ex.setStatuses(["done"])
        check(ex.summary.scenes == 0, "a status filter leaves out scenes in other statuses")
        ex.setStatuses(["idea", "draft", "revised", "done"])
        check(ex.summary.scenes == 3, "and with all four ticked everything is in again")
        ex.setTOCScenes(true)
        check(ex.isEdited && ex.options.tocScenes, "the contents can list the scenes (a choice of the profile)")
        ex.setFormat(.epub)
        ex.saveCurrent()
        check(ExportStore(book: exFolder).profile(named: "Manuscript DOCX")?.tocScenes == true, "and the profile keeps it")
        let outDir = temp.appendingPathComponent("exports")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        ex.setFolder(outDir)
        check(LocalBookState.load(book: exFolder).exportFolder == outDir.path, "the chosen folder is remembered for this book, outside the book's files")
        var made: [String: Int] = [:]
        for f in ExportFormat.allCases {
            ex.setFormat(f)
            if let url = try? ex.exportNow(to: outDir) { made[f.rawValue] = (try? Data(contentsOf: url).count) ?? 0 }
        }
        check(made.count == ExportFormat.allCases.count && made.values.allSatisfy { $0 > 100 }, "every format makes a file", "\(made)")
        if let pdf = outDir.appendingPathComponent("Export Test.pdf") as URL?, let doc = CGPDFDocument(pdf as CFURL) {
            check(doc.numberOfPages >= 2 && (try? Data(contentsOf: pdf).prefix(5)) == Data("%PDF-".utf8), "the PDF is a real, paginated PDF (a title page and the text)", "\(doc.numberOfPages)")
        } else { check(false, "the PDF can be read") }
        let txtText = (try? String(contentsOf: outDir.appendingPathComponent("Export Test.txt"), encoding: .utf8)) ?? ""
        check(txtText.contains("Первый абзац главы.") && txtText.contains("Текст второй сцены."), "the exported text has what was typed (the open scene was saved first)")
        check(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("Export Test.epub").path), "the file is named from the book's title")
        ex.window.close()
        app.showExport(); spin(0.3)
        check(app.exportWindowCount == 1, "File ▸ Export… opens the window for the book")
        app.showExport()
        check(app.exportWindowCount == 1, "and asking again brings the same window forward")

        // Import.
        let md = "# Дом на Сосновой\n\n## Глава 1\n\nПервый абзац.\n\nВторой абзац.\n\n* * *\n\nТретий.\n\n## Глава 2\n\nТекст **жирный**.\n"
        let im = ImportWindowController()
        im.language = "ru"
        im.openBookName = "Export Test"
        im.intoOpenBook = { exMain.performImport($0) }
        im.intoNewBook = { [app] plan, title, language in app.importIntoNewBook(plan, title: title, language: language) }
        im.applyDestinationChoices()
        im.show()
        im.loadText(md, source: .markdown); spin(0.2)
        do {
            // Every column of the kinds table, "Becomes" among them, is inside the table.
            func tableIn(_ v: NSView) -> NSTableView? { (v as? NSTableView) ?? v.subviews.lazy.compactMap(tableIn).first }
            im.window.contentView?.layoutSubtreeIfNeeded()
            if let table = im.window.contentView.flatMap(tableIn), let scroll = table.enclosingScrollView {
                let titles = table.tableColumns.map(\.title)
                let lastRight = table.tableColumns.indices.map { table.rect(ofColumn: $0).maxX }.max() ?? 0
                check(titles.contains("Becomes") && lastRight <= scroll.contentView.bounds.width + 1, "the Import window shows every column of the kinds table, with the choice of what a line becomes", "\(titles) right \(lastRight) of \(scroll.contentView.bounds.width)")
            } else { check(false, "the kinds table is there") }
        }
        check(im.kinds.map(\.id) == ["h1", "h2", "break"] && im.treeTitles == ["Глава 1", "  Сцена 1", "  Сцена 2", "Глава 2", "  Сцена 1"], "Import analyses the text and shows the tree that will be made", "\(im.kinds.map(\.id)) \(im.treeTitles)")
        check(im.summaryText.hasPrefix("0 parts, 2 chapters, 3 scenes"), "with the size of what will be made", im.summaryText)
        im.setOptions(split: false)
        check(im.plan.sceneCount == 2, "the scene breaks can be left in the text")
        im.setOptions(split: true)
        im.setRole("h2", .scene)
        check(im.plan.chapterCount == 1 && im.plan.sceneCount >= 2, "choosing another role for a kind changes the tree")
        im.setRole("h2", .chapter)
        check(im.importEnabled, "Import is ready")
        let scenesBefore = exMain.session.structure.scenes.count
        im.chooseDestination(openBook: true)
        check(im.performImport(), "Import into the open book goes through")
        spin(0.6)
        check(exMain.session.structure.scenes.count == scenesBefore + 3 && exMain.banner.isShowing && exMain.undoStack.last?.name == "Import", "three scenes are added at the end, with a banner offering Undo")
        check(BookStructure.problemsFree(exFolder), "the book reads without problems after the import")
        exMain.undoStructure(confirm: false); spin(0.6)
        check(exMain.session.structure.scenes.count == scenesBefore, "Undo takes the import back")
        // A real file from the disk (a Russian name, as the file chooser gives it).
        do {
            let file = temp.appendingPathComponent("Моя книга.md")
            try? Data(md.utf8).write(to: file)
            let fromDisk = ImportWindowController()
            fromDisk.language = "ru"
            fromDisk.loadFile(file); spin(0.3)
            check(fromDisk.kinds.map(\.id) == ["h1", "h2", "break"] && fromDisk.treeTitles.count == 5 && fromDisk.summaryText.hasPrefix("0 parts, 2 chapters, 3 scenes"), "a Markdown file from the disk is read, analysed and shown", "\(fromDisk.kinds.map(\.id)) \(fromDisk.treeTitles) \(fromDisk.summaryText)")
            fromDisk.window.close()
        }
        // A long book is read in the background, and the window stays alive meanwhile.
        do {
            var big = "# Большая книга\n\n"
            for c in 1...30 { big += "## Глава \(c)\n\n"; for s in 1...6 { if s > 1 { big += "* * *\n\n" }; for _ in 1...20 { big += "Это абзац, в котором достаточно слов, чтобы текст стал длинным и заметным для проверки. Анна пошла дальше по дороге.\n\n" } } }
            let file = temp.appendingPathComponent("Большая.md")
            try? Data(big.utf8).write(to: file)
            let slow = ImportWindowController()
            slow.language = "ru"
            slow.loadFile(file)
            let readingAtOnce = slow.summaryText
            for _ in 0..<80 where slow.summaryText == readingAtOnce { spin(0.1) }
            check(big.utf8.count > 300_000 && readingAtOnce == "Reading…" && slow.treeTitles.count == 30 + 180 && slow.summaryText.hasPrefix("0 parts, 30 chapters, 180 scenes"), "a long file is read in the background, and the tree arrives", "\(big.utf8.count) \(readingAtOnce) | \(slow.treeTitles.count) \(slow.summaryText)")
            slow.window.close()
        }
        let im2 = ImportWindowController()
        im2.intoNewBook = { [app] plan, title, language in app.importIntoNewBook(plan, title: title, language: language) }
        im2.applyDestinationChoices()
        im2.loadText(md, source: .markdown); spin(0.2)
        let windowsBefore = app.bookWindows.count
        check(!im2.importsIntoOpenBook && im2.importEnabled, "with no open book, Import goes into a new book, titled from the text's one H1")
        check(im2.performImport(), "Import into a new book goes through")
        spin(0.8)
        let newBook = app.bookWindows.last
        check(app.bookWindows.count == windowsBefore + 1 && newBook?.bookTitle == "Дом на Сосновой" && newBook?.main.session.structure.scenes.count == 3, "the new book opens with the imported scenes and no empty first chapter", "\(String(describing: newBook?.bookTitle)) \(String(describing: newBook?.main.session.structure.scenes.count))")
        newBook?.window.close(); exWin.window.close(); spin(0.3)

        // Snapshots.
        guard let snFolder = create(title: "Snapshot Test", plan: false) else { check(false, "the book for the snapshot checks is made"); return 1 }
        spin(0.6)
        guard let snWin = app.bookWindows.last else { return 1 }
        snWin.usesFullScreen = false
        let snMain = snWin.main
        func setScene(_ index: Int, _ text: String) {
            let entry = snMain.session.structure.scenes[index]
            let doc = snMain.session.document(entry.id)!
            doc.storage.replaceCharacters(in: NSRange(location: 0, length: doc.storage.length), with: text)
            doc.textDidChange(); doc.updateCounts(); _ = doc.saveNow()
        }
        func sceneFile(_ index: Int) -> String {
            let s = (try? BookStructure.load(folder: snFolder)) ?? BookStructure(folder: snFolder)
            return s.scenes.indices.contains(index) ? ((try? String(contentsOf: s.markdownURL(for: s.scenes[index].node), encoding: .utf8)) ?? "") : "(none)"
        }
        setScene(0, "Первый абзац.\nВторой абзац.")
        snMain.add(.scene); spin(0.5)
        setScene(1, "Текст второй сцены.")
        let snStore = SnapshotStore(bookFolder: snFolder)
        check(snWin.saveSnapshot() && snStore.list().last?.kind == .manual && snStore.list().last?.reason == "Saved" && snMain.banner.isShowing, "⌘S takes a saved snapshot and says so")
        check(snWin.saveSnapshot(named: "До правки") && snStore.list().last?.name == "До правки", "⌥⌘S takes a named one")
        check(!snWin.automaticSnapshot(), "an automatic snapshot is not taken when nothing changed since the newest")
        setScene(0, "Первый абзац.\nВторой абзац изменён.\nТретий абзац.")
        check(snWin.automaticSnapshot() && snStore.list().last?.kind == .automatic && !snWin.automaticSnapshot(), "it is taken when something changed, and once")
        let namedInfo = snStore.list().first { $0.name == "До правки" }!
        // The book moves on: the first scene is changed again and the second one is deleted.
        setScene(0, "Совсем другой текст.")
        snMain.delete(snMain.session.structure.scenes[1].id, confirm: false); spin(0.6)
        check(snMain.session.structure.scenes.count == 1, "the second scene is deleted (to see it recovered)")
        let sw = SnapshotsWindowController(folder: snFolder)
        sw.prepare = { snMain.saveAll() }
        sw.onChanged = { snMain.reloadFromDisk() }
        sw.show(); spin(0.3)
        check(sw.allSnapshots.count >= 4 && sw.snapshotCount == sw.allSnapshots.count, "the window lists the snapshots")
        sw.setFilter(.saved)
        check(sw.snapshotCount == 2, "the filter shows only named and saved ones", "\(sw.snapshotCount)")
        sw.setFilter(.beforeActions)
        let beforeCount = sw.snapshotCount
        check(beforeCount >= 1, "and the ones taken before an action (the delete took one)", "\(beforeCount)")
        sw.setFilter(.deleted)
        check(sw.snapshotCount >= 2 && sw.snapshotCount < sw.allSnapshots.count + 1, "and the ones that hold things deleted since")
        sw.setFilter(.all)
        sw.select(namedInfo)
        check(sw.countsFor(namedInfo).total > 0 && sw.changes.count >= 2, "a snapshot says what differs from the book now", "\(sw.changes.map { "\($0.item.title) \($0.label)" })")
        let changedOne = sw.changes.first { $0.status == .changed && $0.item.group == .scene }!
        let deletedOne = sw.changes.first { $0.status == .deletedSince && $0.item.group == .scene }!
        sw.selectChange(changedOne)
        check(sw.comparisonText.contains("Совсем другой текст.") && sw.comparisonText.contains("Второй абзац изменён.") == false && sw.comparisonText.contains("Второй абзац."), "the text is compared paragraph by paragraph", sw.comparisonText)
        check(sw.buttonStates.restore && sw.buttonStates.copy && !sw.buttonStates.recover && sw.buttonStates.name && sw.buttonStates.whole, "Restore This and Copy are for a changed item")
        let snapshotsBefore = snStore.list().count
        sw.restoreSelected(confirm: false); spin(0.6)
        check(sceneFile(0).contains("Второй абзац.") && !sceneFile(0).contains("Совсем"), "Restore This puts the text back as the snapshot had it")
        check(snStore.list().count > snapshotsBefore && snStore.list().last?.kind == .beforeOperation, "after a snapshot of the present state was taken first")
        sw.select(namedInfo)
        let deletedAgain = sw.changes.first { $0.status == .deletedSince && $0.item.group == .scene }!
        sw.selectChange(deletedAgain)
        check(sw.comparisonText.contains("Текст второй сцены.") && sw.buttonStates.recover && !sw.buttonStates.restore, "a deleted scene shows its text as it was, and offers Recover")
        sw.restoreSelected(confirm: false); spin(0.6)
        check(snMain.session.structure.scenes.count == 2 && sceneFile(1).contains("Текст второй сцены.") && BookStructure.problemsFree(snFolder), "Recover Deleted puts the scene back in its place")
        _ = deletedOne
        setScene(0, "Ещё раз изменено.")
        sw.select(namedInfo)
        sw.selectChange(sw.changes.first { $0.status == .changed && $0.item.group == .scene }!)
        sw.copySelected(); spin(0.6)
        check(snMain.session.structure.scenes.count == 3 && snMain.session.structure.scenes[1].node.title.hasSuffix("(restored)") && sceneFile(0).contains("Ещё раз изменено."), "Restore as a Copy puts the old text beside the present one, titled (restored)")
        let anAutomatic = sw.allSnapshots.first { $0.kind == .automatic }!
        sw.select(anAutomatic)
        sw.nameSelected("Хорошая версия")
        check(snStore.list().contains { $0.name == "Хорошая версия" && $0.kind == .manual }, "Name… gives a snapshot a name (and so keeps it)")
        check(sw.cleanUp() == 0 && sw.allSnapshots.count >= 5, "Clean Up Now removes nothing from a fresh book")
        sw.select(snStore.list().first { $0.name == "До правки" })
        sw.restoreWholeBook(confirm: false); spin(0.8)
        check(snMain.session.structure.scenes.count == 2 && sceneFile(0).contains("Второй абзац.") && !sceneFile(0).contains("изменён") && sceneFile(1).contains("Текст второй сцены."), "Restore the Whole Book puts every file back as it was")
        app.showSnapshots(); spin(0.3)
        check(app.snapshotWindowCount == 1, "File ▸ Snapshots… opens the window for the book")
        sw.window.close()
        snWin.window.close(); spin(0.3)
        return nil
    }
}
