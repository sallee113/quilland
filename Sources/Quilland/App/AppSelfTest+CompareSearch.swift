import AppKit
import QuillandCore

/// Search in the split Book view: what it does follows the side the cursor is in, and only that side scrolls.
extension AppSelfTest {
    func compareSearch() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes.map(\.id)
        guard scenes.count >= 3 else { check(false, "the book has three scenes for the checks"); return 1 }
        let first = scenes[0], second = scenes[1], last = scenes[scenes.count - 1]
        // (Long scenes, so that the last one is far below the first and a pane has to be scrolled to show it.)
        let filler = String(repeating: "\nЗаполнитель заполнитель заполнитель.", count: 150)
        setText(first, "Альфа: слово первое." + filler)
        setText(second, "Бета: слово второе." + filler)
        setText(last, "Омега: слово последнее.")
        app.modeBook(); main.setSplit(true); spin(0.5)
        let left = main.controllers[0], right = main.controllers[1]
        left.jump(to: first); spin(0.2)
        right.focus(sceneID: second); spin(0.3)
        check(main.activeArea === right && main.currentSceneID == second, "with the cursor in the right side, the current scene is the right side's", "\(String(describing: main.currentSceneID))")

        // The scope follows the side the cursor is in.
        main.showSearch(.search); spin(0.3)
        let panel = main.searchPanel
        panel.findField.stringValue = "слово"
        panel.setChoices(scope: .scene)
        check(panel.hits.map(\.owner) == [second], "\"This scene\" searches the scene of the side the cursor is in", "\(panel.hits.map(\.owner))")

        // Clicking a result scrolls only the side the cursor is in.
        panel.setChoices(scope: .book)
        check(panel.hits.count == 3, "the whole book has three results", "\(panel.hits.count)")
        right.focus(sceneID: second); spin(0.2)
        var visited: [String] = []
        for _ in 0..<panel.hits.count {
            panel.step(1); spin(0.3)
            visited.append(right.currentSceneID ?? "-")
            right.focus(sceneID: right.currentSceneID ?? second); spin(0.1)
            if left.currentSceneID != first { break }
        }
        check(left.currentSceneID == first, "going through the results leaves the left side where it was", "\(String(describing: left.currentSceneID))")
        check(Set(visited) == Set([first, second, last]), "and the right side visits every result", "\(visited)")

        // The cursor on the left: the left side moves.
        left.focus(sceneID: first); spin(0.3)
        right.jump(to: second); spin(0.2)
        left.focus(sceneID: first); spin(0.2)
        check(main.activeArea === left, "with the cursor back on the left, the left side is the active one")
        let rightBefore = right.currentSceneID
        panel.setChoices(scope: .book)
        panel.step(1); spin(0.3)
        check(right.currentSceneID == rightBefore, "a result then moves the left side and the right stays", "\(String(describing: right.currentSceneID))")

        // The selected word goes into the Find field from the side the cursor is in; closing the panel gives the focus back to that side.
        main.hideSearch(); spin(0.2)
        right.focus(sceneID: second); spin(0.2)
        if let tv = right.currentSheet?.textView { tv.setSelectedRange((tv.string as NSString).range(of: "Бета")) }
        left.currentSheet?.textView.setSelectedRange(NSRange(location: 0, length: 0))
        main.showSearch(.search); spin(0.2)
        check(panel.findField.stringValue == "Бета", "the Find field takes the word selected in the side the cursor is in", panel.findField.stringValue)
        main.hideSearch(); spin(0.3)
        check(main.activeArea === right, "closing the search gives the focus back to the same side")
        // Opening the split puts the same scene in both sides, with the cursor in the left one.
        main.setSplit(false); spin(0.4)
        main.controllers[0].jump(to: last); spin(0.3)
        main.setSplit(true); spin(0.6)
        check(main.controllers.count == 2 && main.controllers[0].currentSceneID == last && main.controllers[1].currentSceneID == last, "opening the split shows the same scene in both sides", "\(main.controllers.map { String(describing: $0.currentSceneID) }) \(last)")
        check(main.activeArea === main.controllers[0], "and the cursor stays in the left side")
        check(main.controllers[1].isShowing(sceneID: last), "and the right side is scrolled to it, not left at the top of the book")
        // Closing the split keeps the left side, with the cursor in it; the split is part of what is kept for the book.
        main.controllers[0].jump(to: first); spin(0.2)
        main.controllers[1].focus(sceneID: second); spin(0.3)
        check(main.localState().split, "the split is part of the state kept for the book")
        main.setSplit(false); spin(0.5)
        check(main.controllers.count == 1 && main.currentSceneID == first && !main.localState().split, "closing the split keeps the left side, and the cursor goes there", "\(main.controllers.count) \(String(describing: main.currentSceneID)) \(first)")
        main.setSplit(true); spin(0.5)
        check(main.controllers.count == 2 && main.localState().split, "and it opens again")
        main.setMode(.plan); spin(0.3)
        check(main.isSplit && !main.showsSplit, "the Plan has no split, and the book remembers it")
        main.setMode(.book); spin(0.5)
        check(main.showsSplit && main.controllers.count == 2, "coming back to the Book view brings the split back")
        main.setSplit(false)
        main.setMode(.panels); spin(0.3)
        return nil
    }
}
