import AppKit
import QuillandCore

/// The Settings window and the language of the interface.
extension AppSelfTest {
    func settings() -> Int32? {
        // Settings.
        guard let stFolder = create(title: "Settings Test", plan: false) else { check(false, "the book for the settings checks is made"); return 1 }
        spin(0.6)
        guard let stWin = app.bookWindows.last else { return 1 }
        stWin.usesFullScreen = false
        let stMain = stWin.main
        let prefs = AppPreferences.shared
        app.showSettings(); spin(0.3)
        guard let set = app.settingsWindow else { check(false, "Settings… opens the window"); return 1 }
        check(set.visibleSections == [.general, .appearance, .writing, .panels, .ai, .aiPrompts, .shortcuts], "Settings lists its sections")
        set.filter("quotes")
        check(set.visibleSections == [.writing], "the search field narrows the list to the sections that have the word")
        set.filter("")
        check(set.visibleSections.count == 7 && prefs.values == Preferences(), "and with nothing typed shows all; the preferences start at the design's defaults")

        // Appearance.
        stMain.setMode(.book); spin(0.4)
        let stScene = stMain.session.structure.scenes[0].id
        let stDoc = stMain.session.document(stScene)!
        stDoc.storage.replaceCharacters(in: NSRange(location: 0, length: stDoc.storage.length), with: String(repeating: "Длинная строка текста для проверки высоты листа. ", count: 30))
        stDoc.textDidChange(); spin(0.3)
        let sheetBefore = stMain.controllers[0].currentSheet?.height ?? stMain.controllers[0].stack.sheets[0].height
        let widthBefore = stMain.controllers[0].stack.sheets[0].frame.width
        set.setNumber("fontSize", 24); spin(0.4)
        check(Fonts.baseSize == 24 && (stMain.controllers[0].stack.sheets[0].textView.font?.pointSize ?? 0) == 24, "a larger text size reaches the text at once")
        check(stMain.controllers[0].stack.sheets[0].height > sheetBefore, "and the sheet grows to fit it", "\(sheetBefore) → \(stMain.controllers[0].stack.sheets[0].height)")
        set.setNumber("lineSpacing", 1.8); spin(0.3)
        check(Fonts.lineSpacing == 1.8, "line spacing follows")
        set.setNumber("readingWidth", 900); spin(0.4)
        check(stMain.controllers[0].stack.sheets[0].frame.width > widthBefore, "a wider reading width makes the sheets wider", "\(widthBefore) → \(stMain.controllers[0].stack.sheets[0].frame.width)")
        set.setChoice("font", "Palatino"); spin(0.3)
        check(Fonts.name == "Palatino" && (stMain.controllers[0].stack.sheets[0].textView.font?.familyName ?? "").contains("Palatino"), "the font family changes")
        set.setChoice("appearance", "dark")
        check(NSApp.appearance?.name == .darkAqua, "Dark makes the app dark")
        set.setChoice("appearance", "system")
        check(NSApp.appearance == nil, "and Like the system gives it back")
        set.reset(.appearance); spin(0.3)
        check(Fonts.baseSize == 17 && Fonts.lineSpacing == 1.3 && Fonts.name == "Georgia" && prefs.values.readingWidth == 640, "Reset to Defaults puts the section back")

        // Writing: the typing corrections, by the book's language.
        stMain.setMode(.panels); spin(0.4)
        stMain.reveal(scene: stScene, range: nil); spin(0.3)
        let typer = stMain.controllers[0].currentSheet!.textView
        func type(_ s: String) {
            typer.setSelectedRange(NSRange(location: typer.string.utf16.count, length: 0))
            for ch in s { typer.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        typer.setSelectedRange(NSRange(location: 0, length: typer.string.utf16.count))
        typer.insertText("", replacementRange: typer.selectedRange())
        type("Он сказал \"привет\" - да.")
        check(typer.string == "Он сказал «привет»\u{00A0}— да.", "typing: Russian quotes and a dash with a non-breaking space", typer.string.debugDescription)
        type("\n- Ну...")
        check(typer.string.hasSuffix("\n— Ну..."), "a dialogue dash at the start of a paragraph; three dots stay three dots", typer.string.debugDescription)
        set.setFlag("ellipsis", true)
        type(" Да...")
        check(typer.string.hasSuffix("Да…"), "with the ellipsis correction on, three dots become one character")
        set.setChoice("quoteStyle", "en")
        type(" \"x\"")
        check(typer.string.hasSuffix("“x”"), "a quote style can be forced")
        set.setFlag("corrections", false)
        type(" \"y\" - z")
        check(typer.string.hasSuffix("\"y\" - z"), "with the corrections off nothing is replaced")
        check(!(set.controls["dashes"]?.isEnabled ?? true), "and their switches are greyed")
        set.reset(.writing)
        check(prefs.autocorrect == AutocorrectSettings(), "Reset puts the writing choices back (the ellipsis one is off)")
        set.setFlag("spelling", false)
        check(!typer.isContinuousSpellCheckingEnabled, "turning spelling off reaches the text views")
        set.setFlag("spelling", true)
        check(typer.isContinuousSpellCheckingEnabled, "and on")

        // Panels.
        stMain.setRightPanel(true); spin(0.4)
        check(stMain.rightPanel.visibleTabs == [.section, .characters], "the right panel starts with both tabs")
        set.setFlag("tab.characters", false)
        check(stMain.rightPanel.visibleTabs == [.section], "a tab can be hidden")
        set.setFlag("tab.section", false)
        check(prefs.values.panelTabs == ["section"], "but one stays")
        set.setFlag("tab.characters", true)
        set.setFlag("tab.research", true)
        check(stMain.rightPanel.visibleTabs == [.section, .characters, .research], "the Research tab can be switched on in Settings", "\(stMain.rightPanel.visibleTabs)")
        set.setFlag("tab.research", false)
        set.setNumber("followDelay", 3)
        check(stMain.rightPanel.followDelay == 3 && stMain.rightPanel.visibleTabs == [.section, .characters], "the follow delay changes, and the tab is back")
        stMain.setRightPanel(false)
        set.reset(.panels)

        // General.
        check(stWin.snapshotTimerIsRunning, "automatic snapshots are on by default")
        set.setFlag("autoSnapshots", false)
        check(!stWin.snapshotTimerIsRunning, "turning them off stops the timer")
        set.setFlag("autoSnapshots", true)
        set.setNumber("snapshotMinutes", 5)
        check(stWin.snapshotTimerIsRunning && stWin.snapshotInterval == 300, "and the interval is the one chosen")
        set.setNumber("recent", 2)
        check(app.settings.knownBooks.count <= 2 || AppPreferences.shared.values.recentLimit == 2, "the number of recent books is kept")
        set.setNewBookFolder(temp.appendingPathComponent("my books").path)
        set.setFlag("reopen", false)
        set.setChoice("mode", "book")
        let fromFile = AppSettings(directory: app.settings.directory).preferences
        check(fromFile == prefs.values && fromFile.newBookFolder == temp.appendingPathComponent("my books").path && !fromFile.reopenLastBook && fromFile.defaultMode == "book", "every choice is in settings.json, and a new run would read it back")
        check(FileManager.default.fileExists(atPath: app.settings.directory.appendingPathComponent("autocorrect.json").path), "the typing corrections are in autocorrect.json")
        let plainBook = try! BookCreator.create(NewBookRequest(title: "No State", parentFolder: temp))
        check(app.openBook(at: plainBook) && app.bookWindows.last?.main.mode == .book, "a book with no remembered view opens in the mode chosen")
        app.bookWindows.last?.window.close(); spin(0.3)
        set.reset(.general)
        check(prefs.values == Preferences() && prefs.autocorrect == AutocorrectSettings(), "everything is back to the defaults after the resets")

        // Book Settings.
        app.showBookSettings(); spin(0.3)
        check(app.bookSettingsWindowCount == 1, "File ▸ Book Settings… opens the window for the book")
        if let bs = app.bookSettingsController(for: stFolder) {
            bs.apply { $0.title = "Новое имя" }
            spin(0.2)
            check(BookSettings.load(book: stFolder).title == "Новое имя" && stWin.window.title == "Новое имя" && app.settings.knownBooks.first { $0.path == stFolder.path }?.name == "Новое имя", "a new title is saved, shown in the window, and in the list of books")
            bs.apply { $0.title = "   " }
            check(BookSettings.load(book: stFolder).title == "Новое имя", "a blank title is refused")
            bs.apply { $0.author = "А. Автор"; $0.copyright = "© 2026"; $0.targetCharacters = 300000 }
            check(BookSettings.load(book: stFolder).author == "А. Автор" && BookSettings.load(book: stFolder).targetCharacters == 300000, "author, copyright and target size are saved in book.json")
            bs.setLanguage("en")
            check(stMain.session.document(stScene)?.language == "en", "the language reaches the text")
            typer.insertText("", replacementRange: NSRange(location: 0, length: typer.string.utf16.count))
            type("\"q\"")
            check(typer.string == "“q”", "and the quotes follow it", typer.string.debugDescription)
            bs.setLanguage("ru")
            bs.addWords("Аврора, кемпинг аврора")
            check(BookDictionary.load(book: stFolder) == ["аврора", "кемпинг"] && stMain.session.document(stScene)?.dictionaryWords == ["аврора", "кемпинг"], "dictionary words are saved in the book and given to the spell checker")
            bs.removeWord("кемпинг")
            check(BookDictionary.load(book: stFolder) == ["аврора"], "and can be removed")
            bs.window.close()
        } else { check(false, "the Book Settings window has a controller") }
        set.window.close()
        stWin.window.close(); spin(0.3)

        // The AI settings (no server is asked: the checks keep to their own address).
        do {
            app.showSettings(); spin(0.3)
            guard let st = app.settingsWindow else { check(false, "Settings opens for the AI checks"); return 1 }
            st.select(.ai); spin(0.2)
            let prefsNow = AppPreferences.shared
            st.setFlag("aiEnabled", false)
            check(!prefsNow.values.aiEnabled && !AIService.shared.isReady && AIService.shared.unavailableReason?.contains("switched off") == true, "with the AI switched off the actions are unavailable, and say why")
            st.setNumber("aiContext", 12288)
            check(prefsNow.values.aiContext == 12288 && AppSettings(directory: app.settings.directory).preferences.aiContext == 12288, "the context size is kept in settings.json")
            prefsNow.update { $0.aiAddress = "http://127.0.0.1:9"; $0.aiEnabled = true }
            var answered: AIStatus?
            AIService.shared.refresh { answered = $0 }
            let until = Date().addingTimeInterval(8)
            while answered == nil, Date() < until { spin(0.1) }
            check(answered?.reachable == false && !AIService.shared.isReady && AIService.shared.unavailableReason?.contains("LM Studio") == true, "a server that does not answer makes the actions unavailable, with the reason", "\(String(describing: answered))")
            check(NSApp.mainMenu?.items.contains { $0.submenu?.title == "AI" } == true, "the AI menu is there")
            st.reset(.ai); spin(0.2)
            check(prefsNow.values.aiAddress == AIConnection.defaultAddress && prefsNow.values.aiContext == 0 && prefsNow.values.aiEnabled, "Reset to Defaults gives the AI settings back")
            st.window.close(); spin(0.2)
        }

        // The AI prompts: the author's wording and temperatures, kept in prompts.json, used by the actions at once.
        do {
            app.showSettings(); spin(0.3)
            guard let st = app.settingsWindow else { check(false, "Settings opens for the prompt checks"); return 1 }
            st.select(.aiPrompts); spin(0.2)
            check(st.shownPromptKey == "collect", "the section starts with the first action")
            st.setPrompt("Пиши коротко. Язык: {language}.", key: "continue")
            check(ContinuePrompt.system(language: "ru") == "Пиши коротко. Язык: Russian." && AIPromptSettings.load(directory: app.settings.directory).prompts["continue"] == "Пиши коротко. Язык: {language}.", "the author's wording is used by the action at once and kept in prompts.json")
            st.setTemperature(1.2, key: "continue")
            check(AIPrompts.temperature("continue", default: 0.8) == 1.2 && AIPromptSettings.load(directory: app.settings.directory).temperatures["continue"] == 1.2, "and so is a temperature")
            st.setPrompt(AIPrompts.template(for: "continue"), key: "continue")
            check(AIPromptSettings.load(directory: app.settings.directory).prompts["continue"] == nil && ContinuePrompt.system(language: "ru").contains("co-author"), "putting the built-in text back removes the override")
            st.setTemperature(0.8, key: "continue")
            check(AIPromptSettings.load(directory: app.settings.directory).temperatures["continue"] == nil, "the action's own temperature is not kept as a choice")
            st.setPrompt("Что-то своё.", key: "chat"); st.setTemperature(0.3, key: "chat")
            st.reset(.aiPrompts); spin(0.2)
            check(AIPrompts.current == AIPromptSettings() && ChatPrompt.system(language: "ru").contains("thoughtful"), "Reset to Defaults takes all of them back")
            st.window.close(); spin(0.2)
        }

        // Saved AI actions: kept in actions.json, listed in the AI menu, renamed and deleted in Settings.
        do {
            let prefsNow = AppPreferences.shared
            prefsNow.updateActions { $0 = [AIAction(name: "Слабые места", prompt: "Найди слабые места.", attach: ["scene", "characters"]), AIAction(name: "Про план", prompt: "Перескажи план.")] }
            check(AIActions.load(directory: app.settings.directory).map(\.name) == ["Слабые места", "Про план"], "saved actions are kept in actions.json")
            let aiMenu = NSApp.mainMenu?.items.first { $0.submenu?.title == "AI" }?.submenu
            if let actions = aiMenu?.items.first(where: { $0.title == "Actions" })?.submenu {
                app.menuNeedsUpdate(actions)
                check(actions.items.map(\.title) == ["Слабые места", "Про план"], "they are listed in the AI menu under Actions")
            } else { check(false, "the AI menu has an Actions submenu") }
            app.showSettings(); spin(0.3)
            if let st = app.settingsWindow {
                st.select(.aiPrompts); spin(0.2)
                let titles = st.promptChoiceTitles
                check(titles.prefix(AIPrompts.entries.count).allSatisfy { $0.hasSuffix("System") } && titles.suffix(2) == ["Слабые места", "Про план"], "the system prompts and the author's own are in one list, the system ones marked")
                st.chooseAction(prefsNow.actions[0].id)
                st.setActionPrompt("Найди слабые места в сцене.", id: prefsNow.actions[0].id)
                check(AIActions.load(directory: app.settings.directory)[0].prompt == "Найди слабые места в сцене." && st.shownActionID == prefsNow.actions[0].id, "an own prompt is edited there too, and kept")
                st.setActionPrompt("   ", id: prefsNow.actions[0].id)
                check(AIActions.load(directory: app.settings.directory)[0].prompt == "Найди слабые места в сцене.", "an empty text is not kept")
                let id = prefsNow.actions[1].id
                st.renameAction(id, to: "  О плане  ")
                check(prefsNow.actions.map(\.name) == ["Слабые места", "О плане"] && AIActions.load(directory: app.settings.directory).map(\.name) == ["Слабые места", "О плане"], "an action can be renamed in Settings")
                st.removeAction(id)
                check(prefsNow.actions.map(\.name) == ["Слабые места"], "and deleted")
                st.reset(.aiPrompts)
                st.window.close(); spin(0.2)
            }
            prefsNow.updateActions { $0 = [] }
            check(AIActions.load(directory: app.settings.directory).isEmpty, "none left")
        }

        // The book's text size commands: a point at a time, inside the limits.
        do {
            let sizeNow = AppPreferences.shared.values
            app.appLarger()
            check(AppPreferences.shared.values.fontSize == sizeNow.fontSize + 1, "Larger Book Text makes the text a point bigger")
            app.appSmaller(); app.appSmaller()
            check(AppPreferences.shared.values.fontSize == sizeNow.fontSize - 1, "Smaller Book Text takes it back, and one step more")
            app.appUsualSize()
            check(AppPreferences.shared.values.fontSize == Preferences().fontSize, "Usual Book Text Size puts it back")
            for _ in 0..<40 { app.appLarger() }
            check(AppPreferences.shared.values.fontSize <= 36, "and it stops at its limit")
            app.appUsualSize(); spin(0.5)
        }

        // Shortcuts.
        do {
            app.showSettings(); spin(0.3)
            guard let st = app.settingsWindow else { check(false, "Settings opens for the shortcut checks"); return 1 }
            st.select(.shortcuts); spin(0.2)
            let page = st.shortcutsPage
            st.window.contentView?.layoutSubtreeIfNeeded()
            check(page.view.window != nil && page.view.frame.height > 250 && page.visibleRowCount > 30, "the Shortcuts page shows its list", "\(page.view.frame) rows \(page.visibleRowCount)")
            func menuItem(_ selector: String) -> NSMenuItem? {
                for top in NSApp.mainMenu?.items ?? [] { if let m = top.submenu?.items.first(where: { $0.action.map(NSStringFromSelector) == selector }) { return m } }
                return nil
            }
            check(app.shortcutCatalog.count > 30 && app.shortcutCatalog.contains { $0.id == "showExport" && $0.defaults == Shortcut("cmd+e") }, "the list has the app's own menu actions with their shortcuts", "\(app.shortcutCatalog.count)")
            check(menuItem("showExport")?.keyEquivalent == "e", "Export has ⌘E at first")
            page.select("showExport")
            check(page.set("showExport", to: Shortcut("opt+cmd+shift+x"), confirm: false) && menuItem("showExport")?.keyEquivalent == "x" && menuItem("showExport")?.keyEquivalentModifierMask.contains(.option) == true, "a new shortcut is in the menu at once")
            check(AppSettings(directory: app.settings.directory).preferences.shortcuts["showExport"] == "opt+shift+cmd+x", "and kept in settings.json")
            check(!page.set("showExport", to: Shortcut("cmd+c"), confirm: false) && !page.set("showExport", to: Shortcut("n"), confirm: false), "a standard command's keys and a bare letter are refused")
            check(page.set("showSnapshots", to: Shortcut("opt+cmd+shift+x"), confirm: false) && page.shortcut(of: "showExport") == nil && menuItem("showExport")?.keyEquivalent == "", "a key taken from another action leaves that one with none")
            check(page.set("showExport", to: nil, confirm: false) && AppSettings(directory: app.settings.directory).preferences.shortcuts["showExport"] == "none", "an action can have no shortcut")
            st.reset(.shortcuts); spin(0.2)
            check(AppSettings(directory: app.settings.directory).preferences.shortcuts.isEmpty && menuItem("showExport")?.keyEquivalent == "e" && menuItem("showSnapshots")?.keyEquivalent == "s", "Reset to Defaults gives them all back")
            st.window.close(); spin(0.2)
        }

        // The language of the interface.
        app.showSettings(); spin(0.3)
        guard let langSettings = app.settingsWindow else { check(false, "Settings opens for the language checks"); return 1 }
        check(L("Cancel") == "Cancel" && Lp("{n} scene", "{n} scenes", 21) == "21 scenes", "the interface starts in English (the checks keep to it)")
        check(["system", "en", "ru"].allSatisfy(langSettings.languageChoices.contains), "Settings lists the languages: the system's, English, and Russian (which comes with the app)", "\(langSettings.languageChoices)")
        langSettings.setChoice("language", "ru"); spin(0.5)
        check(L("Cancel") == "Отмена" && L("Open Book…") == "Открыть книгу…", "Russian: the texts change")
        check(Lp("{n} scene", "{n} scenes", 21) == "21 сцена" && Lp("{n} scene", "{n} scenes", 3) == "3 сцены" && Lp("{n} scene", "{n} scenes", 11) == "11 сцен", "and the plurals follow Russian's rule")
        let menuTitles = NSApp.mainMenu?.items.compactMap { $0.submenu?.title } ?? []
        check(menuTitles.contains("Файл") && menuTitles.contains("Правка") && menuTitles.contains("Вид") && menuTitles.contains("Раздел"), "the menus are made again in Russian at once", "\(menuTitles)")
        check(app.settingsWindow !== langSettings && app.settingsWindow?.window.title == "Настройки", "the Settings window is opened again in the new language")
        check(AppSettings(directory: app.settings.directory).preferences.interfaceLanguage == "ru", "and the choice is kept in settings.json")
        // A language of the user's own: a file.
        let ukFile = temp.appendingPathComponent("uk.json")
        try! Data("{\"code\":\"uk\",\"name\":\"Українська\",\"plural_rule\":\"ru\",\"strings\":{\"Cancel\":\"Скасувати\"}}".utf8).write(to: ukFile)
        let badFile = temp.appendingPathComponent("bad.json")
        try! Data("{ nope".utf8).write(to: badFile)
        check(app.settingsWindow?.installLanguage(from: badFile, quiet: true) == false && L("Cancel") == "Отмена", "a file that is not a language is refused and nothing changes")
        check(app.settingsWindow?.installLanguage(from: ukFile, quiet: true) == true, "a language file is installed")
        check(L("Cancel") == "Скасувати" && L("Open Book…") == "Open Book…", "its texts show, and a text it does not have shows in English")
        check(app.settingsWindow?.languageChoices.contains("uk") == true && FileManager.default.fileExists(atPath: app.settings.directory.appendingPathComponent("Languages/uk.json").path), "it is in the list, in the user's own folder")
        app.settingsWindow?.setChoice("language", "en"); spin(0.4)
        check(L("Cancel") == "Cancel" && (NSApp.mainMenu?.items.compactMap { $0.submenu?.title } ?? []).contains("File"), "English comes back")
        app.settingsWindow?.setChoice("language", "ru"); spin(0.3)
        app.settingsWindow?.reset(.general); spin(0.4)
        check(L("Cancel") == "Cancel" && prefs.values.interfaceLanguage == "en", "Reset to Defaults goes back to English")
        app.settingsWindow?.window.close(); spin(0.2)
        return nil
    }
}
