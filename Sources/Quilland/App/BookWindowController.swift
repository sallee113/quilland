import AppKit
import QuillandCore

/// The window of one open book.
final class BookWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let folder: URL
    let main: MainAreaController
    private(set) var bookTitle: String
    private let status = StatusBarView()
    private var stateTimer: Timer?
    /// The window is closing (by the author): the app decides what to show next.
    var onClose: ((BookWindowController) -> Void)?

    init(folder: URL) throws {
        self.folder = folder
        let info = (try? JSONParser.parseObject(Data(contentsOf: folder.appendingPathComponent("book.json")))) ?? [:]
        bookTitle = info.string("title") ?? folder.lastPathComponent
        main = try MainAreaController(folder: folder, state: LocalBookState.load(book: folder))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = bookTitle + Self.titleSeparator + MainAreaController.title(of: main.mode)
        window.representedURL = folder
        window.delegate = self
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.setFrameAutosaveName("QuillandBook")
        if !window.setFrameUsingName("QuillandBook") { window.center() }

        let content = NSView()
        let area = main.view
        for v in [area, status] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            area.topAnchor.constraint(equalTo: content.topAnchor), area.leadingAnchor.constraint(equalTo: content.leadingAnchor), area.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            area.bottomAnchor.constraint(equalTo: status.topAnchor),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor), status.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        main.onCursorMoved = { [weak self] _, _ in self?.scheduleStateSave() }
        main.onChange = { [weak self] in self?.refreshStatus() }
        main.onModeChange = { [weak self] in self?.updateTitle() }
        main.onStateChanged = { [weak self] in self?.scheduleStateSave() }
        main.onAIStatus = { [weak self] text in self?.aiStatus = text; self?.refreshStatus() }
        main.onFocusModeChange = { [weak self] on in self?.focusModeChanged(on) }
        startSnapshotTimer()
        refreshStatus()
    }

    private static let titleSeparator = " — "

    /// The window is titled with the book and the view it shows: `Растительный мир — Characters`.
    func updateTitle() {
        let view = main.inBible ? L("World Bible") + " ▸ " + MainAreaController.title(of: main.mode) : MainAreaController.title(of: main.mode)
        window.title = bookTitle + Self.titleSeparator + view
    }

    /// The book's language code (`ru`, `en`…).
    var language: String {
        ((try? JSONParser.parseObject(Data(contentsOf: folder.appendingPathComponent("book.json"))))?.string("language")) ?? "en"
    }

    func show() { window.makeKeyAndOrderFront(nil) }

    // MARK: Reminders

    private(set) var remindersSheet: NSWindow?
    private(set) var remindersPopup: RemindersPopup?

    /// A book that is just opened shows the reminders not yet done, in a window over it, if the author wants that (Settings ▸ General).
    @discardableResult
    func showRemindersIfAny() -> Bool {
        guard AppPreferences.shared.values.showReminders, remindersSheet == nil, !main.remindersStore.open.isEmpty else { return false }
        let popup = RemindersPopup(store: main.remindersStore)
        let sheet = NSWindow(contentViewController: popup)
        popup.onChange = { [weak self] in self?.main.remindersView?.reload(); self?.refreshStatus() }
        popup.onClose = { [weak self] in self?.closeReminders() }
        remindersSheet = sheet
        remindersPopup = popup
        window.beginSheet(sheet)
        return true
    }

    func closeReminders() {
        guard let sheet = remindersSheet else { return }
        window.endSheet(sheet)
        remindersSheet = nil
        remindersPopup = nil
        main.remindersView?.reload()
        refreshStatus()
    }

    // MARK: Snapshots

    /// Seconds between automatic snapshots (Settings ▸ General: 15 minutes unless the author chose otherwise).
    var snapshotInterval: TimeInterval = TimeInterval(AppPreferences.shared.values.snapshotMinutes * 60)
    private var snapshotTimer: Timer?

    /// (Re)starts the timer from the preferences: off when automatic snapshots are off.
    func startSnapshotTimer() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        let p = AppPreferences.shared.values
        snapshotInterval = TimeInterval(p.snapshotMinutes * 60)
        guard p.autoSnapshots else { return }
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) { [weak self] _ in _ = self?.automaticSnapshot() }
    }

    var snapshotTimerIsRunning: Bool { snapshotTimer?.isValid == true }

    /// A preference changed: the text, the panels and the snapshot timer take it.
    func preferencesChanged() {
        main.preferencesChanged()
        startSnapshotTimer()
    }

    /// Book Settings changed something: the title in the window and the list of books, the language and the dictionary in the text.
    func bookSettingsChanged(settings: AppSettings) {
        let s = BookSettings.load(book: folder)
        bookTitle = s.title
        updateTitle()
        targetCharacters = s.targetCharacters
        settings.noteTitle(folder: folder, name: s.title)
        main.bookSettingsChanged()
    }

    /// An automatic snapshot, if the book changed since the newest one; the old ones are thinned by the rule. Returns whether one was taken.
    @discardableResult
    func automaticSnapshot() -> Bool {
        main.saveAll()
        let store = SnapshotStore(bookFolder: folder)
        guard store.changedSinceLatest() else { return false }
        guard (try? store.take(.automatic, reason: Lp("Every minute", "Every {n} minutes", Int(snapshotInterval / 60)))) != nil else { return false }
        _ = try? store.thin()
        return true
    }

    /// ⌘S (saved) and ⌥⌘S (named: kept for good). The open scenes are saved first.
    @discardableResult
    func saveSnapshot(named name: String? = nil) -> Bool {
        main.saveAll()
        do {
            _ = try SnapshotStore(bookFolder: folder).take(.manual, name: name, reason: name == nil ? L("Saved") : nil)
            main.banner.show(name == nil ? L("Snapshot saved.") : L("Snapshot “{name}” saved.", ["name": name!]), undoable: false)
            return true
        } catch {
            main.banner.show(L("A snapshot could not be taken: {error}", ["error": "\(error)"]), undoable: false)
            return false
        }
    }

    // MARK: Focus Mode

    /// False in the automatic checks, which must not leave the screen.
    var usesFullScreen = true

    /// Focus Mode takes the status bar away and fills the screen; leaving gives them back.
    private func focusModeChanged(_ on: Bool) {
        status.isHidden = on
        status.heightConstraint.constant = on ? 0 : 22
        guard usesFullScreen, window.styleMask.contains(.fullScreen) != on else { return }
        window.toggleFullScreen(nil)
    }

    /// The author left full screen by the system's own way: Focus Mode ends too.
    func windowDidExitFullScreen(_ notification: Notification) { main.setFocusMode(false) }

    // MARK: Status

    /// The size the book should reach (Book Settings), for the status bar.
    private(set) lazy var targetCharacters: Int? = BookSettings.load(book: folder).targetCharacters

    func refreshStatus() {
        let number = { (n: Int) in NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
        var parts: [String] = []
        if main.mode == .plan, let plan = main.planController {
            parts.append(L("Plan: {lines}, {cards}", ["lines": Lp("{n} line", "{n} lines", plan.store.lines.count), "cards": Lp("{n} card", "{n} cards", plan.store.cards.count)]))
        } else if main.mode == .events {
            let n = main.eventStore.events.count
            parts.append(Lp("{n} event", "{n} events", n))
        } else if main.mode == .graph {
            parts.append(main.graphView?.noteText.isEmpty == false ? main.graphView!.noteText : L("Graph"))
        } else if main.mode == .reminders {
            let n = main.remindersStore.open.count
            parts.append(n == 0 ? L("No open reminders") : Lp("{n} open reminder", "{n} open reminders", n))
        } else if main.mode == .research {
            parts.append(Lp("{n} document", "{n} documents", main.researchStore.documents.count))
        } else if main.mode == .world {
            let w = main.worlds.worlds.count, p = main.worlds.entries.count
            parts.append(L("{worlds}, {places}", ["worlds": Lp("{n} world", "{n} worlds", w), "places": Lp("{n} place", "{n} places", p)]))
        } else if main.mode == .characters {
            let n = main.characters.characters.count
            parts.append(Lp("{n} character", "{n} characters", n))
        } else if main.mode == .outline {
            let ids = main.tree?.selectedIDs ?? []
            let total = ids.reduce(0) { $0 + main.sectionCharacters($1) }
            parts.append(ids.isEmpty ? L("Outline") : (ids.count > 1 ? L("{n} sections: {size}", ["n": ids.count, "size": Lp("{n} character||text", "{n} characters||text", total)]) : Lp("{n} character||text", "{n} characters||text", total)))
        } else if let doc = main.currentDocument {
            parts.append(Lp("{n} character||text", "{n} characters||text", doc.counts.characters))
        }
        let total = main.session.totalCharacters
        if let percent = BookKinds.percent(characters: total, target: targetCharacters), let target = targetCharacters {
            parts.append(L("book {size} of {target} ({percent}%)", ["size": number(total), "target": number(target), "percent": percent]))
        } else {
            parts.append(L("book {size}", ["size": number(total)]))
        }
        let today = main.writtenToday
        parts.append(L("today {change}", ["change": (today >= 0 ? "+" : "−") + number(abs(today))]))
        status.leftText = parts.joined(separator: "  ·  ")
        status.trailText = main.historyTrail
        let dirty = main.session.documents.values.contains { $0.isDirty }
        let failed = main.session.documents.values.first { $0.lastSaveError != nil }
        status.rightText = aiStatus ?? (failed != nil ? L("Not saved: {error}", ["error": failed?.lastSaveError ?? ""]) : (dirty ? L("editing…") : L("Saved")))
        status.refreshKeyboard()
    }

    /// What the AI is doing for this book (shown in the status bar instead of "Saved" while it lasts).
    private var aiStatus: String?
    var statusBar: StatusBarView { status }

    // MARK: Where the author left off

    private func scheduleStateSave() {
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in self?.saveState() }
    }

    func saveState() {
        stateTimer?.invalidate()
        main.localState().save(book: folder)
    }

    func save() {
        main.saveAll()
        saveState()
        refreshStatus()
    }

    // MARK: Window

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        save()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        main.stopAI()
        snapshotTimer?.invalidate()
        onClose?(self)
    }
    func windowDidResignKey(_ notification: Notification) { main.saveAll(); refreshStatus() }
}
