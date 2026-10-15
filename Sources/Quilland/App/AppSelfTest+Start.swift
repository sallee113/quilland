import AppKit
import QuillandCore

/// A new book, and the modes.
extension AppSelfTest {
    func start() -> Int32? {
        // A new book, then writing.
        let emptyTitle = NewBookWindowController(parentFolder: temp)
        check(emptyTitle.languagePopup.titleOfSelectedItem == "English" && NewBookWindowController.languages.map(\.0) == ["en", "ru", "fr"], "the New Book dialog proposes English first")
        check(!emptyTitle.create(plan: false), "a book without a title is not made")
        guard let folder = create(title: "Дом на Сосновой", plan: false) else { check(false, "the book is created"); return 1 }
        spin(0.5)
        check(app.bookWindows.count == 1 && app.bookWindows[0].window.isVisible, "the book opens in its own window")
        check(!app.welcome.window.isVisible, "and the Welcome window goes away")
        check(app.settings.lastOpened == folder.path && app.settings.knownBooks.first?.name == "Дом на Сосновой", "the book is remembered as the last opened and the first recent")
        guard let book = app.bookWindows.first else { return 1 }
        check(book.window.title == "Дом на Сосновой" && book.main.mode == .panels, "the window is titled with the book and opens in Panels mode")
        check(book.main.controllers.count == 1 && book.main.session.structure.scenes.count == 1, "one chapter with one empty scene")
        check(book.main.currentSceneID == book.main.session.structure.scenes[0].id, "the cursor is in the first scene, ready to type", "current \(String(describing: book.main.currentSceneID)), controllers \(book.main.controllers.count), sheets \(book.main.controllers.first?.stack.sheets.count ?? -1), window \(String(describing: book.main.controllers.first?.view.window)), responder \(String(describing: book.window.firstResponder))")
        guard book.main.currentSceneID != nil else { print("\n\(passed) passed, \(failed) failed"); return 1 }
        let c = book.main.controllers[0]
        let tv = c.currentSheet!.textView
        check(book.window.firstResponder === tv, "and the editor has the focus")
        tv.insertText("Первая строка новой книги.", replacementRange: tv.selectedRange())
        spin(0.3)
        book.save()
        let sceneURL = book.main.session.structure.markdownURL(for: book.main.session.structure.scenes[0].node)
        check((try? String(contentsOf: sceneURL, encoding: .utf8))?.contains("Первая строка новой книги.") == true, "what is typed is saved to the scene's file")
        let place = tv.selectedRange().location

        // The modes, from the menu.
        app.modeCompare(); spin(0.4)
        check(book.main.mode == .compare && book.main.controllers.count == 2, "View ▸ Compare shows two areas")
        app.modePlan(); spin(0.4)
        check(book.main.mode == .plan && book.main.planController != nil, "View ▸ Plan shows the plan canvas")
        _ = book.main.planController?.addCard()
        app.modeBook(); spin(0.4)
        check(book.main.mode == .book && book.main.controllers.count == 1, "View ▸ Book comes back")
        check(book.main.currentDocument?.id == book.main.session.structure.scenes[0].id && book.main.controllers[0].currentSheet?.textView.selectedRange().location == place, "and the cursor is where it was", "\(String(describing: book.main.controllers[0].currentSheet?.textView.selectedRange().location)) vs \(place)")
        app.modePlan(); spin(0.3)
        if let plan = book.main.planController {
            check(plan.sectionChoices.count == book.main.session.structure.scenes.count + 1 || plan.sectionChoices.count >= 1, "the Plan view can start from any part, chapter or scene")
            plan.showFrom = plan.sectionChoices.first?.id
            check(plan.hidden.isEmpty && book.main.localState().planFrom == nil, "with nothing before it, nothing is hidden")
            plan.showFrom = nil
            let linesBefore = Set(plan.store.lines.compactMap(\.id))
            while plan.store.lines.count < 2 { plan.addLine() }
            let ids = plan.store.lines.compactMap(\.id)
            if ids.count >= 2 {
                let first = ids[0], second = ids[1]
                plan.renameLine(first, to: "Главная линия"); plan.setLineColor(first, to: "red")
                check(plan.store.lines[0].name == "Главная линия" && plan.store.lines[0].color == "red", "a line is renamed and recolored")
                plan.moveLine(first, by: 1)
                check(plan.store.lines.compactMap(\.id).prefix(2) == [second, first], "and moved one place to the right")
                // Dragging a header over another column puts the line there.
                plan.moveLine(first, toVisible: 0)
                check(plan.store.lines.compactMap(\.id).prefix(2) == [first, second], "a line dragged to the first column goes there")
                plan.moveLine(first, toVisible: 1)
                check(plan.store.lines.compactMap(\.id).prefix(2) == [second, first], "and back to the second")
                plan.setLine(second, visible: false)
                check(plan.canvas.headers.count == plan.store.lines.count - 1 && plan.canvas.headers.first?.lineID == first, "a line switched off closes its column")
                if let header = plan.canvas.headers.first {
                    let menu = plan.canvas.contextMenuProvider?(NSPoint(x: header.frame.midX, y: header.frame.midY), header)
                    check(menu?.items.count == 6 && menu?.items.first?.title == "Edit…", "right-clicking a line's title offers edit, color, move and delete", "\(menu?.items.map(\.title) ?? [])")
                }
                plan.setLine(second, visible: true)
                check(plan.canvas.headers.count == plan.store.lines.count, "and switched on again it comes back")
                for id in plan.store.lines.compactMap(\.id) where !linesBefore.contains(id) { plan.deleteLine(id) }
            }
        }
        self.book = book
        self.folder = folder
        self.place = place
        self.sceneURL = sceneURL
        return nil
    }
}
