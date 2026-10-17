import AppKit
import QuillandCore

/// Search and Replace, the Format menu, dictation, Focus Mode.
extension AppSelfTest {
    func editing() -> Int32? {
        let main = self.main!
        let folder = self.folder!
        let again = self.again!
        // Search and Replace.
        let sc = main.session.structure.scenes
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
        panel2.view.window?.layoutIfNeeded(); panel2.view.layoutSubtreeIfNeeded()
        check(!panel2.replaceField.isHidden && abs(panel2.replaceField.frame.width - panel2.findField.frame.width) < 1 && panel2.replaceField.frame.width >= 150, "the replacement field is visible and as wide as the Find field", "\(panel2.replaceField.frame)")
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
        self.sc = sc
        return nil
    }
}
