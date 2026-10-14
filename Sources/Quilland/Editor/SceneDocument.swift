import AppKit
import QuillandCore

extension Notification.Name {
    /// A scene's file had been changed by another program since it was read; the other version was kept (object: the document, `copy`: where it is).
    static let sceneExternalConflict = Notification.Name("QuillandSceneExternalConflict")
}

protocol SceneDocumentObserver: AnyObject {
    /// The text, the counts or the saved state changed.
    func sceneDocumentDidChange(_ document: SceneDocument)
}

/// One scene's text, held once however many views show it: a Book-mode sheet and a second area of Compare are two views of the same text.
/// It reads the scene's Markdown, keeps the text styled, and saves it (atomically) shortly after the last key.
final class SceneDocument: NSObject, NSTextStorageDelegate {
    let id: String
    var title: String
    var status: String?
    let url: URL
    let contentStorage = NSTextContentStorage()
    var storage: NSTextStorage { contentStorage.textStorage! }

    private(set) var counts = TextCounts()
    private(set) var isDirty = false
    private(set) var saveCount = 0
    private(set) var lastSaveError: String?
    /// How the scene's file looked when it was read or written last (changed time and size): a different one means another program changed it.
    private var knownStamp: String?
    var autosaveDelay: TimeInterval = 0.8
    /// For tests: do not wait for the timers.
    var timersEnabled = true

    private var isStyling = false
    private var layoutPending = false
    private var saveTimer: Timer?
    private var countTimer: Timer?
    private var attachmentTimer: Timer?
    private let observers = NSHashTable<AnyObject>.weakObjects()
    /// Every view of this text (a sheet, a second area in Compare), so that a setting can reach them all.
    private let views = NSHashTable<EditorTextView>.weakObjects()
    /// The book's language (`ru`, `en`…): the typing corrections choose their quotes by it.
    var language = "ru"

    init(id: String, title: String, status: String?, url: URL) {
        self.id = id
        self.title = title
        self.status = status
        self.url = url
        super.init()
        contentStorage.textStorage = NSTextStorage()
        storage.delegate = self
        load()
    }

    func addObserver(_ observer: SceneDocumentObserver) { observers.add(observer) }
    func removeObserver(_ observer: SceneDocumentObserver) { observers.remove(observer) }
    /// The title or status was changed from outside (the tree): the views that show them are told.
    func updateInfo(title: String? = nil, status: String? = nil) {
        if let title { self.title = title }
        if let status { self.status = status }
        notify()
    }
    private func notify() { for case let o as SceneDocumentObserver in observers.allObjects { o.sceneDocumentDidChange(self) } }

    // MARK: Loading

    func load() {
        let markdown = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let attributed = NSMutableAttributedString(attributedString: AttributedBridge.attributedString(from: MarkdownParser.parse(markdown)))
        isStyling = true
        storage.setAttributedString(attributed)
        Styler.style(storage, range: NSRange(location: 0, length: storage.length))
        Attachments.refresh(storage)
        isStyling = false
        counts = TextStats.count(AttributedBridge.document(from: storage))
        isDirty = false
        knownStamp = Self.stamp(of: url)
    }

    private static func stamp(of url: URL) -> String? {
        // (Not `URL.resourceValues`: a URL keeps the values it read first, and would not see a change.)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let date = attributes[.modificationDate] as? Date else { return nil }
        return "\(date.timeIntervalSince1970)/\((attributes[.size] as? NSNumber)?.intValue ?? 0)"
    }

    /// Another program changed the file (a Git checkout, a synchronised folder, another editor) since it was read: its version is copied into the book's trash folder
    /// before this one is written over it, so that nothing is lost either way. Returns where the copy is.
    private static func keepOtherVersion(of url: URL) -> URL? {
        var root = url.deletingLastPathComponent()
        while root.path != "/", !FileManager.default.fileExists(atPath: root.appendingPathComponent("book.json").path) { root = root.deletingLastPathComponent() }
        guard root.path != "/" else { return nil }
        let folder = root.appendingPathComponent(".quilland/trash/\(TrashFolder.newName())/conflicts")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        } catch { return nil }
    }

    // MARK: Keeping the text valid

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard !isStyling, editedMask.contains(.editedCharacters), textStorage.length > 0 else { return }
        isStyling = true
        let start = min(editedRange.location, textStorage.length)
        let range = NSRange(location: start, length: min(editedRange.length, textStorage.length - start))
        let paragraphs = (textStorage.string as NSString).paragraphRange(for: range)
        let string = textStorage.string as NSString
        // Text typed next to a footnote marker or a fragment boundary must not inherit what makes it one.
        for key in [NSAttributedString.Key.quillandNote, .quillandFragment, .attachment, .toolTip] {
            textStorage.enumerateAttribute(key, in: paragraphs, options: []) { value, run, _ in
                guard value != nil else { return }
                var index = run.location
                while index < NSMaxRange(run) {
                    if string.character(at: index) != 0xFFFC { textStorage.removeAttribute(key, range: NSRange(location: index, length: 1)) }
                    index += 1
                }
            }
        }
        Styler.style(textStorage, range: paragraphs)
        isStyling = false
        // Text that is not final yet (dictation, an input method) never reaches `textDidChange`, but it takes room: the views that show
        // this text measure it again as soon as the edit is over (not inside it, where the layout is not settled).
        if !layoutPending {
            layoutPending = true
            DispatchQueue.main.async { [weak self] in
                self?.layoutPending = false
                self?.notify()
            }
        }
    }

    /// Called by a view after the author changed the text.
    func textDidChange() {
        isDirty = true
        if timersEnabled {
            schedule(&saveTimer, after: autosaveDelay) { [weak self] in self?.saveNow() }
            schedule(&countTimer, after: 0.3) { [weak self] in self?.updateCounts() }
            schedule(&attachmentTimer, after: 0.25) { [weak self] in
                guard let self else { return }
                self.isStyling = true
                Attachments.refresh(self.storage)
                self.isStyling = false
            }
        }
        notify()
    }

    private func schedule(_ timer: inout Timer?, after seconds: TimeInterval, _ block: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in block() }
    }

    /// Set while a suggestion is shown in a view of this text: it takes the suggestion away (before saving or counting, which must not see it).
    var discardGhost: (() -> Void)?

    func updateCounts() {
        discardGhost?()
        counts = TextStats.count(AttributedBridge.document(from: storage))
        notify()
    }

    // MARK: Saving

    @discardableResult
    func saveNow() -> Bool {
        saveTimer?.invalidate()
        discardGhost?()
        let (markdown, _) = MarkdownWriter.writeWithReport(AttributedBridge.document(from: storage))
        var otherVersion: URL?
        if let known = knownStamp, let now = Self.stamp(of: url), now != known { otherVersion = Self.keepOtherVersion(of: url) }
        do {
            try AtomicFile.write(Data(markdown.utf8), to: url)
            knownStamp = Self.stamp(of: url)
            if let otherVersion { NotificationCenter.default.post(name: .sceneExternalConflict, object: self, userInfo: ["copy": otherVersion]) }
            isDirty = false
            saveCount += 1
            lastSaveError = nil
            notify()
            return true
        } catch {
            lastSaveError = "\(error)"
            notify()
            return false
        }
    }

    // MARK: Views

    /// A view of this text, as wide as a sheet. Several views may be made; they share the text.
    func makeTextView(width: CGFloat) -> EditorTextView {
        let layout = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: Self.containerWidth(forSheet: width), height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.textContainer = container
        contentStorage.addTextLayoutManager(layout)
        let view = EditorTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100), textContainer: container)
        view.document = self
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.isRichText = true
        view.allowsUndo = true
        view.importsGraphics = false
        view.allowsImageEditing = false
        view.drawsBackground = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.smartInsertDeleteEnabled = true
        view.textContainerInset = NSSize(width: Self.sideInset, height: 30)
        view.font = Fonts.base(size: Fonts.baseSize)
        view.typingAttributes = Styler.attributes(kind: BlockKind.body)
        view.documentLanguage = { [weak self] in self?.language ?? "ru" }
        views.add(view)
        applyWritingPreferences(to: view)
        return view
    }

    /// The system's own quote and dash substitution is off: the app's typing corrections (`Autocorrect`) do that work by the book's language.
    func applyWritingPreferences(to view: EditorTextView) {
        let p = AppPreferences.shared.values
        view.isContinuousSpellCheckingEnabled = p.checkSpelling
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = p.systemTextReplacement
        view.setIgnoredWords(dictionaryWords)
    }

    /// The words of the book's dictionary: the spell checker accepts them in every view of this text.
    var dictionaryWords: [String] = [] {
        didSet { for v in views.allObjects { v.setIgnoredWords(dictionaryWords) } }
    }

    /// A setting changed: the views take it, and the text is drawn again with the font and spacing now chosen.
    func preferencesChanged() {
        for v in views.allObjects { applyWritingPreferences(to: v) }
        isStyling = true
        Styler.style(storage, range: NSRange(location: 0, length: storage.length))
        isStyling = false
        for v in views.allObjects {
            v.font = Fonts.base(size: Fonts.baseSize)
            v.typingAttributes = Styler.attributes(kind: BlockKind.body)
            v.needsDisplay = true
        }
        notify()
    }

    static let sideInset: CGFloat = 34

    /// The text is laid out in the sheet's width less the margin on each side (the view puts its container inside the inset).
    static func containerWidth(forSheet width: CGFloat) -> CGFloat { max(40, width - 2 * sideInset) }

    /// The height a view needs for the whole text.
    static func neededHeight(of view: EditorTextView) -> CGFloat {
        guard let layout = view.textLayoutManager else { return 100 }
        layout.ensureLayout(for: layout.documentRange)
        return ceil(layout.usageBoundsForTextContainer.height) + view.textContainerInset.height * 2
    }
}
