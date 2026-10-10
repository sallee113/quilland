import AppKit
import QuillandCore

/// Book mode: the scenes of a book as sheets in one scroll. The author is always in one scene (where the cursor is); the others are only shown.
final class BookViewController: NSViewController, NSTextViewDelegate, SceneNavigationDelegate {
    let session: BookSession
    let scrollView = NSScrollView()
    let stack = BookStackView()
    /// Typewriter scrolling: the line with the cursor stays in the middle of the screen.
    private(set) var typewriter = false
    private(set) var currentSceneID: String?
    /// Panels mode shows one scene at a time: its id; nil shows the whole book.
    private(set) var onlyScene: String?
    var onCurrentSceneChange: ((SceneDocument) -> Void)?
    var onActivity: (() -> Void)?
    /// A title was typed or a status chosen in a scene's header.
    var onRename: ((String, String) -> Void)?
    var onStatus: ((String, String) -> Void)?
    /// The cursor moved (by keys, typing or a click): the scene and the place in it.
    var onSelectionChange: ((SceneDocument, Int) -> Void)?

    init(session: BookSession, only: String? = nil) {
        self.session = session
        onlyScene = only
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Book and Compare have a jump bar at the top; the single scene of Panels does not (it has the tree).
    let jumpBar = JumpBarView()
    private var popover: NSPopover?
    /// Focus Mode: the jump bar goes, the headers and bands between the sheets become faint.
    var focusChrome = false { didSet { applyFocusChrome() } }
    /// Esc in the text: return true when it was used.
    var escapeHandler: (() -> Bool)?

    private func applyFocusChrome() {
        jumpBar.heightConstraint.constant = focusChrome ? 0 : 30
        jumpBar.isHidden = focusChrome
        for row in stack.rows {
            switch row {
            case .sheet: break
            default: row.view.alphaValue = focusChrome ? 0.25 : 1
            }
        }
    }

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.documentView = stack
        stack.autoresizingMask = []
        stack.sheetWidth = CGFloat(AppPreferences.shared.values.readingWidth)
        stack.frame = NSRect(x: 0, y: 0, width: 900, height: 1000)
        if onlyScene == nil {
            let container = NSView()
            for v in [jumpBar, scrollView] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
            NSLayoutConstraint.activate([
                jumpBar.topAnchor.constraint(equalTo: container.topAnchor), jumpBar.leadingAnchor.constraint(equalTo: container.leadingAnchor), jumpBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: jumpBar.bottomAnchor), scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
            view = container
            jumpBar.path.target = self; jumpBar.path.action = #selector(openJumpList)
            jumpBar.previous.target = self; jumpBar.previous.action = #selector(previousScene)
            jumpBar.next.target = self; jumpBar.next.action = #selector(nextScene)
        } else {
            view = scrollView
        }
        buildRows()
        updateJumpBar()
        NotificationCenter.default.addObserver(self, selector: #selector(clipResized), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsFrameChangedNotifications = true
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Building

    func buildRows() {
        var rows: [BookStackView.Row] = []
        var part: String?
        var chapter: String?
        for entry in session.structure.scenes {
            guard let document = session.document(entry.id) else { continue }
            if let only = onlyScene {
                guard entry.id == only else { continue }
            } else if let partID = entry.partID, partID != part {
                rows.append(.band(BandView(title: entry.partTitle ?? "", level: 1)))
                part = partID
            }
            if onlyScene == nil, let chapterID = entry.chapterID, chapterID != chapter {
                rows.append(.band(BandView(title: entry.chapterTitle ?? "", level: 2)))
                chapter = chapterID
            }
            let header = SceneHeaderView(document: document)
            header.onRename = { [weak self] id, title in self?.onRename?(id, title) }
            header.onStatus = { [weak self] id, status in self?.onStatus?(id, status) }
            header.onFinishedRenaming = { [weak self] in
                // The keyboard goes back to the scene's text, where the cursor was.
                guard let self, let sheet = self.stack.sheets.first(where: { $0.document.id == document.id }) else { return }
                self.view.window?.makeFirstResponder(sheet.textView)
            }
            rows.append(.header(header))
            let sheet = SheetView(document: document, width: stack.sheetWidth)
            sheet.textView.delegate = self
            sheet.textView.navigation = self
            sheet.textView.onEscape = { [weak self] in self?.escapeHandler?() ?? false }
            sheet.onHeightChange = { [weak self] in
                self?.stack.arrange()
                self?.onActivity?()
            }
            rows.append(.sheet(sheet))
        }
        stack.setRows(rows)
        stack.arrange()
        if focusChrome { applyFocusChrome() }
    }

    /// Panels: shows this scene alone, from its top.
    func show(only sceneID: String) {
        guard onlyScene != sceneID else { return }
        onlyScene = sceneID
        currentSceneID = nil
        buildRows()
        scrollView.contentView.setBoundsOrigin(.zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// A preference changed: the sheets take the reading width, and the rows are measured again for the font.
    func preferencesChanged() {
        stack.sheetWidth = CGFloat(AppPreferences.shared.values.readingWidth)
        fitStackToClip()
        for sheet in stack.sheets { sheet.measure() }
        stack.arrange()
    }

    @objc private func clipResized() { fitStackToClip() }

    override func viewDidLayout() {
        super.viewDidLayout()
        fitStackToClip()
    }

    /// The stack is as wide as the visible area; the sheets are centred in it.
    private func fitStackToClip() {
        let width = scrollView.contentView.bounds.width
        if abs(stack.frame.width - width) > 0.5 { stack.frame.size.width = width }
        if typewriter { applyTypewriterInsets() } else { stack.arrange() }
    }

    // MARK: Typewriter

    func setTypewriter(_ on: Bool) {
        typewriter = on
        applyTypewriterInsets()
        if on, let sheet = currentSheet { centerCaret(of: sheet.textView, animated: false) }
    }

    private func applyTypewriterInsets() {
        let half = scrollView.contentView.bounds.height / 2
        stack.topInset = typewriter ? max(40, half) : 40
        stack.bottomInset = typewriter ? max(40, half) : 40
        stack.arrange()
    }

    var currentSheet: SheetView? { stack.sheets.first { $0.document.id == currentSceneID } }

    /// Scrolls so that the cursor's line is in the middle of the visible area.
    func centerCaret(of textView: EditorTextView, animated: Bool) {
        guard let caret = textView.caretRect() else { return }
        let stackRect = stack.convert(caret, from: textView)
        let clip = scrollView.contentView
        let maxY = max(0, stack.frame.height - clip.bounds.height)
        let target = min(max(0, stackRect.midY - clip.bounds.height / 2), maxY)
        guard abs(clip.bounds.origin.y - target) >= 1 else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                clip.animator().setBoundsOrigin(NSPoint(x: 0, y: target))
            }
        } else {
            clip.setBoundsOrigin(NSPoint(x: 0, y: target))
        }
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Keeping the cursor in sight

    /// Without typewriter scrolling: when the cursor moves out of the visible area (down the page, or up), the view follows it by the least it must,
    /// leaving some room below or above the line. (A text view inside a stack does not scroll the stack by itself.)
    func keepCaretVisible(of textView: EditorTextView) {
        guard let caret = textView.caretRect() else { return }
        let rect = stack.convert(caret, from: textView)
        let clip = scrollView.contentView
        let visible = clip.bounds
        let margin: CGFloat = min(90, visible.height / 4)
        var target = visible.origin.y
        if rect.maxY > visible.maxY - margin { target = rect.maxY + margin - visible.height }
        else if rect.minY < visible.minY + margin { target = rect.minY - margin }
        target = min(max(0, target), max(0, stack.frame.height - visible.height))
        guard abs(target - visible.origin.y) >= 1 else { return }
        clip.setBoundsOrigin(NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: The jump bar

    /// The path of the current scene on the bar, and the arrows that can still go somewhere.
    func updateJumpBar() {
        guard onlyScene == nil else { return }
        let scenes = session.structure.scenes
        let index = scenes.firstIndex { $0.id == currentSceneID }
        if let index {
            let e = scenes[index]
            let parts = [e.partTitle, e.chapterTitle, e.node.title].compactMap { $0 }.filter { !$0.isEmpty }
            jumpBar.path.title = parts.joined(separator: " › ") + " ▾"
        } else {
            jumpBar.path.title = L("Jump to a scene ▾")
        }
        jumpBar.previous.isEnabled = (index ?? 0) > 0
        jumpBar.next.isEnabled = index.map { $0 < scenes.count - 1 } ?? !scenes.isEmpty
    }

    @objc func openJumpList() {
        guard onlyScene == nil else { return }
        popover?.close()
        let list = JumpListController(structure: session.structure, characters: { [session] in session.document($0)?.counts.characters ?? 0 })
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = list
        list.onChoose = { [weak self] id in
            self?.closeJumpList()
            self?.jump(to: id)
        }
        list.onClose = { [weak self] in self?.closeJumpList() }
        popover = pop
        pop.show(relativeTo: jumpBar.path.bounds, of: jumpBar.path, preferredEdge: .maxY)
        list.select(currentSceneID)
    }

    var isJumpListOpen: Bool { popover?.isShown == true }

    func closeJumpList() {
        popover?.close()
        popover = nil
    }

    @objc private func previousScene() { step(-1) }
    @objc private func nextScene() { step(1) }

    private func step(_ by: Int) {
        let scenes = session.structure.scenes
        let index = scenes.firstIndex { $0.id == currentSceneID } ?? (by > 0 ? -1 : scenes.count)
        let target = index + by
        guard scenes.indices.contains(target) else { return }
        jump(to: scenes[target].id)
    }

    /// Goes to a scene: the cursor at its start, the scene in view at the top (or its first line in the middle with typewriter scrolling).
    func jump(to sceneID: String) {
        guard let sheet = stack.sheets.first(where: { $0.document.id == sceneID }) else { return }
        focus(sceneID: sceneID)
        if typewriter { centerCaret(of: sheet.textView, animated: false) } else { reveal(sheet) }
    }

    /// Scrolls so that the sheet's top is near the top of the visible area, its header above it showing.
    private func reveal(_ sheet: SheetView) {
        let clip = scrollView.contentView
        let target = min(max(0, sheet.frame.minY - 40), max(0, stack.frame.height - clip.bounds.height))
        clip.setBoundsOrigin(NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: The cursor

    /// Brings the cursor into view, in the middle with typewriter scrolling, otherwise with the room around it.
    func scrollToCursor() {
        guard let tv = currentSheet?.textView else { return }
        if typewriter { centerCaret(of: tv, animated: false) } else { centerCaretOnce(of: tv) }
    }

    /// Opening a book: the cursor's line is put in the middle of the screen, as the spec says.
    private func centerCaretOnce(of textView: EditorTextView) {
        guard let caret = textView.caretRect() else { return }
        let rect = stack.convert(caret, from: textView)
        let clip = scrollView.contentView
        let target = min(max(0, rect.midY - clip.bounds.height / 2), max(0, stack.frame.height - clip.bounds.height))
        clip.setBoundsOrigin(NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Makes a scene the current one without moving the keyboard focus (Panels: the author is in the tree).
    func select(sceneID: String) {
        guard let sheet = stack.sheets.first(where: { $0.document.id == sceneID }) else { return }
        currentSceneID = sceneID
        onCurrentSceneChange?(sheet.document)
        onSelectionChange?(sheet.document, sheet.textView.selectedRange().location)
    }

    func focus(sceneID: String, atEnd: Bool = false) {
        guard let sheet = stack.sheets.first(where: { $0.document.id == sceneID }) else { return }
        view.window?.makeFirstResponder(sheet.textView)
        sheet.textView.setSelectedRange(NSRange(location: atEnd ? sheet.textView.textStorage?.length ?? 0 : 0, length: 0))
        sheet.textView.scrollRangeToVisible(sheet.textView.selectedRange())
        // Setting the selection to what it already is (an empty scene) tells the delegate nothing, so the scene is made current here.
        if currentSceneID != sceneID {
            currentSceneID = sceneID
            onCurrentSceneChange?(sheet.document)
            onSelectionChange?(sheet.document, sheet.textView.selectedRange().location)
            updateJumpBar()
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? EditorTextView, textView.window?.firstResponder === textView,
              let sheet = stack.sheets.first(where: { $0.textView === textView }) else { return }
        if currentSceneID != sheet.document.id {
            currentSceneID = sheet.document.id
            onCurrentSceneChange?(sheet.document)
            updateJumpBar()
        }
        onSelectionChange?(sheet.document, textView.selectedRange().location)
        // A click must not make the text jump; typing and the arrow keys move the view.
        if let type = NSApp.currentEvent?.type, [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown].contains(type) { return }
        if typewriter { centerCaret(of: textView, animated: true) } else { keepCaretVisible(of: textView) }
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? EditorTextView, let sheet = stack.sheets.first(where: { $0.textView === textView }) else { return }
        sheet.document.textDidChange()
        if !typewriter { keepCaretVisible(of: textView) }
        onActivity?()
    }

    // MARK: Walking from scene to scene

    func editor(_ editor: EditorTextView, moveTo direction: SceneDirection, x: CGFloat?) -> Bool {
        let sheets = stack.sheets
        guard let index = sheets.firstIndex(where: { $0.textView === editor }) else { return false }
        let target = direction == .next ? index + 1 : index - 1
        guard sheets.indices.contains(target) else { return false }
        sheets[target].textView.placeCaret(atTop: direction == .next, windowX: x)
        return true
    }
}
