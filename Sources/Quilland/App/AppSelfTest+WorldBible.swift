import AppKit
import QuillandCore

/// The World Bible: Characters and World are kinds of one view, with a strip to go between them, and one item with the kinds under it in the View menu.
extension AppSelfTest {
    func worldBible() -> Int32? {
        let main = self.main!
        // The menu: one World Bible item with no shortcut, and the two kinds under it with shortcuts of their own.
        let view = NSApp.mainMenu?.items.first { $0.submenu?.title == "View" }?.submenu
        let parent = view?.items.first { $0.title == "World Bible" && $0.hasSubmenu }
        let kids = parent?.submenu?.items ?? []
        check(parent != nil && parent?.keyEquivalent == "" && view?.items.contains { $0.title == "Characters" || $0.title == "World" } == false, "the View menu has one World Bible item with no shortcut, and no Characters or World item of its own", "\(view?.items.map(\.title) ?? [])")
        check(kids.map(\.title) == ["Characters", "World"], "its submenu has just Characters and World", "\(kids.map(\.title))")
        check(kids.first?.keyEquivalent == "1" && kids.first?.keyEquivalentModifierMask == [.command, .control] && kids.last?.keyEquivalent == "2" && kids.last?.keyEquivalentModifierMask == [.command, .control], "Characters is ⌃⌘1 and World is ⌃⌘2")
        // The views, in the order of the digits (⌘8 and ⌘9 are free; Reminders keeps ⌘0).
        let keyed = (view?.items ?? []).filter { $0.keyEquivalentModifierMask == [.command] && "0123456789".contains($0.keyEquivalent) && !$0.keyEquivalent.isEmpty }
        check(keyed.map { $0.keyEquivalent + $0.title } == ["1Panels", "2Book", "3Outline", "4Plan", "5Events", "6Graph", "7Research", "0Reminders"], "the views are on ⌘1 to ⌘7 in the order of the digits, Reminders on ⌘0, and ⌘8 and ⌘9 are free", "\(keyed.map { $0.keyEquivalent + $0.title })")

        // The strip, in both kinds.
        app.modeCharacters(); spin(0.4)
        check(main.inBible && main.bibleStrip?.selectedSegment == 0 && main.bibleStrip?.segmentCount == 2, "the Characters view has the Bible's strip, on Characters", "\(String(describing: main.bibleStrip?.selectedSegment))")
        main.bibleStrip.map { $0.selectedSegment = 1; $0.sendAction($0.action, to: $0.target) }
        spin(0.4)
        check(main.mode == .world && main.bibleStrip?.selectedSegment == 1 && main.worldView != nil, "choosing World on the strip shows the World view, with the strip on World")
        app.modeEvents(); spin(0.3)
        check(!main.inBible, "another view is not in the Bible")
        let title = main.view.window?.title ?? ""
        app.modeCharacters(); spin(0.3)
        check(title.hasSuffix("World Bible ▸ Characters") || (main.view.window?.title ?? "").hasSuffix("World Bible ▸ Characters"), "the window title names the Bible and the kind", title)
        app.modePanels(); spin(0.3)
        return nil
    }
}
