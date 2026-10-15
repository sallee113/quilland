import AppKit
import QuillandCore

extension MainAreaController {
    /// The scenes a proofreading scope covers, with their text and a title for the list.
    func proofreadingTargets(_ scope: SearchScope) -> [(id: String, title: String, text: String)] {
        searchTargets(scope).scenes.compactMap { id in
            guard let doc = session.document(id) else { return nil }
            let title = session.structure.scenes.first { $0.id == id }?.fullPath ?? ""
            return (id, title, doc.storage.string)
        }
    }

    var bookLanguage: String { BookSettings.load(book: folder).language }

    private static var spellTag: Int = NSSpellChecker.uniqueSpellDocumentTag()

    /// Is there a dictionary of the book's language in the system's spell checker?
    func spellingAvailable(language: String) -> Bool {
        let code = language.lowercased()
        return NSSpellChecker.shared.availableLanguages.contains { $0.lowercased().hasPrefix(code) }
    }

    /// The words the spell checker must not flag: the book's dictionary and the words of the names of characters and places (and their beginnings, for the endings
    /// a name gets in a sentence).
    func spellingIgnored() -> (words: Set<String>, stems: [String]) {
        var words = Set(BookDictionary.load(book: folder).map { $0.lowercased() })
        var stems: [String] = []
        let names = characters.entries + worlds.nameEntries
        for entry in names {
            for full in [entry.name] + entry.aliases {
                for part in full.split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
                    let w = part.lowercased()
                    words.insert(w)
                    if w.count >= 5 { stems.append(String(w.dropLast())) }
                }
            }
        }
        return (words, stems)
    }

    /// Misspelled words in a text, each with the checker's first suggestion (empty when it has none).
    func spellingFindings(in text: String, language: String, ignored: (words: Set<String>, stems: [String])) -> [TypographyFinding] {
        guard spellingAvailable(language: language) else { return [] }
        let checker = NSSpellChecker.shared
        let tag = Self.spellTag
        checker.setIgnoredWords(Array(ignored.words), inSpellDocumentWithTag: tag)
        let ns = text as NSString
        var out: [TypographyFinding] = []
        var position = 0
        while position < ns.length {
            let found = checker.checkSpelling(of: text, startingAt: position, language: language, wrap: false, inSpellDocumentWithTag: tag, wordCount: nil)
            guard found.location != NSNotFound, found.length > 0 else { break }
            position = NSMaxRange(found)
            let r = (range: found, 0)
            let word = ns.substring(with: r.range)
            let lower = word.lowercased()
            if word.count < 2 || word.contains(where: { $0.isNumber }) || ignored.words.contains(lower) || ignored.stems.contains(where: { lower.hasPrefix($0) }) { continue }
            let suggestion = checker.guesses(forWordRange: r.range, in: text, language: language, inSpellDocumentWithTag: tag)?.first ?? ""
            let from = max(0, r.range.location - 24), to = min(ns.length, NSMaxRange(r.range) + 24)
            var cb = ns.substring(with: NSRange(location: from, length: r.range.location - from))
            var ca = ns.substring(with: NSRange(location: NSMaxRange(r.range), length: to - NSMaxRange(r.range)))
            if let i = cb.lastIndex(of: "\n") { cb = String(cb[cb.index(after: i)...]) }
            if let i = ca.firstIndex(of: "\n") { ca = String(ca[..<i]) }
            out.append(TypographyFinding(rule: .spelling, range: r.range, before: word, after: suggestion, contextBefore: cb, contextAfter: ca))
        }
        return out
    }

    /// Teaches the book a word: it is saved in the dictionary and every scene's spell checker takes it.
    func addToDictionary(_ word: String) {
        let words = BookDictionary.normalized(BookDictionary.load(book: folder) + [word])
        do { try BookDictionary.save(words, book: folder) } catch { reportError(error); return }
        session.applyBookSettings(language: bookLanguage, words: words)
    }

    /// Applies findings as ordinary edits in the scene's editor, so that ⌘Z takes them back (all of one call as one step). A piece whose text is no longer
    /// what the finding saw is skipped. Returns how many were applied.
    @discardableResult
    func applyProofreading(scene: String, edits: [(range: NSRange, expected: String, replacement: String)]) -> Int {
        guard let first = edits.first else { return 0 }
        _ = first
        // A scene that is already open stays as it is (the cursor and the view do not jump); another one is opened first. No range for reveal: its highlight
        // animation runs a moment later and would meet a text that has changed.
        if !controllers.contains(where: { $0.currentSceneID == scene }) { reveal(scene: scene, range: nil) }
        guard let area = controllers.first(where: { $0.currentSceneID == scene }) ?? controllers.first, let tv = area.currentSheet?.textView else { return 0 }
        var applied = 0
        tv.undoManager?.beginUndoGrouping()
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            let ns = tv.string as NSString
            guard NSMaxRange(edit.range) <= ns.length, ns.substring(with: edit.range) == edit.expected else { continue }
            if tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
                tv.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
                tv.didChangeText()
                applied += 1
            }
        }
        tv.undoManager?.endUndoGrouping()
        if applied > 0, let last = edits.min(by: { $0.range.location < $1.range.location }) {
            let end = min((tv.string as NSString).length, last.range.location + last.replacement.utf16.count)
            tv.setSelectedRange(NSRange(location: end, length: 0))
            // The corrected place is brought into view, so that the author sees what was done.
            area.scrollToCursor()
        }
        return applied
    }
}

/// The Proofreading tab of the bottom panel: the findings of the typography rules in book order, each shown as before → after, accepted or dismissed one by one.
final class ProofreadingView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var main: MainAreaController?
    var onBusyChanged: ((Bool) -> Void)?
    private struct Row { var group: String?; var scene: String?; var finding: TypographyFinding? }
    private var rows: [Row] = []
    private var dismissals = ProofreadingDismissals()
    private let scopePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let summary = NSTextField(labelWithString: "")
    private let table = Hover.rows(NSTableView())
    private let acceptButton = NSButton(title: L("Accept"), target: nil, action: nil)
    private let dismissButton = NSButton(title: L("Dismiss"), target: nil, action: nil)
    private let acceptAllButton = NSButton(title: L("Accept All in This Scene"), target: nil, action: nil)
    private let addWordButton = NSButton(title: L("Add to Dictionary"), target: nil, action: nil)
    private let restoreButton = NSButton(title: L("Show Dismissed Again"), target: nil, action: nil)
    private let rulesButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let checkAgainButton = NSButton(title: L("Check Again"), target: nil, action: nil)
    private let grammarButton = NSButton(title: L("Check Grammar"), target: nil, action: nil)
    private let grammarStop = NSButton(title: L("Stop"), target: nil, action: nil)
    private let grammarBar = NSProgressIndicator()
    private var grammarFraction = 0.0
    /// What the model suggested for each scene, until the text changes under it; and the run that is making them.
    private var grammarFindings: [String: [TypographyFinding]] = [:]
    private var grammarTask: Task<Void, Never>?
    private(set) var grammarMessage = ""
    private(set) var grammarRunning = false
    private var recheckTimer: Timer?
    private let explanation = NSTextField(wrappingLabelWithString: "")
    static let scopes: [SearchScope] = [.scene, .chapter, .part, .book]

    override init(frame: NSRect) {
        super.init(frame: frame)
        for s in Self.scopes { scopePopup.addItem(withTitle: s.title) }
        scopePopup.selectItem(at: 0)
        scopePopup.target = self; scopePopup.action = #selector(refreshAction)
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("finding"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.rowSizeStyle = .small
        table.target = self; table.action = #selector(rowClicked)
        table.setAccessibilityLabel(L("Findings"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        for b in [acceptButton, dismissButton, addWordButton, acceptAllButton, restoreButton] { b.bezelStyle = .rounded; b.controlSize = .small; b.target = self }
        acceptButton.action = #selector(acceptPressed); dismissButton.action = #selector(dismissPressed)
        addWordButton.action = #selector(addWordPressed); acceptAllButton.action = #selector(acceptAllPressed); restoreButton.action = #selector(restorePressed)
        // Return never accepts anything.
        for b in [acceptButton, dismissButton, addWordButton, acceptAllButton, restoreButton] { b.keyEquivalent = "" }
        acceptAllButton.toolTip = L("Takes the typography findings; spelling is always accepted one by one.")
        rulesButton.controlSize = .small
        checkAgainButton.bezelStyle = .rounded; checkAgainButton.controlSize = .small
        for b in [grammarButton, grammarStop] { b.bezelStyle = .rounded; b.controlSize = .small; b.target = self; b.keyEquivalent = "" }
        grammarButton.action = #selector(grammarPressed); grammarStop.action = #selector(grammarStopPressed)
        grammarStop.isHidden = true
        grammarBar.style = .bar; grammarBar.isIndeterminate = false; grammarBar.minValue = 0; grammarBar.maxValue = 1; grammarBar.controlSize = .small
        grammarBar.translatesAutoresizingMaskIntoConstraints = false
        grammarBar.widthAnchor.constraint(equalToConstant: 140).isActive = true
        grammarBar.isHidden = true
        checkAgainButton.target = self; checkAgainButton.action = #selector(refreshAction)
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 3
        let top = NSStackView(views: [NSTextField(labelWithString: L("Where")), scopePopup, rulesButton, checkAgainButton, grammarButton, grammarBar, grammarStop, summary])
        top.spacing = 10
        let bottom = NSStackView(views: [acceptButton, dismissButton, addWordButton, acceptAllButton, restoreButton])
        bottom.spacing = 8
        let stack = NSStackView(views: [top, scroll, explanation, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70),
            explanation.leadingAnchor.constraint(equalTo: stack.leadingAnchor), explanation.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// While the list is open and the scope is small, typing in the text looks at it again a moment later. A big scope waits for Check Again.
    private(set) var isWatching = false

    func watchTyping() {
        isWatching = true
        NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, !self.isHidden, let window = self.window, (note.object as? NSTextView)?.window === window, self.scope == .scene || self.scope == .chapter else { return }
            self.recheckTimer?.invalidate()
            self.recheckTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.refresh() }
        }
    }

    var scope: SearchScope {
        get { Self.scopes[max(0, scopePopup.indexOfSelectedItem)] }
        set { scopePopup.selectItem(at: Self.scopes.firstIndex(of: newValue) ?? 0); refresh() }
    }
    var debugRows: [String] { rows.compactMap { $0.finding }.map { "\($0.rule.rawValue):\($0.before.debugDescription)→\($0.after.debugDescription)" } }
    var findingCount: Int { rows.filter { $0.finding != nil }.count }

    @objc private func refreshAction() { refresh() }

    // MARK: Grammar by the model

    @objc private func grammarPressed() { startGrammar() }
    @objc private func grammarStopPressed() { grammarTask?.cancel() }
    /// The book window is closing: a grammar check that is still running stops.
    func stopGrammar() { grammarTask?.cancel() }

    /// Asks the model to correct the scenes of the scope; its corrections come in as findings, a few at a time. Never accepted all at once.
    func startGrammar() {
        guard let main, !grammarRunning, let client = AIService.shared.client() else { return }
        let targets = main.proofreadingTargets(scope)
        let scenes = targets.map { GrammarScene(id: $0.id, title: $0.title.isEmpty ? $0.id : $0.title, text: $0.text) }
        let language = main.bookLanguage
        for t in targets { grammarFindings[t.id] = nil }
        grammarRunning = true
        grammarFraction = 0
        grammarMessage = L("Checking grammar… the model is reading")
        refresh()
        let me = self
        grammarTask = Task {
            let result = await GrammarJob.run(scenes: scenes, language: language, client: client, progress: { p in
                DispatchQueue.main.async {
                    me.grammarFraction = p.pieces > 0 ? Double(p.piece) / Double(p.pieces) : 0
                    me.grammarMessage = L("Checking grammar: part {n} of {total} · {found} suggestions so far", ["n": min(p.pieces, p.piece + 1), "total": p.pieces, "found": p.found])
                    me.refresh()
                }
            }, found: { id, list in
                DispatchQueue.main.async { me.grammarFindings[id, default: []] += list; me.refreshSoon() }
            })
            await MainActor.run {
                me.grammarRunning = false
                me.grammarTask = nil
                me.grammarMessage = Self.grammarText(result)
                me.refresh()
            }
        }
    }

    static func grammarText(_ s: GrammarSummary) -> String {
        if let error = s.error { return error }
        var parts = [s.stopped ? L("Stopped") : L("Done"), Lp("{n} suggestion by the model", "{n} suggestions by the model", s.found)]
        if s.rewritten > 0 { parts.append(Lp("{n} part left out: the model rewrote it", "{n} parts left out: the model rewrote them", s.rewritten)) }
        if s.failedPieces > 0 { parts.append(Lp("{n} part could not be read", "{n} parts could not be read", s.failedPieces)) }
        return parts.joined(separator: " · ")
    }

    private var refreshPending = false
    private func refreshSoon() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshPending = false; self?.refresh() }
    }

    /// For the checks: waits until the model is done.
    func waitForGrammar(timeout: TimeInterval = 180) {
        let end = Date().addingTimeInterval(timeout)
        while grammarRunning, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    /// For the checks: puts the model's suggestions in as a run would.
    func injectGrammar(scene: String, _ list: [TypographyFinding]) { grammarFindings[scene, default: []] += list; refresh() }

    /// Looks at the text again (the scope, the dismissals or the text changed).
    func refresh() {
        guard let main else { return }
        let keep = selectedRow?.finding?.key
        dismissals = ProofreadingDismissals.load(book: main.folder)
        let language = main.bookLanguage
        let ignored = main.spellingIgnored()
        rows = []
        for target in main.proofreadingTargets(scope) {
            var all = Typography.check(target.text, language: language, rules: dismissals.rules)
            if dismissals.rules.contains(.grammar) {
                // The model's suggestions stay while the words they point at are still there.
                let current = target.text as NSString
                all += (grammarFindings[target.id] ?? []).filter { NSMaxRange($0.range) <= current.length && current.substring(with: $0.range) == $0.before }
            }
            if dismissals.rules.contains(.spelling) { all += main.spellingFindings(in: target.text, language: language, ignored: ignored) }
            let found = all.sorted { $0.range.location < $1.range.location }.filter { !dismissals.isDismissed($0) }
            guard !found.isEmpty else { continue }
            rows.append(Row(group: target.title, scene: target.id, finding: nil))
            rows += found.map { Row(group: nil, scene: target.id, finding: $0) }
        }
        fillRulesMenu()
        table.reloadData()
        if let keep, let i = rows.firstIndex(where: { $0.finding?.key == keep }) { table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false) }
        let n = findingCount
        summary.stringValue = grammarRunning ? grammarMessage : (n == 0 ? L("Nothing to fix") : Lp("{n} finding", "{n} findings", n)) + (grammarMessage.isEmpty ? "" : " · " + grammarMessage)
        onBusyChanged?(grammarRunning)
        grammarButton.isEnabled = !grammarRunning && AIService.shared.isReady
        grammarButton.title = grammarRunning ? L("Checking…") : L("Check Grammar")
        grammarBar.isHidden = !grammarRunning
        grammarBar.doubleValue = grammarFraction
        summary.font = .systemFont(ofSize: 11, weight: grammarRunning ? .semibold : .regular)
        summary.textColor = grammarRunning ? .systemOrange : .secondaryLabelColor
        checkAgainButton.isEnabled = !grammarRunning
        grammarButton.toolTip = AIService.shared.unavailableReason ?? L("The model reads the text and suggests corrections; you accept each one")
        grammarStop.isHidden = !grammarRunning
        updateButtons()
    }

    private func fillRulesMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Rules"), action: nil, keyEquivalent: ""))
        for rule in TypographyFinding.Rule.allCases {
            let item = ClosureMenuItem(title: Self.ruleTitle(rule)) { [weak self] in self?.toggle(rule) }
            item.state = dismissals.rulesOff.contains(rule.rawValue) ? .off : .on
            menu.addItem(item)
        }
        rulesButton.menu = menu
    }

    private func toggle(_ rule: TypographyFinding.Rule) {
        guard let main else { return }
        if dismissals.rulesOff.contains(rule.rawValue) { dismissals.rulesOff.remove(rule.rawValue) } else { dismissals.rulesOff.insert(rule.rawValue) }
        dismissals.save(book: main.folder)
        refresh()
    }

    static func ruleExplanation(_ rule: TypographyFinding.Rule) -> String {
        switch rule {
        case .dash: return L("A hyphen between words is not a dash. The dash is “—”, with a non-breaking space before it so that it never starts a line.")
        case .dialogue: return L("A line of dialogue starts with a dash and a space: “— Hello”.")
        case .quotes: return L("Straight quotes become the book's own typographic quotes (« » in Russian, “ ” in English).")
        case .ellipsis: return L("Three dots become one ellipsis character.")
        case .spaces: return L("A doubled space, or a space before a comma, a full stop and the like, is removed.")
        case .grammar: return L("The model suggests a correction of spelling, punctuation or grammar here. Check it: the model can be wrong. Accept puts it in the text; Dismiss hides it.")
        case .spelling: return L("The system's spell checker does not know this word. Accept puts its first suggestion in the text; Add to Dictionary teaches this book the word (a name, a place, an invented word).")
        case .nbsp: return L("After a short word (в, и, на, не…) the space becomes a non-breaking one, so that the word is never left alone at the end of a line. The change cannot be seen in the text.")
        }
    }

    private func updateButtons() {
        explanation.stringValue = selectedRow?.finding.map { Self.ruleExplanation($0.rule) } ?? L("Choose a finding to see what the rule does. Accept changes the text (⌘Z takes it back); Dismiss hides the finding.")
        let on = selectedRow != nil
        let spelling = selectedRow?.finding?.rule == .spelling
        acceptButton.isEnabled = on && !(spelling && selectedRow?.finding?.after.isEmpty == true)
        dismissButton.isEnabled = on; acceptAllButton.isEnabled = on
        addWordButton.isEnabled = spelling
        restoreButton.isEnabled = !dismissals.keys.isEmpty
    }

    func clearSelection() { table.deselectAll(nil); updateButtons() }

    func selectFirstTypography() {
        guard let i = rows.firstIndex(where: { $0.finding != nil && $0.finding?.rule != .spelling && $0.finding?.rule != .grammar }) else { return }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        updateButtons()
    }

    func selectGrammarFinding() {
        guard let i = rows.firstIndex(where: { $0.finding?.rule == .grammar }) else { return }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        updateButtons()
    }

    func selectSpellingFinding(_ word: String) {
        guard let i = rows.firstIndex(where: { $0.finding?.rule == .spelling && $0.finding?.before == word }) else { return }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        updateButtons()
    }

    /// For the checks and for opening the list with a choice made.
    func selectFirstFinding() {
        guard let i = rows.firstIndex(where: { $0.finding != nil }) else { return }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        updateButtons()
    }

    private var selectedRow: Row? {
        let r = table.selectedRow
        return r >= 0 && r < rows.count && rows[r].finding != nil ? rows[r] : nil
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row].group != nil }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].finding != nil }

    static func ruleTitle(_ rule: TypographyFinding.Rule) -> String {
        switch rule {
        case .dash: return L("Dash")
        case .dialogue: return L("Dialogue dash")
        case .quotes: return L("Quotes")
        case .ellipsis: return L("Ellipsis")
        case .spaces: return L("Spaces")
        case .nbsp: return L("Non-breaking space")
        case .spelling: return L("Spelling")
        case .grammar: return L("Grammar")
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        if let group = rows[row].group {
            label.stringValue = group
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }
        guard let f = rows[row].finding else { return nil }
        let plain: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 12)]
        func visible(_ s: String) -> String { s.replacingOccurrences(of: "\u{00A0}", with: "‹" + L("no-break") + "›").replacingOccurrences(of: " ", with: "‹" + L("space") + "›") }
        let s = NSMutableAttributedString(string: Self.ruleTitle(f.rule) + "   ", attributes: [.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFont.systemFont(ofSize: 10)])
        s.append(NSAttributedString(string: String(f.contextBefore.suffix(24)), attributes: plain))
        s.append(NSAttributedString(string: f.before.isEmpty ? "" : visible(f.before), attributes: [.foregroundColor: NSColor.systemRed, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .font: NSFont.systemFont(ofSize: 12)]))
        s.append(NSAttributedString(string: f.after.isEmpty ? (f.rule == .spelling ? "  (" + L("no suggestion") + ")" : "(—)") : " → " + visible(f.after), attributes: [.foregroundColor: NSColor.systemGreen, .font: NSFont.boldSystemFont(ofSize: 12)]))
        s.append(NSAttributedString(string: String(f.contextAfter.prefix(24)), attributes: plain))
        label.attributedStringValue = s
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    @objc private func rowClicked() {
        guard let row = selectedRow, let scene = row.scene, let f = row.finding else { return }
        main?.reveal(scene: scene, range: f.range)
    }

    /// The keyboard moves with the arrows; Space on the focused button accepts. Return does nothing here.
    override func keyDown(with event: NSEvent) { super.keyDown(with: event) }

    // MARK: Accepting and dismissing

    @objc func acceptPressed() { acceptSelected() }

    @discardableResult
    func acceptSelected() -> Bool {
        guard let row = selectedRow, let scene = row.scene, let f = row.finding, let main else { return false }
        if f.rule == .spelling && f.after.isEmpty { return false }
        let at = table.selectedRow
        let applied = main.applyProofreading(scene: scene, edits: [(f.range, f.before, f.after)])
        refresh()
        selectNear(at)
        return applied == 1
    }

    @objc private func dismissPressed() { dismissSelected() }

    func dismissSelected() {
        guard let row = selectedRow, let f = row.finding, let main else { return }
        let at = table.selectedRow
        dismissals.dismiss(f)
        dismissals.save(book: main.folder)
        refresh()
        selectNear(at)
    }

    @objc private func addWordPressed() { addSelectedWord() }

    func addSelectedWord() {
        guard let row = selectedRow, let f = row.finding, f.rule == .spelling, let main else { return }
        let at = table.selectedRow
        main.addToDictionary(f.before)
        refresh()
        selectNear(at)
    }

    @objc private func acceptAllPressed() { acceptAllInScene() }

    /// Every finding of the selected finding's scene, as one step that ⌘Z takes back.
    func acceptAllInScene() {
        guard let row = selectedRow, let scene = row.scene, let main else { return }
        let edits = rows.filter { $0.scene == scene }.compactMap { $0.finding }.filter { $0.rule != .spelling && $0.rule != .grammar }.map { (range: $0.range, expected: $0.before, replacement: $0.after) }
        let at = table.selectedRow
        main.applyProofreading(scene: scene, edits: edits)
        refresh()
        selectNear(at)
    }

    @objc private func restorePressed() {
        guard let main else { return }
        dismissals.forgetAll()
        dismissals.save(book: main.folder)
        refresh()
    }

    private func selectNear(_ index: Int) {
        guard !rows.isEmpty else { return }
        var i = min(index, rows.count - 1)
        while i < rows.count, rows[i].finding == nil { i += 1 }
        if i >= rows.count { i = rows.count - 1; while i > 0, rows[i].finding == nil { i -= 1 } }
        if rows[i].finding != nil { table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false); table.scrollRowToVisible(i) }
        updateButtons()
    }
}
