import AppKit
import QuillandCore

/// The small window of Collect from the Book: what to look for, where, and how much that is.
final class CollectSheet: NSObject {
    struct Choice { var kinds: Set<CollectKind>; var scope: SearchScope }

    private weak var main: MainAreaController?
    private var boxes: [CollectKind: NSButton] = [:]
    private let scope = NSPopUpButton(frame: .zero, pullsDown: false)
    private let size = NSTextField(wrappingLabelWithString: "")
    static let scopes: [SearchScope] = [.book, .part, .chapter, .scene]
    static let titles: [(CollectKind, String)] = [(.characters, L("Characters")), (.places, L("Places")), (.events, L("Events")), (.relationships, L("Relationships")), (.observations, L("Observations about characters and places")), (.changes, L("Changes of characters and places"))]

    init(main: MainAreaController) { self.main = main; super.init() }

    private var chosenKinds: Set<CollectKind> { Set(boxes.filter { $0.value.state == .on }.map(\.key)) }
    private var chosenScope: SearchScope { Self.scopes[max(0, scope.indexOfSelectedItem)] }

    @objc private func changed() { updateSize() }

    private func updateSize() {
        guard let main else { return }
        let targets = main.proofreadingTargets(chosenScope)
        let characters = targets.reduce(0) { $0 + $1.text.count }
        // (Two passes over each piece when both what is known and what happens are asked for.)
        let passes = max(1, Set(chosenKinds.map(\.pass)).count)
        let pieces = passes * targets.reduce(0) { $0 + max(1, $1.text.count / CollectJob.pieceSize(context: AIService.shared.context) + 1) }
        size.stringValue = L("{scenes} to read, about {size} of text, in about {pieces} requests to the model.", ["scenes": Lp("{n} scene", "{n} scenes", targets.count),
                             "size": Lp("{n} character||text", "{n} characters||text", characters), "pieces": pieces])
    }

    /// Where a run reads unless the author says otherwise: the scene they are in, or the whole book when there is none.
    static func defaultScope(hasCurrentScene: Bool) -> SearchScope { hasCurrentScene ? .scene : .book }

    /// What the window is set to now (for the checks).
    var currentChoice: Choice { Choice(kinds: chosenKinds, scope: chosenScope) }

    /// Builds the controls, set to what they start with.
    func prepare() -> NSStackView {
        var views: [NSView] = []
        for (kind, title) in Self.titles {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed))
            b.state = kind == .observations ? .off : .on
            boxes[kind] = b
            views.append(b)
        }
        for s in Self.scopes { scope.addItem(withTitle: s == .book ? L("The whole book") : L("The current {part}", ["part": s.title.lowercased()])) }
        scope.selectItem(at: Self.scopes.firstIndex(of: Self.defaultScope(hasCurrentScene: main?.currentSceneID != nil)) ?? 0)
        scope.target = self; scope.action = #selector(changed)
        size.font = .systemFont(ofSize: 11); size.textColor = .secondaryLabelColor
        size.preferredMaxLayoutWidth = 380
        let stack = NSStackView(views: views + [scope, size])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        stack.setFrameSize(stack.fittingSize)
        updateSize()
        return stack
    }

    /// Asks. Nil when the author cancels.
    func run() -> Choice? {
        let alert = NSAlert()
        alert.messageText = L("Collect from the Book")
        alert.informativeText = L("The model reads the scenes and suggests cards. Nothing is added until you accept it in the Suggestions tab, and every suggestion shows the words it comes from.")
        let stack = prepare()
        alert.accessoryView = stack
        alert.addButton(withTitle: L("Start"))
        alert.addButton(withTitle: L("Cancel"))
        stack.setFrameSize(stack.fittingSize)
        guard alert.runModal() == .alertFirstButtonReturn, !chosenKinds.isEmpty else { return nil }
        return Choice(kinds: chosenKinds, scope: chosenScope)
    }
}

extension MainAreaController {
    /// AI ▸ Collect from the Book…: asks what and where, then reads in the background; the findings appear in the Suggestions tab.
    func showCollectSheet() {
        guard AIService.shared.isReady else {
            let alert = NSAlert()
            alert.messageText = L("The AI is not available")
            alert.informativeText = AIService.shared.unavailableReason ?? ""
            alert.runModal()
            return
        }
        guard !collect.running else { showSearch(.suggestions); return }
        guard let choice = CollectSheet(main: self).run() else { return }
        showSearch(.suggestions)
        collect.start(kinds: choice.kinds, scope: choice.scope)
    }
}

extension MainAreaController {
    /// AI ▸ Check Consistency…: asks where (the selection, when there is one, else the scene), then looks for contradictions in the background.
    func showConsistencySheet() {
        guard AIService.shared.isReady else {
            let alert = NSAlert()
            alert.messageText = L("The AI is not available")
            alert.informativeText = AIService.shared.unavailableReason ?? ""
            alert.runModal()
            return
        }
        guard !collect.running else { showSearch(.suggestions); return }
        let hasSelection = searchTargets(.selection).selection != nil
        let scopes: [SearchScope] = (hasSelection ? [.selection] : []) + [.scene, .chapter, .part, .book]
        let alert = NSAlert()
        alert.messageText = L("Check Consistency")
        alert.informativeText = L("The model reads the text and looks for facts that contradict the cards and what earlier scenes say. It only points at them: it changes nothing.")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for s in scopes { popup.addItem(withTitle: s == .selection ? L("The selected words") : (s == .book ? L("The whole book") : L("The current {part}", ["part": s.title.lowercased()]))) }
        alert.accessoryView = popup
        alert.addButton(withTitle: L("Start"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        showSearch(.suggestions)
        collect.startConsistency(scope: scopes[max(0, popup.indexOfSelectedItem)])
    }
}
