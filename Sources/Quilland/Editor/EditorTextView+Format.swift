import AppKit
import QuillandCore

/// The Format menu: the commands go to the text view that has the keyboard focus (the menu items have no target).
extension EditorTextView {
    // MARK: Character styles

    @objc func toggleBold(_ sender: Any?) { toggle(.quillandBold) }
    @objc func toggleItalic(_ sender: Any?) { toggle(.quillandItalic) }

    /// Bold or italic for the selection (all of it is bold, or none of it); with no selection, for what is typed next.
    func toggle(_ key: NSAttributedString.Key) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        if range.length == 0 {
            var typing = typingAttributes
            typing[key] = typing[key] as? Bool == true ? nil : true
            let kind = typing[.quillandBlock] as? String ?? BlockKind.body
            typing[.font] = Fonts.font(kind: kind, bold: typing[.quillandBold] as? Bool == true, italic: typing[.quillandItalic] as? Bool == true)
            typingAttributes = typing
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let all = isEntire(range, styled: key)
        storage.beginEditing()
        if all { storage.removeAttribute(key, range: range) } else { storage.addAttribute(key, value: true, range: range) }
        Styler.style(storage, range: range)
        storage.endEditing()
        didChangeText()
    }

    private func isEntire(_ range: NSRange, styled key: NSAttributedString.Key) -> Bool {
        guard let storage = textStorage else { return false }
        var all = true
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if value as? Bool != true { all = false; stop.pointee = true }
        }
        return all
    }

    // MARK: Paragraph styles

    @objc func makeHeading1(_ sender: Any?) { setKind(BlockKind.heading1, forParagraphsIn: selectedRange()) }
    @objc func makeHeading2(_ sender: Any?) { setKind(BlockKind.heading2, forParagraphsIn: selectedRange()) }
    @objc func makeHeading3(_ sender: Any?) { setKind(BlockKind.heading3, forParagraphsIn: selectedRange()) }
    @objc func makeBody(_ sender: Any?) { setKind(BlockKind.body, forParagraphsIn: selectedRange()) }
    /// The set-off block (a quotation set apart). Pressed again on a block that is one, it goes back to body text.
    @objc func makeQuote(_ sender: Any?) {
        let on = kindOfParagraph(at: selectedRange().location) == BlockKind.quote
        setKind(on ? BlockKind.body : BlockKind.quote, forParagraphsIn: selectedRange())
    }

    // MARK: Insertions

    /// `* * *` as its own paragraph after the one the cursor is in; the cursor goes on below it, in body text.
    @objc func insertSceneBreak(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let text = storage.string as NSString
        let selection = selectedRange()
        let paragraph = text.paragraphRange(for: NSRange(location: min(selection.location, text.length), length: 0))
        let endsWithNewline = paragraph.length > 0 && text.character(at: NSMaxRange(paragraph) - 1) == 0x0A
        let at = endsWithNewline ? NSMaxRange(paragraph) - 1 : NSMaxRange(paragraph)
        let marker = NSMutableAttributedString(string: "\n", attributes: Styler.attributes(kind: kindOfParagraph(at: paragraph.location)))
        marker.append(NSAttributedString(string: "* * *", attributes: Styler.attributes(kind: BlockKind.sceneBreak)))
        if !endsWithNewline { marker.append(NSAttributedString(string: "\n", attributes: Styler.attributes(kind: BlockKind.sceneBreak))) }
        guard shouldChangeText(in: NSRange(location: at, length: 0), replacementString: marker.string) else { return }
        storage.beginEditing()
        storage.insert(marker, at: at)
        storage.endEditing()
        didChangeText()
        setSelectedRange(NSRange(location: min(at + marker.length + (endsWithNewline ? 1 : 0), storage.length), length: 0))
        typingAttributes = Styler.attributes(kind: BlockKind.body)
    }

    /// Asks for the text of the note, then puts the marker at the cursor.
    @objc func insertFootnote(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L("Footnote")
        alert.informativeText = L("The text of the note (short, one paragraph).")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: L("Insert"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        insertFootnote(text: field.stringValue)
    }

    func insertFootnote(text: String) {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        var attrs = typingAttributes
        attrs[.quillandNote] = NoteBox([Run(text)])
        attrs[.attachment] = nil
        let marker = NSAttributedString(string: AttributedBridge.object, attributes: attrs)
        guard shouldChangeText(in: range, replacementString: marker.string) else { return }
        storage.replaceCharacters(in: range, with: marker)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + 1, length: 0))
    }

    // MARK: Check marks in the menu

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleBold(_:)), #selector(toggleItalic(_:)):
            let key: NSAttributedString.Key = item.action == #selector(toggleBold(_:)) ? .quillandBold : .quillandItalic
            let range = selectedRange()
            item.state = (range.length > 0 ? isEntire(range, styled: key) : typingAttributes[key] as? Bool == true) ? .on : .off
            return true
        case #selector(makeHeading1(_:)), #selector(makeHeading2(_:)), #selector(makeHeading3(_:)), #selector(makeBody(_:)), #selector(makeQuote(_:)):
            let kind = kindOfParagraph(at: selectedRange().location)
            let want: String
            switch item.action {
            case #selector(makeHeading1(_:)): want = BlockKind.heading1
            case #selector(makeHeading2(_:)): want = BlockKind.heading2
            case #selector(makeHeading3(_:)): want = BlockKind.heading3
            case #selector(makeQuote(_:)): want = BlockKind.quote
            default: want = BlockKind.body
            }
            item.state = kind == want ? .on : .off
            return isEditable
        case #selector(insertSceneBreak(_:)), #selector(insertFootnote(_:)):
            return isEditable
        default:
            return super.validateMenuItem(item)
        }
    }
}
