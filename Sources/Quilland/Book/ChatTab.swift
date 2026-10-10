import AppKit
import QuillandCore

/// The text box of the chat: Return sends, ⇧↩ is a new line, ↑ in an empty box recalls earlier prompts, and `@` opens the list of what can be attached.
final class ChatInputView: NSTextView {
    var onSend: (() -> Void)?
    var onRecall: ((Bool) -> Void)?
    var onAt: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if (event.keyCode == 36 || event.keyCode == 76), flags.isEmpty { onSend?(); return }
        if (event.keyCode == 36 || event.keyCode == 76), flags == [.shift] { insertNewlineIgnoringFieldEditor(nil); return }
        if string.isEmpty || selectedRange().location == 0 {
            if event.keyCode == 126, flags.isEmpty { onRecall?(true); return }
        }
        if event.keyCode == 125, flags.isEmpty, selectedRange().location == (string as NSString).length { onRecall?(false); return }
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        if (string as? String) == "@" { DispatchQueue.main.async { [weak self] in self?.onAt?() } }
    }
}

/// Chips in rows that wrap: the things attached to the next message, each with its size and a ✕.
final class ChipsView: NSView {
    override var isFlipped: Bool { true }
    var chips: [NSView] = [] { didSet { oldValue.forEach { $0.removeFromSuperview() }; chips.forEach(addSubview); needsLayout = true; invalidateIntrinsicContentSize() } }
    private let gap: CGFloat = 6

    private func layoutChips(width: CGFloat) -> CGFloat {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for chip in chips {
            let size = chip.fittingSize
            if x > 0, x + size.width > width { x = 0; y += rowHeight + gap; rowHeight = 0 }
            chip.frame = NSRect(x: x, y: y, width: min(size.width, width), height: size.height)
            x += size.width + gap
            rowHeight = max(rowHeight, size.height)
        }
        return chips.isEmpty ? 0 : y + rowHeight
    }

    override func layout() { super.layout(); _ = layoutChips(width: bounds.width) }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: layoutChips(width: max(bounds.width, 200))) }
    override func resizeSubviews(withOldSize oldSize: NSSize) { super.resizeSubviews(withOldSize: oldSize); invalidateIntrinsicContentSize() }
}

/// The Chat tab of the right panel.
final class ChatTab: NSView, NSTextViewDelegate {
    var session: ChatSession? { didSet { session?.onChange = { [weak self] in self?.refresh() }; refresh() } }
    var mentionsMenu: (() -> NSMenu)?
    var onSaveAnswer: (() -> Void)?
    var onSaveAction: (() -> Void)?
    private let transcript = NSTextView()
    let input = ChatInputView()
    private let chips = ChipsView()
    private let usageLabel = NSTextField(labelWithString: "")
    private let attachButton = NSButton(title: "@", target: nil, action: nil)
    private let sendButton = NSButton(title: L("Send"), target: nil, action: nil)
    private let stopButton = NSButton(title: L("Stop"), target: nil, action: nil)
    private let copyButton = NSButton(title: L("Copy"), target: nil, action: nil)
    private let saveButton = NSButton(title: L("Save as a Note…"), target: nil, action: nil)
    private let actionButton = NSButton(title: L("Save Prompt as Action…"), target: nil, action: nil)
    private let newButton = NSButton(title: L("New Conversation"), target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        transcript.isEditable = false; transcript.isRichText = true
        transcript.textContainerInset = NSSize(width: 6, height: 6)
        transcript.drawsBackground = false
        transcript.isVerticallyResizable = true; transcript.autoresizingMask = [.width]
        transcript.setAccessibilityLabel(L("Conversation"))
        let transcriptScroll = NSScrollView()
        transcriptScroll.documentView = transcript
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.borderType = .bezelBorder
        input.isRichText = false; input.allowsUndo = true
        input.font = .systemFont(ofSize: 13)
        input.textContainerInset = NSSize(width: 4, height: 4)
        input.isVerticallyResizable = true; input.autoresizingMask = [.width]
        input.delegate = self
        input.setAccessibilityLabel(L("Message"))
        input.onSend = { [weak self] in self?.send() }
        input.onRecall = { [weak self] older in self?.recall(older: older) }
        input.onAt = { [weak self] in self?.showMentions(afterTyping: true) }
        let inputScroll = NSScrollView()
        inputScroll.documentView = input
        inputScroll.hasVerticalScroller = true
        inputScroll.borderType = .bezelBorder
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
        usageLabel.font = .systemFont(ofSize: 11)
        usageLabel.textColor = .secondaryLabelColor
        for b in [attachButton, sendButton, stopButton, copyButton, saveButton, actionButton, newButton] { b.bezelStyle = .rounded; b.controlSize = .small; b.target = self }
        attachButton.action = #selector(attachPressed); sendButton.action = #selector(sendPressed); stopButton.action = #selector(stopPressed)
        copyButton.action = #selector(copyPressed); saveButton.action = #selector(savePressed); newButton.action = #selector(newPressed); actionButton.action = #selector(actionPressed)
        actionButton.toolTip = L("Keeps your last question, with what was attached, in the AI menu to use again")
        attachButton.toolTip = L("Attach part of the book to your messages (or type @)")
        sendButton.keyEquivalent = ""
        let buttons = NSStackView(views: [attachButton, sendButton, stopButton])
        buttons.spacing = 6
        let answerButtons = NSStackView(views: [copyButton, saveButton, newButton])
        answerButtons.spacing = 6
        let stack = NSStackView(views: [transcriptScroll, answerButtons, actionButton, chips, usageLabel, inputScroll, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            transcriptScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), inputScroll.widthAnchor.constraint(equalTo: stack.widthAnchor), chips.widthAnchor.constraint(equalTo: stack.widthAnchor),
            transcriptScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Showing

    func refresh() {
        guard let session else { return }
        let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        let out = NSMutableAttributedString()
        func add(_ who: String, _ text: String) {
            if out.length > 0 { out.append(NSAttributedString(string: "\n\n", attributes: body)) }
            out.append(NSAttributedString(string: who + "\n", attributes: bold))
            out.append(NSAttributedString(string: text, attributes: body))
        }
        for t in session.turns { add(t.role == "user" ? L("You") : L("AI"), t.content) }
        if let partial = session.streaming { add(L("AI"), partial.isEmpty ? "…" : partial) }
        if let error = session.error { add(L("Problem"), error) }
        if out.length == 0 { out.append(NSAttributedString(string: L("Ask about your book. Attach the scene, characters, places or the plan with @ so that the model can see them. It only answers: it changes nothing."), attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])) }
        let atBottom = transcript.enclosingScrollView.map { $0.contentView.bounds.maxY >= transcript.frame.height - 30 } ?? true
        transcript.textStorage?.setAttributedString(out)
        if atBottom || session.running { transcript.scrollToEndOfDocument(nil) }

        let usage = session.usage
        chips.chips = session.attachments.map { a in chip(a, tokens: usage.perAttachment[a.id] ?? a.tokens) }
        let number = { (n: Int) in NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
        usageLabel.stringValue = L("Context {tokens} / {context} tokens", ["tokens": number(usage.tokens), "context": number(usage.context)]) + (usage.truncated ? "  ·  " + L("some of it is cut to fit") : "")
        usageLabel.textColor = usage.truncated || Double(usage.tokens) > Double(usage.context) * 0.8 ? .systemOrange : .secondaryLabelColor
        let ready = AIService.shared.isReady
        sendButton.isEnabled = ready && !session.running
        stopButton.isHidden = !session.running
        copyButton.isEnabled = session.lastAnswer != nil
        saveButton.isEnabled = session.lastAnswer != nil && !session.running
        newButton.isEnabled = !session.turns.isEmpty && !session.running
        actionButton.isEnabled = session.turns.contains { $0.role == "user" }
        input.toolTip = ready ? nil : AIService.shared.unavailableReason
    }

    private func chip(_ a: ChatAttachment, tokens: Int) -> NSView {
        let number = NumberFormatter.localizedString(from: NSNumber(value: tokens), number: .decimal)
        let button = NSButton(title: "\(a.label) · \(number) ✕", target: self, action: #selector(chipPressed(_:)))
        button.bezelStyle = .inline
        button.controlSize = .small
        button.identifier = NSUserInterfaceItemIdentifier(a.id.uuidString)
        button.toolTip = L("Click to take it off")
        return button
    }

    @objc private func chipPressed(_ sender: NSButton) {
        if let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) { session?.remove(id) }
    }

    // MARK: Actions

    @objc private func sendPressed() { send() }

    func send() {
        let text = input.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session?.send(text)
        input.string = ""
    }

    @objc private func stopPressed() { session?.stop() }
    @objc private func newPressed() { session?.newConversation() }

    @objc private func copyPressed() {
        guard let text = session?.lastAnswer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func savePressed() { onSaveAnswer?() }
    @objc private func actionPressed() { onSaveAction?() }

    private func recall(older: Bool) {
        guard let text = session?.recall(older: older) else { return }
        input.string = text
        input.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    @objc private func attachPressed() { showMentions(afterTyping: false) }

    /// The list of what can be attached. After a typed `@` the picked item replaces that character.
    private func showMentions(afterTyping: Bool) {
        guard let menu = mentionsMenu?() else { return }
        let at = NSPoint(x: 0, y: attachButton.bounds.height + 2)
        if afterTyping, let caret = input.caretPoint() {
            menu.popUp(positioning: nil, at: caret, in: input)
        } else {
            menu.popUp(positioning: nil, at: at, in: attachButton)
        }
        // A typed @ that was not used stays; one that was used goes.
        if afterTyping, session?.mentionPicked == true { removeTypedAt(); session?.mentionPicked = false }
    }

    private func removeTypedAt() {
        let ns = input.string as NSString
        let r = input.selectedRange()
        if r.location > 0, r.location <= ns.length, ns.substring(with: NSRange(location: r.location - 1, length: 1)) == "@" {
            input.replaceCharacters(in: NSRange(location: r.location - 1, length: 1), with: "")
        }
    }
}

extension NSTextView {
    /// The insertion point as a point in this view (for a menu that opens at the cursor).
    func caretPoint() -> NSPoint? {
        guard let layout = textLayoutManager, let content = layout.textContentManager, let loc = content.location(content.documentRange.location, offsetBy: min(selectedRange().location, (string as NSString).length)) else { return nil }
        layout.ensureLayout(for: NSTextRange(location: loc))
        guard let fragment = layout.textLayoutFragment(for: loc) else { return nil }
        let frame = fragment.layoutFragmentFrame
        return NSPoint(x: textContainerInset.width + frame.minX + 10, y: textContainerInset.height + frame.maxY + 2)
    }
}
