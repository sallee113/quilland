import AppKit
import QuillandCore

/// What the panel needs to know about a scene.
struct SceneInfo {
    var id: String
    var title: String
    var path: String
    var status: String?
    var characters: Int
}

/// The right panel: Section and Characters tabs. It follows the cursor after a delay (so it does not jump while the author moves
/// through the text) and can be pinned to what it shows.
final class RightPanelController: NSViewController, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    enum Tab: Int { case section, characters, world, events, research, chat }

    // Given by the main area.
    var sceneInfo: (String) -> SceneInfo? = { _ in nil }
    var sceneText: (String) -> String = { _ in "" }
    /// The scene where the cursor is now.
    var cursorScene: () -> String? = { nil }
    var editor: () -> BookEditor? = { nil }
    var characterStore: CharacterStore!
    var worldStore: WorldStore!
    var eventStore: EventStore!
    var researchStore: ResearchStore!
    /// The scenes in the order of the book, for ordering the events.
    var sceneOrder: () -> [String] = { [] }
    var onOpenPlace: ((String) -> Void)?
    var onOpenResearch: ((String) -> Void)?
    var chatSession: ChatSession?
    var chatMentions: (() -> NSMenu)?
    var onSaveChatAnswer: (() -> Void)?
    var onSaveChatAction: (() -> Void)?
    var onOpenEvent: ((String) -> Void)?
    /// A structural or textual change was made here (the window refreshes its status).
    var onChange: (() -> Void)?

    /// Seconds of rest in a scene before the panel follows the cursor into it.
    var followDelay: TimeInterval = 1.5
    private(set) var shownScene: String?
    private(set) var pinned = false
    private var followTimer: Timer?

    private let tabs = Hover.segments(NSSegmentedControl(labels: [L("Section"), L("Characters")], trackingMode: .selectOne, target: nil, action: nil))
    /// The tabs shown (Settings ▸ Panels lets the author hide the ones not used), and the one that is open.
    private(set) var visibleTabs: [Tab] = [.section, .characters]
    private var shownTab = Tab.section
    private let pinButton = NSButton(checkboxWithTitle: L("Pin"), target: nil, action: nil)
    private let sectionView = NSView()
    private let charactersView = NSView()
    let worldTab = WorldTab()
    let eventsTab = EventsTab()
    let researchTab = ResearchTab()
    let chatTab = ChatTab()

    // Section tab
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let infoLabel = NSTextField(labelWithString: "")
    private let inSceneLabel = NSTextField(wrappingLabelWithString: "")
    private let placesLabel = NSTextField(wrappingLabelWithString: "")
    let synopsis = SuggestTextView()
    var onWriteSynopsis: (() -> Void)?
    private let writeButton = NSButton(title: L("Write with AI"), target: nil, action: nil)
    let note = NSTextView()
    private var dirty: Set<String> = []
    private var saveTimer: Timer?

    // Characters tab
    private let allBox = NSButton(checkboxWithTitle: L("All characters"), target: nil, action: nil)
    private let addButton = NSButton(title: L("New Character"), target: nil, action: nil)
    private let table = Hover.rows(NSTableView())
    private let sceneLinkButton = NSButton(title: "", target: nil, action: nil)
    private let nameField = NSTextField()
    private let aliasField = NSTextField()
    private let mainBox = NSButton(checkboxWithTitle: L("Main character"), target: nil, action: nil)
    let characterNotes = NSTextView()
    private var listed: [CharacterRecord] = []
    private var selectedCharacter: String?
    /// The characters found in the scene shown.
    private(set) var found: Set<String> = []
    /// For the checks: the characters the Characters tab lists, and the "In scene" line of the Section tab.
    var listedCharacterIDs: [String] { listed.compactMap(\.id) }
    var inSceneText: String { inSceneLabel.stringValue }

    // MARK: View

    override func loadView() {
        subscriptions.append(subscribe(to: .aiStatusChanged) { [weak self] in self?.updateWriteButton() })
        let root = NSView()
        view = root
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.segmentStyle = .texturedRounded
        pinButton.target = self
        pinButton.action = #selector(pinChanged)
        pinButton.toolTip = L("Keep showing this one while the cursor moves on")
        pinButton.controlSize = .small
        tabs.controlSize = .small
        for v in [tabs, pinButton, sectionView, charactersView, worldTab, eventsTab, researchTab, chatTab] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 8), tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            pinButton.centerYAnchor.constraint(equalTo: tabs.centerYAnchor), pinButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            pinButton.leadingAnchor.constraint(greaterThanOrEqualTo: tabs.trailingAnchor, constant: 8),
        ])
        worldTab.store = worldStore; worldTab.sceneText = { [weak self] in self?.sceneText($0) ?? "" }
        worldTab.onOpen = { [weak self] in self?.onOpenPlace?($0) }
        worldTab.onChange = { [weak self] in self?.onChange?() }
        eventsTab.store = eventStore; eventsTab.worlds = worldStore; eventsTab.sceneOrder = { [weak self] in self?.sceneOrder() ?? [] }
        eventsTab.onOpen = { [weak self] in self?.onOpenEvent?($0) }
        eventsTab.onChange = { [weak self] in self?.onChange?() }
        researchTab.store = researchStore
        researchTab.onOpen = { [weak self] in self?.onOpenResearch?($0) }
        researchTab.onChange = { [weak self] in self?.onChange?() }
        chatTab.session = chatSession
        chatTab.mentionsMenu = { [weak self] in self?.chatMentions?() ?? NSMenu() }
        chatTab.onSaveAnswer = { [weak self] in self?.onSaveChatAnswer?() }
        chatTab.onSaveAction = { [weak self] in self?.onSaveChatAction?() }
        for v in [sectionView, charactersView, worldTab, eventsTab, researchTab, chatTab] {
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10), v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ])
        }
        buildSection()
        buildCharacters()
        rebuildTabs()
        showTab(.section)
        refresh()
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func boxed(_ tv: NSTextView, height: CGFloat) -> NSScrollView {
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }

    private func stack(_ views: [NSView], in host: NSView) {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 6
        s.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(s)
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: host.topAnchor), s.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 10),
            s.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10),
        ])
        for v in views where v is NSScrollView || v is NSTextField && (v as! NSTextField).isEditable {
            v.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true
        }
        inSceneLabel.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = host === sectionView
        placesLabel.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = host === sectionView
    }

    private func buildSection() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingTail
        infoLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = .secondaryLabelColor
        inSceneLabel.font = .systemFont(ofSize: 12)
        inSceneLabel.preferredMaxLayoutWidth = 240
        placesLabel.font = .systemFont(ofSize: 12)
        placesLabel.preferredMaxLayoutWidth = 240
        synopsis.setAccessibilityLabel(L("Synopsis"))
        note.setAccessibilityLabel(L("Note"))
        writeButton.bezelStyle = .inline; writeButton.controlSize = .small
        writeButton.target = self; writeButton.action = #selector(writePressed)
        let synopsisRow = NSStackView(views: [label(L("Synopsis")), writeButton])
        synopsisRow.spacing = 10
        stack([titleLabel, pathLabel, infoLabel, synopsisRow, boxed(synopsis, height: 120), label(L("Note")), boxed(note, height: 90), label(L("Characters in this scene")), inSceneLabel, label(L("Places and things in this scene")), placesLabel], in: sectionView)
    }

    @objc private func writePressed() { onWriteSynopsis?() }

    private func buildCharacters() {
        allBox.target = self; allBox.action = #selector(allChanged); allBox.controlSize = .small
        addButton.target = self; addButton.action = #selector(addCharacter); addButton.controlSize = .small
        addButton.bezelStyle = .rounded
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 22
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        nameField.placeholderString = L("Name")
        aliasField.placeholderString = L("Other names, separated by commas")
        for f in [nameField, aliasField] { f.delegate = self; f.target = self }
        mainBox.target = self; mainBox.action = #selector(mainChanged)
        characterNotes.setAccessibilityLabel(L("Notes"))
        sceneLinkButton.target = self; sceneLinkButton.action = #selector(sceneLinkPressed)
        sceneLinkButton.controlSize = .small; sceneLinkButton.bezelStyle = .rounded
        let row = NSStackView(views: [allBox, addButton])
        row.orientation = .horizontal
        row.distribution = .equalSpacing
        stack([row, scroll, sceneLinkButton, label(L("Name")), nameField, label(L("Also called")), aliasField, mainBox, label(L("Notes")), boxed(characterNotes, height: 120)], in: charactersView)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: charactersView.widthAnchor, constant: -20).isActive = true
    }

    // MARK: Tabs

    @objc private func tabChanged() {
        let i = tabs.selectedSegment
        if visibleTabs.indices.contains(i) { showTab(visibleTabs[i]) }
    }

    private func title(of tab: Tab) -> String {
        switch tab {
        case .section: return L("Section")
        case .characters: return L("Characters")
        case .world: return L("World")
        case .events: return L("Events")
        case .research: return L("Research")
        case .chat: return L("Chat")
        }
    }

    private func rebuildTabs() {
        guard isViewLoaded else { return }
        tabs.segmentCount = visibleTabs.count
        for (i, t) in visibleTabs.enumerated() { tabs.setLabel(title(of: t), forSegment: i) }
        tabs.isHidden = visibleTabs.count < 2
        if let i = visibleTabs.firstIndex(of: shownTab) { tabs.selectedSegment = i }
    }

    /// Which tabs are shown; the open one is kept if it is still there, otherwise the first is opened.
    func setVisibleTabs(_ list: [Tab]) {
        visibleTabs = list.isEmpty ? [.section] : list
        rebuildTabs()
        if !visibleTabs.contains(shownTab) { showTab(visibleTabs[0]) }
    }

    func showTab(_ tab: Tab) {
        guard visibleTabs.contains(tab) else { return }
        shownTab = tab
        if let i = visibleTabs.firstIndex(of: tab) { tabs.selectedSegment = i }
        sectionView.isHidden = tab != .section
        charactersView.isHidden = tab != .characters
        worldTab.isHidden = tab != .world
        eventsTab.isHidden = tab != .events
        researchTab.isHidden = tab != .research
        chatTab.isHidden = tab != .chat
        refresh()
    }

    var currentTab: Tab { shownTab }

    // MARK: Following the cursor

    /// The cursor is in this scene now. The panel follows after `followDelay`, unless it is pinned.
    func cursorMoved(to sceneID: String) {
        guard !pinned else { return }
        if shownScene == nil { show(sceneID); return }
        guard sceneID != shownScene else { followTimer?.invalidate(); followTimer = nil; return }
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: followDelay, repeats: false) { [weak self] _ in self?.show(sceneID) }
    }

    func show(_ sceneID: String) {
        followTimer?.invalidate()
        followTimer = nil
        if shownScene != sceneID { commitEdits() }
        shownScene = sceneID
        refresh()
    }

    @objc private func pinChanged() {
        pinned = pinButton.state == .on
        if !pinned, let scene = cursorScene() { cursorMoved(to: scene) }
    }

    func setPinned(_ on: Bool) {
        pinButton.state = on ? .on : .off
        pinChanged()
    }

    // MARK: Showing

    private var subscriptions: [Subscription] = []
    /// For the checks: is the button that asks the model on?
    var writeEnabled: Bool { writeButton.isEnabled }

    /// The button that asks the model follows the connection.
    private func updateWriteButton() {
        writeButton.isEnabled = AIService.shared.isReady
        writeButton.toolTip = AIService.shared.unavailableReason ?? L("The model writes a synopsis; Tab accepts it, Esc drops it")
    }

    /// Shows the scene again (after a change in the book).
    func refresh() {
        guard isViewLoaded else { return }
        updateWriteButton()
        found = []
        if let id = shownScene, let info = sceneInfo(id) {
            titleLabel.stringValue = info.title
            pathLabel.stringValue = info.path
            infoLabel.stringValue = L("{status}  ·  {size}", ["status": L(info.status ?? "idea"), "size": Lp("{n} character||text", "{n} characters||text", info.characters)])
            let record = editor()?.record(id)
            setText(synopsis, record?.string("synopsis") ?? "")
            setText(note, record?.string("note") ?? "")
            synopsis.isEditable = true; note.isEditable = true
            found = SceneMembers.characters(inScene: id, text: sceneText(id), store: characterStore)
            let names = characterStore.characters.filter { found.contains($0.id ?? "") }.compactMap(\.name)
            inSceneLabel.stringValue = names.isEmpty ? L("None found") : names.joined(separator: ", ")
            placesLabel.stringValue = placesFound(in: id)
        } else {
            titleLabel.stringValue = L("No scene")
            pathLabel.stringValue = ""; infoLabel.stringValue = ""; inSceneLabel.stringValue = ""; placesLabel.stringValue = ""
            setText(synopsis, ""); setText(note, "")
            synopsis.isEditable = false; note.isEditable = false
        }
        reloadCharacters()
        if shownTab == .world { worldTab.refresh(scene: shownScene) }
        if shownTab == .events { eventsTab.refresh(scene: shownScene) }
        if shownTab == .research { researchTab.refresh(scene: shownScene) }
    }

    /// The worlds, places and things whose names are in the scene's text (found in any case form, with or without a capital).
    func placesFound(in scene: String) -> String {
        guard let worldStore else { return "" }
        let hits = SceneMembers.places(inScene: scene, text: sceneText(scene), store: worldStore)
        let names = (worldStore.worlds.map { ($0.id, $0.name) } + worldStore.entries.map { ($0.id, $0.name) })
            .filter { hits.contains($0.0 ?? "") }.compactMap(\.1)
        return names.isEmpty ? L("None found") : names.joined(separator: ", ")
    }

    private func setText(_ tv: NSTextView, _ text: String) {
        if tv.string != text { tv.string = text }
        tv.undoManager?.removeAllActions()
    }

    // MARK: Section texts

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        if tv === characterNotes { dirty.insert("character"); scheduleSave(); return }
        guard tv === synopsis || tv === note else { return }
        dirty.insert(tv === synopsis ? "synopsis" : "note")
        scheduleSave()
    }

    func textDidEndEditing(_ notification: Notification) { commitEdits() }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.commitEdits() }
    }

    /// Writes what was typed here and not yet saved.
    @objc func commitEdits() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard !dirty.isEmpty else { return }
        let pending = dirty
        dirty = []
        if let id = shownScene, let editor = editor() {
            if pending.contains("synopsis") { try? editor.setText(id, key: "synopsis", to: synopsis.string) }
            if pending.contains("note") { try? editor.setText(id, key: "note", to: note.string) }
        }
        if pending.contains("character") { saveCharacter() }
        worldTab.commitEdits(); eventsTab.commitEdits(); researchTab.commitEdits()
        onChange?()
    }

    // MARK: Characters

    private func reloadCharacters() {
        let all = characterStore.characters
        listed = allBox.state == .on ? all : all.filter { found.contains($0.id ?? "") }
        table.reloadData()
        if let selected = selectedCharacter, let row = listed.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !listed.isEmpty, selectedCharacter == nil || !listed.contains(where: { $0.id == selectedCharacter }) {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        showCard()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { listed.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = listed[row]
        let cell = NSTextField(labelWithString: record.name ?? "")
        cell.font = .systemFont(ofSize: 13, weight: record.main ? .semibold : .regular)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        commitEdits()
        let row = table.selectedRow
        selectedCharacter = row >= 0 && row < listed.count ? listed[row].id : nil
        showCard()
    }

    private func showCard() {
        let record = selectedCharacter.flatMap { characterStore.character($0) }
        let on = record != nil
        for f in [nameField, aliasField] { f.isEnabled = on }
        mainBox.isEnabled = on
        characterNotes.isEditable = on
        nameField.stringValue = record?.name ?? ""
        aliasField.stringValue = record?.aliases.joined(separator: ", ") ?? ""
        mainBox.state = record?.main == true ? .on : .off
        setText(characterNotes, record?.notes.joined(separator: "\n") ?? "")
        updateSceneLinkButton()
    }

    // MARK: Linking the chosen character to the scene by hand

    /// What the button under the list does for the chosen character: the name is in the text (nothing to do), it is linked by hand (take that away),
    /// or it is not in the scene (link it).
    private enum SceneLinkAction { case add, remove }
    private var sceneLinkAction: SceneLinkAction?

    private func updateSceneLinkButton() {
        sceneLinkAction = nil
        if let scene = shownScene, let id = selectedCharacter, let c = characterStore.character(id) {
            let byName = SceneMembers.named(entries: characterStore.entries, in: sceneText(scene)).contains(id)
            if !byName { sceneLinkAction = (c.links[scene] != nil || c.povScenes.contains(scene)) ? .remove : .add }
        }
        sceneLinkButton.isHidden = sceneLinkAction == nil
        sceneLinkButton.title = sceneLinkAction == .remove ? L("Remove from This Scene") : L("Add to This Scene")
    }

    /// For the checks: the title of the button under the list, or nil when there is none.
    var sceneLinkTitle: String? { sceneLinkButton.isHidden ? nil : sceneLinkButton.title }

    @objc private func sceneLinkPressed() {
        guard let scene = shownScene, let id = selectedCharacter else { return }
        switch sceneLinkAction {
        case .add?: try? characterStore.update(id) { var l = $0.links; if l[scene] == nil { l[scene] = "" }; $0.links = l }
        case .remove?: try? characterStore.update(id) { var l = $0.links; l.removeValue(forKey: scene); $0.links = l; $0.povScenes = $0.povScenes.filter { $0 != scene } }
        case nil: return
        }
        refresh()
        onChange?()
    }

    /// Shows the Characters tab with this character chosen.
    func selectCharacter(_ id: String) {
        guard visibleTabs.contains(.characters) else { return }
        showTab(.characters)
        // Not in the scene (yet): the whole list is shown, so that the character is in it.
        let inScene = shownScene.map { SceneMembers.characters(inScene: $0, text: sceneText($0), store: characterStore).contains(id) } ?? false
        allBox.state = inScene ? .off : .on
        selectedCharacter = id
        refresh()
    }

    /// Shows the World tab with this place chosen.
    func selectPlace(_ id: String) {
        guard visibleTabs.contains(.world) else { return }
        showTab(.world)
        worldTab.selectedID = id
        worldTab.refresh(scene: shownScene)
    }

    @objc private func allChanged() { reloadCharacters() }

    @objc private func addCharacter() {
        guard let id = try? characterStore.add(name: L("New character")) else { return }
        selectedCharacter = id
        allBox.state = .on
        reloadCharacters()
        view.window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
        onChange?()
    }

    @objc private func mainChanged() { saveCharacter() }

    func controlTextDidEndEditing(_ obj: Notification) { saveCharacter() }

    /// Writes the card to the character's file, then lists the characters again.
    func saveCharacter() {
        guard let id = selectedCharacter, characterStore.character(id) != nil else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = aliasField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let notes = characterNotes.string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        try? characterStore.update(id) {
            if !name.isEmpty { $0.name = name }
            $0.aliases = aliases
            $0.main = mainBox.state == .on
            $0.notes = notes
        }
        let keep = selectedCharacter
        refreshAfterCharacterEdit()
        selectedCharacter = keep
        onChange?()
    }

    private func refreshAfterCharacterEdit() {
        let all = characterStore.characters
        found = shownScene.map { SceneMembers.characters(inScene: $0, text: sceneText($0), store: characterStore) } ?? []
        listed = allBox.state == .on ? all : all.filter { found.contains($0.id ?? "") }
        table.reloadData()
        if let selected = selectedCharacter, let row = listed.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        inSceneLabel.stringValue = {
            let names = all.filter { found.contains($0.id ?? "") }.compactMap(\.name)
            return names.isEmpty ? L("None found") : names.joined(separator: ", ")
        }()
    }
}
