import AppKit
import QuillandCore

/// Proofreading, grammar, loose ends and the AI helpers: collecting, consistency, continuing, synopsis, chat.
extension AppSelfTest {
    func aiFeatures() -> Int32? {
        let book = self.book!
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
            do {
                book.main.setBottomPanelHeight(330); spin(0.3)
                let taller = book.main.bottomPanelHeight
                book.main.setBottomPanelHeight(200); spin(0.3)
                let shorter = book.main.bottomPanelHeight
                check(abs(taller - 330) < 3 && abs(shorter - 200) < 3, "the bottom panel can be given a height", "\(taller) \(shorter)")
                func handles(_ v: NSView) -> [PanelResizeHandle] { (v as? PanelResizeHandle).map { [$0] } ?? v.subviews.flatMap(handles) }
                let handle = handles(book.main.searchPanel.view).first
                handle?.onResize?(280); spin(0.3)
                check(handle != nil && abs(book.main.bottomPanelHeight - 280) < 3, "and the strip along its top edge resizes it", "\(book.main.bottomPanelHeight)")
                if let content = book.window.contentView, let panelView = Optional(book.main.searchPanel.view) {
                    let inWindow = panelView.convert(NSPoint(x: panelView.bounds.midX, y: panelView.bounds.maxY - 3), to: nil)
                    let hit = content.hitTest(content.superview?.convert(inWindow, from: nil) ?? inWindow)
                    check(hit is PanelResizeHandle, "the strip is what a click at the top edge of the panel reaches", "\(String(describing: hit))")
                }
                handle?.onReset?(); spin(0.3)
                check(abs(book.main.bottomPanelHeight - 260) < 3, "a double-click on the strip gives it the usual height", "\(book.main.bottomPanelHeight)")
            }
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
            var event = CollectedItem(kind: .events, name: "Приезд Сборкина"); event.date = "осень"; event.places = ["Сборград"]; event.members = ["Сборкин", "Тестовая Аня", "Неизвестный"]; event.detail = "Он приезжает."; event.evidence = [evidence("приезжает")]
            var rel = CollectedItem(kind: .relationships, name: ""); rel.members = ["Сборкин", "Тестовая Аня"]; rel.type = "знакомые"; rel.evidence = [evidence("встреча")]
            var lonely = CollectedItem(kind: .relationships, name: ""); lonely.members = ["Сборкин", "Никто"]; lonely.type = "враги"; lonely.evidence = [evidence("x")]
            var obs = CollectedItem(kind: .observations, name: ""); obs.about = "Сборкин"; obs.detail = "Носит шляпу."; obs.evidence = [evidence("шляпа")]
            var orphan = CollectedItem(kind: .observations, name: ""); orphan.about = "дом Сборкина"; orphan.detail = "Стоит на холме."; orphan.evidence = [evidence("холм")]
            // The Collect window opens on the current scene.
            let modeBefore = main.mode
            main.reveal(scene: sceneID, range: nil); spin(0.3)
            let sheet = CollectSheet(main: main)
            _ = sheet.prepare()
            check(main.currentSceneID != nil && sheet.currentChoice.scope == .scene, "the Collect window starts on the current scene", "\(sheet.currentChoice.scope) \(main.mode)")
            if main.mode != modeBefore { main.setMode(modeBefore); spin(0.3) }
            check(CollectSheet.defaultScope(hasCurrentScene: false) == .book, "and on the whole book when there is no current scene")
            main.collect.inject([c, again, town, square, event, rel, lonely, obs, orphan])
            main.showSearch(.suggestions); spin(0.3)
            let sv = main.searchPanel.suggestView
            check(main.searchPanel.mode == .suggestions && sv.itemCount == 9 && sv.checkedCount == 0, "the findings wait unchecked in the Suggestions tab")
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
            check(made?.links[ev?.id ?? "-"] == "" && main.characters.character(known)?.links[ev?.id ?? "-"] == "", "the characters who take part are linked to the event, in their own files")
            check(!main.characters.characters.contains { $0.name == "Неизвестный" }, "a participant with no card does not get one")
            check(main.relationships.relationships.contains { Set($0.characters) == Set([made?.id ?? "", known]) && $0.kind == "знакомые" } && !main.relationships.relationships.contains { $0.kind == "враги" }, "a relationship is made between characters that have cards; one with a stranger is not")
            check(sv.itemCount == 2, "what was accepted leaves the list; what could not be made stays", "\(sv.itemCount)")
            check(sv.checkedCount == 0, "and what stays is no longer ticked", "\(sv.checkedCount)")
            check(main.collect.skipReason(for: orphan.id)?.contains("дом Сборкина") == true && main.collect.skipReason(for: lonely.id)?.contains("two characters") == true && main.collect.skipReason(for: obs.id) == nil, "each of them says why", "\(String(describing: main.collect.skipReason(for: orphan.id)))")
            check(main.collect.message.contains("2 skipped") && main.collect.message.contains("дом Сборкина"), "and the message names what was skipped", main.collect.message)
            check(sv.reasonShown(for: orphan.id), "and the row shows the reason")
            // The same again does not make a second card.
            main.collect.inject([c]); sv.checkAll()
            let second = sv.acceptChecked()!
            check(second.created.isEmpty && second.updated == 1 && main.characters.characters.filter { $0.name == "Сборкин" }.count == 1, "accepting a thing found again only updates its card")
            // An event that is already in the book gets its participants too.
            try? main.characters.update(known) { r in var l = r.links; l.removeValue(forKey: ev?.id ?? "-"); r.links = l }
            main.collect.inject([event]); sv.checkAll()
            let third = sv.acceptChecked()!
            check(third.created.isEmpty && main.characters.character(known)?.links[ev?.id ?? "-"] == "" && main.eventStore.events.filter { $0.title == "Приезд Сборкина" }.count == 1, "an event found again links its participants without a second event", "\(third)")
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
            // A new run starts from an empty list: what an earlier run found and what was left waiting goes.
            var leftover = CollectedItem(kind: .characters, name: "Остаток"); leftover.evidence = [CollectedEvidence(scene: sceneID, quote: "x", range: NSRange(location: 0, length: 1), note: "")]
            main.collect.inject([leftover])
            check(sv.itemCount == 1 && sv.findingCount == 1, "an earlier run's findings and contradictions are waiting")
            main.collect.beginNewRun(); spin(0.2)
            check(sv.itemCount == 0 && sv.findingCount == 0 && main.collect.items.isEmpty && main.collect.findings.isEmpty && main.collect.summary == nil, "a new run starts from an empty list")
            // (Put the contradiction back for the checks that follow.)
            main.collect.injectFindings([finding]); spin(0.2); sv.checkAll()
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
        return nil
    }
}
