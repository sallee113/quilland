import AppKit
import QuillandCore

/// A scene's sheet: a page-coloured card with the scene's text on it.
final class SheetView: NSView, SceneDocumentObserver {
    let document: SceneDocument
    let textView: EditorTextView
    var onHeightChange: (() -> Void)?
    private(set) var height: CGFloat = 100

    init(document: SceneDocument, width: CGFloat) {
        self.document = document
        textView = document.makeTextView(width: width)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 0.5
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 5
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(textView)
        document.addObserver(self)
        measure()
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() { updateColors() }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    /// Measures the text again; returns true when the height changed.
    @discardableResult
    func measure() -> Bool {
        let wanted = max(120, SceneDocument.neededHeight(of: textView))
        guard abs(wanted - height) > 0.5 else { return false }
        height = wanted
        frame.size.height = wanted
        textView.frame = NSRect(x: 0, y: 0, width: frame.width, height: wanted)
        return true
    }

    func setWidth(_ width: CGFloat) {
        frame.size.width = width
        textView.frame.size.width = width
        textView.textContainer?.size = NSSize(width: SceneDocument.containerWidth(forSheet: width), height: CGFloat.greatestFiniteMagnitude)
        measure()
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    func sceneDocumentDidChange(_ document: SceneDocument) {
        if measure() { onHeightChange?() }
    }
}

/// The small header between two sheets: the scene's title (a click renames it), a status dot (a click chooses the status) and its
/// character count.
final class SceneHeaderView: NSView, SceneDocumentObserver, NSTextFieldDelegate {
    let document: SceneDocument
    /// The author gave the scene a new title or chose a status here.
    var onRename: ((String, String) -> Void)?
    var onStatus: ((String, String) -> Void)?
    /// Renaming is over (Return or a click elsewhere): the text can have the keyboard back.
    var onFinishedRenaming: (() -> Void)?
    private(set) lazy var titleField: NSTextField = title
    private let title = NSTextField(string: "")
    private let count = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let dot = NSView()

    init(document: SceneDocument) {
        self.document = document
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 26))
        for label in [title, count, status] {
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }
        for label in [count, status] { label.isEditable = false; label.isBordered = false; label.drawsBackground = false; label.isSelectable = false }
        // The title is a field that can be typed in at once, like a title in Finder: a click and type.
        title.isEditable = true
        title.isBordered = false
        title.drawsBackground = false
        title.focusRingType = .none
        title.delegate = self
        title.toolTip = L("Click to rename the scene")
        title.textColor = .labelColor
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        addSubview(dot)
        document.addObserver(self)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    static func color(for status: String?) -> NSColor {
        switch status {
        case "done": return .systemGreen
        case "revised": return .systemBlue
        case "draft": return .systemOrange
        default: return .systemGray
        }
    }

    func refresh() {
        title.stringValue = document.title
        status.stringValue = document.status ?? "idea"
        count.stringValue = NumberFormatter.localizedString(from: NSNumber(value: document.counts.characters), number: .decimal)
        dot.layer?.backgroundColor = Self.color(for: document.status).cgColor
        needsLayout = true
    }

    func sceneDocumentDidChange(_ document: SceneDocument) {
        // While the title is being typed the field is the author's, not the document's.
        if title.currentEditor() == nil { refresh() } else {
            status.stringValue = document.status ?? "idea"
            count.stringValue = NumberFormatter.localizedString(from: NSNumber(value: document.counts.characters), number: .decimal)
            dot.layer?.backgroundColor = Self.color(for: document.status).cgColor
            needsLayout = true
        }
    }

    // MARK: Renaming and the status

    func controlTextDidChange(_ obj: Notification) { needsLayout = true }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === title else { return }
        let text = title.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text == document.title { title.stringValue = document.title } else { onRename?(document.id, text) }
        needsLayout = true
        onFinishedRenaming?()
    }

    /// The status is chosen from a small menu under the dot (a click on the dot or on its word).
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let area = dot.frame.union(status.frame).insetBy(dx: -4, dy: -4)
        guard area.contains(point) else { return super.mouseDown(with: event) }
        let menu = NSMenu()
        for name in ["idea", "draft", "revised", "done"] {
            let item = ClosureMenuItem(title: L(name).capitalized) { [weak self] in self?.chooseStatus(name) }
            item.state = (document.status ?? "idea") == name ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: area.minX, y: area.maxY), in: self)
    }

    func chooseStatus(_ name: String) {
        guard name != (document.status ?? "idea") else { return }
        onStatus?(document.id, name)
    }

    override func layout() {
        super.layout()
        title.sizeToFit(); status.sizeToFit(); count.sizeToFit()
        // Room for what is being typed.
        if title.currentEditor() != nil { title.frame.size.width = max(title.frame.width, 120) + 16 }
        let y = (bounds.height - title.frame.height) / 2
        title.frame.origin = NSPoint(x: 4, y: y)
        dot.frame = NSRect(x: title.frame.maxX + 10, y: bounds.height / 2 - 4, width: 8, height: 8)
        status.frame.origin = NSPoint(x: dot.frame.maxX + 5, y: y)
        count.frame.origin = NSPoint(x: bounds.width - count.frame.width - 4, y: y)
    }
}

/// The wider band where a chapter or a part begins.
final class BandView: NSView {
    private let label = NSTextField(labelWithString: "")
    let level: Int

    init(title: String, level: Int) {
        self.level = level
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: level == 1 ? 54 : 40))
        label.stringValue = title.uppercased()
        label.font = NSFont.systemFont(ofSize: level == 1 ? 12 : 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        addSubview(label)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        label.sizeToFit()
        label.frame = NSRect(x: 0, y: (bounds.height - label.frame.height) / 2, width: bounds.width, height: label.frame.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
        NSRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5).fill()
    }
}
