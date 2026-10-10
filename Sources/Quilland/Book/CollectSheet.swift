import AppKit
import QuillandCore

/// The small window of Collect from the Book: what to look for, where, and how much that is.
final class CollectSheet: NSObject {
    struct Choice { var kinds: Set<CollectKind>; var scope: SearchScope; var reanalyse: Bool }

    private weak var main: MainAreaController?
    private var boxes: [CollectKind: NSButton] = [:]
    private let scope = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reanalyse = NSButton(checkboxWithTitle: L("Read again the scenes that were already read and have not changed"), target: nil, action: nil)
    private let size = NSTextField(wrappingLabelWithString: "")
    static let scopes: [SearchScope] = [.book, .part, .chapter, .scene]
    static let titles: [(CollectKind, String)] = [(.characters, L("Characters")), (.places, L("Places and things")), (.events, L("Events")), (.relationships, L("Relationships")), (.observations, L("Observations about characters and places"))]

    init(main: MainAreaController) { self.main = main; super.init() }

    private var chosenKinds: Set<CollectKind> { Set(boxes.filter { $0.value.state == .on }.map(\.key)) }
    private var chosenScope: SearchScope { Self.scopes[max(0, scope.indexOfSelectedItem)] }

    @objc private func changed() { updateSize() }

    private func updateSize() {
        guard let main else { return }
        let targets = main.proofreadingTargets(chosenScope)
        let analysed = AnalysedScenes.load(book: main.folder)
        let kinds = chosenKinds
        let fresh = reanalyse.state == .on ? targets : targets.filter { analysed[$0.id] != CollectJob.fingerprint($0.text, kinds: kinds) }
        let characters = fresh.reduce(0) { $0 + $1.text.count }
        let pieces = fresh.reduce(0) { $0 + max(1, $1.text.count / CollectJob.pieceSize(context: AIService.shared.context) + 1) }
        size.stringValue = L("{scenes} to read, about {size} of text, in about {pieces} requests to the model.", ["scenes": Lp("{n} scene", "{n} scenes", fresh.count),
                             "size": Lp("{n} character||text", "{n} characters||text", characters), "pieces": pieces]) + (targets.count > fresh.count ? " " + L("{n} unchanged scenes are skipped.", ["n": targets.count - fresh.count]) : "")
    }

    /// Asks. Nil when the author cancels.
    func run() -> Choice? {
        let alert = NSAlert()
        alert.messageText = L("Collect from the Book")
        alert.informativeText = L("The model reads the scenes and suggests cards. Nothing is added until you accept it in the Suggestions tab, and every suggestion shows the words it comes from.")
        var views: [NSView] = []
        for (kind, title) in Self.titles {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(changed))
            b.state = kind == .observations ? .off : .on
            boxes[kind] = b
            views.append(b)
        }
        for s in Self.scopes { scope.addItem(withTitle: s == .book ? L("The whole book") : L("The current {part}", ["part": s.title.lowercased()])) }
        scope.selectItem(at: 0)
        scope.target = self; scope.action = #selector(changed)
        reanalyse.target = self; reanalyse.action = #selector(changed)
        reanalyse.font = .systemFont(ofSize: 11)
        size.font = .systemFont(ofSize: 11); size.textColor = .secondaryLabelColor
        size.preferredMaxLayoutWidth = 380
        let stack = NSStackView(views: views + [scope, reanalyse, size])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        stack.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
        stack.setFrameSize(stack.fittingSize)
        alert.accessoryView = stack
        alert.addButton(withTitle: L("Start"))
        alert.addButton(withTitle: L("Cancel"))
        updateSize()
        stack.setFrameSize(stack.fittingSize)
        guard alert.runModal() == .alertFirstButtonReturn, !chosenKinds.isEmpty else { return nil }
        return Choice(kinds: chosenKinds, scope: chosenScope, reanalyse: reanalyse.state == .on)
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
        collect.start(kinds: choice.kinds, scope: choice.scope, reanalyse: choice.reanalyse)
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
