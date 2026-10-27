import AppKit
import QuillandCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    let settings: AppSettings
    let welcome = WelcomeWindowController()
    private(set) var bookWindows: [BookWindowController] = []
    private var newBook: NewBookWindowController?
    /// Where New Book and Import make their books (the Documents folder; the automatic checks use a temporary one).
    var booksParent: URL {
        get { overriddenBooksParent ?? AppPreferences.shared.values.newBookFolder.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
        set { overriddenBooksParent = newValue }
    }
    private var overriddenBooksParent: URL?
    private var exportWindows: [String: ExportWindowController] = [:]
    private var snapshotWindows: [String: SnapshotsWindowController] = [:]
    private var bookSettingsWindows: [String: BookSettingsWindowController] = [:]
    private(set) var settingsWindow: SettingsWindowController?
    var bookSettingsWindowCount: Int { bookSettingsWindows.count }
    func bookSettingsController(for folder: URL) -> BookSettingsWindowController? { bookSettingsWindows[folder.standardizedFileURL.path] }
    var snapshotWindowCount: Int { snapshotWindows.count }
    var exportWindowCount: Int { exportWindows.count }
    private(set) var importWindow: ImportWindowController?
    private lazy var lab = LabWindowController()
    private var terminating = false
    private var newBookItem: NSMenuItem?
    private var recentMenu = NSMenu(title: "")

    override init() {
        let dir = ProcessInfo.processInfo.environment["QUILLAND_SETTINGS_DIR"].map { URL(fileURLWithPath: $0) } ?? AppSettings.standardDirectory
        settings = AppSettings(directory: dir)
        AppPreferences.shared.load(settings: settings)
        super.init()
        shownLanguage = Localizer.shared.current?.code ?? "en"
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: .quillandPreferencesChanged, object: nil)
        welcome.onNewBook = { [weak self] in self?.showNewBook() }
        welcome.onOpenBook = { [weak self] in self?.chooseBook() }
        welcome.onOpenRecent = { [weak self] url in _ = self?.openBook(at: url) }
        welcome.onImport = { [weak self] in self?.showImport() }
    }

    /// A preference changed in the Settings window: the appearance, every open book's text and panels, and the timers take it.
    @objc private func preferencesChanged() {
        applyAppearance()
        bookWindows.forEach { $0.preferencesChanged() }
        // A new language: the menus are made again at once; the Settings window is opened again in it. Other windows that are open keep
        // their texts until they are opened again.
        // Other shortcuts: the menus are made again.
        if AppPreferences.shared.values.shortcuts != shownShortcuts { buildMenu() }
        let language = Localizer.shared.current?.code ?? "en"
        if language != shownLanguage {
            shownLanguage = language
            buildMenu()
            if let open = settingsWindow {
                let section = open.current
                // Not at once: the change comes from a control of that very window.
                DispatchQueue.main.async { [weak self] in
                    open.window.close()
                    self?.showSettings()
                    self?.settingsWindow?.select(section)
                }
            }
        }
    }
    private var shownLanguage = Localizer.shared.current?.code ?? "en"

    func applyAppearance() {
        switch AppPreferences.shared.values.appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    /// What the application listens to (see `subscribe(to:)`).
    private var subscriptions: [Subscription] = []

    /// Back in the application: if the model was not there when it was last asked (LM Studio is started after Quilland, often), ask again.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--selftest-app"), !CommandLine.arguments.contains("--selftest-lab") else { return }
        recheckAIIfNeeded()
    }

    /// Asks the model server again when the actions cannot run (and it is not being asked already).
    func recheckAIIfNeeded() {
        let ai = AIService.shared
        if ai.isEnabled, !ai.isReady, !ai.checking { ai.refresh() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        Hover.installForAllButtons()
        buildMenu()
        subscriptions.append(subscribe(to: .aiStatusChanged) { [weak self] in self?.updateAIStatusItem(); self?.settingsWindow?.refreshAll() })
        // Ask LM Studio once at the start, so that the actions know whether they can run (the checks do not).
        if !CommandLine.arguments.contains("--selftest-app") && !CommandLine.arguments.contains("--selftest-lab") { AIService.shared.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--selftest-lab") { lab.show(); return }
        if CommandLine.arguments.contains("--selftest-app") { return }
        if CommandLine.arguments.contains("--lab") { lab.show(); return }
        start()
    }

    /// A book that was open comes back exactly as left; with none, the Welcome window.
    func start() {
        if AppPreferences.shared.values.reopenLastBook, let path = settings.lastOpened, openBook(at: URL(fileURLWithPath: path)) { return }
        showWelcome()
    }

    /// ⌘N is New Book while no book is open, and New Scene while one is.
    private func updateNewBookKey() { newBookItem?.keyEquivalent = bookWindows.isEmpty ? "n" : "" }

    func showWelcome() { welcome.show(books: settings.knownBooks) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        bookWindows.forEach { $0.save() }
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }

    // MARK: Books

    static func isBook(_ folder: URL) -> Bool {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("book.json")), let o = try? JSONParser.parseObject(data) else { return false }
        return o.string("id") != nil && o.string("title") != nil
    }

    /// Opens a book (or brings its window to the front). Returns false when the folder is not a Quilland book.
    @discardableResult
    func openBook(at folder: URL, mode: MainAreaController.Mode? = nil) -> Bool {
        if let existing = bookWindows.first(where: { $0.folder.standardizedFileURL == folder.standardizedFileURL }) { existing.show(); return true }
        guard Self.isBook(folder) else { return false }
        // The links between characters and events live in the events now: an old book is asked about and moved first; a book that has none gets the default event.
        guard let migrationNote = prepareEvents(of: folder) else { return false }
        // A book with no remembered view starts in the writing mode the author chose in Settings.
        let hasState = FileManager.default.fileExists(atPath: folder.appendingPathComponent(".quilland/state.json").path)
        let mode = mode ?? (hasState ? nil : MainAreaController.Mode(rawValue: AppPreferences.shared.values.defaultMode))
        if let mode {
            var state = LocalBookState.load(book: folder)
            state.mode = mode.rawValue
            state.save(book: folder)
        }
        guard let controller = try? BookWindowController(folder: folder) else { return false }
        controller.onClose = { [weak self] c in self?.bookClosed(c) }
        bookWindows.append(controller)
        updateNewBookKey()
        settings.noteOpened(folder: folder, name: controller.bookTitle)
        welcome.window.orderOut(nil)
        controller.show()
        DispatchQueue.main.async { controller.showRemindersIfAny() }
        if let migrationNote { controller.main.banner.show(migrationNote, undoable: false) }
        return true
    }

    /// Asks the author before the links between characters and events (and the relationships that start at no event) are moved; the decision can be replaced for the checks.
    var migrationDecision: (EventLinkMigration.Plan, URL) -> Bool = { plan, folder in
        let alert = NSAlert()
        alert.messageText = L("This book needs to be migrated")
        alert.informativeText = L("Quilland now keeps the links between characters and events in the events, and every relationship starts at an event. This book keeps them in the characters' files, so {links} in {characters} will be moved, and {relationships} will start at the event “Book starts”. A snapshot of the book is taken first, so you can go back.", [
            "links": Lp("{n} link", "{n} links", plan.links), "characters": Lp("{n} character", "{n} characters", plan.characters), "relationships": Lp("{n} relationship", "{n} relationships", plan.relationships)])
        alert.addButton(withTitle: L("Start migration"))
        alert.addButton(withTitle: L("Not now"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Nil: the book is not to be opened (the author said "Not now", or the migration failed; nothing was changed by "Not now"). Otherwise a line about what was moved, or an empty text.
    private func prepareEvents(of folder: URL) -> String?? {
        let plan = EventLinkMigration.plan(book: folder)
        guard plan.isNeeded else {
            try? EventLinkMigration.ensureStartEvent(book: folder)
            return .some(nil)
        }
        guard migrationDecision(plan, folder) else {
            showWelcome()
            let alert = NSAlert()
            alert.messageText = L("The book was not opened")
            alert.informativeText = L("This version of Quilland needs the links between characters and events to be moved into the events first. Nothing in the book was changed.")
            if !CommandLine.arguments.contains("--selftest-app") { alert.runModal() }
            return nil
        }
        do {
            let report = try EventLinkMigration.run(book: folder)
            return .some(L("Moved {links} and {relationships} to the events. A snapshot was taken first.", ["links": Lp("{n} link", "{n} links", report.links), "relationships": Lp("{n} relationship", "{n} relationships", report.relationships)]))
        } catch {
            let alert = NSAlert()
            alert.messageText = L("The book could not be migrated")
            alert.informativeText = "\(error)"
            if !CommandLine.arguments.contains("--selftest-app") { alert.runModal() }
            return nil
        }
    }

    private func bookClosed(_ controller: BookWindowController) {
        bookWindows.removeAll { $0 === controller }
        updateNewBookKey()
        guard !terminating else { return }
        // Closing the book by hand: the next start shows the Welcome window; now, too, if it was the last one.
        if bookWindows.isEmpty { settings.clearLastOpened(); showWelcome() }
    }

    func chooseBook() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !Self.isBook(url) {
            let alert = NSAlert()
            alert.messageText = L("This folder is not a Quilland book")
            alert.informativeText = L("A book has a book.json file. Importing a folder of text files is not built yet.")
            alert.runModal()
        } else {
            openBook(at: url)
        }
    }

    // MARK: New Book

    @objc func showNewBook() {
        let dialog = NewBookWindowController(parentFolder: booksParent)
        dialog.onCreated = { [weak self] folder, plan in
            self?.newBook = nil
            _ = self?.openBook(at: folder, mode: plan ? .plan : (MainAreaController.Mode(rawValue: AppPreferences.shared.values.defaultMode) ?? .panels))
        }
        dialog.onCancel = { [weak self] in self?.newBook = nil }
        newBook = dialog
        dialog.present(over: bookWindows.first(where: { $0.window.isKeyWindow })?.window ?? (welcome.window.isVisible ? welcome.window : nil))
    }

    // MARK: Export and Import

    @objc func showExport() {
        guard let book = keyBook else { return }
        let key = book.folder.standardizedFileURL.path
        if let open = exportWindows[key] { open.show(); return }
        do {
            let controller = try ExportWindowController(folder: book.folder)
            controller.prepare = { [weak book] in book?.save() }
            controller.onClose = { [weak self] in self?.exportWindows[key] = nil }
            exportWindows[key] = controller
            controller.show()
        } catch {
            let alert = NSAlert()
            alert.messageText = L("The book could not be read for export")
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }

    @objc func saveSnapshotAction() { keyBook?.saveSnapshot() }

    @objc func saveNamedSnapshotAction() {
        guard let book = keyBook else { return }
        let field = NSTextField(string: "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = L("Name this snapshot")
        alert.informativeText = L("A named snapshot is kept for good; it is never thinned out.")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Save"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { book.saveSnapshot(named: name) }
    }

    @objc func showSettings() {
        if let open = settingsWindow { open.show(); return }
        let controller = SettingsWindowController()
        controller.onClose = { [weak self] in self?.settingsWindow = nil }
        settingsWindow = controller
        controller.show()
    }

    /// The book whose window this is.
    func bookMain(for window: NSWindow?) -> MainAreaController? { (bookWindows.first { $0.window === window } ?? keyBook)?.main }

    /// "Learn Spelling" in a text: the word goes into the dictionary of the book whose window it was asked in.
    func learnWord(_ word: String, from window: NSWindow?) {
        guard let book = bookWindows.first(where: { $0.window === window }) ?? keyBook else { return }
        book.main.addToDictionary(word)
        bookSettingsController(for: book.folder)?.reloadWords()
    }

    @objc func showBookSettings() {
        guard let book = keyBook else { return }
        let key = book.folder.standardizedFileURL.path
        if let open = bookSettingsWindows[key] { open.show(); return }
        let controller = BookSettingsWindowController(folder: book.folder)
        controller.currentSize = { [weak book] in (book?.main.session.totalCharacters ?? 0, book?.main.session.totalWords ?? 0) }
        controller.onChanged = { [weak self, weak book] in
            guard let self, let book else { return }
            book.bookSettingsChanged(settings: self.settings)
        }
        controller.onClose = { [weak self] in self?.bookSettingsWindows[key] = nil }
        bookSettingsWindows[key] = controller
        controller.show()
    }

    @objc func showSnapshots() {
        guard let book = keyBook else { return }
        let key = book.folder.standardizedFileURL.path
        if let open = snapshotWindows[key] { open.reload(); open.show(); return }
        let controller = SnapshotsWindowController(folder: book.folder)
        controller.prepare = { [weak book] in book?.main.saveAll() }
        controller.onChanged = { [weak book] in book?.main.reloadFromDisk() }
        controller.onClose = { [weak self] in self?.snapshotWindows[key] = nil }
        snapshotWindows[key] = controller
        controller.show()
    }

    @objc func showImport() {
        if let open = importWindow { open.show(); return }
        let controller = ImportWindowController()
        if let book = keyBook {
            controller.openBookName = book.bookTitle
            controller.language = book.language
            controller.intoOpenBook = { [weak book] plan in book?.main.performImport(plan) ?? false }
        }
        controller.intoNewBook = { [weak self] plan, title, language in self?.importIntoNewBook(plan, title: title, language: language) ?? false }
        controller.onClose = { [weak self] in self?.importWindow = nil }
        controller.applyDestinationChoices()
        importWindow = controller
        controller.show()
    }

    /// Makes a new book with what was imported (in the Documents folder, like New Book) and opens it.
    func importIntoNewBook(_ plan: ImportPlan, title: String, language: String) -> Bool {
        do {
            let folder = try BookCreator.create(NewBookRequest(title: title, language: language, parentFolder: booksParent))
            try TextImporter.write(plan, into: folder, replacingEmptyStart: true)
            return openBook(at: folder, mode: .panels)
        } catch {
            let alert = NSAlert()
            alert.messageText = L("The new book could not be made")
            alert.informativeText = "\(error)"
            alert.runModal()
            return false
        }
    }

    // MARK: Menu

    var keyBook: BookWindowController? { bookWindows.first { $0.window === NSApp.keyWindow } ?? bookWindows.first }

    /// Every action of the menus that the author may give a shortcut to: its id (the selector's name), a title for the list, and the shortcut it comes with.
    private(set) var shortcutCatalog: [(id: String, title: String, defaults: Shortcut?)] = []
    private var shownShortcuts: [String: String] = [:]

    private var aiStatusItem: NSMenuItem?
    /// The prompts saved from the Chat; made again each time the menu opens.
    private var actionsMenu = NSMenu(title: "Actions")

    private func updateAIStatusItem() {
        let service = AIService.shared
        if service.checking { aiStatusItem?.title = L("Asking LM Studio…"); return }
        if let reason = service.unavailableReason { aiStatusItem?.title = reason; return }
        let info = service.status?.info
        aiStatusItem?.title = L("Connected: {model}", ["model": (info?.displayName.isEmpty == false ? info?.displayName : info?.id) ?? ""])
    }

    @objc func synopsisAction() { keyBook?.main.writeSynopsis() }
    @objc func continueAction() { keyBook?.main.continueWriting(askDirection: false) }
    @objc func continueDirectionAction() { keyBook?.main.continueWriting(askDirection: true) }
    @objc func grammarAction() {
        guard let main = keyBook?.main else { return }
        main.showSearch(.proofread)
        main.searchPanel.proofView.startGrammar()
    }
    /// Right-click in the text: the selected words, or else the scene, are checked for contradictions at once.
    @objc func consistencyHereAction() {
        guard let main = keyBook?.main, AIService.shared.isReady else { return }
        main.showSearch(.suggestions)
        main.collect.startConsistency(scope: main.searchTargets(.selection).selection != nil ? .selection : .scene)
    }
    @objc func consistencyAction() { keyBook?.main.showConsistencySheet() }
    @objc func collectAction() { keyBook?.main.showCollectSheet() }
    @objc func showSuggestionsAction() { keyBook?.main.showSearch(.suggestions) }

    @objc func showAISettings() {
        showSettings()
        settingsWindow?.select(.ai)
        if AIService.shared.status == nil || AIService.shared.status?.reachable != true { AIService.shared.refresh() }
    }

    private func buildMenu() {
        let main = NSMenu()
        shortcutCatalog = []
        shownShortcuts = AppPreferences.shared.values.shortcuts
        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) {
            var key = key, modifiers = modifiers
            // An action of the app (not a standard command of the responder chain) can be given another shortcut, or none.
            if target === self, let action {
                let id = NSStringFromSelector(action)
                let defaults = Shortcut(keyEquivalent: key, modifiers: modifiers)
                shortcutCatalog.append((id, menu.title + " ▸ " + title.replacingOccurrences(of: "…", with: ""), defaults))
                if let chosen = Shortcuts.effective(id: id, defaults: defaults, overrides: shownShortcuts) { (key, modifiers) = chosen.menuKey } else { key = ""; modifiers = [] }
            }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); main.addItem(item)
            let menu = NSMenu(title: title); item.submenu = menu
            return menu
        }
        let app = submenu("Quilland")
        add(app, L("About Quilland"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add(app, L("Settings…"), #selector(showSettings), ",", target: self)
        app.addItem(.separator())
        add(app, L("Hide Quilland"), #selector(NSApplication.hide(_:)), "h")
        app.addItem(.separator())
        add(app, L("Quit Quilland"), #selector(NSApplication.terminate(_:)), "q")

        let file = submenu(L("File"))
        add(file, L("New Book…"), #selector(showNewBook), "n", [.command], target: self)
        newBookItem = file.items.last
        add(file, L("Open Book…"), #selector(chooseBookAction), "o", target: self)
        let recent = NSMenuItem(title: L("Open Recent"), action: nil, keyEquivalent: "")
        recentMenu = NSMenu(title: L("Open Recent"))
        recentMenu.delegate = self
        recent.submenu = recentMenu
        file.addItem(recent)
        file.addItem(.separator())
        add(file, L("Save Snapshot"), #selector(saveSnapshotAction), "s", target: self)
        add(file, L("Save Named Snapshot…"), #selector(saveNamedSnapshotAction), "s", [.command, .option], target: self)
        add(file, L("Snapshots…"), #selector(showSnapshots), "s", [.command, .shift], target: self)
        file.addItem(.separator())
        add(file, L("Import…"), #selector(showImport), "i", [.command, .shift], target: self)
        add(file, L("Export…"), #selector(showExport), "e", target: self)
        file.addItem(.separator())
        add(file, L("Book Settings…"), #selector(showBookSettings), ",", [.command, .shift], target: self)
        file.addItem(.separator())
        add(file, L("Close"), #selector(NSWindow.performClose(_:)), "w")

        let edit = submenu(L("Edit"))
        add(edit, L("Undo"), Selector(("undo:")), "z")
        add(edit, L("Redo"), Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, L("Find…"), #selector(findAction), "f", target: self)
        add(edit, L("Replace…"), #selector(replaceAction), "f", [.command, .option], target: self)
        add(edit, L("Proofread…"), #selector(proofreadAction), "p", [.command, .option], target: self)
        add(edit, L("Loose Ends…"), #selector(looseEndsAction), "l", [.command, .option], target: self)
        add(edit, L("Find Duplicate Cards…"), #selector(duplicatesAction), "d", [.command, .option], target: self)
        add(edit, L("Find Next"), #selector(findNextAction), "g", target: self)
        add(edit, L("Find Previous"), #selector(findPreviousAction), "g", [.command, .shift], target: self)
        edit.addItem(.separator())
        add(edit, L("Cut"), #selector(NSText.cut(_:)), "x")
        add(edit, L("Copy"), #selector(NSText.copy(_:)), "c")
        add(edit, L("Paste"), #selector(NSText.paste(_:)), "v")
        add(edit, L("Select All"), #selector(NSText.selectAll(_:)), "a")

        let view = submenu(L("View"))
        add(view, L("Panels"), #selector(modePanels), "1", target: self)
        add(view, L("Book"), #selector(modeBook), "2", target: self)
        add(view, L("Split Book View"), #selector(toggleSplit), "\\", target: self)
        add(view, L("Outline"), #selector(modeOutline), "3", target: self)
        add(view, L("Plan"), #selector(modePlan), "4", target: self)
        // The World Bible: one item, with no shortcut, and the kinds under it.
        let bibleItem = NSMenuItem(title: L("World Bible"), action: nil, keyEquivalent: "")
        let bible = NSMenu(title: L("World Bible"))
        bibleItem.submenu = bible
        view.addItem(bibleItem)
        add(bible, L("Characters"), #selector(modeCharacters), "1", [.command, .control], target: self)
        add(bible, L("World"), #selector(modeWorld), "2", [.command, .control], target: self)
        add(view, L("Events"), #selector(modeEvents), "5", target: self)
        add(view, L("Graph"), #selector(modeGraph), "6", target: self)
        add(view, L("Research"), #selector(modeResearch), "7", target: self)
        add(view, L("Reminders"), #selector(modeReminders), "0", target: self)
        view.addItem(.separator())
        add(view, L("Back"), #selector(historyBack), "[", target: self)
        add(view, L("Forward"), #selector(historyForward), "]", target: self)
        view.addItem(.separator())
        add(view, L("Jump to Scene…"), #selector(jumpToScene), "j", target: self)
        add(view, L("Right Panel"), #selector(toggleRightPanel), "r", [.command, .option], target: self)
        add(view, L("Focus Mode"), #selector(toggleFocusMode), "\r", [.command, .control], target: self)
        add(view, L("Typewriter Scrolling"), #selector(toggleTypewriter), "t", [.command, .option], target: self)
        // These zoom the Plan's canvas.
        add(view, L("Zoom In"), #selector(zoomIn), "+", [.command], target: self)
        add(view, L("Zoom Out"), #selector(zoomOut), "-", [.command], target: self)
        add(view, L("Fit"), #selector(zoomFit), "0", [.command, .shift], target: self)
        view.addItem(.separator())
        add(view, L("Larger Book Text"), #selector(appLarger), "+", [.command, .option], target: self)
        add(view, L("Smaller Book Text"), #selector(appSmaller), "-", [.command, .option], target: self)
        add(view, L("Usual Book Text Size"), #selector(appUsualSize), "0", [.command, .option], target: self)

        let format = submenu(L("Format"))
        add(format, L("Bold"), Selector(("toggleBold:")), "b")
        add(format, L("Italic"), Selector(("toggleItalic:")), "i")
        format.addItem(.separator())
        add(format, L("Heading 1"), Selector(("makeHeading1:")), "1", [.command, .option])
        add(format, L("Heading 2"), Selector(("makeHeading2:")), "2", [.command, .option])
        add(format, L("Heading 3"), Selector(("makeHeading3:")), "3", [.command, .option])
        add(format, L("Body Text"), Selector(("makeBody:")), "0", [.command, .option])
        add(format, L("Set-off Block"), Selector(("makeQuote:")), "'")
        format.addItem(.separator())
        add(format, L("Scene Break"), Selector(("insertSceneBreak:")), "\r", [.command, .shift])
        add(format, L("Footnote…"), Selector(("insertFootnote:")), "n", [.command, .control])

        let section = submenu(L("Section"))
        add(section, L("New Scene"), #selector(newScene), "n", target: self)
        add(section, L("New Scene Before"), #selector(newSceneBefore), "", target: self)
        add(section, L("New Chapter"), #selector(newChapter), "n", [.command, .shift], target: self)
        add(section, L("New Part"), #selector(newPart), "n", [.command, .option, .shift], target: self)
        section.addItem(.separator())
        add(section, L("Rename"), #selector(renameSection), "", target: self)
        let status = NSMenuItem(title: L("Status"), action: nil, keyEquivalent: "")
        let statusMenu = NSMenu(title: L("Status"))
        for name in SceneRecord.knownStatuses {
            let item = NSMenuItem(title: L(name).capitalized, action: #selector(setSectionStatus(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            statusMenu.addItem(item)
        }
        status.submenu = statusMenu
        section.addItem(status)
        section.addItem(.separator())
        add(section, L("Move Up"), #selector(moveSectionUp), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option], target: self)
        add(section, L("Move Down"), #selector(moveSectionDown), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option], target: self)
        add(section, L("Move To…"), #selector(moveSectionTo), "", target: self)
        section.addItem(.separator())
        add(section, L("Split Scene Here"), #selector(splitScene), "\r", [.command, .option], target: self)
        add(section, L("Merge with Next Scene"), #selector(mergeNextScene), "", target: self)
        add(section, L("Merge with Previous Scene"), #selector(mergePreviousScene), "", target: self)
        add(section, L("Merge Chosen Scenes"), #selector(mergeChosenScenes), "", target: self)
        section.addItem(.separator())
        add(section, L("Group into a New Part…"), #selector(groupIntoPart), "", target: self)
        add(section, L("Ungroup Part…"), #selector(ungroupPart), "", target: self)
        section.addItem(.separator())
        add(section, L("Delete…"), #selector(deleteSection), "", target: self)

        // The AI actions arrive here; for now its settings and whether the model answers.
        let aiMenu = submenu(L("AI"))
        let aiStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        aiStatus.isEnabled = false
        aiMenu.addItem(aiStatus)
        aiStatusItem = aiStatus
        updateAIStatusItem()
        aiMenu.addItem(.separator())
        add(aiMenu, L("Continue Writing"), #selector(continueAction), "g", [.command, .control], target: self)
        add(aiMenu, L("Continue Writing with a Direction…"), #selector(continueDirectionAction), "g", [.command, .control, .shift], target: self)
        aiMenu.addItem(.separator())
        add(aiMenu, L("Write Synopsis"), #selector(synopsisAction), "y", [.command, .control], target: self)
        let actionsItem = NSMenuItem(title: L("Actions"), action: nil, keyEquivalent: "")
        // A menu can be in one place only: the menus are made again (a language, a shortcut), so this one is too.
        actionsMenu = NSMenu(title: L("Actions"))
        actionsItem.submenu = actionsMenu
        actionsMenu.delegate = self
        aiMenu.addItem(actionsItem)
        aiMenu.addItem(.separator())
        add(aiMenu, L("Collect from the Book…"), #selector(collectAction), "k", [.command, .option], target: self)
        add(aiMenu, L("Check Grammar"), #selector(grammarAction), "g", [.command, .option, .shift], target: self)
        add(aiMenu, L("Check Consistency…"), #selector(consistencyAction), "y", [.command, .option], target: self)
        add(aiMenu, L("Show Suggestions"), #selector(showSuggestionsAction), "j", [.command, .option, .shift], target: self)
        aiMenu.addItem(.separator())
        add(aiMenu, L("AI Settings…"), #selector(showAISettings), "", target: self)

        let window = submenu(L("Window"))
        add(window, L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === actionsMenu {
            menu.removeAllItems()
            for action in AppPreferences.shared.actions {
                let item = ClosureMenuItem(title: action.name) { [weak self] in self?.keyBook?.main.runAIAction(action) }
                item.isEnabled = AIService.shared.isReady && keyBook != nil
                menu.addItem(item)
            }
            if menu.items.isEmpty { let none = NSMenuItem(title: L("None yet: save a prompt from the Chat"), action: nil, keyEquivalent: ""); none.isEnabled = false; menu.addItem(none) }
            return
        }
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        for book in settings.knownBooks where FileManager.default.fileExists(atPath: book.path + "/book.json") {
            let item = ClosureMenuItem(title: book.name) { [weak self] in _ = self?.openBook(at: URL(fileURLWithPath: book.path)) }
            menu.addItem(item)
        }
        if menu.items.isEmpty { let none = NSMenuItem(title: L("No Recent Books"), action: nil, keyEquivalent: ""); none.isEnabled = false; menu.addItem(none) }
    }

    @objc private func chooseBookAction() { chooseBook() }
    @objc func jumpToScene() { keyBook?.main.openJump() }
    @objc func toggleRightPanel() { if let m = keyBook?.main { m.setRightPanel(!m.showsRightPanel) } }
    @objc func findAction() { keyBook?.main.showSearch(.search) }
    @objc func replaceAction() { keyBook?.main.showSearch(.replace) }
    @objc func proofreadAction() { keyBook?.main.showSearch(.proofread) }
    @objc func looseEndsAction() { keyBook?.main.showSearch(.looseEnds) }
    @objc func duplicatesAction() { keyBook?.main.showSearch(.duplicates) }
    @objc func findNextAction() { keyBook?.main.searchStep(1) }
    @objc func findPreviousAction() { keyBook?.main.searchStep(-1) }
    @objc func modeEvents() { keyBook?.main.setMode(.events); keyBook?.refreshStatus() }
    @objc func historyBack() { keyBook?.main.goBack(); keyBook?.refreshStatus() }
    @objc func historyForward() { keyBook?.main.goForward(); keyBook?.refreshStatus() }
    @objc func modeReminders() { keyBook?.main.setMode(.reminders); keyBook?.refreshStatus() }
    @objc func modeResearch() { keyBook?.main.setMode(.research); keyBook?.refreshStatus() }
    @objc func modeWorld() { keyBook?.main.setMode(.world); keyBook?.refreshStatus() }
    @objc func modeCharacters() { keyBook?.main.setMode(.characters); keyBook?.refreshStatus() }
    @objc func modeOutline() { keyBook?.main.setMode(.outline); keyBook?.refreshStatus() }
    @objc func modePanels() { keyBook?.main.setMode(.panels); keyBook?.refreshStatus() }
    @objc func newScene() { keyBook?.main.add(.scene) }
    @objc func newSceneBefore() { keyBook?.main.add(.scene, place: .before) }
    @objc func newChapter() { keyBook?.main.add(.chapter) }
    @objc func newPart() { keyBook?.main.add(.part) }
    @objc func renameSection() { keyBook?.main.renameSelected() }
    @objc func setSectionStatus(_ sender: NSMenuItem) { if let name = sender.representedObject as? String { keyBook?.main.setStatus(to: name) } }
    @objc func moveSectionTo() { keyBook?.main.moveChosenTo() }
    @objc func moveSectionUp() { keyBook?.main.move(by: -1) }
    @objc func moveSectionDown() { keyBook?.main.move(by: 1) }
    @objc func splitScene() { keyBook?.main.splitSceneHere() }
    @objc func mergeNextScene() { keyBook?.main.merge(direction: 1) }
    @objc func mergePreviousScene() { keyBook?.main.merge(direction: -1) }
    @objc func mergeChosenScenes() { keyBook?.main.mergeSelected() }
    @objc func groupIntoPart() { keyBook?.main.groupIntoPart() }
    @objc func ungroupPart() { keyBook?.main.ungroupPart() }
    @objc func deleteSection() { keyBook?.main.delete() }
    @objc func modeBook() { keyBook?.main.setMode(.book); keyBook?.refreshStatus() }
    @objc func toggleSplit() { if let m = keyBook?.main { m.setSplit(!m.isSplit); keyBook?.refreshStatus() } }
    @objc func modeGraph() { keyBook?.main.setMode(.graph); keyBook?.refreshStatus() }
    @objc func modePlan() { keyBook?.main.setMode(.plan); keyBook?.refreshStatus() }
    @objc private func toggleTypewriter() { if let m = keyBook?.main, !m.focusMode { m.setTypewriter(!m.typewriter) } }
    @objc func toggleFocusMode() { if let m = keyBook?.main { m.setFocusMode(!m.focusMode) } }

    /// Focus Mode is for Book mode only; its item shows whether it is on.
    static let sectionActions: Set<Selector> = [#selector(newScene), #selector(newSceneBefore), #selector(newChapter), #selector(newPart), #selector(renameSection), #selector(setSectionStatus(_:)),
                                                #selector(moveSectionUp), #selector(moveSectionDown), #selector(moveSectionTo), #selector(splitScene), #selector(mergeNextScene), #selector(mergePreviousScene),
                                                #selector(mergeChosenScenes), #selector(groupIntoPart), #selector(ungroupPart), #selector(deleteSection)]

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(showBookSettings) { return keyBook != nil }
        if item.action == #selector(historyBack) { return keyBook?.main.canGoBack ?? false }
        if item.action == #selector(historyForward) { return keyBook?.main.canGoForward ?? false }
        // The view in use and the right panel are ticked.
        let views: [(Selector, MainAreaController.Mode)] = [(#selector(modePanels), .panels), (#selector(modeBook), .book), (#selector(modeOutline), .outline),
                                                            (#selector(modePlan), .plan), (#selector(modeGraph), .graph), (#selector(modeCharacters), .characters), (#selector(modeWorld), .world), (#selector(modeEvents), .events), (#selector(modeResearch), .research), (#selector(modeReminders), .reminders)]
        if let action = item.action, let view = views.first(where: { $0.0 == action }) {
            item.state = keyBook?.main.mode == view.1 ? .on : .off
            return keyBook != nil
        }
        if item.action == #selector(toggleSplit) {
            item.state = keyBook?.main.isSplit == true ? .on : .off
            return keyBook?.main.mode == .book
        }
        if item.action == #selector(toggleRightPanel) {
            item.state = keyBook?.main.showsRightPanel == true ? .on : .off
            return keyBook != nil
        }
        if item.action == #selector(zoomIn) || item.action == #selector(zoomOut) || item.action == #selector(zoomFit) { return keyBook?.main.planController != nil || keyBook?.main.graphView != nil }
        if item.action == #selector(synopsisAction) { return keyBook != nil && AIService.shared.isReady }
        if item.action == #selector(continueAction) || item.action == #selector(continueDirectionAction) {
            let main = keyBook?.main
            return AIService.shared.isReady && main != nil && main?.mode != .outline && main?.mode != .plan && main?.mode != .characters && main?.mode != .world && main?.mode != .events && main?.mode != .research && main?.mode != .reminders
        }
        if item.action == #selector(grammarAction) { return keyBook != nil && AIService.shared.isReady }
        if item.action == #selector(consistencyAction) { return keyBook != nil && AIService.shared.isReady }
        if item.action == #selector(collectAction) { return keyBook != nil && AIService.shared.isReady }
        if item.action == #selector(showSuggestionsAction) { return keyBook != nil }
        // The Section menu follows what is chosen: nothing that cannot be done is offered.
        if let action = item.action, Self.sectionActions.contains(action) {
            guard let main = keyBook?.main else { return false }
            let state = main.sectionState()
            switch action {
            case #selector(renameSection), #selector(deleteSection): return state.hasSection
            case #selector(moveSectionUp): return state.canMoveUp
            case #selector(moveSectionDown): return state.canMoveDown
            case #selector(moveSectionTo): return state.canMoveTo
            case #selector(mergeNextScene): return state.hasNextScene
            case #selector(mergePreviousScene): return state.hasPreviousScene
            case #selector(mergeChosenScenes): return state.canMergeChosen
            case #selector(groupIntoPart): return state.canGroup
            case #selector(ungroupPart): return state.isPart
            case #selector(splitScene): return state.canSplit
            case #selector(setSectionStatus(_:)):
                item.state = state.isScene && (item.representedObject as? String) == state.status ? .on : .off
                return state.isScene
            default: return true
            }
        }
        if item.action == #selector(toggleFocusMode) {
            let main = keyBook?.main
            item.state = main?.focusMode == true ? .on : .off
            return main?.mode == .book
        }
        if item.action == #selector(toggleTypewriter) {
            item.state = keyBook?.main.typewriter == true ? .on : .off
            return keyBook?.main.focusMode != true
        }
        return true
    }
    @objc private func zoomIn() { if let plan = keyBook?.main.planController { plan.zoomIn() } else { keyBook?.main.graphView?.zoomIn() } }
    @objc private func zoomOut() { if let plan = keyBook?.main.planController { plan.zoomOut() } else { keyBook?.main.graphView?.zoomOut() } }
    @objc private func zoomFit() { if let plan = keyBook?.main.planController { plan.zoomToFit() } else { keyBook?.main.graphView?.zoomToFit() } }

    /// One step bigger or smaller: the book's text by a point.
    @objc func appLarger() { stepAppSize(1) }
    @objc func appSmaller() { stepAppSize(-1) }
    @objc func appUsualSize() { AppPreferences.shared.update { $0.fontSize = Preferences().fontSize } }

    func stepAppSize(_ steps: Int) {
        AppPreferences.shared.update { p in
            p.fontSize += Double(steps)
        }
    }


    var labController: LabWindowController { lab }
}
