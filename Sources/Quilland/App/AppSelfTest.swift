import AppKit
import QuillandCore

/// `Quilland --selftest-app`: the first launch, a new book, writing, closing, reopening where the author left off.
final class AppSelfTest {
    private var passed = 0
    private var failed = 0
    private let app: AppDelegate
    private let temp: URL

    init(app: AppDelegate, temp: URL) {
        self.app = app
        self.temp = temp
    }

    private func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
        if ok { passed += 1; print("  ok   \(what)") } else { failed += 1; print("  FAIL \(what) \(detail())") }
    }

    private func spin(_ seconds: TimeInterval = 0.2) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func create(title: String, plan: Bool) -> URL? {
        var created: URL?
        let dialog = NewBookWindowController(parentFolder: temp)
        dialog.titleField.stringValue = title
        dialog.authorField.stringValue = "Вадим Сульянов"
        dialog.languagePopup.selectItem(at: NewBookWindowController.languages.firstIndex { $0.0 == "ru" } ?? 0)
        dialog.onCreated = { [app] folder, startPlan in
            created = folder
            _ = app.openBook(at: folder, mode: startPlan ? .plan : .panels)
        }
        dialog.create(plan: plan)
        return created
    }

    func run() -> Int32 {
        print("The first launch and a new book")
        app.showWelcome()
        spin()
        check(app.welcome.window.isVisible && app.bookWindows.isEmpty, "with no book the Welcome window is shown")
        check(app.welcome.visibleBooks.isEmpty, "and it lists no recent books")

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

        // Proofreading: findings in the text, accepted into the editor, dismissed for good.
        do {
            guard let sceneID = book.main.session.structure.scenes.first?.id, let doc = book.main.session.document(sceneID) else { check(false, "a scene to proofread"); return 1 }
            app.modeBook(); spin(0.4)
            let tv = book.main.controllers.first?.currentSheet?.textView
            if let tv, let w = tv.window {
                tv.setSelectedRange(NSRange(location: 5, length: 4))
                let ev = NSEvent.mouseEvent(with: .rightMouseDown, location: tv.convert(NSPoint(x: 20, y: 20), to: nil), modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                if let m = tv.menu(for: ev) {
                    let extra = NSMenuItem(title: "Translate", action: Selector(("_translate:")), keyEquivalent: ""); m.insertItem(extra, at: 0); m.insertItem(.separator(), at: 1)
                    tv.willOpenMenu(m, with: ev)
                    let acts = m.items.compactMap { $0.action.map { NSStringFromSelector($0) } }
                    check(acts.contains("cut:") && acts.contains("copy:") && acts.contains("paste:") && !m.items.contains { $0.title == "Font" || $0.title == "Substitutions" || $0.title == "Speech" || $0.title == "Translate" || $0.title == "Layout Orientation" }, "the editor's right-click menu keeps editing and drops fonts, substitutions, speech and the like", "\(m.items.map(\.title))")
                    check(m.items.contains { $0.title == "Spelling and Grammar" } && m.items.first?.isSeparatorItem == false && m.items.last?.isSeparatorItem == false, "and keeps the spelling, with no separator at the ends", "\(m.items.map(\.title))")
                }
            }
            let original = tv?.string ?? doc.storage.string, cursor = tv?.selectedRange() ?? NSRange(location: 0, length: 0)
            tv?.string = original + "\nОн жил в доме - и ждал...\n- Привет!\nПрчина странная.\n"
            doc.textDidChange(); spin(0.2)
            book.main.showSearch(.proofread); spin(0.3)
            let panel = book.main.searchPanel.proofView
            panel.scope = .scene
            panel.refresh()
            let found = panel.findingCount
            check(!panel.debugRows.contains { $0.hasPrefix("nbsp") }, "the non-breaking space rule is off at first")
            if book.main.spellingAvailable(language: "ru") {
                let base = tv?.string ?? ""
                check(panel.debugRows.contains { $0.hasPrefix("spelling:\"Прчина\"") }, "a misspelled word is found by the system's spell checker", "\(panel.debugRows)")
                panel.selectSpellingFinding("Прчина")
                panel.addSelectedWord()
                check(BookDictionary.load(book: book.main.folder).contains("прчина") && !panel.debugRows.contains { $0.hasPrefix("spelling:\"Прчина\"") }, "Add to Dictionary teaches the book the word and the finding goes")
                tv?.setSelectedRange(NSRange(location: (tv?.string as NSString?)?.length ?? 0, length: 0))
                tv?.insertText("Пажалуй пойдём.", replacementRange: tv?.selectedRange() ?? NSRange(location: 0, length: 0))
                spin(1.4)
                check(panel.debugRows.contains { $0.hasPrefix("spelling:\"Пажалуй\"→\"Пожалуй\"") }, "typing in the text updates the list by itself, with the suggestion", "\(panel.debugRows)")
                try? BookDictionary.save([], book: book.main.folder); book.main.session.applyBookSettings(language: book.main.bookLanguage, words: [])
                tv?.string = base; doc.textDidChange(); spin(0.2)
                tv?.undoManager?.removeAllActions()
                panel.refresh()
            }
            check(book.main.searchPanel.mode == .proofread && found >= 3, "Proofreading lists the typography findings of the scene", "\(found)")
            panel.clearSelection()
            check(panel.acceptSelected() == false, "nothing is accepted when no finding is chosen")
            panel.selectFirstTypography()
            check(panel.acceptSelected() && panel.findingCount == found - 1, "Accept applies one finding in the editor and it leaves the list")
            check(tv?.selectedRange().location ?? 0 > 10 && book.main.currentSceneID == sceneID, "the cursor goes to the corrected place, not to the start of the scene", "\(String(describing: tv?.selectedRange()))")
            tv?.undoManager?.undo(); spin(0.2)
            panel.refresh()
            check(panel.findingCount == found, "and ⌘Z in the editor takes it back")
            panel.selectFirstTypography(); panel.acceptAllInScene()
            check(panel.debugRows.allSatisfy { $0.hasPrefix("spelling") }, "Accept All takes the typography of the scene and leaves spelling for one-by-one", "\(panel.debugRows)")
            tv?.undoManager?.undo(); spin(0.2)
            panel.refresh()
            check(panel.findingCount == found, "and one ⌘Z takes them all back")
            panel.selectFirstTypography(); panel.dismissSelected()
            check(panel.findingCount == found - 1 && ProofreadingDismissals.load(book: book.main.folder).keys.count == 1, "Dismiss removes a finding and keeps it on this machine")
            var forgotten = ProofreadingDismissals.load(book: book.main.folder); forgotten.forgetAll(); forgotten.save(book: book.main.folder)
            book.main.searchPanel.onClose?(); spin(0.2)
            tv?.string = original; tv?.setSelectedRange(cursor); doc.textDidChange(); spin(0.2)
            app.modePlan(); spin(0.3)
        }

        // Grammar by the model: its corrections are findings, accepted one at a time into the editor.
        do {
            let main = book.main
            app.modeBook(); spin(0.4)
            guard let tv = main.controllers.first?.currentSheet?.textView, let doc = main.currentDocument else { check(false, "a text view for the grammar checks"); return 1 }
            let original = String(decoding: Array(tv.string.utf8), as: UTF8.self)
            tv.undoManager?.removeAllActions()
            tv.string = original + "\nОн пришол домой - и лёг.\n"; doc.textDidChange(); spin(0.2)
            main.showSearch(.proofread); spin(0.3)
            let panel = main.searchPanel.proofView
            panel.scope = .scene
            let range = (tv.string as NSString).range(of: "пришол")
            panel.injectGrammar(scene: doc.id, [TypographyFinding(rule: .grammar, range: range, before: "пришол", after: "пришёл", contextBefore: "Он ", contextAfter: " домой")])
            check(panel.debugRows.contains { $0.hasPrefix("grammar:\"пришол\"→\"пришёл\"") }, "the model's correction is in the list with the other findings", "\(panel.debugRows)")
            panel.selectFirstTypography(); panel.acceptAllInScene()
            check(panel.debugRows.contains { $0.hasPrefix("grammar:") } && tv.string.contains("пришол"), "Accept All takes the typography and leaves the model's suggestions for one-by-one")
            panel.selectGrammarFinding()
            check(panel.acceptSelected() && tv.string.contains("пришёл домой") && !panel.debugRows.contains { $0.hasPrefix("grammar:") }, "Accept puts the correction into the text")
            tv.undoManager?.undo(); spin(0.2)
            tv.undoManager?.undo(); spin(0.2)
            panel.injectGrammar(scene: doc.id, [TypographyFinding(rule: .grammar, range: NSRange(location: 3, length: 5), before: "никогда", after: "ничего", contextBefore: "", contextAfter: "")])
            panel.refresh()
            check(!panel.debugRows.contains { $0.hasPrefix("grammar:\"никогда\"") }, "a suggestion for words that are no longer there leaves the list")
            tv.string = original; tv.setSelectedRange(NSRange(location: 0, length: 0)); doc.textDidChange(); _ = doc.saveNow(); spin(0.2)
            tv.undoManager?.removeAllActions()
            main.searchPanel.onClose?(); spin(0.2)
            app.modePlan(); spin(0.3)
        }

        // Loose ends: a link to nothing, and a damaged file.
        do {
            let main = book.main
            let ch = try! main.characters.add(name: "Хвостов")
            try! main.characters.update(ch) { $0.links = ["no-such-scene": "x"] }
            main.showSearch(.looseEnds); spin(0.3)
            let lv = main.searchPanel.looseView
            check(main.searchPanel.mode == .looseEnds && lv.ends.contains { $0.kind == .missingLink && $0.target == "no-such-scene" }, "Loose Ends lists a link that points to nothing")
            lv.select { $0.target == "no-such-scene" }
            check(lv.remove() && !lv.ends.contains { $0.target == "no-such-scene" }, "Remove takes the link out of its owner")
            let broken = try! main.characters.add(name: "Битый")
            _ = try? SnapshotStore(bookFolder: main.folder).take(.manual, name: "Для хвостов")
            let brokenFile = main.folder.appendingPathComponent("bible/characters/\(broken).json")
            try! Data("{ nope".utf8).write(to: brokenFile)
            lv.refresh()
            check(lv.ends.contains { $0.kind == .damagedFile && $0.file.hasSuffix("\(broken).json") }, "a data file that cannot be read is listed")
            lv.select { $0.kind == .damagedFile }
            check(lv.restoreDamaged(confirm: false) && !lv.ends.contains { $0.kind == .damagedFile }, "Restore from a Snapshot puts back the readable copy")
            try? FileManager.default.removeItem(at: brokenFile.appendingPathExtension("damaged"))
            main.searchPanel.onClose?(); spin(0.2)
            for id in [ch, broken] { for ext in ["json", "md"] { try? FileManager.default.removeItem(at: main.folder.appendingPathComponent("bible/characters/\(id).\(ext)")) } }
            main.characters.reload()
        }

        // Collect from the Book: findings wait in the Suggestions tab and become cards when accepted.
        do {
            let main = book.main
            let sceneID = main.session.structure.scenes[0].id
            let known = try! main.characters.add(name: "Тестовая Аня")
            let before = (Set(main.characters.characters.compactMap(\.id)), Set(main.worlds.worlds.compactMap(\.id)), Set(main.worlds.entries.compactMap(\.id)), Set(main.eventStore.events.compactMap(\.id)), Set(main.relationships.relationships.compactMap(\.id)))
            func evidence(_ note: String) -> CollectedEvidence { CollectedEvidence(scene: sceneID, quote: "Первая строка", range: NSRange(location: 0, length: 6), note: note) }
            var c = CollectedItem(kind: .characters, name: "Сборкин"); c.aliases = ["Сбор"]; c.detail = "Придуманный сборщик."; c.evidence = [evidence("входит")]
            var again = CollectedItem(kind: .characters, name: "Тестовая Аня"); again.aliases = ["Анюта"]; again.detail = "Не должно перезаписать."; again.evidence = [evidence("здесь")]
            var town = CollectedItem(kind: .places, name: "Сборград"); town.detail = "Город сборщиков."; town.evidence = [evidence("действие здесь")]
            var square = CollectedItem(kind: .places, name: "Площадь Сборграда"); square.parent = "Сборград"; square.evidence = [evidence("тут")]
            var event = CollectedItem(kind: .events, name: "Приезд Сборкина"); event.date = "осень"; event.places = ["Сборград"]; event.detail = "Он приезжает."; event.evidence = [evidence("приезжает")]
            var rel = CollectedItem(kind: .relationships, name: ""); rel.members = ["Сборкин", "Тестовая Аня"]; rel.type = "знакомые"; rel.evidence = [evidence("встреча")]
            var lonely = CollectedItem(kind: .relationships, name: ""); lonely.members = ["Сборкин", "Никто"]; lonely.type = "враги"; lonely.evidence = [evidence("x")]
            var obs = CollectedItem(kind: .observations, name: ""); obs.about = "Сборкин"; obs.detail = "Носит шляпу."; obs.evidence = [evidence("шляпа")]
            main.collect.inject([c, again, town, square, event, rel, lonely, obs])
            main.showSearch(.suggestions); spin(0.3)
            let sv = main.searchPanel.suggestView
            check(main.searchPanel.mode == .suggestions && sv.itemCount == 8 && sv.checkedCount == 0, "the findings wait unchecked in the Suggestions tab")
            check(main.collect.existingMatch(again) == "Тестовая Аня" && main.collect.existingMatch(c) == nil, "a finding that has a card already is recognised")
            sv.checkAll()
            let report = sv.acceptChecked()!
            check(report.created[.characters] == 1 && report.created[.places] == 2 && report.created[.events] == 1 && report.created[.relationships] == 1 && report.updated == 2, "accepting makes the cards", "\(report)")
            let made = main.characters.characters.first { $0.name == "Сборкин" }
            check(made?.aliases == ["Сбор"] && main.characters.profile(made?.id ?? "") == "Придуманный сборщик." && made?.links[sceneID] == "входит" && made?.notes == ["Носит шляпу."], "a character has its other name, its description, the scene with the model's note, and the observation")
            check(main.characters.character(known)?.name == "Тестовая Аня" && main.characters.profile(known) == "" && main.characters.character(known)?.aliases == ["Анюта"] && main.characters.character(known)?.links[sceneID] == "здесь", "a card that existed is not overwritten: it only gets the scene and the other name")
            let townEntry = main.worlds.entries.first { $0.name == "Сборград" }, squareEntry = main.worlds.entries.first { $0.name == "Площадь Сборграда" }
            check(townEntry != nil && squareEntry?.parent == townEntry?.id && squareEntry?.world == townEntry?.world && main.worlds.text(townEntry?.id ?? "") == "Город сборщиков.", "places are made in the book's world, the inner one inside the larger")
            let ev = main.eventStore.events.first { $0.title == "Приезд Сборкина" }
            check(ev?.date == "осень" && ev?.places.keys.contains(townEntry?.id ?? "-") == true && ev?.links[sceneID] == "приезжает", "an event has its date, its place and its scene")
            check(main.relationships.relationships.contains { Set($0.characters) == Set([made?.id ?? "", known]) && $0.kind == "знакомые" } && !main.relationships.relationships.contains { $0.kind == "враги" }, "a relationship is made between characters that have cards; one with a stranger is not")
            check(sv.itemCount == 1, "what was accepted leaves the list; what could not be made stays", "\(sv.itemCount)")
            // The same again does not make a second card.
            main.collect.inject([c]); sv.checkAll()
            let second = sv.acceptChecked()!
            check(second.created.isEmpty && second.updated == 1 && main.characters.characters.filter { $0.name == "Сборкин" }.count == 1, "accepting a thing found again only updates its card")
            main.searchPanel.onClose?(); spin(0.2)
            // Put the book back as it was.
            main.collect.clear()
            func erase(_ folder: String, _ ids: Set<String>) { for id in ids { for ext in ["json", "md"] { try? FileManager.default.removeItem(at: main.folder.appendingPathComponent("bible/\(folder)/\(id).\(ext)")) } } }
            erase("characters", Set(main.characters.characters.compactMap(\.id)).subtracting(before.0))
            erase("characters", [known])
            erase("worlds", Set(main.worlds.worlds.compactMap(\.id)).subtracting(before.1)); erase("places", Set(main.worlds.entries.compactMap(\.id)).subtracting(before.2))
            erase("events", Set(main.eventStore.events.compactMap(\.id)).subtracting(before.3)); erase("relationships", Set(main.relationships.relationships.compactMap(\.id)).subtracting(before.4))
            main.characters.reload(); main.worlds.reload(); main.eventStore.reload(); main.relationships.reload(); main.collectedCardsChanged()
        }

        // Consistency Check: contradictions are pointed at, never fixed.
        do {
            let main = book.main
            let sceneID = main.session.structure.scenes[0].id
            let card = try! main.characters.add(name: "Тестовый Ян")
            let source = ConsistencySource(label: "C1", kind: .character, ref: card, title: "Тестовый Ян", text: "Серые глаза.")
            let finding = ConsistencyFinding(scene: sceneID, problem: "Цвет глаз не совпадает с карточкой.", quote: "Первая строка", range: NSRange(location: 0, length: 13), source: source, sourceQuote: "Серые глаза")
            main.collect.injectFindings([finding])
            main.showSearch(.suggestions); spin(0.3)
            let sv = main.searchPanel.suggestView
            check(sv.findingCount == 1 && sv.itemCount == 0, "a contradiction waits in the Suggestions tab")
            sv.checkAll()
            check(sv.acceptChecked() == nil, "a contradiction cannot be accepted: there is nothing to apply")
            sv.selectFirstFinding(); sv.openSource(); spin(0.4)
            check(main.mode == .characters && main.charactersView?.selected == card, "Open the Card goes to the card it conflicts with")
            main.setMode(.plan); spin(0.3)
            main.showSearch(.suggestions); spin(0.2)
            main.collect.dismissFindings([finding.id])
            check(sv.findingCount == 0 && AIDismissals.load(book: main.folder).contains(finding.key), "Dismiss removes it and remembers its words on this machine")
            AIDismissals.forgetAll(book: main.folder)
            main.searchPanel.onClose?(); spin(0.2)
            for ext in ["json", "md"] { try? FileManager.default.removeItem(at: main.folder.appendingPathComponent("bible/characters/\(card).\(ext)")) }
            main.characters.reload(); main.collectedCardsChanged()
        }

        // Continue Writing: a suggestion is faint text that is in no file until it is accepted.
        do {
            let main = book.main
            app.modeBook(); spin(0.4)
            guard let tv = main.controllers.first?.currentSheet?.textView, let doc = main.currentDocument else { check(false, "a text view for the suggestion checks"); return 1 }
            // A real copy: the view hands out its live text, which would change with the suggestion.
            let original = String(decoding: Array(tv.string.utf8), as: UTF8.self)
            tv.undoManager?.removeAllActions()
            tv.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
            var ended = 0
            tv.beginGhost { ended += 1 }
            tv.appendGhost(" Продолжение"); tv.appendGhost(" пошло дальше.")
            check(tv.hasGhost && tv.ghostText == " Продолжение пошло дальше." && tv.string == original + " Продолжение пошло дальше." && !doc.isDirty, "a suggestion is shown after the cursor and does not make the text dirty")
            let faint = tv.textStorage?.attribute(.foregroundColor, at: (original as NSString).length + 3, effectiveRange: nil) as? NSColor
            check(faint == NSColor.tertiaryLabelColor && tv.textStorage?.attribute(.ghost, at: (original as NSString).length + 3, effectiveRange: nil) != nil, "it is faint", "\(String(describing: faint))")
            _ = doc.saveNow()
            let saved = (try? String(contentsOf: main.session.structure.markdownURL(for: main.session.structure.scenes.first { $0.id == doc.id }!.node), encoding: .utf8)) ?? ""
            check(!tv.hasGhost && tv.string == original && !saved.contains("Продолжение") && ended == 1, "saving takes it away: it never reaches a file", "ghost \(tv.hasGhost) same \(tv.string == original) saved \(saved.contains("Продолжение")) ended \(ended)")
            tv.beginGhost { ended += 1 }
            tv.appendGhost(" Принятое продолжение.")
            check(tv.acceptGhost() && !tv.hasGhost && tv.string == original + " Принятое продолжение." && doc.isDirty && ended == 2, "Tab accepts it: it becomes the text")
            tv.undoManager?.undo(); spin(0.1)
            check(tv.string == original, "and one ⌘Z takes all of it back")
            tv.beginGhost { ended += 1 }
            tv.appendGhost(" Не нужное.")
            tv.insertText("я", replacementRange: NSRange(location: NSNotFound, length: 0))
            check(!tv.hasGhost && tv.string == original + "я" && ended == 3, "typing drops it and types")
            tv.beginGhost { ended += 1 }; tv.appendGhost(" Ещё одно.")
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            check(!tv.hasGhost && tv.string == original + "я", "moving the cursor drops it too")
            tv.string = original; doc.textDidChange(); _ = doc.saveNow(); spin(0.2)
            tv.undoManager?.removeAllActions()
            app.modePlan(); spin(0.3)
        }

        // A synopsis suggestion in a plain field: faint, then Tab replaces the field.
        do {
            let field = SuggestTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            field.isRichText = false
            field.string = "Старый синопсис."
            field.setSelectedRange(NSRange(location: 16, length: 0))
            field.ghost.replacesAll = true
            var ended = 0
            field.ghost.begin { ended += 1 }
            field.ghost.append("\n"); field.ghost.append("Новый синопсис ")
            field.ghost.append("сцены.")
            check(field.ghost.isActive && field.string == "Старый синопсис.\nНовый синопсис сцены." && field.ghost.text == "\nНовый синопсис сцены.", "a synopsis suggestion is shown faint after the old text")
            field.ghost.discard()
            check(field.string == "Старый синопсис." && !field.ghost.isActive && ended == 1, "Esc leaves the old synopsis")
            field.ghost.replacesAll = true
            field.ghost.begin { ended += 1 }
            field.ghost.append("\nНовый синопсис сцены.")
            check(field.ghost.accept() && field.string == "Новый синопсис сцены." && ended == 2, "Tab replaces the whole synopsis with it")
            field.ghost.replacesAll = false
            field.ghost.begin { ended += 1 }
            field.ghost.append(" Ещё.")
            field.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
            check(!field.ghost.isActive && field.string.hasSuffix("!") && !field.string.contains("Ещё"), "typing in the field drops the suggestion")
        }

        // The Chat: what @ attaches, the size line, the prompts for the up arrow, saving an answer as a note.
        do {
            let main = book.main
            let chat = main.chatSession
            _ = main.rightPanel.view
            main.rightPanel.setVisibleTabs([.section, .characters, .chat]); main.rightPanel.showTab(.chat)
            let sceneID = main.session.structure.scenes[0].id
            main.rightPanel.show(sceneID)
            let menu = main.chatMentionsMenu()
            check(menu.items.prefix(8).map(\.title) == ["@scene", "@chapter", "@characters", "@places", "@events", "@plan", "@cards", "@synopses"] && menu.items.contains { $0.title == "A character…" }, "@ offers the scene, the chapter, what is found in it, the plan and the synopses, and any one thing")
            if let item = menu.items.first, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
            check(chat.attachments.count == 1 && chat.attachments[0].label.hasPrefix("Scene:") && chat.usage.tokens > 0 && chat.usage.perAttachment[chat.attachments[0].id] ?? 0 > 0, "picking @scene attaches the scene with its size")
            if let item = menu.items.first, let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
            check(chat.attachments.count == 1, "the same thing is not attached twice")
            chat.remove(chat.attachments[0].id)
            check(chat.attachments.isEmpty, "a chip can be taken off")
            for p in ["первый вопрос", "второй вопрос"] { ChatPrompts.remember(p, book: main.folder) }
            chat.loadRecent()
            check(chat.recall(older: true) == "второй вопрос" && chat.recall(older: true) == "первый вопрос" && chat.recall(older: false) == "второй вопрос", "the up arrow recalls the earlier prompts, newest first")
            chat.send("Кто здесь главный герой?")
            check(chat.turns.isEmpty && chat.error != nil && !chat.running, "with the AI not available the chat says so and sends nothing", "\(String(describing: chat.error))")
            chat.inject([ChatTurn("user", "Вопрос"), ChatTurn("assistant", "Это ответ модели.")])
            check(chat.lastAnswer == "Это ответ модели." && chat.noteTargets().first?.kind == "scene", "an answer can be saved on the scene's note, a character or a place")
            check(chat.saveAnswer("Это ответ модели.", kind: "scene", id: sceneID) && BookEditor(structure: main.session.structure).record(sceneID)?.string("note")?.contains("Это ответ модели.") == true, "saving appends it to the note")
            try? BookEditor(structure: main.session.structure).setText(sceneID, key: "note", to: "")
            main.didChangeSectionTexts()
            ChatPrompts.remember("x", book: main.folder); try? FileManager.default.removeItem(at: main.folder.appendingPathComponent(".quilland/chat-prompts.json"))
            chat.newConversation()
            check(chat.turns.isEmpty, "a new conversation starts empty")
            main.rightPanel.setVisibleTabs([.section, .characters]); chat.loadRecent()
        }

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
        check(((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(".quilland/trash").path)) ?? []).count == 1, "what was deleted is in the trash folder, not gone")
        check(BookStructure.problemsFree(folder), "the book on disk reads without problems")
        again.save()

        // The right panel.
        main.setRightPanel(true); spin(0.5)
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

        // Search and Replace.
        let sc = main.session.structure.scenes
        func setText(_ id: String, _ text: String) {
            let doc = main.session.document(id)!
            doc.storage.replaceCharacters(in: NSRange(location: 0, length: doc.storage.length), with: text)
            doc.textDidChange(); doc.updateCounts(); _ = doc.saveNow()
        }
        func text(_ id: String) -> String { main.session.document(id)!.storage.string }
        let originalOne = "Кот спал. Потом кот ушёл. Котёнок остался."
        setText(sc[0].id, originalOne)
        setText(sc[1].id, "Здесь нет зверя.")
        main.reveal(scene: sc[0].id, range: nil); spin(0.3)
        main.showSearch(.search); spin(0.3)
        let panel2 = main.searchPanel
        check(main.isSearchOpen && panel2.mode == .search, "⌘F opens the bottom panel on Search")
        panel2.findField.stringValue = "кот"
        panel2.queryChanged()
        check(panel2.hits.count == 3 && panel2.hits.allSatisfy { $0.owner == sc[0].id }, "results appear as the field changes", "\(panel2.hits.count)")
        panel2.setChoices(wholeWords: true)
        check(panel2.hits.count == 2, "whole words leave out Котёнок")
        panel2.setChoices(wholeWords: false, endings: true)
        check(panel2.hits.count >= 2, "word endings find case forms")
        panel2.setChoices(endings: false)
        panel2.step(1)
        let tvNow = main.controllers[0].currentSheet?.textView
        check(tvNow?.selectedRange() == panel2.hits[0].range && main.currentSceneID == sc[0].id, "a step jumps to the first result and selects it")
        panel2.step(1)
        check(tvNow?.selectedRange() == panel2.hits[1].range, "and to the next")
        check(panel2.control(panel2.findField, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))) && text(sc[0].id) == originalOne, "Return in the field only moves on; nothing is changed")
        panel2.setChoices(scope: .scene)
        check(panel2.hits.count == 3, "the scope can be the scene")
        panel2.setChoices(scope: .book)

        main.showSearch(.replace); spin(0.2)
        check(panel2.mode == .replace && panel2.currentQuery.sources == [.text] && panel2.currentQuery.scope == .scene, "Replace starts with only the text and the scene as scope, chosen anew")
        panel2.setChoices(scope: .book)
        panel2.findField.stringValue = "кот"
        panel2.replaceField.stringValue = "пёс"
        panel2.queryChanged()
        check(panel2.hits.count == 3 && panel2.ticked.isEmpty && !panel2.replaceButton.isEnabled, "results are unticked and the button waits for a tick")
        panel2.checkAllResults()
        check(panel2.replaceButton.title == "Replace 3 checked" && panel2.replaceButton.isEnabled, "the button says how many are checked")
        panel2.replaceField.stringValue = ""
        panel2.queryChanged()
        panel2.checkAllResults()
        check(panel2.replaceButton.title == "Delete 3 checked", "an empty replacement turns the button into Delete")
        panel2.replaceField.stringValue = "пёс"
        panel2.queryChanged()
        check(panel2.ticked.isEmpty, "ticks are cleared when the replacement changes")
        panel2.checkAllResults()
        panel2.replaceChecked(confirm: false); spin(0.3)
        check(text(sc[0].id) == "пёс спал. Потом пёс ушёл. пёсёнок остался.", "the checked places are replaced", text(sc[0].id))
        check((try? String(contentsOf: main.session.structure.markdownURL(for: sc[0].node), encoding: .utf8))?.contains("пёс спал.") == true, "and the scene's file is written")
        check(!SnapshotStore(bookFolder: folder).list().isEmpty, "a snapshot was taken first")
        check(panel2.banners.contains("Replaced 3") && panel2.canUndo, "a banner offers Undo Replace")
        panel2.undoReplace(); spin(0.2)
        check(text(sc[0].id) == originalOne, "Undo Replace puts the text back", text(sc[0].id))
        // A result that went stale (the text was typed in) is skipped, the others are replaced.
        panel2.replaceField.stringValue = "Х"
        panel2.queryChanged()
        panel2.checkAllResults()
        setText(sc[0].id, "Пёс спал. Потом кот ушёл. Котёнок остался.")
        panel2.replaceChecked(confirm: false); spin(0.2)
        check(text(sc[0].id) == "Пёс спал. Потом Х ушёл. Хёнок остался." && panel2.banners.contains("skipped"), "a result that changed meanwhile is skipped", text(sc[0].id))
        panel2.undoReplace()
        // Synopses and notes are sources too.
        try? BookEditor(structure: main.session.structure).setText(sc[1].id, key: "synopsis", to: "Кот в мешке.")
        panel2.setChoices(scope: .book, sources: [.text, .synopsis])
        panel2.replaceField.stringValue = "лис"
        panel2.queryChanged()
        let fieldHits = panel2.hits.filter { $0.source == .synopsis }
        check(fieldHits.count == 1 && fieldHits[0].owner == sc[1].id, "a synopsis is found when it is ticked as a source", "\(panel2.hits.map { "\($0.source) \($0.groupTitle) \($0.match)" }) query \(panel2.currentQuery)")
        panel2.checkAllResults()
        panel2.replaceChecked(confirm: false); spin(0.2)
        check(BookEditor(structure: main.session.structure).record(sc[1].id)?.string("synopsis") == "лис в мешке.", "and replaced")
        panel2.undoReplace()
        check(BookEditor(structure: main.session.structure).record(sc[1].id)?.string("synopsis") == "Кот в мешке.", "and put back")
        main.hideSearch(); spin(0.2)
        check(!main.isSearchOpen, "Esc closes the panel")
        setText(sc[0].id, "Первая строка новой книги.")
        main.setMode(.panels)

        // The Format menu.
        again.usesFullScreen = false
        main.setMode(.book); spin(0.4)
        setText(sc[0].id, "Слово другое слово.")
        main.reveal(scene: sc[0].id, range: nil); spin(0.3)
        let ftv = main.controllers[0].currentSheet!.textView
        func markdown() -> String { MarkdownWriter.write(AttributedBridge.document(from: ftv.textStorage!)) }
        ftv.setSelectedRange(NSRange(location: 0, length: 5))
        ftv.toggleBold(nil)
        check(markdown().contains("**Слово**"), "Bold makes the selected word bold", markdown())
        let boldItem = NSMenuItem(title: "Bold", action: #selector(EditorTextView.toggleBold(_:)), keyEquivalent: "")
        _ = ftv.validateMenuItem(boldItem)
        check(boldItem.state == .on, "and the menu item shows a check mark there")
        ftv.toggleBold(nil)
        check(!markdown().contains("**"), "pressed again, it takes the bold away")
        ftv.setSelectedRange(NSRange(location: 6, length: 6))
        ftv.toggleItalic(nil)
        check(markdown().contains("другое") && (markdown().contains("*другое*") || markdown().contains("_другое_")), "Italic makes the selected word italic", markdown())
        ftv.toggleItalic(nil)
        ftv.setSelectedRange(NSRange(location: 0, length: 0))
        ftv.makeHeading2(nil)
        check(markdown().hasPrefix("## "), "Heading 2 turns the paragraph into a heading", markdown())
        ftv.makeBody(nil)
        check(!markdown().hasPrefix("#"), "Body Text turns it back")
        ftv.makeQuote(nil)
        check(markdown().hasPrefix(">"), "Set-off Block makes a set-off block", markdown())
        ftv.makeQuote(nil)
        check(!markdown().hasPrefix(">"), "and the same key takes it away")
        ftv.setSelectedRange(NSRange(location: 4, length: 0))
        ftv.insertSceneBreak(nil)
        check(markdown().contains("* * *") && ftv.typingAttributes[.quillandBlock] as? String == BlockKind.body, "Scene Break puts * * * between paragraphs and the cursor goes on below", "md \(markdown().debugDescription) storage \(ftv.string.debugDescription) sel \(ftv.selectedRange())")
        ftv.setSelectedRange(NSRange(location: 0, length: 0))
        ftv.insertFootnote(text: "Сноска")
        check(markdown().contains("^[Сноска]"), "Footnote puts a note marker at the cursor", markdown())
        setText(sc[0].id, "Первая строка новой книги.")

        // Dictation and other input methods put text in as "marked" (not yet final) text: the sheet must grow with it at once.
        main.setMode(.book); spin(0.4)
        main.reveal(scene: sc[0].id, range: nil); spin(0.3)
        let dictationSheet = main.controllers[0].currentSheet!
        let dictationView = dictationSheet.textView
        let heightBefore = dictationSheet.height
        dictationView.setSelectedRange(NSRange(location: dictationView.string.utf16.count, length: 0))
        dictationView.setMarkedText(String(repeating: "диктовка идёт и идёт ", count: 60), selectedRange: NSRange(location: 1200, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        spin(0.3)
        let needed = SceneDocument.neededHeight(of: dictationView)
        check(dictationView.hasMarkedText() && needed > heightBefore + 40, "the dictated text is longer than the sheet was")
        let usage = dictationView.textLayoutManager!.usageBoundsForTextContainer
        check(usage.maxX + dictationView.textContainerInset.width <= dictationSheet.frame.width + 1, "lines are kept inside the sheet's right edge", "text reaches \(usage.maxX + dictationView.textContainerInset.width), the sheet is \(dictationSheet.frame.width) wide")
        check(dictationSheet.height >= needed - 1, "the sheet grows with text that is still being dictated", "sheet \(dictationSheet.height), text \(needed)")
        dictationView.unmarkText()
        dictationView.setSelectedRange(NSRange(location: 0, length: dictationView.string.utf16.count))
        dictationView.insertText("Первая строка новой книги.", replacementRange: dictationView.selectedRange())
        spin(0.3)

        // Focus Mode.
        main.setMode(.panels); spin(0.3)
        main.setFocusMode(true)
        check(!main.focusMode, "Focus Mode is only for Book mode")
        main.setMode(.book); spin(0.3)
        main.setRightPanel(true); spin(0.3)
        let typewriterBefore = main.typewriter
        main.setFocusMode(true); spin(0.5)
        check(main.focusMode && main.typewriter, "Focus Mode is on, with typewriter scrolling")
        check(main.controllers[0].jumpBar.isHidden && again.statusBar.isHidden && main.rightPanel.view.window == nil, "the jump bar, the status bar and the right panel are gone")
        check(main.controllers[0].stack.rows.contains { if case .header(let h) = $0 { return h.alphaValue < 1 }; return false }, "the headers between the sheets are faint")
        check(main.controllers[0].currentSheet != nil && again.window.firstResponder === main.controllers[0].currentSheet?.textView, "and the cursor is in the text")
        main.setMode(.book)
        check(main.focusMode, "choosing the same mode keeps Focus Mode")
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: again.window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        main.controllers[0].currentSheet?.textView.keyDown(with: esc); spin(0.5)
        check(!main.focusMode && main.typewriter == typewriterBefore && !main.controllers[0].jumpBar.isHidden && !again.statusBar.isHidden && main.rightPanel.view.window != nil, "Esc leaves Focus Mode and everything comes back")
        main.setFocusMode(true); spin(0.3)
        main.showSearch(.search); spin(0.3)
        check(!main.focusMode && main.isSearchOpen, "⌘F leaves Focus Mode and opens Search")
        main.hideSearch()
        main.setFocusMode(true); spin(0.3)
        main.setMode(.outline); spin(0.3)
        check(!main.focusMode && main.mode == .outline, "choosing another view leaves Focus Mode")
        main.setRightPanel(false)
        main.setMode(.panels); spin(0.3)

        // The Characters view.
        app.modeCharacters(); spin(0.5)
        guard let cv = main.charactersView else { check(false, "View ▸ Characters shows the view"); return 1 }
        check(main.mode == .characters && cv.shownNames == ["Анна Петровна"], "View ▸ Characters lists the characters of the book", "\(cv.shownNames)")
        check(main.localState().mode == "characters", "and it is the view remembered for the book")
        let petr = cv.addCharacter(named: "  Пётр ")!
        check(cv.shownNames.contains("Пётр") && cv.selected == petr && cv.nameField.stringValue == "Пётр", "a typed name makes a character and opens its card")
        check(cv.addCharacter(named: "   ") == nil, "a blank name makes nothing")
        cv.profile.string = "Высокий, молчаливый."
        cv.textDidChange(Notification(name: NSText.didChangeNotification, object: cv.profile))
        cv.commitEdits()
        check(main.characters.profile(petr) == "Высокий, молчаливый.", "the profile is written to the character's text file")
        cv.aliasField.stringValue = "Петя, Петруша"
        cv.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: cv.aliasField))
        check(main.characters.character(petr)?.aliases == ["Петя", "Петруша"], "other names are split at commas")
        cv.mainBox.performClick(nil)
        check(main.characters.character(petr)?.main == true && cv.shownNames.first == "Пётр", "a main character goes to the top of the list")
        cv.nameField.stringValue = "Пётр Иванович"
        cv.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: cv.nameField))
        check(main.characters.character(petr)?.name == "Пётр Иванович" && cv.shownNames.first == "Пётр Иванович", "renaming changes the card and the list")
        setText(sc[0].id, "Петя вошёл. Пётр Иванович сел. Анне Петровне стало легче.")
        cv.select(petr)
        check(cv.rows.count == 1 && cv.rows[0].sceneID == sc[0].id && cv.rows[0].mentions == 2, "the card lists the scenes where the name is, with how often", "\(cv.rows)")
        cv.setSceneLine(row: 0, "Входит и садится.")
        cv.setScenePOV(row: 0, true)
        check(main.characters.character(petr)?.links[sc[0].id] == "Входит и садится." && main.characters.character(petr)?.povScenes == [sc[0].id], "what the character does and the point of view are saved")
        setText(sc[0].id, "Здесь никого.")
        cv.select(petr)
        check(cv.rows.count == 1 && cv.rows[0].mentions == 0 && cv.rows[0].pov, "a scene with a line or the point of view stays in the list although the name is gone")
        cv.filterField.stringValue = "анна"
        cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField))
        check(cv.shownNames == ["Анна Петровна"], "the filter narrows the list")
        cv.filterField.stringValue = ""
        cv.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: cv.filterField))
        // Relationships.
        setText(sc[0].id, "Петя вошёл. Анне Петровне стало легче.")
        let relAnna = main.characters.characters.first { $0.name == "Анна Петровна" }!.id!
        let rel = cv.addRelationship([relAnna, petr], kind: "друзья")!
        check(cv.relationshipTitles == ["Анна Петровна, Пётр Иванович — друзья"] && cv.selectedRelationship == rel && cv.relCard.shownID == rel, "New Relationship makes one and opens its card")
        check(cv.relCard.sceneRows.contains { $0.sceneID == sc[0].id && $0.mentions > 0 }, "its card lists the scenes where both characters are named")
        cv.relCard.setSceneLine(row: 0, "спорят о доме")
        check(main.relationships.relationship(rel)?.links[sc[0].id] == "спорят о доме", "and what the relationship does there is saved")
        cv.relCard.kindField.stringValue = "соседи"
        cv.relCard.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: cv.relCard.kindField))
        check(main.relationships.relationship(rel)?.kind == "соседи" && cv.relationshipTitles == ["Анна Петровна, Пётр Иванович — соседи"], "the kind can be changed, and the list follows")
        check(cv.addRelationship([relAnna], kind: "один") == nil, "a relationship needs two characters")
        cv.select(petr)
        check(cv.selectedRelationship == nil && main.relationships.relationships(of: petr).count == 1, "choosing a character shows the character again")
        for ext in ["json", "md"] { try? FileManager.default.removeItem(at: main.folder.appendingPathComponent("bible/relationships/\(rel).\(ext)")) }
        cv.reloadRelationships()
        cv.onOpenScene?(sc[0].id); spin(0.5)
        check(main.mode == main.writingMode && main.currentSceneID == sc[0].id, "opening a scene from the card goes to the text")
        app.modeCharacters(); spin(0.4)
        let cv2 = main.charactersView!
        cv2.select(petr)
        cv2.deleteSelected(confirm: false)
        check(main.characters.character(petr) == nil && cv2.shownNames == ["Анна Петровна"], "deleting a character takes it out of the list")
        check(!(((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(".quilland/trash").path)) ?? []).isEmpty), "and into the trash folder")
        cv2.onEscape?(); spin(0.4)
        check(main.mode == main.writingMode, "Esc leaves the view")
        setText(sc[0].id, "Первая строка новой книги.")

        // The World view.
        app.modeWorld(); spin(0.5)
        guard let wv = main.worldView else { check(false, "View ▸ World shows the view"); return 1 }
        let defaultWorld = main.worlds.worlds[0].id!
        check(main.mode == .world && wv.visibleTitles == [main.worlds.worlds[0].name!], "View ▸ World shows the world a new book has", "\(wv.visibleTitles)")
        check(main.localState().mode == "world", "and it is the view remembered for the book")
        let germany = wv.addPlace(named: "Германия")!
        let frankfurt = wv.addPlace(named: "Франкфурт")!
        let berlin = wv.addPlace(named: "Берлин", inside: false)!
        check(wv.visibleTitles.dropFirst().sorted() == ["  Германия", "    Берлин", "    Франкфурт"].sorted() && main.worlds.entry(berlin)?.parent == germany && main.worlds.entry(frankfurt)?.parent == germany, "a typed name makes a place inside the chosen one, or beside it", "\(wv.visibleTitles)")
        check(wv.addPlace(named: "  ") == nil, "a blank name makes nothing")
        let north = wv.addWorld(named: "Север")!
        check(wv.visibleTitles.contains("Север") && main.worlds.worlds.count == 2, "New World adds a world")
        check(wv.movePlace(berlin, into: north) && main.worlds.entry(berlin)?.world == north && main.worlds.entry(berlin)?.parent == nil, "a place dropped on another world goes there")
        check(!wv.movePlace(germany, into: frankfurt) && main.worlds.entry(germany)?.parent == nil, "a place cannot be dropped into what is inside it")
        check(wv.movePlace(frankfurt, into: defaultWorld) && main.worlds.entry(frankfurt)?.parent == nil, "dropping on a world makes it a top-level place there")
        setText(sc[0].id, "Он приехал во Франкфурт из Германии.")
        wv.select(frankfurt)
        check(wv.rows.count == 1 && wv.rows[0].mentions == 1, "the card lists the scenes where the name is", "\(wv.rows)")
        wv.setSceneLine(row: 0, "Первая ночь Анны.")
        check(main.worlds.entry(frankfurt)?.links[sc[0].id] == "Первая ночь Анны.", "and what happens there is saved")
        wv.descriptionView.string = "Большой город на реке."
        wv.textDidChange(Notification(name: NSText.didChangeNotification, object: wv.descriptionView))
        wv.commitEdits()
        check(main.worlds.text(frankfurt) == "Большой город на реке.", "the description is written to the place's text file")
        wv.typeBox.stringValue = "people"
        wv.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: wv.typeBox))
        check(main.worlds.entry(frankfurt)?.type == "people", "the kind of entry is a free label")
        wv.select(north)
        wv.deleteSelected(confirm: false)
        check(main.worlds.world(north) != nil, "a world with places in it is not deleted")
        wv.select(germany)
        let child = main.worlds.addEntryForTest(germany)
        wv.reload()
        wv.deleteSelected(confirm: false)
        check(main.worlds.entry(germany) == nil && main.worlds.entry(child)?.parent == nil, "deleting a place lifts what was inside it")
        wv.onOpenScene?(sc[0].id); spin(0.5)
        check(main.mode == main.writingMode, "opening a scene from the card goes to the text")
        app.modeWorld(); spin(0.4)
        main.worldView?.onEscape?(); spin(0.4)
        check(main.mode == main.writingMode, "Esc leaves the view")
        check(main.worlds.problems.isEmpty, "and the files of the worlds read without problems", "\(main.worlds.problems)")
        setText(sc[0].id, "Первая строка новой книги.")

        // The Events view.
        app.modeEvents(); spin(0.5)
        guard let ev = main.eventsView else { check(false, "View ▸ Events shows the view"); return 1 }
        check(main.mode == .events && ev.shownTitles.isEmpty, "View ▸ Events starts empty, inviting the first event")
        check(main.localState().mode == "events", "and it is the view remembered for the book")
        let arrival = ev.addEvent(titled: "  Анна приезжает ")!
        let farewell = ev.addEvent(titled: "Прощание")!
        let loose = ev.addEvent(titled: "Без сцены")!
        check(ev.addEvent(titled: "  ") == nil && main.eventStore.events.count == 3, "a typed title makes an event; a blank one makes nothing")
        let allScenes = main.session.structure.scenes
        ev.select(farewell)
        ev.addScene(allScenes[1].id)
        ev.select(arrival)
        ev.addScene(allScenes[0].id)
        spin(0.2)
        check(((again.window.firstResponder as? NSTextView)?.delegate as? NSTextField)?.placeholderString == "Type what happens here", "adding a connection puts the cursor in its What happens cell", "\(String(describing: again.window.firstResponder))")
        check(ev.shownTitles == ["Анна приезжает", "Прощание", "Без сцены"], "events are listed in the order of the book, those without a scene last", "\(ev.shownTitles)")
        ev.dateField.stringValue = "весна, год 214"
        ev.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: ev.dateField))
        check(main.eventStore.event(arrival)?.date == "весна, год 214", "the date is free text")
        ev.setConnectionText(row: 0, "Она выходит из корабля.")
        check(main.eventStore.event(arrival)?.links[allScenes[0].id] == "Она выходит из корабля." && ev.connections.count == 1, "what happens in a scene is saved")
        let annaID = main.characters.characters.first { $0.name == "Анна Петровна" }!.id!
        ev.addCharacter(annaID)
        ev.setConnectionText(row: ev.connections.firstIndex { $0.kind == .character }!, "Не знает, что станция пуста.")
        check(main.characters.character(annaID)?.links[arrival] == "Не знает, что станция пуста.", "a character who takes part is stored in the character's file")
        let placeID = main.worlds.entries.first?.id ?? (try! main.worlds.addEntry(name: "Посадочная площадка", world: main.worlds.worlds[0].id!))
        ev.addPlace(placeID)
        check(!ev.doubleClickOpens(column: 2) && ev.doubleClickOpens(column: 1), "a double-click in the What happens column is for typing and does not open anything")
        check(ev.connections.map(\.kind.rawValue) == ["Scene", "Place", "Character"], "scenes, places and characters are listed together", "\(ev.connections.map(\.kind.rawValue))")
        ev.removeConnection(row: ev.connections.firstIndex { $0.kind == .place }!)
        check(main.eventStore.event(arrival)?.places.isEmpty == true && ev.connections.count == 2, "a connection is taken away")
        ev.descriptionView.string = "Корабль садится на площадку."
        ev.textDidChange(Notification(name: NSText.didChangeNotification, object: ev.descriptionView))
        ev.commitEdits()
        check(main.eventStore.text(arrival) == "Корабль садится на площадку.", "the description is written to the event's text file")
        check(ev.planText == "Not on the plan yet", "an event starts off the plan")
        let plan = try! PlanStore(folder: folder)
        let line = try! plan.addLine(name: "Анна")
        ev.select(arrival)
        ev.putOnPlanOrShow()
        check(ev.planText == "On the plan: line “Анна”" && (try? PlanStore(folder: folder))?.entry(forEvent: arrival) != nil, "an event is put on the first line of the plan", ev.planText)
        _ = line
        ev.select(loose)
        ev.deleteSelected(confirm: false)
        check(main.eventStore.event(loose) == nil && ev.shownTitles == ["Анна приезжает", "Прощание"], "deleting an event takes it out of the list")
        ev.select(arrival)
        ev.deleteSelected(confirm: false)
        check((try? PlanStore(folder: folder))?.entry(forEvent: arrival) == nil && ev.shownTitles == ["Прощание"], "and off the plan")
        ev.onOpenScene?(allScenes[0].id); spin(0.5)
        check(main.mode == main.writingMode, "opening a scene from the card goes to the text")
        app.modeEvents(); spin(0.4)
        main.eventsView?.onOpenCharacter?(annaID); spin(0.4)
        check(main.mode == .characters && main.charactersView?.selected == annaID, "opening a character from the card goes to the Characters view")
        main.charactersView?.onEscape?(); spin(0.4)
        check(main.eventStore.problems.isEmpty && main.mode == main.writingMode, "the files of the events read without problems")

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
        m2.merge(sc2[0].id, direction: 1); spin(0.6)
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

        // Settings.
        guard let stFolder = create(title: "Settings Test", plan: false) else { check(false, "the book for the settings checks is made"); return 1 }
        spin(0.6)
        guard let stWin = app.bookWindows.last else { return 1 }
        stWin.usesFullScreen = false
        let stMain = stWin.main
        let prefs = AppPreferences.shared
        app.showSettings(); spin(0.3)
        guard let set = app.settingsWindow else { check(false, "Settings… opens the window"); return 1 }
        check(set.visibleSections == [.general, .appearance, .writing, .panels, .ai, .aiPrompts, .shortcuts], "Settings lists its sections")
        set.filter("quotes")
        check(set.visibleSections == [.writing], "the search field narrows the list to the sections that have the word")
        set.filter("")
        check(set.visibleSections.count == 7 && prefs.values == Preferences(), "and with nothing typed shows all; the preferences start at the design's defaults")

        // Appearance.
        stMain.setMode(.book); spin(0.4)
        let stScene = stMain.session.structure.scenes[0].id
        let stDoc = stMain.session.document(stScene)!
        stDoc.storage.replaceCharacters(in: NSRange(location: 0, length: stDoc.storage.length), with: String(repeating: "Длинная строка текста для проверки высоты листа. ", count: 30))
        stDoc.textDidChange(); spin(0.3)
        let sheetBefore = stMain.controllers[0].currentSheet?.height ?? stMain.controllers[0].stack.sheets[0].height
        let widthBefore = stMain.controllers[0].stack.sheets[0].frame.width
        set.setNumber("fontSize", 24); spin(0.4)
        check(Fonts.baseSize == 24 && (stMain.controllers[0].stack.sheets[0].textView.font?.pointSize ?? 0) == 24, "a larger text size reaches the text at once")
        check(stMain.controllers[0].stack.sheets[0].height > sheetBefore, "and the sheet grows to fit it", "\(sheetBefore) → \(stMain.controllers[0].stack.sheets[0].height)")
        set.setNumber("lineSpacing", 1.8); spin(0.3)
        check(Fonts.lineSpacing == 1.8, "line spacing follows")
        set.setNumber("readingWidth", 900); spin(0.4)
        check(stMain.controllers[0].stack.sheets[0].frame.width > widthBefore, "a wider reading width makes the sheets wider", "\(widthBefore) → \(stMain.controllers[0].stack.sheets[0].frame.width)")
        set.setChoice("font", "Palatino"); spin(0.3)
        check(Fonts.name == "Palatino" && (stMain.controllers[0].stack.sheets[0].textView.font?.familyName ?? "").contains("Palatino"), "the font family changes")
        set.setChoice("appearance", "dark")
        check(NSApp.appearance?.name == .darkAqua, "Dark makes the app dark")
        set.setChoice("appearance", "system")
        check(NSApp.appearance == nil, "and Like the system gives it back")
        set.reset(.appearance); spin(0.3)
        check(Fonts.baseSize == 17 && Fonts.lineSpacing == 1.3 && Fonts.name == "Georgia" && prefs.values.readingWidth == 640, "Reset to Defaults puts the section back")

        // Writing: the typing corrections, by the book's language.
        stMain.setMode(.panels); spin(0.4)
        stMain.reveal(scene: stScene, range: nil); spin(0.3)
        let typer = stMain.controllers[0].currentSheet!.textView
        func type(_ s: String) {
            typer.setSelectedRange(NSRange(location: typer.string.utf16.count, length: 0))
            for ch in s { typer.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        typer.setSelectedRange(NSRange(location: 0, length: typer.string.utf16.count))
        typer.insertText("", replacementRange: typer.selectedRange())
        type("Он сказал \"привет\" - да.")
        check(typer.string == "Он сказал «привет»\u{00A0}— да.", "typing: Russian quotes and a dash with a non-breaking space", typer.string.debugDescription)
        type("\n- Ну...")
        check(typer.string.hasSuffix("\n— Ну..."), "a dialogue dash at the start of a paragraph; three dots stay three dots", typer.string.debugDescription)
        set.setFlag("ellipsis", true)
        type(" Да...")
        check(typer.string.hasSuffix("Да…"), "with the ellipsis correction on, three dots become one character")
        set.setChoice("quoteStyle", "en")
        type(" \"x\"")
        check(typer.string.hasSuffix("“x”"), "a quote style can be forced")
        set.setFlag("corrections", false)
        type(" \"y\" - z")
        check(typer.string.hasSuffix("\"y\" - z"), "with the corrections off nothing is replaced")
        check(!(set.controls["dashes"]?.isEnabled ?? true), "and their switches are greyed")
        set.reset(.writing)
        check(prefs.autocorrect == AutocorrectSettings(), "Reset puts the writing choices back (the ellipsis one is off)")
        set.setFlag("spelling", false)
        check(!typer.isContinuousSpellCheckingEnabled, "turning spelling off reaches the text views")
        set.setFlag("spelling", true)
        check(typer.isContinuousSpellCheckingEnabled, "and on")

        // Panels.
        stMain.setRightPanel(true); spin(0.4)
        check(stMain.rightPanel.visibleTabs == [.section, .characters], "the right panel starts with both tabs")
        set.setFlag("tab.characters", false)
        check(stMain.rightPanel.visibleTabs == [.section], "a tab can be hidden")
        set.setFlag("tab.section", false)
        check(prefs.values.panelTabs == ["section"], "but one stays")
        set.setFlag("tab.characters", true)
        set.setNumber("followDelay", 3)
        check(stMain.rightPanel.followDelay == 3 && stMain.rightPanel.visibleTabs == [.section, .characters], "the follow delay changes, and the tab is back")
        stMain.setRightPanel(false)
        set.reset(.panels)

        // General.
        check(stWin.snapshotTimerIsRunning, "automatic snapshots are on by default")
        set.setFlag("autoSnapshots", false)
        check(!stWin.snapshotTimerIsRunning, "turning them off stops the timer")
        set.setFlag("autoSnapshots", true)
        set.setNumber("snapshotMinutes", 5)
        check(stWin.snapshotTimerIsRunning && stWin.snapshotInterval == 300, "and the interval is the one chosen")
        set.setNumber("recent", 2)
        check(app.settings.knownBooks.count <= 2 || AppPreferences.shared.values.recentLimit == 2, "the number of recent books is kept")
        set.setNewBookFolder(temp.appendingPathComponent("my books").path)
        set.setFlag("reopen", false)
        set.setChoice("mode", "book")
        let fromFile = AppSettings(directory: app.settings.directory).preferences
        check(fromFile == prefs.values && fromFile.newBookFolder == temp.appendingPathComponent("my books").path && !fromFile.reopenLastBook && fromFile.defaultMode == "book", "every choice is in settings.json, and a new run would read it back")
        check(FileManager.default.fileExists(atPath: app.settings.directory.appendingPathComponent("autocorrect.json").path), "the typing corrections are in autocorrect.json")
        let plainBook = try! BookCreator.create(NewBookRequest(title: "No State", parentFolder: temp))
        check(app.openBook(at: plainBook) && app.bookWindows.last?.main.mode == .book, "a book with no remembered view opens in the mode chosen")
        app.bookWindows.last?.window.close(); spin(0.3)
        set.reset(.general)
        check(prefs.values == Preferences() && prefs.autocorrect == AutocorrectSettings(), "everything is back to the defaults after the resets")

        // Book Settings.
        app.showBookSettings(); spin(0.3)
        check(app.bookSettingsWindowCount == 1, "Book ▸ Book Settings… opens the window for the book")
        if let bs = app.bookSettingsController(for: stFolder) {
            bs.apply { $0.title = "Новое имя" }
            spin(0.2)
            check(BookSettings.load(book: stFolder).title == "Новое имя" && stWin.window.title == "Новое имя" && app.settings.knownBooks.first { $0.path == stFolder.path }?.name == "Новое имя", "a new title is saved, shown in the window, and in the list of books")
            bs.apply { $0.title = "   " }
            check(BookSettings.load(book: stFolder).title == "Новое имя", "a blank title is refused")
            bs.apply { $0.author = "А. Автор"; $0.copyright = "© 2026"; $0.targetCharacters = 300000 }
            check(BookSettings.load(book: stFolder).author == "А. Автор" && BookSettings.load(book: stFolder).targetCharacters == 300000, "author, copyright and target size are saved in book.json")
            bs.setLanguage("en")
            check(stMain.session.document(stScene)?.language == "en", "the language reaches the text")
            typer.insertText("", replacementRange: NSRange(location: 0, length: typer.string.utf16.count))
            type("\"q\"")
            check(typer.string == "“q”", "and the quotes follow it", typer.string.debugDescription)
            bs.setLanguage("ru")
            bs.addWords("Аврора, кемпинг аврора")
            check(BookDictionary.load(book: stFolder) == ["аврора", "кемпинг"] && stMain.session.document(stScene)?.dictionaryWords == ["аврора", "кемпинг"], "dictionary words are saved in the book and given to the spell checker")
            bs.removeWord("кемпинг")
            check(BookDictionary.load(book: stFolder) == ["аврора"], "and can be removed")
            bs.window.close()
        } else { check(false, "the Book Settings window has a controller") }
        set.window.close()
        stWin.window.close(); spin(0.3)

        // The AI settings (no server is asked: the checks keep to their own address).
        do {
            app.showSettings(); spin(0.3)
            guard let st = app.settingsWindow else { check(false, "Settings opens for the AI checks"); return 1 }
            st.select(.ai); spin(0.2)
            let prefsNow = AppPreferences.shared
            st.setFlag("aiEnabled", false)
            check(!prefsNow.values.aiEnabled && !AIService.shared.isReady && AIService.shared.unavailableReason?.contains("switched off") == true, "with the AI switched off the actions are unavailable, and say why")
            st.setNumber("aiContext", 12288)
            check(prefsNow.values.aiContext == 12288 && AppSettings(directory: app.settings.directory).preferences.aiContext == 12288, "the context size is kept in settings.json")
            prefsNow.update { $0.aiAddress = "http://127.0.0.1:9"; $0.aiEnabled = true }
            var answered: AIStatus?
            AIService.shared.refresh { answered = $0 }
            let until = Date().addingTimeInterval(8)
            while answered == nil, Date() < until { spin(0.1) }
            check(answered?.reachable == false && !AIService.shared.isReady && AIService.shared.unavailableReason?.contains("LM Studio") == true, "a server that does not answer makes the actions unavailable, with the reason", "\(String(describing: answered))")
            check(NSApp.mainMenu?.items.contains { $0.submenu?.title == "AI" } == true, "the AI menu is there")
            st.reset(.ai); spin(0.2)
            check(prefsNow.values.aiAddress == AIConnection.defaultAddress && prefsNow.values.aiContext == 0 && prefsNow.values.aiEnabled, "Reset to Defaults gives the AI settings back")
            st.window.close(); spin(0.2)
        }

        // The AI prompts: the author's wording and temperatures, kept in prompts.json, used by the actions at once.
        do {
            app.showSettings(); spin(0.3)
            guard let st = app.settingsWindow else { check(false, "Settings opens for the prompt checks"); return 1 }
            st.select(.aiPrompts); spin(0.2)
            check(st.shownPromptKey == "collect", "the section starts with the first action")
            st.setPrompt("Пиши коротко. Язык: {language}.", key: "continue")
            check(ContinuePrompt.system(language: "ru") == "Пиши коротко. Язык: Russian." && AIPromptSettings.load(directory: app.settings.directory).prompts["continue"] == "Пиши коротко. Язык: {language}.", "the author's wording is used by the action at once and kept in prompts.json")
            st.setTemperature(1.2, key: "continue")
            check(AIPrompts.temperature("continue", default: 0.8) == 1.2 && AIPromptSettings.load(directory: app.settings.directory).temperatures["continue"] == 1.2, "and so is a temperature")
            st.setPrompt(AIPrompts.template(for: "continue"), key: "continue")
            check(AIPromptSettings.load(directory: app.settings.directory).prompts["continue"] == nil && ContinuePrompt.system(language: "ru").contains("co-author"), "putting the built-in text back removes the override")
            st.setTemperature(0.8, key: "continue")
            check(AIPromptSettings.load(directory: app.settings.directory).temperatures["continue"] == nil, "the action's own temperature is not kept as a choice")
            st.setPrompt("Что-то своё.", key: "chat"); st.setTemperature(0.3, key: "chat")
            st.reset(.aiPrompts); spin(0.2)
            check(AIPrompts.current == AIPromptSettings() && ChatPrompt.system(language: "ru").contains("thoughtful"), "Reset to Defaults takes all of them back")
            st.window.close(); spin(0.2)
        }

        // Saved AI actions: kept in actions.json, listed in the AI menu, renamed and deleted in Settings.
        do {
            let prefsNow = AppPreferences.shared
            prefsNow.updateActions { $0 = [AIAction(name: "Слабые места", prompt: "Найди слабые места.", attach: ["scene", "characters"]), AIAction(name: "Про план", prompt: "Перескажи план.")] }
            check(AIActions.load(directory: app.settings.directory).map(\.name) == ["Слабые места", "Про план"], "saved actions are kept in actions.json")
            let aiMenu = NSApp.mainMenu?.items.first { $0.submenu?.title == "AI" }?.submenu
            if let actions = aiMenu?.items.first(where: { $0.title == "Actions" })?.submenu {
                app.menuNeedsUpdate(actions)
                check(actions.items.map(\.title) == ["Слабые места", "Про план"], "they are listed in the AI menu under Actions")
            } else { check(false, "the AI menu has an Actions submenu") }
            app.showSettings(); spin(0.3)
            if let st = app.settingsWindow {
                st.select(.aiPrompts); spin(0.2)
                let titles = st.promptChoiceTitles
                check(titles.prefix(AIPrompts.entries.count).allSatisfy { $0.hasSuffix("System") } && titles.suffix(2) == ["Слабые места", "Про план"], "the system prompts and the author's own are in one list, the system ones marked")
                st.chooseAction(prefsNow.actions[0].id)
                st.setActionPrompt("Найди слабые места в сцене.", id: prefsNow.actions[0].id)
                check(AIActions.load(directory: app.settings.directory)[0].prompt == "Найди слабые места в сцене." && st.shownActionID == prefsNow.actions[0].id, "an own prompt is edited there too, and kept")
                st.setActionPrompt("   ", id: prefsNow.actions[0].id)
                check(AIActions.load(directory: app.settings.directory)[0].prompt == "Найди слабые места в сцене.", "an empty text is not kept")
                let id = prefsNow.actions[1].id
                st.renameAction(id, to: "  О плане  ")
                check(prefsNow.actions.map(\.name) == ["Слабые места", "О плане"] && AIActions.load(directory: app.settings.directory).map(\.name) == ["Слабые места", "О плане"], "an action can be renamed in Settings")
                st.removeAction(id)
                check(prefsNow.actions.map(\.name) == ["Слабые места"], "and deleted")
                st.reset(.aiPrompts)
                st.window.close(); spin(0.2)
            }
            prefsNow.updateActions { $0 = [] }
            check(AIActions.load(directory: app.settings.directory).isEmpty, "none left")
        }

        // The book's text size commands: a point at a time, inside the limits.
        do {
            let sizeNow = AppPreferences.shared.values
            app.appLarger()
            check(AppPreferences.shared.values.fontSize == sizeNow.fontSize + 1, "Larger Book Text makes the text a point bigger")
            app.appSmaller(); app.appSmaller()
            check(AppPreferences.shared.values.fontSize == sizeNow.fontSize - 1, "Smaller Book Text takes it back, and one step more")
            app.appUsualSize()
            check(AppPreferences.shared.values.fontSize == Preferences().fontSize, "Usual Book Text Size puts it back")
            for _ in 0..<40 { app.appLarger() }
            check(AppPreferences.shared.values.fontSize <= 36, "and it stops at its limit")
            app.appUsualSize(); spin(0.5)
        }

        // Shortcuts.
        do {
            app.showSettings(); spin(0.3)
            guard let st = app.settingsWindow else { check(false, "Settings opens for the shortcut checks"); return 1 }
            st.select(.shortcuts); spin(0.2)
            let page = st.shortcutsPage
            st.window.contentView?.layoutSubtreeIfNeeded()
            check(page.view.window != nil && page.view.frame.height > 250 && page.visibleRowCount > 30, "the Shortcuts page shows its list", "\(page.view.frame) rows \(page.visibleRowCount)")
            func menuItem(_ selector: String) -> NSMenuItem? {
                for top in NSApp.mainMenu?.items ?? [] { if let m = top.submenu?.items.first(where: { $0.action.map(NSStringFromSelector) == selector }) { return m } }
                return nil
            }
            check(app.shortcutCatalog.count > 30 && app.shortcutCatalog.contains { $0.id == "showExport" && $0.defaults == Shortcut("cmd+e") }, "the list has the app's own menu actions with their shortcuts", "\(app.shortcutCatalog.count)")
            check(menuItem("showExport")?.keyEquivalent == "e", "Export has ⌘E at first")
            page.select("showExport")
            check(page.set("showExport", to: Shortcut("opt+cmd+shift+x"), confirm: false) && menuItem("showExport")?.keyEquivalent == "x" && menuItem("showExport")?.keyEquivalentModifierMask.contains(.option) == true, "a new shortcut is in the menu at once")
            check(AppSettings(directory: app.settings.directory).preferences.shortcuts["showExport"] == "opt+shift+cmd+x", "and kept in settings.json")
            check(!page.set("showExport", to: Shortcut("cmd+c"), confirm: false) && !page.set("showExport", to: Shortcut("n"), confirm: false), "a standard command's keys and a bare letter are refused")
            check(page.set("showSnapshots", to: Shortcut("opt+cmd+shift+x"), confirm: false) && page.shortcut(of: "showExport") == nil && menuItem("showExport")?.keyEquivalent == "", "a key taken from another action leaves that one with none")
            check(page.set("showExport", to: nil, confirm: false) && AppSettings(directory: app.settings.directory).preferences.shortcuts["showExport"] == "none", "an action can have no shortcut")
            st.reset(.shortcuts); spin(0.2)
            check(AppSettings(directory: app.settings.directory).preferences.shortcuts.isEmpty && menuItem("showExport")?.keyEquivalent == "e" && menuItem("showSnapshots")?.keyEquivalent == "s", "Reset to Defaults gives them all back")
            st.window.close(); spin(0.2)
        }

        // The language of the interface.
        app.showSettings(); spin(0.3)
        guard let langSettings = app.settingsWindow else { check(false, "Settings opens for the language checks"); return 1 }
        check(L("Cancel") == "Cancel" && Lp("{n} scene", "{n} scenes", 21) == "21 scenes", "the interface starts in English (the checks keep to it)")
        check(["system", "en", "ru"].allSatisfy(langSettings.languageChoices.contains), "Settings lists the languages: the system's, English, and Russian (which comes with the app)", "\(langSettings.languageChoices)")
        langSettings.setChoice("language", "ru"); spin(0.5)
        check(L("Cancel") == "Отмена" && L("Open Book…") == "Открыть книгу…", "Russian: the texts change")
        check(Lp("{n} scene", "{n} scenes", 21) == "21 сцена" && Lp("{n} scene", "{n} scenes", 3) == "3 сцены" && Lp("{n} scene", "{n} scenes", 11) == "11 сцен", "and the plurals follow Russian's rule")
        let menuTitles = NSApp.mainMenu?.items.compactMap { $0.submenu?.title } ?? []
        check(menuTitles.contains("Файл") && menuTitles.contains("Правка") && menuTitles.contains("Вид") && menuTitles.contains("Раздел"), "the menus are made again in Russian at once", "\(menuTitles)")
        check(app.settingsWindow !== langSettings && app.settingsWindow?.window.title == "Настройки", "the Settings window is opened again in the new language")
        check(AppSettings(directory: app.settings.directory).preferences.interfaceLanguage == "ru", "and the choice is kept in settings.json")
        // A language of the user's own: a file.
        let ukFile = temp.appendingPathComponent("uk.json")
        try! Data("{\"code\":\"uk\",\"name\":\"Українська\",\"plural_rule\":\"ru\",\"strings\":{\"Cancel\":\"Скасувати\"}}".utf8).write(to: ukFile)
        let badFile = temp.appendingPathComponent("bad.json")
        try! Data("{ nope".utf8).write(to: badFile)
        check(app.settingsWindow?.installLanguage(from: badFile, quiet: true) == false && L("Cancel") == "Отмена", "a file that is not a language is refused and nothing changes")
        check(app.settingsWindow?.installLanguage(from: ukFile, quiet: true) == true, "a language file is installed")
        check(L("Cancel") == "Скасувати" && L("Open Book…") == "Open Book…", "its texts show, and a text it does not have shows in English")
        check(app.settingsWindow?.languageChoices.contains("uk") == true && FileManager.default.fileExists(atPath: app.settings.directory.appendingPathComponent("Languages/uk.json").path), "it is in the list, in the user's own folder")
        app.settingsWindow?.setChoice("language", "en"); spin(0.4)
        check(L("Cancel") == "Cancel" && (NSApp.mainMenu?.items.compactMap { $0.submenu?.title } ?? []).contains("File"), "English comes back")
        app.settingsWindow?.setChoice("language", "ru"); spin(0.3)
        app.settingsWindow?.reset(.general); spin(0.4)
        check(L("Cancel") == "Cancel" && prefs.values.interfaceLanguage == "en", "Reset to Defaults goes back to English")
        app.settingsWindow?.window.close(); spin(0.2)

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

        print("\n\(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
