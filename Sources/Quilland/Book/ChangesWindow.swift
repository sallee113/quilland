import AppKit
import QuillandCore

/// A text view that shows a grey **ghost** while it is empty: a click does nothing, typing replaces it (it is not text), and Tab accepts it (when `tabAccepts`):
/// the ghost becomes the text, to be edited. The same rule as the faint suggestion of the AI in the editor.
final class GhostTextView: NSTextView {
    var ghost = "" { didSet { needsDisplay = true } }
    var tabAccepts = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !ghost.isEmpty else { return }
        let pad = (textContainer?.lineFragmentPadding ?? 0) + textContainerInset.width
        let rect = NSRect(x: pad, y: textContainerInset.height, width: max(0, bounds.width - 2 * pad), height: max(0, bounds.height - textContainerInset.height))
        (ghost as NSString).draw(in: rect, withAttributes: [.font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor])
    }

    override func didChangeText() { super.didChangeText(); needsDisplay = true }

    /// Tab accepts the ghost of an empty field; otherwise it goes to the next field.
    override func insertTab(_ sender: Any?) {
        if string.isEmpty, tabAccepts, !ghost.isEmpty {
            string = ghost
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
            didChangeText()
        } else {
            window?.selectNextKeyView(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }
}

/// What the changes window needs to read and to write.
struct ChangesContext {
    var events: EventStore
    var event: String
    var characters: CharacterStore
    var worlds: WorldStore
    var relationships: RelationshipStore
}

/// The changes of one event for one character, place or relationship: a window of its own, like the Settings window (quilland-change-events.md). Every field is
/// empty and shows what the card says in grey. What is typed is what the event changes from there on; **empty means no change**, and emptying a field that had a
/// change takes it away. Closing the window saves. The name and the notes are never here.
final class ChangesWindowController: NSWindowController, NSWindowDelegate {
    let context: ChangesContext
    let kind: EffectTarget
    let target: String
    /// The relationship starts in this event: its own fields are edited here, as ordinary fields (the event that creates it owns the first data).
    let startsHere: Bool
    /// Fields that had a change and were emptied when the window closed (the owner may say so, with Undo), and what they held.
    var onSaved: ((_ removed: [(field: EffectField, text: String)]) -> Void)?
    var onClosed: ((ChangesWindowController) -> Void)?

    private var textViews: [EffectField: GhostTextView] = [:]
    private let mainPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var worldBoxes: [(id: String, box: NSButton, base: Bool)] = []
    private var closing = false

    init(context: ChangesContext, kind: EffectTarget, target: String, startsHere: Bool = false) {
        self.context = context; self.kind = kind; self.target = target; self.startsHere = startsHere
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: kind == .character ? 560 : 340), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 240)
        super.init(window: window)
        window.delegate = self
        window.title = L("Changes of “{name}” in “{event}”", ["name": targetTitle, "event": eventTitle])
        build()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var targetTitle: String {
        switch kind {
        case .character: return context.characters.character(target)?.name ?? ""
        case .place: return context.worlds.entry(target)?.name ?? ""
        case .relationship: return Self.title(of: target, context.relationships, context.characters)
        }
    }

    private var eventTitle: String { context.events.event(context.event)?.title ?? "" }

    /// "Анна — Лев (сёстры)".
    static func title(of relationship: String, _ relationships: RelationshipStore, _ characters: CharacterStore) -> String {
        guard let r = relationships.relationship(relationship) else { return "" }
        let names = r.characters.compactMap { characters.character($0)?.name }.joined(separator: " — ")
        return names + (r.kind.map { " (\($0))" } ?? "")
    }

    // MARK: The window

    private func field(_ f: EffectField, ghost: String, tabAccepts: Bool, height: CGFloat, value: String) -> NSView {
        let tv = GhostTextView()
        tv.isRichText = false
        tv.font = .systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = value
        tv.ghost = ghost
        tv.tabAccepts = tabAccepts
        tv.setAccessibilityLabel(label(of: f))
        textViews[f] = tv
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = height > 40
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }

    private func label(of f: EffectField) -> String {
        switch f {
        case .aliases: return L("Also called")
        case .main: return L("Main character")
        case .profile: return L("Profile")
        case .worlds: return L("Worlds")
        case .description: return L("Description")
        case .kind: return L("Kind")
        }
    }

    private func caption(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let effect = context.events.event(context.event)?.effect(of: target) ?? [:]
        var wide: [NSView] = []
        func add(_ title: String, _ view: NSView) { stack.addArrangedSubview(caption(title)); stack.addArrangedSubview(view); wide.append(view) }

        switch kind {
        case .character:
            let c = context.characters.character(target)
            add(L("Also called: new names, separated by commas"), field(.aliases, ghost: (c?.aliases ?? []).joined(separator: ", "), tabAccepts: false, height: 28, value: (effect.strings("aliases") ?? []).joined(separator: ", ")))
            mainPopup.addItems(withTitles: [L("No change"), L("Becomes a main character"), L("Stops being a main character")])
            mainPopup.selectItem(at: effect.bool("main").map { $0 ? 1 : 2 } ?? 0)
            mainPopup.toolTip = (c?.main == true) ? L("On the card: a main character") : L("On the card: not a main character")
            stack.addArrangedSubview(caption(L("Main character")))
            stack.addArrangedSubview(mainPopup)
            add(L("Profile"), field(.profile, ghost: context.characters.profile(target), tabAccepts: true, height: 220, value: effect.string("profile") ?? ""))
            stack.addArrangedSubview(caption(L("Worlds the character belongs to as well from here on")))
            let have = Set(c?.worlds ?? [])
            let chosen = Set(effect.strings("worlds") ?? [])
            let row = NSStackView(); row.orientation = .vertical; row.alignment = .leading; row.spacing = 4
            for w in context.worlds.worlds {
                guard let id = w.id else { continue }
                let box = NSButton(checkboxWithTitle: w.name ?? "", target: nil, action: nil)
                let base = have.contains(id)
                box.state = base || chosen.contains(id) ? .on : .off
                box.isEnabled = !base
                if base { box.toolTip = L("The card already has this world") }
                worldBoxes.append((id, box, base))
                row.addArrangedSubview(box)
            }
            stack.addArrangedSubview(row)
        case .place:
            add(L("Description"), field(.description, ghost: context.worlds.text(target), tabAccepts: true, height: 240, value: effect.string("description") ?? ""))
        case .relationship:
            let base = context.relationships.relationship(target)?.kind ?? ""
            if startsHere {
                add(L("Kind"), field(.kind, ghost: "", tabAccepts: false, height: 28, value: base))
            } else {
                add(L("Kind"), field(.kind, ghost: base, tabAccepts: true, height: 28, value: effect.string("kind") ?? ""))
            }
        }
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        for v in wide { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true }
        window?.contentView = content
        if let first = textViews.values.first { window?.initialFirstResponder = first }
    }

    // MARK: Saving

    /// Writes what is in the window into the event (and, for a relationship that starts here, into the relationship).
    func commit() {
        var removed: [(EffectField, String)] = []
        let before = context.events.event(context.event)?.effect(of: target) ?? [:]
        func text(_ f: EffectField) -> String { (textViews[f]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        if kind == .relationship, startsHere {
            let kindText = text(.kind)
            if !kindText.isEmpty { try? context.relationships.update(target) { $0.kind = kindText } }
            return
        }
        try? context.events.update(context.event) { r in
            switch kind {
            case .character:
                r.setEffect(.aliases, of: target, list: text(.aliases).split(separator: ",").map(String.init))
                r.setEffectFlag(of: target, [nil, true, false][max(0, min(2, mainPopup.indexOfSelectedItem))])
                r.setEffect(.profile, of: target, text: text(.profile))
                r.setEffect(.worlds, of: target, list: worldBoxes.filter { !$0.base && $0.box.state == .on }.map(\.id))
            case .place: r.setEffect(.description, of: target, text: text(.description))
            case .relationship: r.setEffect(.kind, of: target, text: text(.kind))
            }
        }
        let after = context.events.event(context.event)?.effect(of: target) ?? [:]
        for f in kind.fields where before[f.rawValue] != nil && after[f.rawValue] == nil {
            let old: String
            switch before[f.rawValue] {
            case .string(let s)?: old = s
            case .array(let items)?: old = items.compactMap { if case .string(let s) = $0 { return s } else { return nil } }.joined(separator: ", ")
            case .bool(let b)?: old = b ? "true" : "false"
            default: old = ""
            }
            removed.append((f, old))
        }
        onSaved?(removed)
    }

    func windowWillClose(_ notification: Notification) {
        guard !closing else { return }
        closing = true
        commit()
        onClosed?(self)
    }

    // MARK: For the checks

    func text(_ f: EffectField) -> String { textViews[f]?.string ?? "" }
    func ghost(_ f: EffectField) -> String { textViews[f]?.ghost ?? "" }
    func setText(_ f: EffectField, _ value: String) { textViews[f]?.string = value; textViews[f]?.didChangeText() }
    func pressTab(in f: EffectField) { textViews[f]?.insertTab(nil) }
    func setMain(_ value: Bool?) { mainPopup.selectItem(at: value.map { $0 ? 1 : 2 } ?? 0) }
    func setWorld(_ id: String, _ on: Bool) { worldBoxes.first { $0.id == id }?.box.state = on ? .on : .off }
    var worldStates: [(id: String, on: Bool, enabled: Bool)] { worldBoxes.map { ($0.id, $0.box.state == .on, $0.box.isEnabled) } }
}
