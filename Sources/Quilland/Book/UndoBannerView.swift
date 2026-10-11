import AppKit
import QuillandCore

/// A thin bar across the top of the area that names the last structural change and offers to undo it.
final class UndoBannerView: NSView {
    private let label = NSTextField(labelWithString: "")
    let undoButton = NSButton(title: L("Undo"), target: nil, action: nil)
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private(set) var heightConstraint = NSLayoutConstraint()
    private var hideTimer: Timer?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    private var buttonIsRedo = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        undoButton.bezelStyle = .rounded
        undoButton.controlSize = .small
        undoButton.target = self; undoButton.action = #selector(undoPressed)
        closeButton.isBordered = false
        closeButton.target = self; closeButton.action = #selector(close)
        closeButton.setAccessibilityLabel(L("Close"))
        Hover.button(closeButton)
        for v in [label, undoButton, closeButton] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), label.centerYAnchor.constraint(equalTo: centerYAnchor),
            undoButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10), undoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: undoButton.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10), closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() { layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true; layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor }

    /// Shows a message; with `undoable` the Undo button is there too. It goes away by itself after a while.
    func show(_ text: String, undoable: Bool, redo: Bool = false) {
        label.stringValue = text
        buttonIsRedo = redo
        undoButton.title = redo ? L("Redo") : L("Undo")
        undoButton.isHidden = !(undoable || redo)
        isHidden = false
        heightConstraint.constant = 28
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in self?.close() }
    }

    var text: String { label.stringValue }
    var isShowing: Bool { !isHidden }

    @objc func close() {
        hideTimer?.invalidate()
        isHidden = true
        heightConstraint.constant = 0
    }

    @objc private func undoPressed() { if buttonIsRedo { onRedo?() } else { onUndo?() } }
}
