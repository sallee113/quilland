import AppKit
import QuillandCore

/// What the Outline's information area shows about a section.
struct SectionInfo {
    var id: String
    var kind: BookStructure.Kind
    var title: String
    var path: String
    var status: String?
    var characters: Int
    /// A scene's wished size, in characters.
    var target: Int?
    var synopsis: String
    var note: String
    /// A chapter or a part: how many scenes there are in each status.
    var sceneStatuses: [(status: String, count: Int)]
    var sceneCount: Int
    /// Names of the characters found in the section.
    var characterNames: [String]
}

/// The Outline's right-hand part: the selected section's properties, synopsis and note (editable), its size and what is found in it.
final class OutlineDetailController: NSViewController, NSTextViewDelegate, NSTextFieldDelegate {
    var info: (String) -> SectionInfo? = { _ in nil }
    var totalCharacters: ([String]) -> Int = { _ in 0 }
    var onRename: ((String, String) -> Void)?
    var onStatus: ((String, String) -> Void)?
    var onTarget: ((String, Int?) -> Void)?
    var onText: ((String, String, String) -> Void)?
    var onOpen: ((String) -> Void)?
    let narratorButton = NarratorButton()
    private let narratorRow = NSStackView()

    private(set) var shown: [String] = []
    /// For the checks: the size line, the target field's text, and whether the narrator row is shown.
    var countsText: String { countsLabel.stringValue }
    var narratorRowShown: Bool { !narratorRow.isHidden }
    var targetPlaceholder: String { targetField.placeholderString ?? "" }
    private let kindLabel = NSTextField(labelWithString: "")
    let titleField = NSTextField()
    private let pathLabel = NSTextField(labelWithString: "")
    private let statusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetField = NSTextField()
    private let progress = NSProgressIndicator()
    private let countsLabel = NSTextField(wrappingLabelWithString: "")
    let synopsis = SuggestTextView()
    var onWriteSynopsis: (() -> Void)?
    private let writeButton = NSButton(title: L("Write with AI"), target: nil, action: nil)
    let note = NSTextView()
    private let foundLabel = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: L("Open in the Editor"), target: nil, action: nil)
    private let statusRow = NSStackView()
    private let targetRow = NSStackView()
    private let textBlocks = NSStackView()
    private var dirty: Set<String> = []
    private var saveTimer: Timer?
    private var timerID: String?

    override func loadView() {
        let root = NSView()
        view = root
        func caption(_ t: String) -> NSTextField {
            let l = NSTextField(labelWithString: t)
            l.font = .systemFont(ofSize: 11, weight: .semibold)
            l.textColor = .secondaryLabelColor
            return l
        }
        kindLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        kindLabel.textColor = .secondaryLabelColor
        titleField.font = .systemFont(ofSize: 22, weight: .semibold)
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.delegate = self
        titleField.setAccessibilityLabel(L("Title"))
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingTail
        for st in SceneRecord.knownStatuses { statusPopup.addItem(withTitle: L(st).capitalized); statusPopup.lastItem?.representedObject = st }
        statusPopup.target = self; statusPopup.action = #selector(statusChanged)
        targetField.placeholderString = L("for example 5000")
        targetField.toolTip = L("How long you want this scene to be, in characters. A bar shows how close it is.")
        targetField.alignment = .right
        targetField.delegate = self
        targetField.setAccessibilityLabel(L("Target size"))
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1
        countsLabel.textColor = .secondaryLabelColor
        foundLabel.font = .systemFont(ofSize: 13)
        for tv in [synopsis, note] {
            tv.isRichText = false; tv.allowsUndo = true
            tv.font = .systemFont(ofSize: 14)
            tv.textContainerInset = NSSize(width: 6, height: 6)
            tv.isVerticallyResizable = true
            tv.autoresizingMask = [.width]
            tv.delegate = self
        }
        synopsis.setAccessibilityLabel(L("Synopsis")); note.setAccessibilityLabel(L("Note"))
        openButton.target = self; openButton.action = #selector(open)
        openButton.bezelStyle = .rounded

        statusRow.setViews([caption(L("Status")), statusPopup], in: .leading)
        statusRow.orientation = .horizontal; statusRow.spacing = 8
        targetRow.setViews([caption(L("Target length")), targetField, progress], in: .leading)
        targetRow.orientation = .horizontal; targetRow.spacing = 8
        narratorRow.setViews([caption(L("Narrator")), narratorButton], in: .leading)
        narratorRow.orientation = .horizontal; narratorRow.spacing = 8
        targetField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        progress.widthAnchor.constraint(equalToConstant: 160).isActive = true

        func box(_ tv: NSTextView, _ height: CGFloat) -> NSScrollView {
            let sv = NSScrollView()
            sv.documentView = tv; sv.hasVerticalScroller = true; sv.borderType = .bezelBorder
            sv.translatesAutoresizingMaskIntoConstraints = false
            sv.heightAnchor.constraint(equalToConstant: height).isActive = true
            return sv
        }
        let synopsisBox = box(synopsis, 150), noteBox = box(note, 100)
        writeButton.bezelStyle = .inline; writeButton.controlSize = .small
        writeButton.target = self; writeButton.action = #selector(writePressed)
        let synopsisRow = NSStackView(views: [caption(L("Synopsis")), writeButton])
        synopsisRow.spacing = 10
        textBlocks.setViews([synopsisRow, synopsisBox, caption(L("Note")), noteBox, caption(L("Characters found")), foundLabel], in: .leading)
        textBlocks.orientation = .vertical; textBlocks.alignment = .leading; textBlocks.spacing = 6
        for v in [synopsisBox, noteBox] { v.widthAnchor.constraint(equalTo: textBlocks.widthAnchor).isActive = true }
        foundLabel.widthAnchor.constraint(equalTo: textBlocks.widthAnchor).isActive = true

        let column = NSStackView(views: [kindLabel, titleField, pathLabel, statusRow, targetRow, narratorRow, countsLabel, textBlocks, openButton])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 20), column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            titleField.widthAnchor.constraint(equalTo: column.widthAnchor), textBlocks.widthAnchor.constraint(equalTo: column.widthAnchor),
            countsLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        subscriptions.append(subscribe(to: .aiStatusChanged) { [weak self] in self?.updateWriteButton() })
        show([])
    }

    // MARK: Showing

    /// Shows the chosen section (one), several (their total), or nothing.
    func show(_ ids: [String]) {
        guard isViewLoaded else { return }
        if ids != shown { commitEdits() }
        shown = ids
        refresh()
    }

    private var subscriptions: [Subscription] = []
    /// For the checks: is the button that asks the model on?
    var writeEnabled: Bool { writeButton.isEnabled }

    /// The button that asks the model follows the connection, whatever is shown at the time.
    private func updateWriteButton() {
        writeButton.isEnabled = AIService.shared.isReady
        writeButton.toolTip = AIService.shared.unavailableReason ?? L("The model writes a synopsis; Tab accepts it, Esc drops it")
    }

    func refresh() {
        guard isViewLoaded else { return }
        if shown.count > 1 {
            kindLabel.stringValue = L("{n} SECTIONS", ["n": shown.count])
            titleField.stringValue = L("{n} sections chosen", ["n": shown.count])
            titleField.isEditable = false
            pathLabel.stringValue = ""
            countsLabel.stringValue = L("{size} in all", ["size": Lp("{n} character||text", "{n} characters||text", totalCharacters(shown))])
            [statusRow, targetRow, narratorRow, textBlocks, openButton].forEach { $0.isHidden = true }
            return
        }
        guard let id = shown.first, let section = info(id) else {
            kindLabel.stringValue = ""
            titleField.stringValue = L("Choose a section")
            titleField.isEditable = false
            pathLabel.stringValue = ""; countsLabel.stringValue = ""
            [statusRow, targetRow, narratorRow, textBlocks, openButton].forEach { $0.isHidden = true }
            return
        }
        updateWriteButton()
        let isScene = section.kind == .scene
        kindLabel.stringValue = L(section.kind.rawValue).uppercased()
        titleField.stringValue = section.title
        titleField.isEditable = true
        pathLabel.stringValue = section.path
        statusRow.isHidden = !isScene
        targetRow.isHidden = !isScene
        narratorRow.isHidden = !isScene
        if isScene { narratorButton.show(scene: id) }
        textBlocks.isHidden = false
        openButton.isHidden = false
        if isScene {
            if let i = SceneRecord.knownStatuses.firstIndex(of: section.status ?? "idea") { statusPopup.selectItem(at: i) }
            targetField.stringValue = section.target.map(String.init) ?? ""
            progress.isHidden = section.target == nil
            progress.doubleValue = section.target.map { min(1, Double(section.characters) / Double(max(1, $0))) } ?? 0
        }
        let number = { (n: Int) in NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
        var counts = Lp("{n} character||text", "{n} characters||text", section.characters)
        if isScene, let target = section.target, target > 0 { counts = L("{size} of {target} characters ({percent}%)", ["size": number(section.characters), "target": number(target), "percent": section.characters * 100 / target]) }
        if !isScene {
            let list = section.sceneStatuses.filter { $0.count > 0 }.map { "\($0.count) \(L($0.status))" }.joined(separator: " · ")
            counts += "  ·  " + Lp("{n} scene", "{n} scenes", section.sceneCount) + (list.isEmpty ? "" : " (\(list))")
        }
        countsLabel.stringValue = counts
        if synopsis.string != section.synopsis { synopsis.string = section.synopsis }
        if note.string != section.note { note.string = section.note }
        synopsis.undoManager?.removeAllActions(); note.undoManager?.removeAllActions()
        foundLabel.stringValue = section.characterNames.isEmpty ? L("None found") : section.characterNames.joined(separator: ", ")
    }

    // MARK: Editing

    @objc private func statusChanged() {
        guard let id = shown.first, shown.count == 1, let status = statusPopup.selectedItem?.representedObject as? String else { return }
        onStatus?(id, status)
    }

    @objc private func writePressed() { onWriteSynopsis?() }

    @objc private func open() { if let id = shown.first { onOpen?(id) } }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let id = shown.first, shown.count == 1, let field = obj.object as? NSTextField else { return }
        if field === titleField {
            let text = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { refresh() } else if text != info(id)?.title { onRename?(id, text) }
        } else if field === targetField {
            let value = Int(targetField.stringValue.filter(\.isNumber))
            if value != info(id)?.target { onTarget?(id, value == 0 ? nil : value) }
        }
    }

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv === synopsis || tv === note else { return }
        dirty.insert(tv === synopsis ? "synopsis" : "note")
        timerID = shown.first
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.commitEdits() }
    }

    func textDidEndEditing(_ notification: Notification) { commitEdits() }

    /// Writes the synopsis and the note typed here and not yet saved.
    @objc func commitEdits() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard !dirty.isEmpty, let id = timerID ?? shown.first else { dirty = []; return }
        let pending = dirty
        dirty = []
        if pending.contains("synopsis") { onText?(id, "synopsis", synopsis.string) }
        if pending.contains("note") { onText?(id, "note", note.string) }
    }
}

private extension NSStackView {
    func setViews(_ views: [NSView], in gravity: NSStackView.Gravity) { views.forEach { addView($0, in: gravity) } }
}
