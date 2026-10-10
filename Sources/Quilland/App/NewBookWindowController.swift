import AppKit
import QuillandCore

/// The New Book dialog: a title, an author, a language and a place. Nothing else is asked.
final class NewBookWindowController: NSObject {
    let window: NSWindow
    let titleField = NSTextField()
    let authorField = NSTextField()
    let languagePopup = NSPopUpButton()
    private let locationLabel = NSTextField(labelWithString: "")
    private(set) var parentFolder: URL
    /// The folder of the new book, and whether the author chose to start with the plan.
    var onCreated: ((URL, Bool) -> Void)?
    var onCancel: (() -> Void)?
    private var chooserHost: NSWindow?

    init(parentFolder: URL) {
        self.parentFolder = parentFolder
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 280), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = L("New Book")
        titleField.placeholderString = L("Title")
        authorField.placeholderString = L("Author (optional)")
        languagePopup.addItems(withTitles: ["Русский", "English"])
        updateLocation()

        func label(_ t: String) -> NSTextField { let l = NSTextField(labelWithString: t); l.alignment = .right; l.textColor = .secondaryLabelColor; return l }
        let choose = NSButton(title: L("Choose…"), target: self, action: #selector(chooseFolder))
        let place = NSStackView(views: [locationLabel, choose])
        place.spacing = 8
        locationLabel.lineBreakMode = .byTruncatingMiddle
        locationLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        let grid = NSGridView(views: [[label(L("Title")), titleField], [label(L("Author")), authorField], [label(L("Language")), languagePopup], [label(L("Keep in")), place]])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true

        let cancel = NSButton(title: L("Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let plan = NSButton(title: L("Start with the Plan"), target: self, action: #selector(startPlan))
        let write = NSButton(title: L("Start Writing"), target: self, action: #selector(startWriting))
        write.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, plan, write])
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 28), grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            buttons.topAnchor.constraint(greaterThanOrEqualTo: grid.bottomAnchor, constant: 24),
        ])
        window.contentView = content
        window.initialFirstResponder = titleField
    }

    private func updateLocation() { locationLabel.stringValue = (parentFolder.path as NSString).abbreviatingWithTildeInPath }

    func present(over parent: NSWindow?) {
        if let parent { parent.beginSheet(window) } else { window.center(); window.makeKeyAndOrderFront(nil) }
        window.makeFirstResponder(titleField)
    }

    private func dismiss() {
        if let parent = window.sheetParent { parent.endSheet(window) }
        window.orderOut(nil)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = parentFolder
        panel.prompt = L("Choose")
        if panel.runModal() == .OK, let url = panel.url { parentFolder = url; updateLocation() }
    }

    @objc private func cancel() { dismiss(); onCancel?() }
    @objc private func startWriting() { create(plan: false) }
    @objc private func startPlan() { create(plan: true) }

    /// Makes the book; returns false (and says why) when it cannot.
    @discardableResult
    func create(plan: Bool) -> Bool {
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { window.makeFirstResponder(titleField); NSSound.beep(); return false }
        do {
            let folder = try BookCreator.create(NewBookRequest(title: title, author: authorField.stringValue.trimmingCharacters(in: .whitespaces),
                                                              language: languagePopup.indexOfSelectedItem == 0 ? "ru" : "en", parentFolder: parentFolder))
            dismiss()
            onCreated?(folder, plan)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = L("The book could not be created")
            alert.informativeText = "\(error)"
            alert.beginSheetModal(for: window)
            return false
        }
    }
}
