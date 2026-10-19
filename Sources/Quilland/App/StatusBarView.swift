import AppKit
import Carbon.HIToolbox
import QuillandCore

/// The status bar at the bottom of a book's window: the count where the cursor is, the book and today on the left; Caps Lock and the
/// input language in the middle; "Saved" on the right.
final class StatusBarView: NSView {
    private let left = NSTextField(labelWithString: "")
    private let middle = NSTextField(labelWithString: "")
    private let right = NSTextField(labelWithString: "")
    private let trail = NSTextField(labelWithString: "")
    private var monitor: Any?
    private(set) var heightConstraint: NSLayoutConstraint

    var leftText: String { get { left.stringValue } set { left.stringValue = newValue } }
    var rightText: String { get { right.stringValue } set { right.stringValue = newValue } }
    var middleText: String { middle.stringValue }
    /// The views before and after this one in the history (Back and Forward), just before the right-hand text.
    var trailText: String { get { trail.stringValue } set { trail.stringValue = newValue } }

    override init(frame: NSRect) {
        heightConstraint = NSLayoutConstraint()
        super.init(frame: frame)
        for l in [left, middle, trail, right] {
            l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingTail
            l.translatesAutoresizingMaskIntoConstraints = false
            l.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            addSubview(l)
        }
        middle.alignment = .center
        right.alignment = .right
        trail.alignment = .right
        trail.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(2), for: .horizontal)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), left.centerYAnchor.constraint(equalTo: centerYAnchor),
            middle.centerXAnchor.constraint(equalTo: centerXAnchor), middle.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), right.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: middle.leadingAnchor, constant: -12),
            right.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),  // "Saved" and "editing…" do not make the trail move
            trail.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -18), trail.centerYAnchor.constraint(equalTo: centerYAnchor),
            middle.trailingAnchor.constraint(lessThanOrEqualTo: trail.leadingAnchor, constant: -12),
        ])
        heightConstraint = heightAnchor.constraint(equalToConstant: 22)
        heightConstraint.isActive = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.refreshKeyboard()
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshKeyboardNotification), name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
        refreshKeyboard()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5).fill()
    }

    @objc private func refreshKeyboardNotification() { refreshKeyboard() }

    /// Caps Lock and the language of the keyboard now.
    func refreshKeyboard() {
        let caps = NSEvent.modifierFlags.contains(.capsLock)
        middle.stringValue = (caps ? "⇪ \(L("CAPS"))   " : "") + Self.inputLanguage()
    }

    /// A short code of the current input source's language: `RU`, `EN`…
    static func inputLanguage() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return "" }
        let languages = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
        return languages.first.map { String($0.prefix(2)).uppercased() } ?? ""
    }
}
