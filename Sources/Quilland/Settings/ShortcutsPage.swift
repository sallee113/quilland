import AppKit
import QuillandCore

extension Shortcut {
    /// What an NSMenuItem takes: the key and the modifier flags.
    var menuKey: (key: String, modifiers: NSEvent.ModifierFlags) {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if option { flags.insert(.option) }
        if shift { flags.insert(.shift) }
        if control { flags.insert(.control) }
        func fn(_ code: Int) -> String { String(UnicodeScalar(UInt32(code))!) }
        let named: [String: String] = ["return": "\r", "tab": "\t", "space": " ", "delete": "\u{8}", "escape": "\u{1b}",
                                       "up": fn(NSUpArrowFunctionKey), "down": fn(NSDownArrowFunctionKey), "left": fn(NSLeftArrowFunctionKey), "right": fn(NSRightArrowFunctionKey)]
        if let k = named[key] { return (k, flags) }
        if key.hasPrefix("f"), key.count > 1, let n = Int(key.dropFirst()), (1...12).contains(n) { return (fn(NSF1FunctionKey + n - 1), flags) }
        return (key, flags)
    }

    /// From a menu item's key and flags (the defaults written in the menu code).
    init?(keyEquivalent key: String, modifiers: NSEvent.ModifierFlags) {
        guard !key.isEmpty else { return nil }
        let names: [String: String] = ["\r": "return", "\t": "tab", " ": "space", "\u{8}": "delete", "\u{1b}": "escape",
                                       String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!): "up", String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!): "down",
                                       String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!): "left", String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!): "right"]
        self.init(key: names[key] ?? key.lowercased(), command: modifiers.contains(.command), option: modifiers.contains(.option), shift: modifiers.contains(.shift), control: modifiers.contains(.control))
    }

    /// The combination of a key press (for recording a new shortcut). Nil for a key that is not a character or a known key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        let codes: [UInt16: String] = [36: "return", 76: "return", 48: "tab", 49: "space", 51: "delete", 117: "delete", 53: "escape", 123: "left", 124: "right", 125: "down", 126: "up",
                                       122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"]
        var key = codes[event.keyCode]
        if key == nil, let c = event.charactersIgnoringModifiers?.lowercased(), c.count == 1, let scalar = c.unicodeScalars.first, scalar.value >= 0x20, !(0xF700...0xF8FF).contains(scalar.value) { key = c }
        guard let key else { return nil }
        self.init(key: key, command: flags.contains(.command), option: flags.contains(.option), shift: flags.contains(.shift), control: flags.contains(.control))
    }
}

/// A box that takes the next key combination typed into it (key equivalents too, so ⌘N does not fire the menu).
final class ShortcutRecorderView: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var captured: Shortcut?
    var onChange: ((Shortcut) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.stringValue = L("Press the new shortcut")
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([label.centerYAnchor.constraint(equalTo: centerYAnchor), label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { take(event) }
    override func keyDown(with event: NSEvent) { _ = take(event) }

    @discardableResult
    func take(_ event: NSEvent) -> Bool {
        guard let s = Shortcut(event: event) else { return true }
        capture(s)
        return true
    }

    func capture(_ s: Shortcut) {
        captured = s
        label.stringValue = s.display
        label.textColor = s.isUsable ? .labelColor : .systemRed
        onChange?(s)
    }
}

/// The Shortcuts section of Settings: every action of the menus with its shortcut; Change…, Clear and Default for the chosen one.
final class ShortcutsPage: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSView()
    private let table = NSTableView()
    private let changeButton = NSButton(title: L("Change…"), target: nil, action: nil)
    private let clearButton = NSButton(title: L("Clear"), target: nil, action: nil)
    private let defaultButton = NSButton(title: L("Default"), target: nil, action: nil)
    private let note = NSTextField(wrappingLabelWithString: "")
    private var catalog: [(id: String, title: String, defaults: Shortcut?)] = []
    private let prefs = AppPreferences.shared

    override init() {
        super.init()
        for (id, title, width) in [("action", L("Action"), 360), ("shortcut", L("Shortcut"), 120)] as [(String, String, CGFloat)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title; c.width = width
            table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self
        table.rowHeight = 22
        table.setAccessibilityLabel(L("Shortcuts"))
        table.doubleAction = #selector(changePressed); table.target = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 520).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        for (b, a) in [(changeButton, #selector(changePressed)), (clearButton, #selector(clearPressed)), (defaultButton, #selector(defaultPressed))] {
            b.bezelStyle = .rounded; b.controlSize = .small; b.target = self; b.action = a
        }
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.stringValue = L("Choose an action, then Change… and press the new shortcut. Standard commands such as ⌘C and ⌘Z keep their keys.")
        note.preferredMaxLayoutWidth = 520
        let buttons = NSStackView(views: [changeButton, clearButton, defaultButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [note, scroll, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.translatesAutoresizingMaskIntoConstraints = false
        // The page is as tall as its content, so that the page it sits in gives it room.
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: view.topAnchor), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                     stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        refresh()
    }

    func refresh() {
        let keep = selectedID
        catalog = (NSApp.delegate as? AppDelegate)?.shortcutCatalog ?? []
        table.reloadData()
        if let keep, let row = catalog.firstIndex(where: { $0.id == keep }) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        updateButtons()
    }

    /// How many rows the list can show at its size (for the checks: the page must be seen).
    var visibleRowCount: Int { catalog.count }

    var selectedID: String? { table.selectedRow >= 0 && table.selectedRow < catalog.count ? catalog[table.selectedRow].id : nil }

    func select(_ id: String) {
        if let row = catalog.firstIndex(where: { $0.id == id }) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        updateButtons()
    }

    private func updateButtons() {
        let on = selectedID != nil
        changeButton.isEnabled = on; clearButton.isEnabled = on
        defaultButton.isEnabled = on && selectedID.map { prefs.values.shortcuts[$0] != nil } == true
    }

    func shortcut(of id: String) -> Shortcut? {
        guard let a = catalog.first(where: { $0.id == id }) else { return nil }
        return Shortcuts.effective(id: id, defaults: a.defaults, overrides: prefs.values.shortcuts)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { catalog.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let a = catalog[row]
        let text: String
        if tableColumn?.identifier.rawValue == "action" { text = a.title } else { text = shortcut(of: a.id)?.display ?? "" }
        let label = NSTextField(labelWithString: text)
        let changed = prefs.values.shortcuts[a.id] != nil
        label.font = .systemFont(ofSize: 12, weight: changed && tableColumn?.identifier.rawValue == "shortcut" ? .semibold : .regular)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    // MARK: Changing

    /// Gives an action a shortcut (nil: none). A standard command's keys are refused; a key another action has is taken from it, after asking.
    /// Returns whether it was set. `confirm: false` is for the checks.
    @discardableResult
    func set(_ id: String, to new: Shortcut?, confirm: Bool = true) -> Bool {
        if let new {
            guard new.isUsable, !Shortcut.reserved.contains(new) else {
                if confirm { warn(L("“{keys}” cannot be used", ["keys": new.display]), L("Choose a combination with ⌘, ⌃ or ⌥. The standard commands keep their keys.")) }
                return false
            }
            let others = Shortcuts.users(of: new, besides: id, actions: catalog.map { ($0.id, $0.defaults) }, overrides: prefs.values.shortcuts)
            if !others.isEmpty {
                if confirm {
                    let names = others.compactMap { o in catalog.first { $0.id == o }?.title }.joined(separator: ", ")
                    let alert = NSAlert()
                    alert.messageText = L("“{keys}” is already used by {names}", ["keys": new.display, "names": names])
                    alert.informativeText = L("Take it for this action? The other one will have no shortcut.")
                    alert.addButton(withTitle: L("Cancel"))
                    alert.addButton(withTitle: L("Take It"))
                    guard alert.runModal() == .alertSecondButtonReturn else { return false }
                }
                prefs.update { p in for o in others { p.shortcuts[o] = Shortcuts.none } }
            }
        }
        prefs.update { p in
            let defaults = catalog.first { $0.id == id }?.defaults
            if new == defaults { p.shortcuts.removeValue(forKey: id) } else { p.shortcuts[id] = new?.text ?? Shortcuts.none }
        }
        refresh()
        return true
    }

    private func warn(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    @objc private func changePressed() {
        guard let id = selectedID, let action = catalog.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = L("New shortcut for “{action}”", ["action": action.title])
        alert.informativeText = L("Press the keys you want. Nothing changes until you press Set.")
        let recorder = ShortcutRecorderView(frame: NSRect(x: 0, y: 0, width: 260, height: 46))
        alert.accessoryView = recorder
        alert.addButton(withTitle: L("Set"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons[0].isEnabled = false
        recorder.onChange = { s in alert.buttons[0].isEnabled = s.isUsable }
        alert.window.initialFirstResponder = recorder
        DispatchQueue.main.async { alert.window.makeFirstResponder(recorder) }
        guard alert.runModal() == .alertFirstButtonReturn, let s = recorder.captured else { return }
        set(id, to: s)
    }

    @objc private func clearPressed() { if let id = selectedID { set(id, to: nil) } }

    @objc private func defaultPressed() {
        guard let id = selectedID else { return }
        prefs.update { $0.shortcuts.removeValue(forKey: id) }
        refresh()
    }
}
