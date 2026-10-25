import AppKit
import QuillandCore

/// Where the filters of the Characters, World and Events views get what they offer and what they ask (the book's window provides it).
struct RelationFilterSource {
    var sections: () -> [(id: String, title: String, depth: Int)]
    var events: () -> [(id: String, title: String)]
    var characters: () -> [(id: String, title: String)]
    var places: () -> [(id: String, title: String)]
    var index: () -> RelationIndex
}

/// "Filter by…" under the word filter of a list: a menu to choose a section, an event, a character or a place, and a chip for each filter that is on. The list
/// then shows only what is related to all of them, in either direction (`RelationIndex`).
final class RelationFilter: NSObject {
    enum AnchorKind: CaseIterable {
        case section, event, character, place
        var title: String {
            switch self {
            case .section: return L("Section")
            case .event: return L("Event")
            case .character: return L("Character")
            case .place: return L("Place")
            }
        }
    }

    /// What the view lists: the filters offered are the other kinds.
    let kind: RelationIndex.Kind
    var source: RelationFilterSource? { didSet { rebuild() } }
    private(set) var anchors: [RelationIndex.Anchor] = []

    /// Puts the chips back from `memory`; the view then reloads itself (a chip whose item is gone from the book is taken off by `rebuild`).
    func restore(_ keys: [String]) {
        anchors = keys.compactMap { key in
            guard let colon = key.firstIndex(of: ":") else { return nil }
            let id = String(key[key.index(after: colon)...])
            switch key[..<colon] {
            case "section": return .section(id)
            case "event": return .event(id)
            case "character": return .character(id)
            case "place": return .place(id)
            default: return nil
            }
        }
        invalidate()
    }
    var onChange: (() -> Void)?

    let view = NSStackView()
    private let button = NSPopUpButton(frame: .zero, pullsDown: true)
    private let chips = NSStackView()
    private let note = NSTextField(labelWithString: "")
    private var cached: Set<String>?
    private var computed = false

    init(kind: RelationIndex.Kind) {
        self.kind = kind
        super.init()
        button.controlSize = .small
        button.setAccessibilityLabel(L("Filter by…"))
        chips.orientation = .horizontal
        chips.spacing = 4
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        view.setViews([button, chips, note], in: .leading)
        view.orientation = .horizontal
        view.spacing = 6
        view.alignment = .centerY
        rebuild()
    }

    private var offered: [AnchorKind] {
        AnchorKind.allCases.filter { k in
            switch (kind, k) {
            case (.character, .character), (.place, .place), (.event, .event): return false
            default: return true
            }
        }
    }

    var isActive: Bool { !anchors.isEmpty }

    /// The ids the list may show, or nil when no filter is on. Kept until a filter changes or `invalidate()`.
    func allowed() -> Set<String>? {
        guard isActive, let source else { return nil }
        if !computed { cached = source.index().matching(kind, anchors: anchors); computed = true }
        return cached
    }

    /// The book changed (a link, a name, a text): the answer is worked out again next time.
    func invalidate() { computed = false; cached = nil }

    func setCount(shown: Int, of total: Int) {
        guard isActive else { note.stringValue = ""; return }
        note.stringValue = shown == 0 ? emptyMessage : L("{n} of {total}", ["n": shown, "total": total])
    }

    /// What to say when the filters leave nothing: for the connections that go through events, why that can be so.
    private var emptyMessage: String {
        if kind == .character, anchors.contains(where: { Self.kind(of: $0) == .place }) { return L("No character is linked to an event held at this place.") }
        if kind == .place, anchors.contains(where: { Self.kind(of: $0) == .character }) { return L("This character is not linked to an event that has a place.") }
        return L("Nothing matches the filters.")
    }

    /// What a filter means, for its chip's tooltip.
    private func meaning(of anchor: RelationIndex.Anchor) -> String {
        switch (kind, anchor) {
        case (.character, .place): return L("Characters who take part in events held at this place")
        case (.place, .character): return L("Places of the events this character takes part in")
        case (.character, .section), (.place, .section), (.event, .section): return L("What is in the scenes of this section")
        case (.character, .event): return L("Characters linked to this event")
        case (.place, .event): return L("Places of this event")
        case (.event, .character): return L("Events this character takes part in")
        case (.event, .place): return L("Events held at this place")
        default: return L("Take this filter off")
        }
    }

    private static func kind(of anchor: RelationIndex.Anchor) -> AnchorKind {
        switch anchor {
        case .section: return .section
        case .event: return .event
        case .character: return .character
        case .place: return .place
        }
    }

    private static func id(of anchor: RelationIndex.Anchor) -> String {
        switch anchor {
        case .section(let s), .event(let s), .character(let s), .place(let s): return s
        }
    }

    /// Turns a filter on; one of each kind at a time (a new one replaces the old).
    func set(_ anchor: RelationIndex.Anchor) {
        anchors.removeAll { Self.kind(of: $0) == Self.kind(of: anchor) }
        anchors.append(anchor)
        changed()
    }

    func remove(_ anchor: RelationIndex.Anchor) {
        anchors.removeAll { $0 == anchor }
        changed()
    }

    func clear() {
        guard isActive else { return }
        anchors = []
        changed()
    }

    private func changed() {
        invalidate()
        rebuild()
        onChange?()
    }

    /// The name shown for a filter's item, or nil when it is gone from the book.
    private func title(of anchor: RelationIndex.Anchor) -> String? {
        guard let source else { return nil }
        let id = Self.id(of: anchor)
        switch anchor {
        case .section: return source.sections().first { $0.id == id }?.title
        case .event: return source.events().first { $0.id == id }?.title
        case .character: return source.characters().first { $0.id == id }?.title
        case .place: return source.places().first { $0.id == id }?.title
        }
    }

    /// Filters whose item is no longer in the book are taken off.
    func prune() {
        let before = anchors.count
        anchors = anchors.filter { title(of: $0) != nil }
        if anchors.count != before { invalidate() }
    }

    func rebuild() {
        prune()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Filter by…"), action: nil, keyEquivalent: ""))
        if let source {
            for k in offered {
                let parent = NSMenuItem(title: k.title, action: nil, keyEquivalent: "")
                let sub = NSMenu()
                func entry(_ title: String, indent: Int = 0, _ anchor: RelationIndex.Anchor) {
                    let item = ClosureMenuItem(title: title) { [weak self] in self?.set(anchor) }
                    item.indentationLevel = indent
                    if anchors.contains(anchor) { item.state = .on }
                    sub.addItem(item)
                }
                switch k {
                case .section: for s in source.sections() { entry(s.title, indent: s.depth, .section(s.id)) }
                case .event: for e in source.events() { entry(e.title, .event(e.id)) }
                case .character: for c in source.characters() { entry(c.title, .character(c.id)) }
                case .place: for p in source.places() { entry(p.title, .place(p.id)) }
                }
                if sub.items.isEmpty { let none = NSMenuItem(title: L("None"), action: nil, keyEquivalent: ""); none.isEnabled = false; sub.addItem(none) }
                parent.submenu = sub
                menu.addItem(parent)
            }
        }
        button.menu = menu
        chips.arrangedSubviews.forEach { chips.removeArrangedSubview($0); $0.removeFromSuperview() }
        for anchor in anchors {
            let name = Self.kind(of: anchor).title + ": " + (title(of: anchor) ?? "")
            let chip = ClosureButton(title: name + "  ✕") { [weak self] in self?.remove(anchor) }
            chip.bezelStyle = .inline
            chip.controlSize = .small
            chip.lineBreakMode = .byTruncatingTail
            chip.toolTip = meaning(of: anchor) + ". " + L("Click to take this filter off.")
            chip.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
            chips.addArrangedSubview(chip)
        }
    }

    // MARK: For the checks

    /// The chips' texts.
    var chipTexts: [String] { chips.arrangedSubviews.compactMap { ($0 as? NSButton)?.title } }
    var menuKinds: [String] { button.menu?.items.dropFirst().map(\.title) ?? [] }
    var noteText: String { note.stringValue }
}

/// A button that runs a closure.
final class ClosureButton: NSButton {
    private let action_: () -> Void
    init(title: String, _ action: @escaping () -> Void) {
        action_ = action
        super.init(frame: .zero)
        self.title = title
        target = self
        self.action = #selector(run)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func run() { action_() }
}
