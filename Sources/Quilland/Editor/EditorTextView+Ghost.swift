import AppKit

extension NSAttributedString.Key {
    /// Marks text that is only a suggestion (Continue Writing, Write Synopsis): it is in the view, faint, and in no file until the author accepts it.
    static let ghost = NSAttributedString.Key("QuillandGhost")
}

/// A suggestion the model is writing, shown after the cursor as faint text in any text view. Tab accepts it as one edit that ⌘Z takes back; Esc, a click, or any
/// other key discards it (and stops the request). It never reaches `textDidChange`, so nothing is saved or counted while it is only a suggestion.
final class GhostController {
    unowned let view: NSTextView
    private(set) var range: NSRange?
    private var onEnd: (() -> Void)?
    private var ownSelection: NSRange?
    /// True while the text system moves the selection because of our own edit: that is not the author moving the cursor.
    var settingSelection = false
    /// Told when a suggestion starts (with a way to drop it) and when it is over, so that a document can drop it before saving.
    var onStart: ((@escaping () -> Void) -> Void)?
    var onFinish: (() -> Void)?
    /// A suggestion for a whole field (a synopsis): accepting replaces everything in it, not just adds at the cursor.
    var replacesAll = false

    init(view: NSTextView) { self.view = view }

    var isActive: Bool { range != nil }

    func begin(onEnd: @escaping () -> Void) {
        discard()
        range = NSRange(location: NSMaxRange(view.selectedRange()), length: 0)
        self.onEnd = onEnd
        ownSelection = view.selectedRange()
        onStart?({ [weak self] in self?.discard() })
    }

    /// Adds a piece of the suggestion. Not a change of the text: no undo step, no save.
    func append(_ piece: String) {
        guard var r = range, let storage = view.textStorage, !piece.isEmpty else { return }
        var attributes = view.typingAttributes
        attributes[.foregroundColor] = NSColor.tertiaryLabelColor
        attributes[.ghost] = true
        settingSelection = true
        view.undoManager?.disableUndoRegistration()
        storage.beginEditing()
        storage.insert(NSAttributedString(string: piece, attributes: attributes), at: NSMaxRange(r))
        storage.endEditing()
        view.undoManager?.enableUndoRegistration()
        r.length += piece.utf16.count
        range = r
        if let caret = ownSelection { view.setSelectedRange(NSRange(location: r.location, length: caret.length)) }
        settingSelection = false
        view.scrollRangeToVisible(NSRange(location: NSMaxRange(r), length: 0))
    }

    var text: String {
        guard let r = range, let storage = view.textStorage, NSMaxRange(r) <= storage.length else { return "" }
        return (storage.string as NSString).substring(with: r)
    }

    private func removeFromStorage(_ r: NSRange) {
        guard let storage = view.textStorage, NSMaxRange(r) <= storage.length, r.length > 0 else { return }
        settingSelection = true
        view.undoManager?.disableUndoRegistration()
        storage.beginEditing(); storage.deleteCharacters(in: r); storage.endEditing()
        view.undoManager?.enableUndoRegistration()
        settingSelection = false
    }

    /// Takes the suggestion away without a trace.
    func discard() {
        guard let r = range else { return }
        let end = onEnd
        range = nil; onEnd = nil
        removeFromStorage(r)
        settingSelection = true
        view.setSelectedRange(NSRange(location: min(r.location, view.textStorage?.length ?? 0), length: 0))
        settingSelection = false
        onFinish?()
        end?()
    }

    /// Makes the suggestion real text: one edit, as if it had been typed in one go. Returns whether there was anything.
    @discardableResult
    func accept() -> Bool {
        guard let r = range, r.length > 0 else { discard(); return false }
        let words = text
        let end = onEnd
        range = nil; onEnd = nil
        removeFromStorage(r)
        let at = replacesAll ? NSRange(location: 0, length: view.textStorage?.length ?? 0) : NSRange(location: r.location, length: 0)
        let wanted = replacesAll ? words.trimmingCharacters(in: .whitespacesAndNewlines) : words
        if view.shouldChangeText(in: at, replacementString: wanted) {
            view.replaceCharacters(in: at, with: wanted)
            view.didChangeText()
        }
        view.setSelectedRange(NSRange(location: at.location + wanted.utf16.count, length: 0))
        onFinish?()
        end?()
        return true
    }

    /// What a view does with a key while a suggestion waits: Tab takes it, Esc drops it, anything else drops it and then does its own work.
    /// Returns true when the key was used up here.
    func handle(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if event.keyCode == 48, plain { accept(); return true }
        if event.keyCode == 53 { discard(); return true }
        discard()
        return false
    }
}

extension EditorTextView {
    var hasGhost: Bool { ghost.isActive }
    var ghostText: String { ghost.text }

    /// Starts a suggestion at the cursor.
    func beginGhost(onEnd: @escaping () -> Void) {
        ghost.onStart = { [weak self] drop in self?.document?.discardGhost = drop }
        ghost.onFinish = { [weak self] in self?.document?.discardGhost = nil }
        ghost.begin(onEnd: onEnd)
    }

    func appendGhost(_ piece: String) { ghost.append(piece) }
    func discardGhost() { ghost.discard() }
    @discardableResult func acceptGhost() -> Bool { ghost.accept() }
}

/// A text view for a field the model may suggest text for (a synopsis): the same faint suggestion, accepted with Tab.
final class SuggestTextView: NSTextView {
    lazy var ghost = GhostController(view: self)

    override func keyDown(with event: NSEvent) {
        if ghost.handle(event) { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if ghost.isActive { ghost.discard() }
        super.mouseDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if ghost.isActive { ghost.discard() }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        if ghost.isActive, !ghost.settingSelection { ghost.discard() }
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelectingFlag)
    }
}
