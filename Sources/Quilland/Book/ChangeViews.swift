import AppKit
import QuillandCore

/// The changes events make in a text field of a card (a place's description, a character's profile), as rows under the base text: no labels, a border above each
/// row, not editable until clicked (the click opens the window of that change). A tooltip names the event and the scene; the row of an event with no scene is greyed.
final class ChangeRowsView: NSStackView {
    /// A row was clicked: the event.
    var onOpen: ((String) -> Void)?
    private(set) var rows: [ChangeRow] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .vertical
        alignment = .leading
        spacing = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Shows the changes that have `text`.
    func set(_ changes: [EntityChange], text: (EntityChange) -> String?, tooltip: (EntityChange) -> String) {
        for r in rows { r.removeFromSuperview() }
        rows = changes.compactMap { c in
            guard let value = text(c), !value.isEmpty else { return nil }
            let row = ChangeRow(text: value, applies: c.applies, event: c.event)
            row.toolTip = tooltip(c)
            row.onClick = { [weak self] in self?.onOpen?($0) }
            return row
        }
        for r in rows {
            addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        isHidden = rows.isEmpty
    }

    var texts: [String] { rows.map(\.text) }
}


/// A relationship of a character as a brick on the card: "Лев — friends → enemies", greyed when it has ended; a click opens `event`, which holds it.
struct RelationshipBrick: Equatable {
    var title: String
    var dimmed: Bool
    var tooltip: String
    var event: String
}

final class ChangeRow: NSView {
    let text: String
    let applies: Bool
    let event: String
    var onClick: ((String) -> Void)?
    private let label: NSTextField

    init(text: String, applies: Bool, event: String) {
        self.text = text; self.applies = applies; self.event = event
        label = NSTextField(wrappingLabelWithString: text)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 13)
        label.textColor = applies ? .labelColor : .tertiaryLabelColor
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7), label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// A border above the row.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) { onClick?(self.event) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// A small rounded brick with a light outline and no fill, in the colour of the text around it (a name an event added, a world, a relationship). A click calls `onClick`.
final class BrickView: NSView {
    let title: String
    var onClick: (() -> Void)?
    private let label: NSTextField

    init(_ title: String, dimmed: Bool = false, tooltip: String? = nil) {
        self.title = title
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 12)
        label.textColor = dimmed ? .tertiaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        updateOutline()
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateOutline() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.35).cgColor } }
    override func viewDidChangeEffectiveAppearance() { updateOutline() }
    override var intrinsicContentSize: NSSize { NSSize(width: label.intrinsicContentSize.width + 16, height: 20) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { if onClick != nil { addCursorRect(bounds, cursor: .pointingHand) } }
}

/// Lays its views out in lines, left to right, wrapping when a line is full: the field of a card first, then the bricks after it on the same line when they fit.
final class FlowView: NSView {
    private let spacing: CGFloat = 6
    private var lineHeight: CGFloat = 24
    private var heightConstraint: NSLayoutConstraint?
    override var isFlipped: Bool { true }

    /// The first view is the card's own field: it takes at least `minimumFieldWidth` of its line.
    var minimumFieldWidth: CGFloat = 220

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: lineHeight)
        heightConstraint?.isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(_ views: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        for v in views { v.translatesAutoresizingMaskIntoConstraints = true; addSubview(v) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width, 100)
        var x: CGFloat = 0, y: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let size = i == 0 && v is NSTextField ? NSSize(width: min(width, max(minimumFieldWidth, width * 0.45)), height: lineHeight) : NSSize(width: min(v.intrinsicContentSize.width, width), height: v.intrinsicContentSize.height > 0 ? v.intrinsicContentSize.height : lineHeight)
            if x > 0, x + size.width > width { x = 0; y += lineHeight + 4 }
            v.frame = NSRect(x: x, y: y + (lineHeight - size.height) / 2, width: size.width, height: size.height)
            x += size.width + spacing
        }
        let total = subviews.isEmpty ? 0 : y + lineHeight
        if heightConstraint?.constant != total { heightConstraint?.constant = total }
    }

    var bricks: [BrickView] { subviews.compactMap { $0 as? BrickView } }
}
