import AppKit
import QuillandCore

/// An interrupted move, starting with the plan, a folder that is not a book.
extension AppSelfTest {
    func startup() -> Int32? {
        // A move that was interrupted is finished when the book is opened.
        guard let jFolder = create(title: "Journal Test", plan: false) else { check(false, "the book for the journal check is made"); return 1 }
        spin(0.6)
        if let jWin = app.bookWindows.last {
            let jMain = jWin.main
            _ = jMain.add(.scene) as Void
            spin(0.5)
            jWin.save()
            let jStructure = try! BookStructure.load(folder: jFolder)
            let jItems = try! Renumber.scan(jFolder.appendingPathComponent("manuscript/001-chapter"))
            let jSteps = try! Renumber.plan(folder: "manuscript/001-chapter", items: jItems, order: [.item("002-scene"), .item("001-scene")])
            struct Stop: Error {}
            let jJournal = jFolder.appendingPathComponent(".quilland/journal.json")
            _ = try? Renumber.execute(jSteps, root: jFolder, journal: jJournal) { k in if k >= jSteps.count + 1 { throw Stop() } }
            check(FileManager.default.fileExists(atPath: jJournal.path), "an interrupted move leaves its journal")
            let firstBefore = jStructure.scenes[0].id
            jWin.window.close(); spin(0.4)
            check(app.openBook(at: jFolder), "the book is opened again")
            spin(0.6)
            let reopened = app.bookWindows.last
            check(reopened?.main.finishedInterruptedMove == true && !FileManager.default.fileExists(atPath: jJournal.path) && reopened?.main.banner.text == "Finished a move that was interrupted.", "opening it finishes the move and says so")
            check(reopened?.main.session.structure.scenes.first?.id != firstBefore && BookStructure.problemsFree(jFolder), "the two scenes are in their new order and the book reads without problems")
            reopened?.window.close(); spin(0.3)
        }

        // Start with the plan; a folder that is not a book.
        guard let second = create(title: "Plan First", plan: true) else { check(false, "second book"); return 1 }
        spin(0.5)
        check(app.bookWindows.last?.main.mode == .plan && app.bookWindows.last?.main.planController?.store.cards.isEmpty == true, "\"Start with the Plan\" opens the Plan canvas, empty")
        let plain = temp.appendingPathComponent("plain-folder")
        try? FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        check(!app.openBook(at: plain), "a folder that is not a Quilland book is not opened")
        _ = second
        return nil
    }
}
