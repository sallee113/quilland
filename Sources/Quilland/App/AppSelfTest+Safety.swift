import AppKit
import QuillandCore

/// Nothing is lost: saving, a file changed by another program, closing windows, looking changes nothing, text typed before a view is left.
extension AppSelfTest {
    func safety() -> Int32? {
        let main = self.main!
        let again = self.again!
        // A scene changed by another program since it was read is not silently overwritten: its version is kept in the trash folder, and the author is told.
        do {
            let sceneID = main.session.structure.scenes[0].id
            let doc = main.session.document(sceneID)!
            let file = doc.url
            let theirs = "Чужая версия сцены, которую написала другая программа.\n"
            func theirCopies() -> Int {
                let trash = main.folder.appendingPathComponent(".quilland/trash")
                return ((try? FileManager.default.subpathsOfDirectory(atPath: trash.path)) ?? []).filter { $0.contains("conflicts/") && (try? String(contentsOf: trash.appendingPathComponent($0), encoding: .utf8)) == theirs }.count
            }
            func type(_ text: String) { doc.storage.replaceCharacters(in: NSRange(location: doc.storage.length, length: 0), with: text); doc.textDidChange(); doc.saveNow() }
            type(" Моя версия.")
            doc.saveNow()
            try? Data(theirs.utf8).write(to: file)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: file.path)
            type(" Ещё слово.")
            spin(0.3)
            check(theirCopies() == 1 && ((try? String(contentsOf: file, encoding: .utf8)) ?? "").contains("Моя версия."), "a scene another program changed is kept in the trash folder before this version is written", "copies \(theirCopies())")
            check(main.banner.isShowing, "and the author is told")
            type(" И ещё.")
            check(theirCopies() == 1, "a save after that, with no outside change, keeps nothing more")
            // A save that fails says so in the status bar.
            let folder = file.deletingLastPathComponent()
            try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
            doc.storage.replaceCharacters(in: NSRange(location: doc.storage.length, length: 0), with: " Не сохранится.")
            doc.textDidChange(); let saved = doc.saveNow()
            again.refreshStatus()
            let statusText = again.statusBar.rightText
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            check(!saved && statusText.hasPrefix("Not saved"), "a save that fails is told in the status bar, not shown as editing", statusText)
            doc.saveNow(); again.refreshStatus()
            check(again.statusBar.rightText == "Saved" || again.statusBar.rightText == "editing…", "and the next save that works takes it away", again.statusBar.rightText)
        }
        // Closing a book's window stops what the model is still doing for it.
        do {
            guard create(title: "Close Test", plan: false) != nil, let closing = app.bookWindows.last else { check(false, "a book to close"); return 1 }
            spin(0.5)
            closing.main.continueTask = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 50_000_000) } }
            let running = closing.main.continueTask
            closing.window.close(); spin(0.3)
            check(running?.isCancelled == true, "closing the window stops a job of the model that is still running")
            again.window.makeKeyAndOrderFront(nil); spin(0.3)
            app.settings.noteOpened(folder: main.folder, name: again.bookTitle)   // (the book of the checks is the one to reopen again)
        }
        // Looking at the book changes nothing in its files (Git shows no change from only browsing): every view is opened, scenes are chosen, everything is saved.
        do {
            func stamps() -> [String: String] {
                var out: [String: String] = [:]
                let root = main.folder
                let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
                while let url = walker?.nextObject() as? URL {
                    if url.pathComponents.contains(".quilland") { walker?.skipDescendants(); continue }
                    let relative = url.pathComponents.suffix(from: max(0, url.pathComponents.firstIndex(of: root.lastPathComponent).map { $0 + 1 } ?? 0)).joined(separator: "/")
                    guard let a = try? FileManager.default.attributesOfItem(atPath: url.path), (a[.type] as? FileAttributeType) == .typeRegular else { continue }
                    out[relative] = "\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)/\((a[.size] as? NSNumber)?.intValue ?? 0)"
                }
                return out
            }
            main.saveAll(); spin(1.0)
            let before = stamps()
            let startMode = main.mode
            for mode in [app.modeBook, app.modeOutline, app.modePlan, app.modeCharacters, app.modeWorld, app.modeEvents, app.modePanels] { mode(); spin(0.5) }
            for id in main.session.structure.scenes.map(\.id) { main.tree?.select(id); spin(0.1) }
            main.saveAll(); spin(1.5)
            main.setMode(startMode); spin(0.4)
            let after = stamps()
            let changed = after.filter { before[$0.key] != $0.value }.keys.sorted() + before.keys.filter { after[$0] == nil }.sorted()
            check(changed.isEmpty, "only looking at the book (every view, every scene) writes nothing to its files", "\(changed)")
        }
        // Text typed in a card (its own save waits for a timer) is saved when the view is left at once, not lost with the view.
        do {
            let who = main.characters.characters.first!.id!
            main.charactersView?.select(who)
            let v = main.charactersView!
            v.profile.string = "Профиль, набранный секунду назад."
            v.textDidChange(Notification(name: NSText.didChangeNotification, object: v.profile))
            app.modeWorld(); spin(0.3)
            check(CharacterStore(book: main.folder).profile(who) == "Профиль, набранный секунду назад.", "what was typed in a character's card is saved when the view is left before its timer fires", CharacterStore(book: main.folder).profile(who))
            let place = try! main.worlds.addEntry(name: "Проверочный дом", world: main.worlds.worlds[0].id!)
            main.worldView?.reload(); main.worldView?.select(place)
            main.worldView!.descriptionView.string = "Описание, набранное секунду назад."
            main.worldView!.textDidChange(Notification(name: NSText.didChangeNotification, object: main.worldView!.descriptionView))
            app.modeCharacters(); spin(0.3)
            check(WorldStore(book: main.folder).text(place) == "Описание, набранное секунду назад.", "and so is a place's description", WorldStore(book: main.folder).text(place))
            try? main.worlds.deleteEntry(place)
            app.modeCharacters(); spin(0.3)
        }
        // The same for the other editors that wait for a timer: an event's description and a scene's note in the Outline; and every kind of editor is on the list of
        // those that Save All and a rebuild reach.
        do {
            let event = try! main.eventStore.add(title: "Проверочное событие")
            app.modeEvents(); spin(0.4)
            main.eventsView?.reload(); main.eventsView?.select(event)
            main.eventsView!.descriptionView.string = "Описание события, набранное секунду назад."
            main.eventsView!.textDidChange(Notification(name: NSText.didChangeNotification, object: main.eventsView!.descriptionView))
            app.modeBook(); spin(0.3)
            check(EventStore(book: main.folder).text(event) == "Описание события, набранное секунду назад.", "what was typed in an event's card is saved when the view is left before its timer fires", EventStore(book: main.folder).text(event))
            try? main.eventStore.delete(event)
            let scene = main.session.structure.scenes[0].id
            app.modeOutline(); spin(0.4)
            main.tree?.select(scene); spin(0.3)
            main.outlineDetail!.note.string = "Заметка, набранная секунду назад."
            main.outlineDetail!.textDidChange(Notification(name: NSText.didChangeNotification, object: main.outlineDetail!.note))
            app.modeBook(); spin(0.3)
            check(BookEditor(structure: try! BookStructure.load(folder: main.folder)).record(scene)?.string("note") == "Заметка, набранная секунду назад.", "and a scene's note typed in the Outline")
            app.modeCharacters(); spin(0.3)
            // Every class of the application that has a `commitEdits()` is declared a `PendingEdits`, so that it can be put on the list.
            var strays: [String] = []
            var found = 0
            var count: UInt32 = 0
            // (Only the classes of this application's own image: asking every class of the process reaches system classes that cannot be asked.)
            if let image = class_getImageName(MainAreaController.self), let names = objc_copyClassNamesForImage(image, &count) {
                for i in 0..<Int(count) {
                    let name = String(cString: names[i])
                    guard let cls = NSClassFromString(name), class_getInstanceMethod(cls, NSSelectorFromString("commitEdits")) != nil else { continue }
                    found += 1
                    // (A subclass of a class that declares it declares it too.)
                    var current: AnyClass? = cls, declared = false
                    while let c = current, !declared { declared = class_conformsToProtocol(c, PendingEdits.self); current = class_getSuperclass(c) }
                    if !declared { strays.append(name) }
                }
                free(names)
            }
            check(strays.isEmpty && found >= 8, "every editor with a commitEdits() is declared a PendingEdits", "found \(found) strays \(strays)")
        }
        return nil
    }
}
