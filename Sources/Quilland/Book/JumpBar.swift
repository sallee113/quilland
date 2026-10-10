import AppKit
import QuillandCore

/// The bar at the top of a Book or Compare area: the path of the scene where the cursor is (`Part › Chapter › Scene ▾`), with arrows to
/// the previous and the next scene. Clicking the path opens the jump list.
final class JumpBarView: NSView {
    let previous = NSButton(title: "", target: nil, action: nil)
    let next = NSButton(title: "", target: nil, action: nil)
    let path = NSButton(title: "", target: nil, action: nil)
    private(set) var heightConstraint = NSLayoutConstraint()

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (button, symbol, tip) in [(previous, "chevron.left", L("Previous scene")), (next, "chevron.right", L("Next scene"))] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.toolTip = tip
            button.setAccessibilityLabel(tip)
        }
        path.bezelStyle = .texturedRounded
        path.isBordered = false
        path.alignment = .center
        path.lineBreakMode = .byTruncatingMiddle
        path.font = .systemFont(ofSize: 12)
        path.toolTip = L("Jump to a scene (⌘J)")
        for v in [previous, path, next] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            previous.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), previous.centerYAnchor.constraint(equalTo: centerYAnchor),
            next.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), next.centerYAnchor.constraint(equalTo: centerYAnchor),
            path.centerYAnchor.constraint(equalTo: centerYAnchor), path.centerXAnchor.constraint(equalTo: centerXAnchor),
            path.leadingAnchor.constraint(greaterThanOrEqualTo: previous.trailingAnchor, constant: 8),
            path.trailingAnchor.constraint(lessThanOrEqualTo: next.leadingAnchor, constant: -8),
        ])
        heightConstraint = heightAnchor.constraint(equalToConstant: 30)
        heightConstraint.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
    }
}

/// The list that opens under the jump bar: the whole structure with a filter field. Arrows and Return choose, Esc closes.
final class JumpListController: NSViewController, NSSearchFieldDelegate {
    let tree = StructureTreeController()
    let field = NSSearchField()
    private let structure: BookStructure
    private let characters: (String) -> Int
    var onChoose: ((String) -> Void)?
    var onClose: (() -> Void)?

    init(structure: BookStructure, characters: @escaping (String) -> Int) {
        self.structure = structure
        self.characters = characters
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 440))
        field.placeholderString = L("Find a scene")
        field.delegate = self
        tree.choosesOnClick = true
        _ = tree.view
        tree.onEnterText = { [weak self] in self?.choose() }
        for v in [field, tree.view] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            tree.view.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8), tree.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            tree.view.leadingAnchor.constraint(equalTo: root.leadingAnchor), tree.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        view = root
        reload(filter: "", selecting: nil)
    }

    /// The structure with only the scenes (and the chapters and parts around them) whose title or section's title has the text in it.
    static func filtered(_ structure: BookStructure, by text: String) -> BookStructure {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return structure }
        func keep(_ node: BookStructure.Node) -> BookStructure.Node? {
            if node.kind == .scene { return node.title.lowercased().contains(needle) ? node : nil }
            let selfMatches = node.title.lowercased().contains(needle)
            let kids = node.children.compactMap(keep)
            if selfMatches { return node }
            if kids.isEmpty { return nil }
            var copy = node
            copy.children = kids
            return copy
        }
        var out = structure
        out.roots = structure.roots.compactMap(keep)
        return out
    }

    private func reload(filter: String, selecting id: String?) {
        tree.reload(structure: Self.filtered(structure, by: filter), characters: characters, selecting: id, expandAll: true)
        if let id, tree.selectedID == id { return }
        tree.selectFirstScene()
    }

    func select(_ id: String?) {
        if let id { tree.select(id, notify: false) }
        view.window?.makeFirstResponder(field)
    }

    func controlTextDidChange(_ obj: Notification) { reload(filter: field.stringValue, selecting: nil) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): tree.moveSelection(by: 1); return true
        case #selector(NSResponder.moveUp(_:)): tree.moveSelection(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)): choose(); return true
        case #selector(NSResponder.cancelOperation(_:)): onClose?(); return true
        default: return false
        }
    }

    private func choose() {
        guard let id = tree.selectedID else { return }
        onChoose?(id)
    }
}
