import AppKit
import QuillandCore

/// View ▸ Back and Forward between the views.
extension AppSelfTest {
    func history() -> Int32? {
        let main = self.main!
        let folder = self.folder!
        main.setMode(main.writingMode); spin(0.3)
        main.clearHistory()
        let backItem = NSMenuItem(title: "Back", action: #selector(AppDelegate.historyBack), keyEquivalent: "")
        let forwardItem = NSMenuItem(title: "Forward", action: #selector(AppDelegate.historyForward), keyEquivalent: "")
        check(!app.validateMenuItem(backItem) && !app.validateMenuItem(forwardItem), "with no history Back and Forward are dimmed")

        // A character, a jump to a scene by its link, and back.
        let anna = main.characters.characters[0].id!
        let writing = main.mode
        app.modeCharacters(); spin(0.4)
        main.charactersView?.select(anna)
        main.charactersView?.onOpenScene?(main.session.structure.scenes[0].id); spin(0.4)
        check(main.mode == writing, "a link in the Characters view leads to the text")
        check(app.validateMenuItem(backItem) && !app.validateMenuItem(forwardItem), "and Back is on, Forward is dimmed")
        main.goBack(); spin(0.4)
        check(main.mode == .characters && main.charactersView?.selected == anna, "Back returns to the Characters view with the same card")
        check(app.validateMenuItem(forwardItem), "and now Forward is on")
        main.goForward(); spin(0.4)
        check(main.mode == writing, "Forward goes to the text again")

        // A view chosen by hand is a step too; a new step drops the way forward.
        app.modeWorld(); spin(0.4)
        let place = main.worlds.entries.first?.id ?? main.worlds.worlds[0].id!
        main.worldView?.select(place)
        app.modeEvents(); spin(0.4)
        main.goBack(); spin(0.4)
        check(main.mode == .world && main.worldView?.selected == place, "a view chosen by hand is remembered with its card")
        main.goBack(); spin(0.4)
        check(main.mode == writing, "Back goes on, step by step")
        main.goForward(); spin(0.4)
        app.modeOutline(); spin(0.4)
        check(!main.canGoForward, "a new change of the view drops the way forward")
        main.goBack(); spin(0.4)
        check(main.mode == .world, "Back from there returns to the view before", "\(main.mode)")

        // The writing view gets its scene and cursor back.
        main.setMode(.panels); spin(0.4)
        main.reveal(scene: main.session.structure.scenes[0].id, range: NSRange(location: 3, length: 0)); spin(0.3)
        app.modeCharacters(); spin(0.4)
        main.goBack(); spin(0.4)
        check(main.mode == .panels && main.currentSceneID == main.session.structure.scenes[0].id, "Back to a writing view puts the scene back", "\(main.mode)")

        // A card that is gone in the meantime: the view opens, nothing breaks.
        let gone = try! main.characters.add(name: "Мимолётный")
        app.modeCharacters(); spin(0.4)
        main.charactersView?.reload(); main.charactersView?.select(gone)
        app.modeBook(); spin(0.4)
        try? main.characters.delete(gone)
        main.goBack(); spin(0.4)
        check(main.mode == .characters && main.charactersView?.selected != gone, "a card deleted meanwhile does not stop Back")

        // The status bar names the views before and after this one.
        let book = app.bookWindows.first { $0.main === main }!
        main.setMode(.panels); spin(0.3)
        main.clearHistory()
        book.refreshStatus()
        check(book.statusBar.trailText == "●", "with no history the status bar shows only the dot", book.statusBar.trailText)
        app.modeCharacters(); spin(0.4)
        book.refreshStatus()
        check(book.statusBar.trailText == "\(MainAreaController.title(of: .panels)) ‹ ●", "after one change it names the view Back goes to", book.statusBar.trailText)
        app.modeWorld(); spin(0.4)
        main.goBack(); spin(0.4)
        book.refreshStatus()
        check(book.statusBar.trailText == "\(MainAreaController.title(of: .panels)) ‹ ● › \(MainAreaController.title(of: .world))", "and after a step back both sides are named", book.statusBar.trailText)
        main.goBack(); spin(0.4)
        book.refreshStatus()
        check(book.statusBar.trailText == "● › \(MainAreaController.title(of: .characters))", "at the start of the history only the next view is named", book.statusBar.trailText)

        // The history is not endless.
        main.clearHistory()
        for _ in 0..<40 { main.setMode(main.mode == .world ? .events : .world) }
        check(main.backPlaces.count <= 50, "the history is kept to a limit")
        main.clearHistory()
        main.setMode(main.writingMode); spin(0.3)
        _ = folder
        return nil
    }
}
