import AppKit
import QuillandCore

extension NSPasteboard.PasteboardType {
    /// The selection as Quilland Markdown: bold, italic, footnotes, headings and quotes survive copy and paste.
    static let quillandMarkdown = NSPasteboard.PasteboardType("com.quilland.markdown")
}

/// A stack of scene editors (Book mode) lets the cursor walk from one scene into the next.
enum SceneDirection { case previous, next }

protocol SceneNavigationDelegate: AnyObject {
    /// The cursor is at the end (or start) of a scene and wants to go on. `x` is the horizontal place in window coordinates to keep, or nil for the very start or end.
    func editor(_ editor: EditorTextView, moveTo direction: SceneDirection, x: CGFloat?) -> Bool
}

final class EditorTextView: NSTextView {
    weak var navigation: SceneNavigationDelegate?
    /// The text this view shows (set by the document that made it).
    weak var document: SceneDocument?
    lazy var ghost = GhostController(view: self)

    /// Milliseconds the last key press took to handle (not including drawing).
    var lastKeyMilliseconds = 0.0

    /// The book's language, for the quotes of the typing corrections.
    var documentLanguage: () -> String = { "ru" }

    /// Words the spell checker accepts here (the book's dictionary).
    func setIgnoredWords(_ words: [String]) {
        NSSpellChecker.shared.setIgnoredWords(words, inSpellDocumentWithTag: spellCheckerDocumentTag)
    }

    /// The typing corrections: a typed quote, dash or dot may be replaced by what the author's rules say (one undo step takes it back).
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if hasGhost { discardGhost() }
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if typed.utf16.count == 1, !hasMarkedText(), replacementRange.location == NSNotFound, selectedRange().length == 0, let storage = textStorage {
            let caret = selectedRange().location
            let text = storage.string as NSString
            let paragraphStart = text.paragraphRange(for: NSRange(location: min(caret, text.length), length: 0)).location
            let before = caret > paragraphStart ? text.substring(with: NSRange(location: paragraphStart, length: caret - paragraphStart)) : ""
            if let edit = Autocorrect.edit(typed: typed, before: before, settings: AppPreferences.shared.autocorrect, language: documentLanguage()) {
                let back = (before as NSString).substring(from: max(0, (before as NSString).length - edit.back)).utf16.count
                super.insertText(edit.text, replacementRange: NSRange(location: caret - back, length: back))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Esc: the owner may use it (Focus Mode is left with it); return true when it did.
    var onEscape: (() -> Bool)?

    /// Where the menu was asked for: "Learn Spelling" teaches the word that is there.
    private var contextIndex: Int?

    /// The word "Learn Spelling" is about: the selection, or the word under the pointer when the menu was opened.
    func wordToLearn() -> String? {
        let ns = string as NSString
        var range = selectedRange()
        if range.length == 0, let i = contextIndex, i <= ns.length, let storage = textStorage, storage.length > 0 {
            range = storage.doubleClick(at: min(i, ns.length - 1))
        }
        guard range.length > 0, NSMaxRange(range) <= ns.length else { return nil }
        let word = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return word.isEmpty || word.contains(" ") ? nil : word
    }

    /// The system's "Learn Spelling" item would teach the whole system (and its action may not even come to this view): it is pointed at this view's own.
    @discardableResult
    func rewireLearn(_ menu: NSMenu) -> Bool {
        var found = false
        var learnItems: [NSMenuItem] = []
        for item in menu.items {
            if item.identifier == Self.addWordItem { found = true }
            // The system's item is `_learnSpellingFromMenu:` (its title is in the system's language, so the action is what tells it).
            let name = item.action.map(NSStringFromSelector) ?? ""
            if name.localizedCaseInsensitiveContains("learn") || item.title == "Learn Spelling" || item.title == L("Learn Spelling") {
                learnItems.append(item)
            }
            if let sub = item.submenu, rewireLearn(sub) { found = true }
        }
        for item in learnItems {
            item.target = self
            item.action = #selector(learnSpelling(_:))
            item.isEnabled = wordToLearn() != nil
            found = true
        }
        // One is enough: the system may offer two (the word and the spelling) and both come here.
        for extra in learnItems.dropFirst() { menu.removeItem(extra) }
        // The system did not offer it (or it is not found): the menu gets an item of its own for a misspelled word.
        if !found, menu === topMenu, let word = wordToLearn(), NSSpellChecker.shared.checkSpelling(of: word, startingAt: 0, language: document?.language ?? documentLanguage(), wrap: false, inSpellDocumentWithTag: spellCheckerDocumentTag, wordCount: nil).location != NSNotFound,
           !(document?.dictionaryWords.contains(word.lowercased()) ?? false) {
            let item = NSMenuItem(title: L("Add “{word}” to the Dictionary", ["word": word]), action: #selector(learnSpelling(_:)), keyEquivalent: "")
            item.target = self
            item.identifier = Self.addWordItem
            let at = menu.items.firstIndex { $0.isSeparatorItem } ?? menu.items.count
            menu.insertItem(item, at: at)
            found = true
        }
        return found
    }

    private static let addWordItem = NSUserInterfaceItemIdentifier("quilland.addWord")
    /// The menu that is being shown (the top of the tree that `rewireLearn` walks).
    weak var topMenu: NSMenu?

    /// The menu's "Learn Spelling" teaches the word to this book (its dictionary, which Book Settings shows and Git keeps), not to the whole system.
    @objc func learnSpelling(_ sender: Any?) {
        guard let word = wordToLearn() else { return }
        (NSApp.delegate as? AppDelegate)?.learnWord(word, from: window)
    }

    /// The usual menu, and under it what the model can do here.
    override func menu(for event: NSEvent) -> NSMenu? {
        // A Control-click comes here without passing the mouse handlers, and the system would show its own menu: ours is shown instead.
        if event.type == .leftMouseDown {
            DispatchQueue.main.async { [weak self] in self?.showOwnMenu(event) }
            return nil
        }
        return makeMenu(for: event)
    }

    private func makeMenu(for event: NSEvent) -> NSMenu? {
        contextIndex = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let menu = super.menu(for: event) ?? NSMenu()
        guard AIService.shared.isEnabled, let delegate = NSApp.delegate as? AppDelegate else { return menu }
        menu.addItem(.separator())
        let ai = NSMenuItem(title: L("AI"), action: nil, keyEquivalent: "")
        ai.identifier = Self.aiMenuItem
        let sub = NSMenu(title: L("AI"))
        let ready = AIService.shared.isReady
        let hasSelection = selectedRange().length > 0
        for (title, selector) in [(hasSelection ? L("Check the Selection for Contradictions") : L("Check the Scene for Contradictions"), #selector(AppDelegate.consistencyHereAction)),
                                  (L("Continue Writing"), #selector(AppDelegate.continueAction))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = delegate
            item.isEnabled = ready
            sub.addItem(item)
        }
        if !ready, let why = AIService.shared.unavailableReason { let note = NSMenuItem(title: why, action: nil, keyEquivalent: ""); note.isEnabled = false; sub.addItem(.separator()); sub.addItem(note) }
        ai.submenu = sub
        menu.addItem(ai)
        return menu
    }

    static let aiMenuItem = NSUserInterfaceItemIdentifier("quilland.ai")

    /// What stays of the system's menu: editing, the spelling (its suggestions and its submenu) and our own AI. Fonts, substitutions, speech,
    /// layout, translation, sharing, web search, services and the like have no use in a book (the text's look comes from Markdown).
    static func keeps(_ item: NSMenuItem) -> Bool {
        if item.isSeparatorItem || item.identifier == aiMenuItem { return true }
        if item.submenu?.items.first?.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierSpellingAndGrammar" || item.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierSpellingAndGrammar" { return true }
        guard let action = item.action else { return false }
        let name = NSStringFromSelector(action)
        return ["cut:", "copy:", "paste:", "pasteAsPlainText:"].contains(name) || name.localizedCaseInsensitiveContains("spelling") || name.localizedCaseInsensitiveContains("spellcheck")
    }

    /// The system writes its items in the system's language; the application's own language is used instead.
    private static func title(forAction name: String) -> String? {
        switch name {
        case "cut:": return L("Cut")
        case "copy:": return L("Copy")
        case "paste:": return L("Paste")
        case "pasteAsPlainText:": return L("Paste and Match Style")
        case "showGuessPanel:": return L("Show Spelling and Grammar")
        case "checkSpelling:": return L("Check Document Now")
        case "toggleContinuousSpellChecking:": return L("Check Spelling While Typing")
        case "toggleGrammarChecking:": return L("Check Grammar with Spelling")
        case "toggleAutomaticSpellingCorrection:": return L("Correct Spelling Automatically")
        case "learnSpelling:": return L("Learn Spelling")
        case "ignoreSpelling:": return L("Ignore Spelling")
        default: return nil
        }
    }

    private static func localize(_ menu: NSMenu) {
        for item in menu.items {
            if let action = item.action, let title = title(forAction: NSStringFromSelector(action)) { item.title = title }
            if item.identifier?.rawValue == "__NSTextViewContextSubmenuIdentifierSpellingAndGrammar" {
                item.title = L("Spelling and Grammar")
                if let sub = item.submenu { sub.title = item.title; localize(sub) }
            }
        }
    }

    static func trim(_ menu: NSMenu) {
        for item in menu.items.reversed() where !keeps(item) { menu.removeItem(item) }
        localize(menu)
        // No separator at the ends or two in a row.
        var previousSeparator = true
        for item in menu.items { if item.isSeparatorItem { if previousSeparator { menu.removeItem(item) } else { previousSeparator = true } } else { previousSeparator = false } }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
    }

    /// The system adds some of its items (AutoFill, Services) after the menu is handed over, so the menu is trimmed again as it opens.
    private final class MenuTrimmer: NSObject, NSMenuDelegate {
        weak var view: EditorTextView?
        func menuWillOpen(_ menu: NSMenu) {
            EditorTextView.trim(menu)
            view?.rewireLearn(menu)
            DispatchQueue.main.async { [weak self] in EditorTextView.trim(menu); self?.view?.rewireLearn(menu) }
        }
    }
    private static let trimmer = MenuTrimmer()

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        Self.trim(menu)
        topMenu = menu
        rewireLearn(menu)
        Self.trimmer.view = self
        menu.delegate = Self.trimmer
    }

    /// The menu is opened here, from our own trimmed menu: the system's way of opening a text view's menu adds AutoFill and Services itself, after anything we can do.
    override func rightMouseDown(with event: NSEvent) {
        guard window != nil else { super.rightMouseDown(with: event); return }
        showOwnMenu(event)
    }

    private func showOwnMenu(_ event: NSEvent) {
        guard window != nil, let menu = makeMenu(for: event) else { return }
        Self.trim(menu)
        topMenu = menu
        rewireLearn(menu)
        guard !menu.items.isEmpty else { return }
        menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
    }

    override func mouseDown(with event: NSEvent) {
        if hasGhost { discardGhost() }
        // Control-click is a right click.
        if event.modifierFlags.contains(.control), !event.modifierFlags.contains(.command) { rightMouseDown(with: event); return }
        super.mouseDown(with: event)
    }

    /// Moving the cursor by any other means drops a suggestion too.
    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        if hasGhost, !ghost.settingSelection { discardGhost() }
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
    }

    override func keyDown(with event: NSEvent) {
        // A suggestion waits: Tab takes it, Esc drops it, and any other key drops it and does its own work. Return never accepts.
        if ghost.handle(event) { return }
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty, onEscape?() == true { return }
        let started = CACurrentMediaTime()
        super.keyDown(with: event)
        lastKeyMilliseconds = (CACurrentMediaTime() - started) * 1000
    }

    // MARK: Walking across the boundary of a scene

    /// The insertion point as a rectangle in this view's own coordinates, worked out from the layout (not from the screen, which is
    /// useless for a view that is scrolled out of sight).
    func caretRect() -> NSRect? { caretRect(at: selectedRange().location) }

    func caretRect(at offset: Int) -> NSRect? {
        guard let layout = textLayoutManager, let content = layout.textContentManager else { return nil }
        let length = textStorage?.length ?? 0
        let clamped = min(max(0, offset), length)
        guard let location = content.location(content.documentRange.location, offsetBy: clamped) else { return nil }
        // The very end of the text has no layout fragment of its own: it belongs to the last character's.
        let lookup = (clamped >= length && length > 0) ? (content.location(content.documentRange.location, offsetBy: length - 1) ?? location) : location
        layout.ensureLayout(for: NSTextRange(location: lookup))
        guard let fragment = layout.textLayoutFragment(for: lookup) else {
            // An empty text: the first line.
            return NSRect(x: textContainerInset.width, y: textContainerInset.height, width: 1, height: font?.pointSize ?? 17)
        }
        let inFragment = content.offset(from: fragment.rangeInElement.location, to: location)
        let frame = fragment.layoutFragmentFrame
        // A position exactly at a soft line break belongs to the line that starts there (the cursor is shown at the start of the next line),
        // not to the end of the line before it; only the very end of the text belongs to the last line's end.
        let lines = fragment.textLineFragments
        let line = lines.first { $0.characterRange.location <= inFragment && inFragment < NSMaxRange($0.characterRange) }
            ?? lines.last { $0.characterRange.location <= inFragment && inFragment <= NSMaxRange($0.characterRange) }
        if let line {
            let x = line.locationForCharacter(at: inFragment).x
            return NSRect(x: textContainerInset.width + frame.minX + line.typographicBounds.minX + x, y: textContainerInset.height + frame.minY + line.typographicBounds.minY,
                          width: 1, height: line.typographicBounds.height)
        }
        return NSRect(x: textContainerInset.width + frame.minX, y: textContainerInset.height + frame.minY, width: 1, height: frame.height)
    }

    /// The text offset where the last line of the text starts (from the layout, not from the cursor).
    func startOfLastLine() -> Int {
        guard let layout = textLayoutManager, let content = layout.textContentManager, let length = textStorage?.length, length > 0,
              let last = content.location(content.documentRange.location, offsetBy: length - 1) else { return 0 }
        layout.ensureLayout(for: NSTextRange(location: last))
        guard let fragment = layout.textLayoutFragment(for: last), let line = fragment.textLineFragments.last else { return 0 }
        return content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location) + line.characterRange.location
    }

    /// The horizontal place of the insertion point in window coordinates.
    func caretWindowX() -> CGFloat? {
        guard let rect = caretRect() else { return nil }
        return convert(rect, to: nil).minX
    }

    private func crossIfStuck(before: NSRange, direction: SceneDirection, useX: Bool) {
        let length = textStorage?.length ?? 0
        let after = selectedRange()
        guard after == before, after.length == 0 else { return }
        let atEdge = direction == .next ? after.location == length : after.location == 0
        guard atEdge else { return }
        _ = navigation?.editor(self, moveTo: direction, x: useX ? caretWindowX() : nil)
    }

    /// Is the cursor on the last (or first) line of this scene? Then Down (or Up) goes into the neighbouring scene at once,
    /// instead of first running to the end (or start) of the line.
    private func cursorIsOnEdgeLine(last: Bool) -> Bool {
        guard selectedRange().length == 0, let here = caretRect(), let edge = caretRect(at: last ? (textStorage?.length ?? 0) : 0) else { return false }
        return abs(here.minY - edge.minY) < 1
    }

    override func moveDown(_ sender: Any?) {
        if cursorIsOnEdgeLine(last: true), navigation?.editor(self, moveTo: .next, x: caretWindowX()) == true { return }
        let b = selectedRange(); super.moveDown(sender); crossIfStuck(before: b, direction: .next, useX: true)
    }

    override func moveUp(_ sender: Any?) {
        if cursorIsOnEdgeLine(last: false), navigation?.editor(self, moveTo: .previous, x: caretWindowX()) == true { return }
        let b = selectedRange(); super.moveUp(sender); crossIfStuck(before: b, direction: .previous, useX: true)
    }
    override func moveRight(_ sender: Any?) { let b = selectedRange(); super.moveRight(sender); crossIfStuck(before: b, direction: .next, useX: false) }
    override func moveLeft(_ sender: Any?) { let b = selectedRange(); super.moveLeft(sender); crossIfStuck(before: b, direction: .previous, useX: false) }

    /// Puts the cursor on the first or last line, as near as it can to the window's x.
    func placeCaret(atTop: Bool, windowX: CGFloat?) {
        guard let window else { return }
        window.makeFirstResponder(self)
        let length = textStorage?.length ?? 0
        guard let x = windowX else { setSelectedRange(NSRange(location: atTop ? 0 : length, length: 0)); return }
        let local = convert(NSPoint(x: x, y: 0), from: nil)
        let y = atTop ? textContainerInset.height + 4 : max(textContainerInset.height, bounds.height - textContainerInset.height - 4)
        let index = min(characterIndexForInsertion(at: NSPoint(x: local.x, y: y)), length)
        setSelectedRange(NSRange(location: index, length: 0))
    }

    // MARK: Kinds of paragraph

    func kindOfParagraph(at location: Int) -> String {
        guard let storage = textStorage, storage.length > 0 else { return BlockKind.body }
        let at = min(max(0, location), storage.length - 1)
        return storage.attribute(.quillandBlock, at: at, effectiveRange: nil) as? String ?? BlockKind.body
    }

    func setKind(_ kind: String, forParagraphsIn range: NSRange) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let paragraphs = text.paragraphRange(for: range)
        guard shouldChangeText(in: paragraphs, replacementString: nil) else { return }
        storage.beginEditing()
        storage.addAttribute(.quillandBlock, value: kind, range: paragraphs)
        Styler.style(storage, range: paragraphs)
        storage.endEditing()
        didChangeText()
    }

    // MARK: Return

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { return super.insertNewline(sender) }
        let selection = selectedRange()
        let text = storage.string as NSString
        let paragraph = text.paragraphRange(for: NSRange(location: min(selection.location, max(0, text.length - 1)), length: 0))
        let kind = kindOfParagraph(at: paragraph.location)
        let content = text.length == 0 ? "" : text.substring(with: paragraph).trimmingCharacters(in: .newlines)

        // Return on an empty set-off block leaves it.
        if kind == BlockKind.quote, content.isEmpty, selection.length == 0 {
            setKind(BlockKind.body, forParagraphsIn: paragraph)
            typingAttributes = Styler.attributes(kind: BlockKind.body)
            return
        }
        super.insertNewline(sender)
        // After a heading, a scene break or a fragment boundary the next paragraph is ordinary text.
        if [BlockKind.heading1, BlockKind.heading2, BlockKind.heading3, BlockKind.sceneBreak, BlockKind.fragment].contains(kind) {
            typingAttributes = Styler.attributes(kind: BlockKind.body)
            let after = selectedRange().location
            if after < storage.length { setKind(BlockKind.body, forParagraphsIn: NSRange(location: after, length: 0)) }
        }
    }

    // MARK: Clipboard (also used by drag and drop)

    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        _ = writeSelection(to: pb, types: [.quillandMarkdown, .string])
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0, isEditable else { return }
        copy(sender)
        insertText("", replacementRange: selectedRange())
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.quillandMarkdown, .string] }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.quillandMarkdown, .string] }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let storage = textStorage else { return false }
        let range = selectedRange()
        guard range.length > 0 else { return false }
        let selected = storage.attributedSubstring(from: range)
        let markdown = MarkdownWriter.write(AttributedBridge.document(from: selected))
        if types.contains(.quillandMarkdown) { pboard.setString(markdown, forType: .quillandMarkdown) }
        if types.contains(.string) { pboard.setString(Self.plainText(of: selected), forType: .string) }
        return true
    }

    /// What other programs get: the words, with paragraph breaks, without the placeholders.
    static func plainText(of attributed: NSAttributedString) -> String {
        attributed.string
            .replacingOccurrences(of: AttributedBridge.object, with: "")
            .replacingOccurrences(of: AttributedBridge.lineSeparator, with: "\n")
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard let storage = textStorage else { return false }
        let range = selectedRange()
        let kind = kindOfParagraph(at: range.location)
        let inserted: NSAttributedString
        if type == .quillandMarkdown, let markdown = pboard.string(forType: .quillandMarkdown) {
            let document = MarkdownParser.parse(markdown)
            if document.blocks.count == 1, case .paragraph = document.blocks[0], kind != BlockKind.sceneBreak, kind != BlockKind.fragment {
                // One paragraph pasted into a paragraph takes the paragraph's kind.
                let piece = NSMutableAttributedString(attributedString: AttributedBridge.attributedString(from: document))
                piece.addAttribute(.quillandBlock, value: kind, range: NSRange(location: 0, length: piece.length))
                inserted = piece
            } else {
                inserted = AttributedBridge.attributedString(from: document)
            }
        } else if let string = pboard.string(forType: .string) {
            inserted = Self.paragraphs(fromPlainText: string, kind: kind)
        } else {
            return false
        }
        let styled = NSMutableAttributedString(attributedString: inserted)
        guard shouldChangeText(in: range, replacementString: styled.string) else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: styled)
        let pasted = NSRange(location: range.location, length: styled.length)
        Styler.style(storage, range: pasted)
        storage.endEditing()
        setSelectedRange(NSRange(location: NSMaxRange(pasted), length: 0))
        didChangeText()
        return true
    }

    /// Text from another program: its formatting is dropped; every line is a paragraph.
    static func paragraphs(fromPlainText string: String, kind: String) -> NSAttributedString {
        var text = string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: "\u{FEFF}", with: "\u{2060}")
        text = text.precomposedStringWithCanonicalMapping
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
        let kept = kind == BlockKind.sceneBreak || kind == BlockKind.fragment ? BlockKind.body : kind
        return NSAttributedString(string: lines.joined(separator: "\n").replacingOccurrences(of: "\n\n+", with: "\n", options: .regularExpression),
                                  attributes: Styler.attributes(kind: kept))
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if pb.availableType(from: [.quillandMarkdown]) != nil { _ = readSelection(from: pb, type: .quillandMarkdown) }
        else if pb.availableType(from: [.string]) != nil { _ = readSelection(from: pb, type: .string) }
        else { super.paste(sender) }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        let pb = NSPasteboard.general
        if pb.availableType(from: [.string]) != nil { _ = readSelection(from: pb, type: .string) }
    }

    override func pasteAsRichText(_ sender: Any?) { paste(sender) }
}
