import AppKit
import QuillandCore

/// Settings… (⌘,): a list of sections on the left, the controls on the right, a search field on top. A change takes effect at once (no
/// Apply). Each section has Reset to Defaults. The sections here are the ones that change something the app does now.
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    enum Section: Int, CaseIterable {
        case general, appearance, writing, panels, ai, aiPrompts, shortcuts
        var title: String { [L("General"), L("Appearance"), L("Writing"), L("Panels"), L("AI"), L("AI Prompts"), L("Shortcuts")][rawValue] }
        var keywords: String {
            switch self {
            case .general: return L("general language folder books recent reopen start mode snapshot automatic minutes backup default")
            case .appearance: return L("appearance font size text line spacing reading width light dark theme sheet")
            case .writing: return L("writing typing corrections quotes dash dialogue ellipsis spelling spell check replacement autocorrect")
            case .panels: return L("panels right panel tabs section characters follow delay cursor")
            case .ai: return L("ai artificial intelligence model lm studio local server address context tokens connection")
            case .aiPrompts: return L("ai prompts instructions temperature wording continue writing consistency grammar synopsis chat collect model")
            case .shortcuts: return L("shortcuts keyboard keys menu commands key equivalents bindings")
            }
        }
    }

    let window: NSWindow
    var onClose: (() -> Void)?
    private var shown: [Section] = Section.allCases
    private(set) var current = Section.general
    private let list = Hover.rows(NSTableView())
    private let search = NSSearchField()
    private let host = NSView()
    private var pages: [Section: NSView] = [:]
    private let prefs = AppPreferences.shared
    private var loading = false
    let shortcutsPage = ShortcutsPage()
    private let promptView = NSTextView()
    private var promptTemperatureRow: NSStackView?
    private var promptLoading = false


    // The controls, by name (so that the checks and the resets can reach them).
    private(set) var controls: [String: NSControl] = [:]

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 700), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        build()
        select(.general)
        window.center()
    }

    func show() { window.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: Layout

    private func build() {
        search.placeholderString = L("Search")
        search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        list.addTableColumn(column)
        list.headerView = nil
        list.dataSource = self; list.delegate = self
        list.rowHeight = 28
        list.style = .sourceList
        list.setAccessibilityLabel(L("Sections"))
        let scroll = NSScrollView()
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        for v in [search, scroll, host] { v.translatesAutoresizingMaskIntoConstraints = false }
        let content = NSView()
        content.addSubview(search); content.addSubview(scroll); content.addSubview(host)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            search.widthAnchor.constraint(equalToConstant: 176),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.widthAnchor.constraint(equalToConstant: 200), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            host.topAnchor.constraint(equalTo: content.topAnchor), host.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: scroll.trailingAnchor), host.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        window.contentView = content
        for s in Section.allCases { pages[s] = page(for: s) }
        refreshAll()
    }

    private func caption(_ t: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: t)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func heading(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = .systemFont(ofSize: 18, weight: .semibold)
        return l
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal; s.spacing = 8; s.alignment = .centerY
        return s
    }

    private func check(_ id: String, _ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: action)
        controls[id] = b
        return b
    }

    private func popup(_ id: String, _ items: [(String, String)], _ action: Selector) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        for (title, key) in items { p.addItem(withTitle: title); p.lastItem?.representedObject = key }
        p.target = self; p.action = action
        controls[id] = p
        return p
    }

    private func stepperField(_ id: String, range: ClosedRange<Double>, step: Double, width: CGFloat = 60, _ action: Selector) -> NSStackView {
        let field = NSTextField()
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.target = self; field.action = action
        let stepper = NSStepper()
        stepper.minValue = range.lowerBound; stepper.maxValue = range.upperBound; stepper.increment = step
        stepper.target = self; stepper.action = action
        controls[id] = field
        controls[id + ".stepper"] = stepper
        return row([field, stepper])
    }

    private func page(for section: Section) -> NSView {
        let reset = NSButton(title: L("Reset to Defaults"), target: self, action: #selector(resetSection))
        reset.bezelStyle = .rounded
        var rows: [NSView] = [heading(section.title)]
        switch section {
        case .general:
            let folderLabel = NSTextField(labelWithString: "")
            folderLabel.lineBreakMode = .byTruncatingMiddle
            folderLabel.textColor = .secondaryLabelColor
            folderLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
            controls["newBookFolder"] = folderLabel
            rows += [
                row([NSTextField(labelWithString: L("Interface language")), popup("language", [(L("Like the system"), "system")], #selector(popupChanged(_:)))]),
                row([NSButton(title: L("Add Language…"), target: self, action: #selector(addLanguage)), NSButton(title: L("Export Template…"), target: self, action: #selector(exportTemplate)),
                     NSButton(title: L("Show Languages Folder"), target: self, action: #selector(showLanguagesFolder))]),
                caption(L("Menus change at once; windows that are already open take the language when they are opened again. A language is one text file: Export Template… writes the list of texts to translate.")),
                caption(L("Where New Book proposes to keep books")),
                row([folderLabel, NSButton(title: L("Choose…"), target: self, action: #selector(chooseNewBookFolder)), NSButton(title: L("Documents"), target: self, action: #selector(useDocumentsFolder))]),
                row([NSTextField(labelWithString: L("Recent books to remember")), stepperField("recent", range: 1...30, step: 1, #selector(stepperChanged(_:)))]),
                check("reopen", L("Reopen the last book when Quilland starts"), #selector(boxChanged(_:))),
                row([NSTextField(labelWithString: L("A book with no remembered view opens in")), popup("mode", [("Panels", "panels"), ("Book", "book"), ("Compare", "compare")], #selector(popupChanged(_:)))]),
                caption(L("Snapshots")),
                check("autoSnapshots", L("Take snapshots by themselves while something changes"), #selector(boxChanged(_:))),
                row([NSTextField(labelWithString: L("Every")), stepperField("snapshotMinutes", range: 1...240, step: 5, #selector(stepperChanged(_:))), NSTextField(labelWithString: L("minutes"))]),
            ]
        case .appearance:
            let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            let families = (["Georgia", "Palatino", "Times New Roman", "Baskerville", "Charter", "Iowan Old Style", "Hoefler Text", "New York", "Helvetica Neue", "Avenir Next", "Menlo"]).filter { NSFontManager.shared.availableFontFamilies.contains($0) }
            for f in families { fontPopup.addItem(withTitle: f); fontPopup.lastItem?.representedObject = f }
            fontPopup.target = self; fontPopup.action = #selector(popupChanged(_:))
            controls["font"] = fontPopup
            let sample = NSTextField(wrappingLabelWithString: "Анна вышла на платформу станции. The morning was cold and the lights were low.")
            controls["sample"] = sample
            rows += [
                row([NSTextField(labelWithString: L("Font")), fontPopup]),
                row([NSTextField(labelWithString: L("Text size")), stepperField("fontSize", range: 10...36, step: 1, #selector(stepperChanged(_:)))]),
                row([NSTextField(labelWithString: L("Line spacing")), stepperField("lineSpacing", range: 1.0...2.2, step: 0.05, #selector(stepperChanged(_:)))]),
                row([NSTextField(labelWithString: L("Reading width of a sheet")), stepperField("readingWidth", range: 420...1100, step: 20, width: 70, #selector(stepperChanged(_:))), NSTextField(labelWithString: L("points"))]),
                row([NSTextField(labelWithString: L("Appearance")), popup("appearance", [(L("Like the system"), "system"), (L("Light"), "light"), (L("Dark"), "dark")], #selector(popupChanged(_:)))]),
                caption(L("How the text looks")), sample,
            ]
        case .writing:
            rows += [
                check("corrections", L("Correct my typing as I write"), #selector(boxChanged(_:))),
                row([NSTextField(labelWithString: "      "), check("smartQuotes", L("Quotes by the book's language: «…» for Russian, “…” for English"), #selector(boxChanged(_:)))]),
                row([NSTextField(labelWithString: "      "), check("dashes", L("A dash for “ - ” (with a non-breaking space before it) and for “--”"), #selector(boxChanged(_:)))]),
                row([NSTextField(labelWithString: "      "), check("dialogueDash", L("A dialogue dash for “- ” at the start of a paragraph"), #selector(boxChanged(_:)))]),
                row([NSTextField(labelWithString: "      "), check("ellipsis", L("An ellipsis for “...” (off: three dots stay three dots)"), #selector(boxChanged(_:)))]),
                row([NSTextField(labelWithString: L("Quotes")), popup("quoteStyle", [(L("Follow the book's language"), "auto"), (L("« » (Russian)"), "ru"), (L("“ ” (English)"), "en")], #selector(popupChanged(_:)))]),
                caption(L("Spelling")),
                check("spelling", L("Check spelling while typing"), #selector(boxChanged(_:))),
                check("textReplacement", L("Use the system's text replacements (System Settings ▸ Keyboard)"), #selector(boxChanged(_:))),
                caption(L("One ⌘Z takes back a correction just made.")),
            ]
        case .panels:
            rows += [
                caption(L("Tabs of the right panel")),
                check("tab.section", L("Section"), #selector(boxChanged(_:))),
                check("tab.characters", L("Characters"), #selector(boxChanged(_:))),
                check("tab.world", L("World"), #selector(boxChanged(_:))),
                check("tab.events", L("Events"), #selector(boxChanged(_:))),
                check("tab.chat", L("Chat"), #selector(boxChanged(_:))),
                row([NSTextField(labelWithString: L("The panel follows the cursor after")), stepperField("followDelay", range: 0.3...6, step: 0.1, #selector(stepperChanged(_:))), NSTextField(labelWithString: L("seconds"))]),
            ]
        case .ai:
            let address = NSTextField()
            address.placeholderString = AIConnection.defaultAddress
            address.widthAnchor.constraint(equalToConstant: 260).isActive = true
            address.delegate = self
            controls["aiAddress"] = address
            let status = NSTextField(wrappingLabelWithString: "")
            status.font = .systemFont(ofSize: 12)
            status.preferredMaxLayoutWidth = 480
            controls["aiStatus"] = status
            let test = NSButton(title: L("Test Connection"), target: self, action: #selector(testAI))
            test.bezelStyle = .rounded
            controls["aiTest"] = test
            rows += [
                check("aiEnabled", L("Use the AI actions"), #selector(boxChanged(_:))),
                caption(L("The AI runs on this computer, in LM Studio. Nothing is sent anywhere else, and nothing it suggests is applied until you accept it.")),
                row([NSTextField(labelWithString: L("LM Studio address")), address]),
                row([NSTextField(labelWithString: L("Model")), popup("aiModel", [(L("The loaded one"), "")], #selector(popupChanged(_:))), test]),
                row([NSTextField(labelWithString: L("Tokens read at once")), stepperField("aiContext", range: 0...262144, step: 1024, width: 80, #selector(stepperChanged(_:)))]),
                caption(L("0 means what the server says. A smaller number makes the actions read less at a time.")),
                status,
            ]
        case .aiPrompts:
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.target = self; popup.action = #selector(promptChosen)
            popup.widthAnchor.constraint(equalToConstant: 330).isActive = true
            controls["promptChoice"] = popup
            let note = NSTextField(wrappingLabelWithString: "")
            note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; note.preferredMaxLayoutWidth = 520
            controls["promptNote"] = note
            promptView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            promptView.isRichText = false; promptView.allowsUndo = true
            promptView.isVerticallyResizable = true; promptView.autoresizingMask = [.width]
            promptView.textContainerInset = NSSize(width: 6, height: 6)
            promptView.delegate = self
            promptView.setAccessibilityLabel(L("The prompt"))
            let promptScroll = NSScrollView()
            promptScroll.documentView = promptView
            promptScroll.hasVerticalScroller = true; promptScroll.borderType = .bezelBorder
            promptScroll.translatesAutoresizingMaskIntoConstraints = false
            promptScroll.widthAnchor.constraint(equalToConstant: 540).isActive = true
            promptScroll.heightAnchor.constraint(equalToConstant: 230).isActive = true
            let status = NSTextField(labelWithString: "")
            status.font = .systemFont(ofSize: 11)
            controls["promptStatus"] = status
            let resetOne = NSButton(title: L("Back to the Built-in Text"), target: self, action: #selector(resetPrompt))
            resetOne.bezelStyle = .rounded; resetOne.controlSize = .small
            controls["promptResetOne"] = resetOne
            let rename = NSButton(title: L("Rename…"), target: self, action: #selector(renameActionPressed))
            let delete = NSButton(title: L("Delete"), target: self, action: #selector(deleteActionPressed))
            for b in [rename, delete] { b.bezelStyle = .rounded; b.controlSize = .small }
            controls["promptRename"] = rename; controls["promptDelete"] = delete
            let temperatureRow = row([NSTextField(labelWithString: L("Temperature")), stepperField("promptTemperature", range: 0...2, step: 0.05, #selector(promptTemperatureChanged(_:))),
                                      NSTextField(labelWithString: L("0 is exact and repeatable, 1 and more is freer"))])
            promptTemperatureRow = temperatureRow
            rows += [
                caption(L("The instructions the AI actions send to the model, in your words. A change counts at once. {language} stands for the language of the book. Prompts you saved from the Chat are here too, without the mark “System”: they are in the AI menu, under Actions.")),
                row([NSTextField(labelWithString: L("Prompt")), popup, rename, delete]),
                note, promptScroll, row([status, resetOne]), temperatureRow,
            ]
        case .shortcuts:
            rows += [shortcutsPage.view]
        }
        rows.append(reset)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.setCustomSpacing(20, after: rows[0])
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 26, bottom: 20, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: view.topAnchor), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor)])
        return view
    }

    // MARK: Sections

    func select(_ section: Section) {
        current = section
        host.subviews.forEach { $0.removeFromSuperview() }
        guard let page = pages[section] else { return }
        page.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(page)
        NSLayoutConstraint.activate([page.topAnchor.constraint(equalTo: host.topAnchor), page.bottomAnchor.constraint(equalTo: host.bottomAnchor), page.leadingAnchor.constraint(equalTo: host.leadingAnchor), page.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
        if let row = shown.firstIndex(of: section) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    var visibleSections: [Section] { shown }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let l = NSTextField(labelWithString: shown[row].title)
        l.font = .systemFont(ofSize: 13)
        return CenteredCell(l, leading: 6)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = list.selectedRow
        if row >= 0, shown.indices.contains(row), shown[row] != current { select(shown[row]) }
    }

    /// The search field narrows the list of sections to those that have the word.
    func controlTextDidChange(_ obj: Notification) { filter(search.stringValue) }

    func filter(_ text: String) {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        shown = needle.isEmpty ? Section.allCases : Section.allCases.filter { ($0.title + " " + $0.keywords).lowercased().contains(needle) }
        list.reloadData()
        if let first = shown.first, !shown.contains(current) { select(first) } else if let row = shown.firstIndex(of: current) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    // MARK: Showing the values

    private func set(_ id: String, number v: Double) {
        (controls[id] as? NSTextField)?.stringValue = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
        (controls[id + ".stepper"] as? NSStepper)?.doubleValue = v
    }

    private func select(_ id: String, key: String) {
        guard let p = controls[id] as? NSPopUpButton, let i = p.itemArray.firstIndex(where: { ($0.representedObject as? String) == key }) else { return }
        p.selectItem(at: i)
    }

    private func state(_ id: String, _ on: Bool) { (controls[id] as? NSButton)?.state = on ? .on : .off }

    /// Puts the current values into the controls (after a change or a reset).
    func refreshAll() {
        loading = true
        defer { loading = false }
        let v = prefs.values, a = prefs.autocorrect
        shortcutsPage.refresh()
        (controls["newBookFolder"] as? NSTextField)?.stringValue = v.newBookFolder ?? "Documents"
        set("recent", number: Double(v.recentLimit))
        state("reopen", v.reopenLastBook)
        refreshLanguages()
        select("mode", key: v.defaultMode)
        state("autoSnapshots", v.autoSnapshots)
        set("snapshotMinutes", number: Double(v.snapshotMinutes))
        controls["snapshotMinutes"]?.isEnabled = v.autoSnapshots
        controls["snapshotMinutes.stepper"]?.isEnabled = v.autoSnapshots
        select("font", key: v.fontName)
        set("fontSize", number: v.fontSize)
        set("lineSpacing", number: v.lineSpacing)
        set("readingWidth", number: v.readingWidth)
        select("appearance", key: v.appearance)
        if let sample = controls["sample"] as? NSTextField {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = CGFloat(v.lineSpacing)
            sample.attributedStringValue = NSAttributedString(string: "Анна вышла на платформу станции. The morning was cold and the lights were low.",
                                                              attributes: [.font: Fonts.base(size: CGFloat(v.fontSize)), .paragraphStyle: style, .foregroundColor: NSColor.labelColor])
        }
        state("corrections", a.enabled)
        state("smartQuotes", a.smartQuotes); state("dashes", a.dashes); state("dialogueDash", a.dialogueDash); state("ellipsis", a.ellipsis)
        for id in ["smartQuotes", "dashes", "dialogueDash", "ellipsis", "quoteStyle"] { controls[id]?.isEnabled = a.enabled }
        select("quoteStyle", key: a.quoteStyle)
        state("spelling", v.checkSpelling)
        state("textReplacement", v.systemTextReplacement)
        state("tab.section", v.panelTabs.contains("section"))
        state("tab.characters", v.panelTabs.contains("characters"))
        state("tab.world", v.panelTabs.contains("world"))
        state("tab.events", v.panelTabs.contains("events"))
        state("tab.chat", v.panelTabs.contains("chat"))
        set("followDelay", number: v.followDelay)
        state("aiEnabled", v.aiEnabled)
        (controls["aiAddress"] as? NSTextField).map { if $0.currentEditor() == nil { $0.stringValue = v.aiAddress } }
        set("aiContext", number: Double(v.aiContext))
        refreshAIModels()
        refreshPrompt()
        for id in ["aiAddress", "aiModel", "aiTest", "aiContext", "aiContext.stepper"] { controls[id]?.isEnabled = v.aiEnabled }
    }

    // MARK: AI prompts

    /// The prompt chosen in the popup: a system one (by its key) or one saved from the Chat (by the action's id).
    private enum PromptChoice: Equatable { case system(String), action(String) }
    private var promptChoice: PromptChoice = .system(AIPrompts.entries[0].key)

    /// The key of the system prompt shown (empty when one of the author's is).
    var shownPromptKey: String { if case .system(let k) = promptChoice { return k }; return "" }
    var shownActionID: String? { if case .action(let id) = promptChoice { return id }; return nil }
    /// What the popup lists, as the author sees it.
    var promptChoiceTitles: [String] { (controls["promptChoice"] as? NSPopUpButton)?.itemArray.filter { !$0.isSeparatorItem }.map(\.title) ?? [] }

    /// The popup: the system prompts, marked, then the author's own, with their names.
    private func rebuildPromptPopup() {
        guard let popup = controls["promptChoice"] as? NSPopUpButton else { return }
        popup.removeAllItems()
        for e in AIPrompts.entries {
            popup.addItem(withTitle: e.title + "  ·  " + L("System"))
            popup.lastItem?.representedObject = "sys:" + e.key
        }
        if !prefs.actions.isEmpty {
            popup.menu?.addItem(.separator())
            for a in prefs.actions {
                let name = a.name.count > 60 ? String(a.name.prefix(60)) + "…" : a.name
                popup.addItem(withTitle: name)
                popup.lastItem?.representedObject = "act:" + a.id
                popup.lastItem?.toolTip = a.prompt.count > 300 ? String(a.prompt.prefix(300)) + "…" : a.prompt
            }
        }
        // The choice is kept when it is still there; a deleted action leaves the first system prompt.
        var wanted: String
        switch promptChoice { case .system(let k): wanted = "sys:" + k; case .action(let id): wanted = "act:" + id }
        if let i = popup.itemArray.firstIndex(where: { ($0.representedObject as? String) == wanted }) { popup.selectItem(at: i) }
        else { promptChoice = .system(AIPrompts.entries[0].key); popup.selectItem(at: 0) }
    }

    /// Shows the chosen prompt: the author's wording or the built-in one for a system prompt, the saved text for one of the author's own.
    func refreshPrompt() {
        guard controls["promptChoice"] != nil else { return }
        rebuildPromptPopup()
        let status = controls["promptStatus"] as? NSTextField
        promptLoading = true
        defer { promptLoading = false }
        func show(_ text: String) { if promptView.string != text, promptView.window?.firstResponder !== promptView { promptView.string = text } }
        switch promptChoice {
        case .system(let key):
            guard let entry = AIPrompts.entries.first(where: { $0.key == key }) else { return }
            let own = prefs.promptSettings.prompts[key]
            show(own ?? AIPrompts.template(for: key))
            (controls["promptNote"] as? NSTextField)?.stringValue = entry.note
            status?.stringValue = own == nil ? L("The built-in text") : L("Your own text")
            status?.textColor = own == nil ? .secondaryLabelColor : .systemOrange
            controls["promptResetOne"]?.isHidden = false
            controls["promptResetOne"]?.isEnabled = own != nil
            controls["promptRename"]?.isEnabled = false; controls["promptDelete"]?.isEnabled = false
            promptTemperatureRow?.isHidden = entry.temperature == nil
            if let t = entry.temperature { set("promptTemperature", number: prefs.promptSettings.temperatures[key] ?? t) }
        case .action(let id):
            guard let action = prefs.actions.first(where: { $0.id == id }) else { return }
            show(action.prompt)
            let kinds = action.attach.map { L($0) }.joined(separator: ", ")
            (controls["promptNote"] as? NSTextField)?.stringValue = kinds.isEmpty ? L("Saved from the Chat. Nothing is attached when it runs.") : L("Saved from the Chat. When it runs, it attaches: {kinds}.", ["kinds": kinds])
            status?.stringValue = L("Your prompt")
            status?.textColor = .systemOrange
            controls["promptResetOne"]?.isHidden = true
            controls["promptRename"]?.isEnabled = true; controls["promptDelete"]?.isEnabled = true
            promptTemperatureRow?.isHidden = true
        }
    }

    @objc private func promptChosen() {
        guard let raw = (controls["promptChoice"] as? NSPopUpButton)?.selectedItem?.representedObject as? String else { return }
        promptChoice = raw.hasPrefix("act:") ? .action(String(raw.dropFirst(4))) : .system(String(raw.dropFirst(4)))
        promptView.string = ""
        refreshPrompt()
    }

    /// Chooses a prompt (for the checks).
    func choosePrompt(key: String) { promptChoice = .system(key); promptView.string = ""; refreshPrompt() }
    func chooseAction(_ id: String) { promptChoice = .action(id); promptView.string = ""; refreshPrompt() }

    var chosenActionID: String? { shownActionID }

    @objc private func deleteActionPressed() { removeAction(shownActionID) }

    func removeAction(_ id: String?) {
        guard let id else { return }
        prefs.updateActions { $0.removeAll { $0.id == id } }
        if shownActionID == id { promptChoice = .system(AIPrompts.entries[0].key); promptView.string = "" }
        refreshPrompt()
    }

    @objc private func renameActionPressed() {
        guard let id = shownActionID, let action = prefs.actions.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = L("Rename the action")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = action.name
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        renameAction(id, to: field.stringValue)
    }

    func renameAction(_ id: String, to name: String) {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        prefs.updateActions { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].name = text } }
        refreshPrompt()
    }

    func textDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextView) === promptView, !promptLoading else { return }
        if let id = shownActionID { setActionPrompt(promptView.string, id: id) } else { setPrompt(promptView.string) }
    }

    /// The text of one of the author's own prompts. An empty text is not kept (the prompt would do nothing).
    func setActionPrompt(_ text: String, id: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        prefs.updateActions { list in if let i = list.firstIndex(where: { $0.id == id }) { list[i].prompt = text } }
        let a = prefs.actions.first { $0.id == id }
        if let tip = a?.prompt { (controls["promptChoice"] as? NSPopUpButton)?.selectedItem?.toolTip = String(tip.prefix(300)) }
    }

    /// Keeps the author's wording of the shown prompt; the built-in text itself is not kept as an override.
    func setPrompt(_ text: String, key: String? = nil) {
        let k = key ?? shownPromptKey
        guard !k.isEmpty else { return }
        let same = text.trimmingCharacters(in: .whitespacesAndNewlines) == AIPrompts.template(for: k).trimmingCharacters(in: .whitespacesAndNewlines)
        prefs.updatePrompts { s in if same || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { s.prompts.removeValue(forKey: k) } else { s.prompts[k] = text } }
        if key != nil { promptChoice = .system(k); promptView.string = ""; refreshPrompt() } else { refreshPromptStatus() }
    }

    private func refreshPromptStatus() {
        guard !shownPromptKey.isEmpty else { return }
        let own = prefs.promptSettings.prompts[shownPromptKey]
        let status = controls["promptStatus"] as? NSTextField
        status?.stringValue = own == nil ? L("The built-in text") : L("Your own text")
        status?.textColor = own == nil ? .secondaryLabelColor : .systemOrange
        controls["promptResetOne"]?.isEnabled = own != nil
    }

    @objc private func resetPrompt() {
        let key = shownPromptKey
        guard !key.isEmpty else { return }
        prefs.updatePrompts { $0.prompts.removeValue(forKey: key) }
        promptView.string = ""
        refreshPrompt()
    }

    @objc private func promptTemperatureChanged(_ sender: NSControl) {
        guard !loading else { return }
        let value = (sender as? NSStepper)?.doubleValue ?? (sender as? NSTextField).flatMap { Double($0.stringValue.replacingOccurrences(of: ",", with: ".")) }
        setTemperature(value)
    }

    func setTemperature(_ value: Double?, key: String? = nil) {
        let k = key ?? shownPromptKey
        guard let entry = AIPrompts.entries.first(where: { $0.key == k }), let base = entry.temperature else { return }
        prefs.updatePrompts { s in
            if let v = value, (0...2).contains(v), v != base { s.temperatures[k] = v } else { s.temperatures.removeValue(forKey: k) }
        }
        refreshPrompt()
    }

    // MARK: AI

    /// The model popup: "the loaded one", then the models the server has (as last asked), and the author's choice even if the server did not list it.
    private func refreshAIModels() {
        guard let p = controls["aiModel"] as? NSPopUpButton else { return }
        let chosen = prefs.values.aiModel
        p.removeAllItems()
        p.addItem(withTitle: L("The loaded one")); p.lastItem?.representedObject = ""
        var names = AIService.shared.status?.models.map(\.id) ?? []
        if !chosen.isEmpty && !names.contains(chosen) { names.append(chosen) }
        for n in names { p.addItem(withTitle: n); p.lastItem?.representedObject = n }
        select("aiModel", key: chosen)
        (controls["aiStatus"] as? NSTextField)?.attributedStringValue = Self.describeAI(AIService.shared)
    }

    /// The state of the connection, to be seen at a glance: a coloured dot and a headline, then what is known about the model.
    static func describeAI(_ service: AIService) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        func headline(_ text: String, _ color: NSColor) -> NSMutableAttributedString {
            let s = NSMutableAttributedString(string: "● ", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: color])
            s.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor]))
            return s
        }
        if !service.isEnabled { return headline(L("The AI is switched off"), .systemGray) }
        if service.checking { return headline(L("Asking LM Studio…"), .systemOrange) }
        guard let status = service.status else { return NSAttributedString(string: L("Not checked yet. Test Connection asks LM Studio."), attributes: body) }
        guard status.reachable, let info = status.info else {
            let s = headline(L("No connection"), .systemRed)
            s.append(NSAttributedString(string: "\n" + status.message, attributes: body))
            return s
        }
        let s = headline(status.loaded ? L("Connected to LM Studio") : L("Connected, the model is not loaded"), status.loaded ? .systemGreen : .systemOrange)
        let name = info.displayName.isEmpty ? info.id : info.displayName
        var details = [(L("Model"), name == info.id ? info.id : "\(name)  (\(info.id))")]
        var facts = [info.params, info.quantization].filter { !$0.isEmpty }
        if let bytes = info.sizeBytes { facts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)) }
        if !facts.isEmpty { details.append((L("Size"), facts.joined(separator: " · "))) }
        let number = NumberFormatter.localizedString(from: NSNumber(value: status.context), number: .decimal)
        details.append((L("Reads at once"), Lp("{n} token", "{n} tokens", status.context).replacingOccurrences(of: String(status.context), with: number)))
        if !status.loaded { details.append(("", L("LM Studio loads it when the first request comes."))) }
        for (label, value) in details {
            s.append(NSAttributedString(string: "\n", attributes: body))
            if !label.isEmpty { s.append(NSAttributedString(string: label + ":  ", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.tertiaryLabelColor])) }
            s.append(NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]))
        }
        return s
    }

    @objc private func testAI() {
        AIService.shared.refresh { [weak self] _ in self?.refreshAll() }
        refreshAll()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === controls["aiAddress"] else { return }
        prefs.update { $0.aiAddress = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        AIService.shared.refresh { [weak self] _ in self?.refreshAll() }
        refreshAll()
    }

    // MARK: Changes

    @objc private func stepperChanged(_ sender: NSControl) {
        guard !loading else { return }
        guard let id = controls.first(where: { $0.value === sender })?.key else { return }
        let base = id.replacingOccurrences(of: ".stepper", with: "")
        let value = (sender as? NSStepper)?.doubleValue ?? (sender as? NSTextField).flatMap { Double($0.stringValue.replacingOccurrences(of: ",", with: ".")) }
        guard let value else { refreshAll(); return }
        setNumber(base, value)
    }

    /// Changes a number setting (the field, the stepper, and the checks all come here).
    func setNumber(_ id: String, _ value: Double) {
        prefs.update { p in
            switch id {
            case "recent": p.recentLimit = Int(value)
            case "snapshotMinutes": p.snapshotMinutes = Int(value)
            case "fontSize": p.fontSize = value
            case "lineSpacing": p.lineSpacing = value
            case "readingWidth": p.readingWidth = value
            case "followDelay": p.followDelay = value
            case "aiContext": p.aiContext = Int(value)
            default: break
            }
        }
        refreshAll()
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard !loading, let key = sender.selectedItem?.representedObject as? String, let id = controls.first(where: { $0.value === sender })?.key else { return }
        setChoice(id, key)
    }

    func setChoice(_ id: String, _ key: String) {
        switch id {
        case "mode": prefs.update { $0.defaultMode = key }
        case "language": prefs.update { $0.interfaceLanguage = key }
        case "font": prefs.update { $0.fontName = key }
        case "appearance": prefs.update { $0.appearance = key }
        case "aiModel": prefs.update { $0.aiModel = key }; AIService.shared.refresh()
        case "quoteStyle": prefs.updateAutocorrect { $0.quoteStyle = key }
        default: break
        }
        refreshAll()
    }

    @objc private func boxChanged(_ sender: NSButton) {
        guard !loading, let id = controls.first(where: { $0.value === sender })?.key else { return }
        setFlag(id, sender.state == .on)
    }

    func setFlag(_ id: String, _ on: Bool) {
        switch id {
        case "reopen": prefs.update { $0.reopenLastBook = on }
        case "autoSnapshots": prefs.update { $0.autoSnapshots = on }
        case "corrections": prefs.updateAutocorrect { $0.enabled = on }
        case "smartQuotes": prefs.updateAutocorrect { $0.smartQuotes = on }
        case "dashes": prefs.updateAutocorrect { $0.dashes = on }
        case "dialogueDash": prefs.updateAutocorrect { $0.dialogueDash = on }
        case "ellipsis": prefs.updateAutocorrect { $0.ellipsis = on }
        case "spelling": prefs.update { $0.checkSpelling = on }
        case "aiEnabled": prefs.update { $0.aiEnabled = on }; AIService.shared.refresh()
        case "textReplacement": prefs.update { $0.systemTextReplacement = on }
        case "tab.section", "tab.characters", "tab.world", "tab.events", "tab.chat":
            let name = String(id.dropFirst(4))
            prefs.update { p in
                var tabs = p.panelTabs.filter { $0 != name }
                if on { tabs.append(name) }
                // At least one tab stays; the order is the panel's own.
                let ordered = ["section", "characters", "world", "events", "chat"].filter { tabs.contains($0) }
                p.panelTabs = ordered.isEmpty ? [name] : ordered
            }
        default: break
        }
        refreshAll()
    }

    // MARK: Languages

    /// The choices of the language popup: the system's, English, and every language installed.
    private func refreshLanguages() {
        guard let popup = controls["language"] as? NSPopUpButton else { return }
        popup.removeAllItems()
        popup.addItem(withTitle: L("Like the system")); popup.lastItem?.representedObject = "system"
        popup.addItem(withTitle: "English"); popup.lastItem?.representedObject = "en"
        for language in Localizer.shared.available() where language.code.lowercased() != "en" {
            popup.addItem(withTitle: language.name); popup.lastItem?.representedObject = language.code.lowercased()
        }
        select("language", key: prefs.values.interfaceLanguage.lowercased())
    }

    var languageChoices: [String] { (controls["language"] as? NSPopUpButton)?.itemArray.compactMap { $0.representedObject as? String } ?? [] }

    @objc private func addLanguage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.message = L("Choose a language file (.json)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = installLanguage(from: url)
    }

    /// Checks a language file, puts it in the user's folder and switches to it. Returns false (after telling the author why) if it is not usable.
    @discardableResult
    func installLanguage(from url: URL, quiet: Bool = false) -> Bool {
        guard let folder = prefs.userLanguagesDirectory else { return false }
        do {
            let language = try LanguageFiles.install(url, into: folder)
            prefs.update { $0.interfaceLanguage = language.code.lowercased() }
            refreshAll()
            return true
        } catch {
            if !quiet {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L("That language file cannot be used")
                alert.informativeText = "\(error)"
                alert.runModal()
            }
            return false
        }
    }

    @objc private func exportTemplate() {
        guard let template = AppPreferences.bundledLanguagesDirectory?.appendingPathComponent("template.json") else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "quilland-language.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LanguageFiles.writeTemplate(from: template, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = L("The template could not be written")
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }

    @objc private func showLanguagesFolder() {
        guard let folder = prefs.userLanguagesDirectory else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func chooseNewBookFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setNewBookFolder(url.path)
    }

    func setNewBookFolder(_ path: String?) {
        prefs.update { $0.newBookFolder = path }
        refreshAll()
    }

    @objc private func useDocumentsFolder() { setNewBookFolder(nil) }

    /// Reset to Defaults for the section shown: its settings only.
    @objc private func resetSection() { reset(current) }

    func reset(_ section: Section) {
        let d = Preferences()
        switch section {
        case .general:
            prefs.update { $0.interfaceLanguage = d.interfaceLanguage; $0.defaultMode = d.defaultMode; $0.recentLimit = d.recentLimit; $0.reopenLastBook = d.reopenLastBook
                $0.autoSnapshots = d.autoSnapshots; $0.snapshotMinutes = d.snapshotMinutes; $0.newBookFolder = d.newBookFolder }
        case .appearance:
            prefs.update { $0.fontName = d.fontName; $0.fontSize = d.fontSize; $0.lineSpacing = d.lineSpacing; $0.readingWidth = d.readingWidth; $0.appearance = d.appearance }
        case .writing:
            prefs.update { $0.checkSpelling = d.checkSpelling; $0.systemTextReplacement = d.systemTextReplacement }
            prefs.updateAutocorrect { $0 = AutocorrectSettings() }
        case .panels:
            prefs.update { $0.panelTabs = d.panelTabs; $0.followDelay = d.followDelay }
        case .ai:
            prefs.update { $0.aiEnabled = d.aiEnabled; $0.aiAddress = d.aiAddress; $0.aiModel = d.aiModel; $0.aiContext = d.aiContext }
            AIService.shared.refresh()
        case .aiPrompts:
            prefs.updatePrompts { $0 = AIPromptSettings() }
        case .shortcuts:
            prefs.update { $0.shortcuts = [:] }
        }
        refreshAll()
    }
}
