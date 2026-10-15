import AppKit
import QuillandCore

/// The book window: the tree and its scene, hover, pointer and button checks, menus, the right panel, the Plan's hover, tabs, the Outline, the status bar.
extension AppSelfTest {
    func panels() -> Int32? {
        let book = self.book!
        let folder = self.folder!
        let place = self.place!
        let sceneURL = self.sceneURL!
        // Closing the book by hand, then opening it again from the list.
        book.window.performClose(nil)
        spin(0.4)
        check(app.bookWindows.isEmpty && app.welcome.window.isVisible, "closing the last book shows the Welcome window")
        check(app.settings.lastOpened == nil && app.welcome.visibleBooks.map(\.name) == ["Дом на Сосновой"], "the next start would show it too, and the book is in the list")
        let state = LocalBookState.load(book: folder)
        check(state.scene == book.main.session.structure.scenes[0].id && state.position == place && state.mode == "plan", "where the author left off is on disk (scene, place, view)", "\(state)")
        app.welcome.onOpenRecent?(folder)
        spin(0.5)
        guard let again = app.bookWindows.first else { check(false, "the book opens again"); return 1 }
        check(again.main.mode == .plan, "it opens in the view it was left in")
        app.modeBook(); spin(0.5)
        let tv2 = again.main.controllers.first?.currentSheet?.textView
        check(tv2?.string.contains("Первая строка новой книги.") == true, "the text is there")
        check(tv2?.selectedRange().location == place, "and the cursor is at the place where it was left", "\(String(describing: tv2?.selectedRange().location)) vs \(place)")
        check(app.openBook(at: folder) && app.bookWindows.count == 1, "opening the same book again only brings its window forward")

        // Panels: the structure tree beside one scene.
        again.main.setMode(.panels); spin(0.4)
        guard let main = Optional(again.main), let firstTree = main.tree else { check(false, "Panels shows a tree"); return 1 }
        let firstID = main.session.structure.scenes[0].id
        check(firstTree.visibleTitles == ["Глава 1", "Сцена 1"] && firstTree.selectedID == firstID, "Panels shows the structure tree with the scene selected", "\(firstTree.visibleTitles) \(String(describing: firstTree.selectedID))")
        check(main.controllers.count == 1 && main.controllers[0].onlyScene == firstID && main.controllers[0].stack.sheets.count == 1, "and only that scene in the centre")
        check(firstTree.hasFooter && firstTree.newMenuTitles == ["New Scene", "New Scene Before", "New Chapter", "New Part"], "the tree has a + button with a menu of what can be added", "\(firstTree.newMenuTitles)")
        let openTitles = firstTree.visibleTitles
        firstTree.foldAll()
        let folded = firstTree.visibleTitles
        firstTree.reload(structure: main.session.structure, characters: { _ in 0 })
        check(folded == ["Глава 1"] && firstTree.visibleTitles == ["Глава 1"], "the arrow beside + closes every chapter, and a reload keeps them closed", "\(folded) \(firstTree.visibleTitles)")
        firstTree.foldAll()
        check(firstTree.visibleTitles == openTitles, "and pressed again opens them all", "\(firstTree.visibleTitles)")
        firstTree.requestNew(.scene, .after); spin(0.5)
        var scenes = main.session.structure.scenes
        check(scenes.count == 2 && scenes[1].node.title == "Новая сцена" && main.currentSceneID == scenes[1].id, "New Scene adds a scene after the current one and goes into it", "\(scenes.map(\.node.title)) \(String(describing: main.currentSceneID))")
        check(main.tree?.visibleTitles == ["Глава 1", "Сцена 1", "Новая сцена"] && main.controllers[0].stack.sheets.count == 1 && main.controllers[0].stack.sheets[0].document.id == scenes[1].id, "the tree shows it and the centre shows only it", "\(main.tree?.visibleTitles ?? []) sheets \(main.controllers[0].stack.sheets.map(\.document.title))")
        let firstText = try? String(contentsOf: scenes[0].node.base.isEmpty ? sceneURL : main.session.structure.markdownURL(for: scenes[0].node), encoding: .utf8)
        check(firstText?.contains("Первая строка новой книги.") == true, "the first scene's text is untouched")
        main.rename(scenes[1].id, to: "Вторая")
        main.setStatus(scenes[1].id, to: "draft")
        main.move(by: -1); spin(0.5)
        scenes = main.session.structure.scenes
        check(scenes.map(\.node.title) == ["Вторая", "Сцена 1"] && scenes[0].node.status == "draft", "rename, status and move up are in the structure", "\(scenes.map(\.node.title))")
        check(try! String(contentsOf: main.session.structure.markdownURL(for: scenes[1].node), encoding: .utf8).contains("Первая строка новой книги."), "and the text went with its scene when the files were renumbered")
        main.tree?.select(scenes[1].id)
        spin(0.3)
        check(main.controllers[0].onlyScene == scenes[1].id && main.currentSceneID == scenes[1].id, "choosing a scene in the tree shows it", "only \(String(describing: main.controllers[0].onlyScene)) want \(scenes[1].id) cur \(String(describing: main.currentSceneID)) tree \(String(describing: main.tree?.selectedID))")
        main.add(.chapter); spin(0.5)
        check(main.session.structure.roots.count == 2 && main.tree?.visibleTitles.contains("Новая глава") == true, "New Chapter adds a chapter with its first scene", "\(main.session.structure.roots.count) \(main.tree?.visibleTitles ?? [])")
        let removed = main.session.structure.roots[1].id
        main.delete(removed, confirm: false); spin(0.5)
        check(main.session.structure.roots.count == 1 && main.session.structure.scenes.count == 2 && main.currentSceneID != nil, "Delete removes the chapter, and the cursor stays in a scene that is left")
        // (A folder of the trash that only holds the other version of a scene another program changed is not a deletion.)
        let trashRoot = folder.appendingPathComponent(".quilland/trash")
        let deletions = ((try? FileManager.default.contentsOfDirectory(atPath: trashRoot.path)) ?? []).filter { name in !((try? FileManager.default.subpathsOfDirectory(atPath: trashRoot.appendingPathComponent(name).path)) ?? []).allSatisfy { $0.hasPrefix("conflicts") } }
        check(deletions.count == 1, "what was deleted is in the trash folder, not gone", "\(deletions)")
        check(BookStructure.problemsFree(folder), "the book on disk reads without problems")
        check(NSApp.mainMenu?.items.contains { $0.submenu?.title == "Debug" } == false, "there is no Debug menu")
        // A list lights the row under the pointer, and only a row that can be chosen.
        do {
            func outlineIn(_ v: NSView) -> NSOutlineView? { (v as? NSOutlineView) ?? v.subviews.lazy.compactMap(outlineIn).first }
            if let tree = main.tree?.view, let outline = outlineIn(tree), outline.numberOfRows > 1 {
                func look(_ row: Int) -> Data? {
                    guard let rv = outline.rowView(atRow: row, makeIfNecessary: false), let rep = rv.bitmapImageRepForCachingDisplay(in: rv.bounds) else { return nil }
                    rv.cacheDisplay(in: rv.bounds, to: rep)
                    return rep.representation(using: .tiff, properties: [:])
                }
                outline.deselectAll(nil)
                let plain0 = look(0), plain1 = look(1)
                Hover.setHoveredRow(outline, 1)
                let lit1 = look(1), still0 = look(0)
                Hover.setHoveredRow(outline, -1)
                check(plain1 != nil && plain1 != lit1 && still0 == plain0 && look(1) == plain1, "a row is lit while the pointer is over it, and only that one, and is as before afterwards")
                // A chosen row is left alone: its selection look is the same with the pointer on it and away from it, and a row that gets chosen under the pointer stops being lit.
                outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false); spin(0.1)
                let chosen = look(1)
                Hover.setHoveredRow(outline, 1)
                let chosenHovered = look(1)
                Hover.setHoveredRow(outline, 0); Hover.setHoveredRow(outline, -1)
                check(chosen != nil && chosenHovered == chosen && look(1) == chosen && outline.selectedRow == 1 && outline.rowView(atRow: 1, makeIfNecessary: false)?.isSelected == true, "a chosen row keeps its selection look when the pointer comes and goes", "selected \(outline.selectedRow)")
                outline.deselectAll(nil)
                Hover.setHoveredRow(outline, 1)
                outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false); spin(0.1)
                let lights = outline.rowView(atRow: 1, makeIfNecessary: false)?.subviews.filter { String(describing: Swift.type(of: $0)).contains("RowLight") }.count ?? -1
                check(look(1) == chosen && lights == 0, "and a row chosen while the pointer is on it is not lit over its selection", "lights \(lights) same \(look(1) == chosen)")
                Hover.setHoveredRow(outline, -1)
                // The pointer moves: every tracking area under it hears it, as the system would tell it (the system's own tracking needs the application in front, which an
                // automatic run is not, so the messages are sent here, to whatever answers for each area).
                if let window = outline.window {
                    func lights(_ row: Int) -> Int { outline.rowView(atRow: row, makeIfNecessary: false)?.subviews.filter { String(describing: Swift.type(of: $0)).contains("RowLight") }.count ?? -1 }
                    outline.deselectAll(nil); spin(0.1)
                    let pointer = PointerSimulator(window: window)
                    let centre = { (row: Int) -> NSPoint in outline.convert(NSPoint(x: outline.bounds.midX, y: outline.rect(ofRow: row).midY), to: nil) }
                    pointer.move(to: centre(1)); spin(0.1)
                    let over = lights(1)
                    pointer.move(to: centre(0)); spin(0.1)
                    let moved = (lights(0), lights(1))
                    pointer.move(to: NSPoint(x: -50, y: -50)); spin(0.1)
                    check(over == 1 && moved.0 == 1 && moved.1 == 0 && lights(0) == 0 && pointer.unanswered.isEmpty, "a pointer moving over the tree lights the row under it, one at a time, and none when it leaves", "over \(over) moved \(moved) after \(lights(0)) \(lights(1)) unanswered \(pointer.unanswered)")
                    // Over every button of the window: each answers, and the pointer leaving puts things back.
                    func buttons(_ v: NSView) -> [NSView] { ((v is NSButton || v is NSSegmentedControl) ? [v] : []) + v.subviews.flatMap(buttons) }
                    for v in window.contentView.map(buttons) ?? [] where !v.isHiddenOrHasHiddenAncestor && v.bounds.width > 4 {
                        pointer.move(to: v.convert(NSPoint(x: v.bounds.midX, y: v.bounds.midY), to: nil))
                    }
                    pointer.move(to: NSPoint(x: -50, y: -50))
                    check(pointer.unanswered.isEmpty && pointer.entered > 0, "the pointer over every button and tab of the window is answered", "entered \(pointer.entered) unanswered \(pointer.unanswered)")
                    outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false); spin(0.1)
                }
                // The caret moves in the text (the right panel follows it after a moment): the tree keeps its choice.
                let chosenID = main.tree?.selectedID
                if let tv = main.controllers.first?.currentSheet?.textView { tv.setSelectedRange(NSRange(location: min(3, tv.string.utf16.count), length: 0)); spin(1.2); tv.setSelectedRange(NSRange(location: 0, length: 0)); spin(1.2) }
                check(main.tree?.selectedID == chosenID && outline.selectedRow == 1, "and so does a move of the caret in the text")
            } else { check(false, "the tree has rows to light") }
        }
        do {
            func buttons(_ v: NSView) -> [NSButton] { ((v as? NSButton).map { [$0] } ?? []) + v.subviews.flatMap(buttons) }
            var missing: [String] = []
            for w in NSApp.windows where !(w is NSPanel) { if let c = w.contentView { for b in buttons(c) where b.action != nil && !(b is NSPopUpButton) && !Hover.isAttached(b) && !(b.superview is NSSearchField) && !b.title.isEmpty { missing.append(b.title) } } }
            check(missing.isEmpty, "every titled button in the windows reacts to the pointer", "\(missing)")
        }
        // The system is told that the checks can see an exception, and that the global button hook sits on buttons only (not on every view).
        do {
            let before = QuillandApplication.caught.count
            NSApp.reportException(NSException(name: .genericException, reason: "probe of the automatic check", userInfo: nil))
            check(QuillandApplication.caught.count == before + 1, "an exception AppKit catches is kept for the checks")
            QuillandApplication.caught.removeLast()
            let sel = #selector(NSView.viewDidMoveToWindow)
            check(NSButton.instanceMethod(for: sel) != NSView.instanceMethod(for: sel), "the hook on buttons is not on every view")
        }
        // Every tracking area answers to the messages it asks for: an unanswered message is an exception, and one thrown while a dialog is open ends the dialog.
        do {
            func everyView(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(everyView) }
            var unanswered: [String] = []
            for w in NSApp.windows { for v in w.contentView.map(everyView) ?? [] { for area in v.trackingAreas {
                guard let owner = area.owner as? NSObject else { continue }
                func needs(_ option: NSTrackingArea.Options, _ names: [String]) { if area.options.contains(option) { for n in names where !owner.responds(to: NSSelectorFromString(n)) { unanswered.append("\(Swift.type(of: owner)) \(n)") } } }
                needs(.mouseEnteredAndExited, ["mouseEntered:", "mouseExited:"])
                needs(.mouseMoved, ["mouseMoved:"])
                needs(.cursorUpdate, ["cursorUpdate:"])
            } } }
            check(unanswered.isEmpty, "every tracking area's owner answers all the messages it asks for", "\(Set(unanswered))")
        }
        // A button that is off is faded, one that works is not.
        do {
            let probe = NSButton(title: "Probe", target: app, action: #selector(AppDelegate.findAction))
            probe.bezelStyle = .inline
            again.window.contentView?.addSubview(probe); spin(0.1)
            let on = probe.alphaValue
            probe.isEnabled = false; spin(0.1)
            let off = probe.alphaValue
            probe.isEnabled = true; spin(0.1)
            let back = probe.alphaValue
            // The look under the pointer, drawn: a corner-free spot at the edge of the button changes.
            func picture(_ v: NSView) -> Data? {
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
                v.cacheDisplay(in: v.bounds, to: rep)
                return rep.representation(using: .tiff, properties: [:])
            }
            probe.frame = NSRect(x: 0, y: 0, width: 90, height: 22); probe.layoutSubtreeIfNeeded()
            let before = picture(probe)
            Hover.simulateHover(probe, true)
            let during = picture(probe)
            Hover.simulateHover(probe, false)
            let after = picture(probe)
            check(before != during && before == after, "a button looks different with the pointer on it, and the same again after")
            // The system sends mouseEntered: and mouseExited: to the owner of a tracking area: the owner must answer to exactly those names.
            let owners = probe.trackingAreas.compactMap { $0.owner as? NSObject }
            check(owners.contains { $0.responds(to: NSSelectorFromString("mouseEntered:")) && $0.responds(to: NSSelectorFromString("mouseExited:")) && $0.responds(to: NSSelectorFromString("cursorUpdate:")) }, "a button's pointer tracking answers to the messages the system sends")
            func tablesIn(_ v: NSView) -> [NSTableView] { ((v as? NSTableView).map { [$0] } ?? []) + v.subviews.flatMap(tablesIn) }
            if let table = again.window.contentView.map(tablesIn)?.first {
                let rowOwners = table.trackingAreas.compactMap { $0.owner as? NSObject }
                check(rowOwners.contains { $0.responds(to: NSSelectorFromString("mouseMoved:")) && $0.responds(to: NSSelectorFromString("mouseEntered:")) && $0.responds(to: NSSelectorFromString("mouseExited:")) }, "and so does a list's (every message its tracking asks for)")
            }
            probe.removeFromSuperview()
            check(on == 1 && off < 0.6 && back == 1, "a button that is switched off is faded, and a button that works is not", "\(on) \(off) \(back)")
        }
        // The Section menu offers only what can be done.
        do {
            again.window.makeKeyAndOrderFront(nil); spin(0.2)
            func on(_ action: Selector, status: String? = nil) -> Bool {
                let item = NSMenuItem(title: "x", action: action, keyEquivalent: "")
                item.representedObject = status
                return app.validateMenuItem(item)
            }
            let ids = main.session.structure.scenes.map(\.id)
            main.tree?.select(ids[0]); spin(0.2)
            check(!on(#selector(AppDelegate.moveSectionUp)) && on(#selector(AppDelegate.moveSectionDown)) && !on(#selector(AppDelegate.mergePreviousScene)) && on(#selector(AppDelegate.mergeNextScene)), "the first scene cannot move up or merge with a previous one")
            check(on(#selector(AppDelegate.setSectionStatus(_:)), status: "draft") && !on(#selector(AppDelegate.ungroupPart)) && !on(#selector(AppDelegate.mergeChosenScenes)), "a scene has a status, is not a part, and has no chosen scenes to merge")
            // The real menu shows it: the items are dimmed.
            if let section = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == L("Section") })?.submenu {
                main.tree?.select(ids[0]); spin(0.2)
                section.update()
                func enabled(_ action: Selector) -> Bool? { section.items.first { $0.action == action }?.isEnabled }
                check(enabled(#selector(AppDelegate.moveSectionUp)) == false && enabled(#selector(AppDelegate.moveSectionDown)) == true && enabled(#selector(AppDelegate.mergePreviousScene)) == false, "in the Section menu the items that cannot be done are dimmed", "\(String(describing: enabled(#selector(AppDelegate.moveSectionUp)))) \(String(describing: enabled(#selector(AppDelegate.moveSectionDown))))")
            } else { check(false, "the Section menu is there") }
            main.tree?.select(ids[1]); spin(0.2)
            check(on(#selector(AppDelegate.moveSectionUp)) && !on(#selector(AppDelegate.moveSectionDown)) && on(#selector(AppDelegate.mergePreviousScene)) && !on(#selector(AppDelegate.mergeNextScene)), "the last scene cannot move down or merge with a next one")
            let chapterID = main.session.structure.roots[0].id
            // Two chapters: the last scene of the first does not merge with the first scene of the second, and the menu says so.
            main.add(.chapter); spin(0.5)
            let all = main.session.structure.scenes.map(\.id)
            let lastOfFirst = main.session.structure.roots[0].children.last!.id, firstOfSecond = main.session.structure.roots[1].children[0].id
            check(all.firstIndex(of: firstOfSecond) == all.firstIndex(of: lastOfFirst)! + 1, "the new chapter's scene follows the first chapter's last scene in the book")
            main.tree?.select(lastOfFirst); spin(0.2)
            check(!on(#selector(AppDelegate.mergeNextScene)) && on(#selector(AppDelegate.mergePreviousScene)), "the last scene of a chapter cannot merge with the next chapter's scene")
            main.tree?.select(firstOfSecond); spin(0.2)
            check(!on(#selector(AppDelegate.mergePreviousScene)), "nor the first scene of a chapter with the previous chapter's")
            let before = main.session.structure.scenes.count
            main.merge(lastOfFirst, direction: 1); spin(0.3)
            check(main.session.structure.scenes.count == before, "and Merge does nothing across chapters even if it is asked to")
            // A scene at the edge of its chapter moves into the next one.
            main.tree?.select(lastOfFirst); spin(0.2)
            check(on(#selector(AppDelegate.moveSectionDown)), "the last scene of a chapter can move down into the next chapter")
            main.move(lastOfFirst, by: 1); spin(0.6)
            check(main.session.structure.roots[1].children.first?.id == lastOfFirst && main.session.structure.roots[1].children.count == 2, "Move Down puts it first in the next chapter")
            main.move(lastOfFirst, by: -1); spin(0.6)
            check(main.session.structure.roots[0].children.last?.id == lastOfFirst, "and Move Up brings it back to the end of the first")
            // Delete… asks first: the warning appears, and its Delete button does the work.
            var alertSeen = false, titles: [String] = []
            let clicker = Timer(timeInterval: 0.3, repeats: true) { _ in
                guard let w = NSApp.modalWindow else { return }
                alertSeen = true
                func found(_ v: NSView) -> [NSButton] { ((v as? NSButton).map { [$0] } ?? []) + v.subviews.flatMap(found) }
                let all = w.contentView.map(found) ?? []
                titles = all.map(\.title)
                all.first { $0.title == L("Delete") }?.performClick(nil)
            }
            RunLoop.main.add(clicker, forMode: .common)
            let chaptersBefore = main.session.structure.roots.count
            main.delete(main.session.structure.roots[1].id)
            clicker.invalidate(); spin(0.5)
            check(alertSeen && main.session.structure.roots.count == chaptersBefore - 1, "Delete… shows its warning, and the Delete button removes the section", "alert \(alertSeen) \(titles) chapters \(main.session.structure.roots.count)")
            main.tree?.select(chapterID); spin(0.2)
            check(!on(#selector(AppDelegate.setSectionStatus(_:)), status: "draft") && !on(#selector(AppDelegate.mergeNextScene)) && !on(#selector(AppDelegate.moveSectionUp)) && on(#selector(AppDelegate.groupIntoPart)) && on(#selector(AppDelegate.renameSection)) && on(#selector(AppDelegate.deleteSection)), "a lone chapter has no status and cannot move, but can be grouped, renamed and deleted")
            main.tree?.select(ids[1]); spin(0.2)
            check(on(#selector(AppDelegate.newScene)) && on(#selector(AppDelegate.newChapter)) && on(#selector(AppDelegate.newPart)), "new scene, chapter and part are always offered")
        }
        again.save()

        // The right panel.
        main.setRightPanel(true); spin(0.5)
        // The Plan's cards and line headers react to the pointer.
        do {
            func look(_ v: NSView) -> Data? {
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
                v.cacheDisplay(in: v.bounds, to: rep)
                return rep.representation(using: .tiff, properties: [:])
            }
            func enter(_ v: NSView, _ type: NSEvent.EventType) -> NSEvent? { NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) }
            let card = PlanItemView(item: PlanItem(kind: .card, id: "x", title: "Приезд", text: "Анна приезжает.", colorName: "teal", lineIndex: 0, start: 0, floatingAt: nil), frame: NSRect(x: 0, y: 0, width: 150, height: 80))
            let plain = look(card)
            if let e = enter(card, .mouseEntered), let x = enter(card, .mouseExited) {
                card.mouseEntered(with: e)
                let lit = look(card)
                card.mouseExited(with: x)
                check(card.isHovered == false && plain != nil && plain != lit && look(card) == plain, "a Plan card is drawn differently with the pointer on it, and the same again after")
                card.isTopLayer = false
                card.mouseEntered(with: e)
                check(!card.isHovered, "a card in the lower layer (which cannot be taken) does not react")
                let header = PlanLineHeaderView(lineID: "l", name: "Линия", summary: nil, colorName: "teal", frame: NSRect(x: 0, y: 0, width: 150, height: 34))
                let headerPlain = look(header)
                header.mouseEntered(with: e)
                let headerLit = look(header)
                header.mouseExited(with: x)
                check(headerPlain != nil && headerPlain != headerLit && look(header) == headerPlain, "and so is a line's header")
            }
        }
        // A tab strip lights the tab under the pointer.
        do {
            func strips(_ v: NSView) -> [NSSegmentedControl] { ((v as? NSSegmentedControl).map { [$0] } ?? []) + v.subviews.flatMap(strips) }
            let found = again.window.contentView.map(strips)?.filter { $0.segmentCount >= 2 && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor } ?? []
            if let strip = found.first {
                let frames = Hover.segmentFrames(of: strip)
                let ordered = zip(frames, frames.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 1 }
                let equal = frames.dropFirst().allSatisfy { abs($0.width - frames[0].width) < 0.5 }
                check(frames.count == strip.segmentCount && ordered && frames.allSatisfy { $0.width > 10 } && !equal && frames[0].minX < 6 && frames.last!.maxX > strip.bounds.width - 6, "the frames of the tabs are their real ones (each as wide as its label needs), one after another", "\(frames)")
                func look() -> Data? {
                    guard let rep = strip.bitmapImageRepForCachingDisplay(in: strip.bounds) else { return nil }
                    strip.cacheDisplay(in: strip.bounds, to: rep)
                    return rep.representation(using: .tiff, properties: [:])
                }
                let other = (0..<strip.segmentCount).first { $0 != strip.selectedSegment } ?? 0
                let plain = look()
                Hover.setHoveredSegment(strip, other)
                let shown = look()
                Hover.setHoveredSegment(strip, -1)
                check(plain != nil && plain != shown && look() == plain, "a tab under the pointer looks different, and the same again after")
            } else { check(false, "there is a tab strip to light") }
        }
        if let viewMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == L("View") })?.submenu {
            func ticked(_ title: String) -> Bool? { viewMenu.update(); return viewMenu.items.first { $0.title == L(title) }?.state == .on }
            check(ticked("Panels") == true && ticked("Book") == false && ticked("Right Panel") == true, "View ▸ Panels and Right Panel are ticked while they are in use")
            main.setRightPanel(false); main.setMode(.book); spin(0.4)
            check(ticked("Panels") == false && ticked("Book") == true && ticked("Right Panel") == false, "and the ticks move with the view and the panel")
            main.setMode(.panels); main.setRightPanel(true); spin(0.4)
        } else { check(false, "the View menu is there") }
        let panel = main.rightPanel
        again.window.contentView?.layoutSubtreeIfNeeded()
        panel.followDelay = 0.3
        check(main.showsRightPanel && panel.view.window != nil && panel.view.frame.width >= 250, "View ▸ Right Panel shows the panel beside the text", "width \(panel.view.frame.width) super \(String(describing: panel.view.superview)) win \(again.window.frame) content \(String(describing: panel.view.superview?.frame)) hidden \(panel.view.isHidden)")
        check(panel.shownScene == main.currentSceneID && main.tree != nil, "it shows the scene where the cursor is, and the tree is still there")
        check(main.localState().rightPanel, "and the open panel is remembered for the book")
        panel.synopsis.string = "Анна приходит домой."
        panel.textDidChange(Notification(name: NSText.didChangeNotification, object: panel.synopsis))
        panel.commitEdits()
        check(BookEditor(structure: main.session.structure).record(main.currentSceneID!)?.string("synopsis") == "Анна приходит домой.", "a synopsis typed in the panel is saved in the scene's file")
        let anna = try! panel.characterStore.add(name: "Анна Петровна")
        try! panel.characterStore.update(anna) { $0.aliases = ["Аня"] }
        let editorView = main.controllers[0].currentSheet!.textView
        editorView.insertText("Анне Петровне стало легче.", replacementRange: NSRange(location: editorView.string.count, length: 0))
        panel.refresh()
        check(panel.found == [anna], "a character is found in the scene by a case form of the name", "\(panel.found)")
        let other = main.session.structure.scenes.first { $0.id != main.currentSceneID }!.id
        let here = panel.shownScene!
        panel.cursorMoved(to: other)
        check(panel.shownScene == here, "the panel does not follow the cursor at once")
        spin(0.6)
        check(panel.shownScene == other, "and follows it after a moment of rest")
        panel.setPinned(true)
        panel.cursorMoved(to: here); spin(0.6)
        check(panel.shownScene == other, "a pinned panel stays")
        panel.setPinned(false); spin(0.6)
        check(panel.shownScene == here, "and follows again when unpinned")
        // The World and Events tabs.
        panel.setVisibleTabs([.section, .characters, .world, .events])
        let tabWorld = try! main.worlds.addWorld(name: "Тестовый мир")
        let tabPlace = try! main.worlds.addEntry(name: "Выдумград", world: tabWorld)
        editorView.insertText(" Он жил в Выдумграде.", replacementRange: NSRange(location: editorView.string.count, length: 0))
        panel.showTab(.world); panel.refresh()
        check(panel.worldTab.rowIDs == [tabPlace], "the World tab lists the places found in the scene", "\(panel.worldTab.rowIDs)")
        check(panel.worldTab.heading.stringValue == "Выдумград", "and shows the card of the first one")
        panel.worldTab.notes.string = "Город на холме."
        panel.worldTab.textDidChange(Notification(name: NSText.didChangeNotification, object: panel.worldTab.notes))
        panel.worldTab.commitEdits()
        check(main.worlds.entry(tabPlace)?.notes == ["Город на холме."], "notes typed there are saved in the place's file")
        let tabEvent = try! main.eventStore.add(title: "Приезд в Выдумград")
        try! main.eventStore.update(tabEvent) { $0.date = "весна"; $0.links = [here: "приезжает"] }
        panel.showTab(.events); panel.refresh()
        check(panel.eventsTab.rowIDs == [tabEvent] && panel.eventsTab.detail.stringValue.contains("весна"), "the Events tab lists the events linked to the scene, with the date")
        panel.eventsTab.allBox.state = .on; panel.eventsTab.refresh(scene: here)
        check(panel.eventsTab.rowIDs.contains(tabEvent), "and all of them when asked")
        panel.eventsTab.allBox.state = .off
        for (folderName, id) in [("places", tabPlace), ("worlds", tabWorld), ("events", tabEvent)] { for ext in ["json", "md"] { try? FileManager.default.removeItem(at: main.folder.appendingPathComponent("bible/\(folderName)/\(id).\(ext)")) } }
        main.worlds.reload(); main.eventStore.reload()
        panel.setVisibleTabs([.section, .characters]); panel.refresh()
        editorView.string = String(editorView.string.dropLast(" Он жил в Выдумграде.".count))
        main.setRightPanel(false); spin(0.3)
        check(!main.showsRightPanel && main.tree != nil && !main.localState().rightPanel, "the panel can be closed")
        again.save()

        // The Outline.
        main.add(.chapter); spin(0.5)
        app.modeOutline(); spin(0.5)
        guard let outlineTree = main.tree, let detail = main.outlineDetail else { check(false, "the Outline shows a tree and the information area"); return 1 }
        check(main.mode == .outline && outlineTree.visibleTitles.count == 5, "View ▸ Outline shows the whole tree and the information area", "\(outlineTree.visibleTitles)")
        let st = main.session.structure
        let sceneOne = st.scenes.first { $0.node.title == "Сцена 1" }!.id
        outlineTree.select(sceneOne); spin(0.2)
        check(detail.shown == [sceneOne] && detail.titleField.stringValue == "Сцена 1", "choosing a section shows it in the information area")
        detail.synopsis.string = "Начало дня."
        detail.textDidChange(Notification(name: NSText.didChangeNotification, object: detail.synopsis))
        detail.commitEdits()
        check(BookEditor(structure: main.session.structure).record(sceneOne)?.string("synopsis") == "Начало дня.", "the synopsis is edited there and saved")
        let chapterTwo = st.roots[1].id
        outlineTree.select(chapterTwo); spin(0.2)
        check(detail.shown == [chapterTwo] && main.sectionInfo(chapterTwo)?.sceneCount == 1 && main.sectionInfo(chapterTwo)?.kind == .chapter, "a chapter shows its scenes and status counts")
        // Dropping: the scene into the other chapter, first; then the chapter before the first.
        main.moveSections([sceneOne], parent: chapterTwo, index: 0); spin(0.5)
        var shape = main.session.structure.roots.map { $0.children.map(\.title).joined(separator: ",") }
        check(shape == ["Вторая", "Сцена 1,Новая сцена"], "dragging a scene into another chapter puts it there", "\(shape)")
        check(main.session.structure.scenes.first { $0.id == sceneOne }.flatMap { try? String(contentsOf: main.session.structure.markdownURL(for: $0.node), encoding: .utf8) }?.contains("Первая строка") == true, "with its text")
        check(BookEditor(structure: main.session.structure).record(sceneOne)?.string("synopsis") == "Начало дня.", "and its synopsis")
        main.moveSections([chapterTwo], parent: nil, index: 0); spin(0.5)
        shape = main.session.structure.roots.map { $0.children.map(\.title).joined(separator: ",") }
        check(shape == ["Сцена 1,Новая сцена", "Вторая"], "dragging a chapter above the first one", "\(shape)")
        check(BookStructure.problemsFree(folder) && main.mode == .outline && main.tree?.visibleTitles.count == 5, "the book on disk is sound and the Outline is still open")
        check(main.localState().mode == "outline", "the Outline is the view remembered for the book")
        main.openInEditor(sceneOne); spin(0.5)
        check(main.mode == .panels && main.currentSceneID == sceneOne, "Open in the Editor goes back to the writing mode, in that scene", "\(main.mode) \(String(describing: main.currentSceneID))")
        app.modeOutline(); spin(0.3)
        main.leaveOutline(); spin(0.4)
        check(main.mode == .panels, "leaving the Outline returns to the writing mode")
        again.save()

        // The status bar and the jump bar.
        again.refreshStatus()
        let bar = again.statusBar
        check(bar.leftText.contains("characters") && bar.leftText.contains("book ") && bar.leftText.contains("today +"), "the status bar shows the scene's count, the book's and today's", bar.leftText)
        check(bar.rightText == "Saved", "and Saved on the right", bar.rightText)
        check(bar.middleText.count <= 20, "with Caps Lock and the input language in the middle", bar.middleText)
        let before = main.writtenToday
        main.controllers.first?.currentSheet?.textView.insertText("Ещё слова.", replacementRange: NSRange(location: 0, length: 0))
        let barAfterTyping = again.statusBar.rightText
        spin(1.4)
        check(main.writtenToday > before, "typing raises today's count", "\(before) → \(main.writtenToday)")
        check(again.statusBar.leftText.contains("today +\(NumberFormatter.localizedString(from: NSNumber(value: main.writtenToday), number: .decimal))"), "and the status bar follows by itself", again.statusBar.leftText)
        _ = barAfterTyping
        again.save()
        main.setMode(.book); spin(0.5)
        let area = main.controllers[0]
        let scenes2 = main.session.structure.scenes
        let cur = area.currentSceneID.flatMap { id in scenes2.first { $0.id == id } }
        check(cur != nil && area.jumpBar.path.title.contains(cur!.node.title) && area.jumpBar.path.title.contains(" › "), "Book mode has a jump bar with the path of the scene", area.jumpBar.path.title)
        let target = scenes2.last!.id
        area.jump(to: target); spin(0.3)
        check(area.currentSceneID == target && !area.jumpBar.next.isEnabled && area.jumpBar.previous.isEnabled, "jumping goes to the scene, and the arrows know the ends")
        area.jumpBar.previous.performClick(nil); spin(0.3)
        check(area.currentSceneID == scenes2[scenes2.count - 2].id, "the previous-scene arrow goes one scene back")
        let narrowed = JumpListController.filtered(main.session.structure, by: "втор")
        check(narrowed.roots.count == 1 && narrowed.roots[0].children.map(\.title) == ["Вторая"], "the jump list's filter narrows to the scenes that match", "\(narrowed.roots.map { $0.children.map(\.title) })")
        area.openJumpList(); spin(0.3)
        check(area.isJumpListOpen, "the path opens the jump list")
        area.closeJumpList()
        main.setMode(.panels); spin(0.4)
        self.main = main
        self.again = again
        return nil
    }
}
