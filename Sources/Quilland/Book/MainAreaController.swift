import AppKit
import QuillandCore

/// The main area of an open book's window: Panels (the tree and one scene), Book mode, Compare, or the Plan canvas (more views come later), for one book.
final class MainAreaController: NSViewController {
    enum Mode: String { case panels, book, outline, characters, world, events, research, reminders, plan, graph }

    let folder: URL
    var session: BookSession
    private(set) var mode: Mode
    private(set) var typewriter = false
    /// Focus Mode (Book mode only): only the text, the line with the cursor in the middle.
    private(set) var focusMode = false
    private var beforeFocus: Bool?
    var onFocusModeChange: ((Bool) -> Void)?
    /// The view (mode) has changed: the window shows its name in the title.
    var onModeChange: (() -> Void)?
    /// Something kept in the book's local state changed (the place the Graph view is looking at): it is to be saved.
    var onStateChanged: (() -> Void)?
    private(set) var controllers: [BookViewController] = []
    private(set) var planController: PlanCanvasController?
    private(set) var tree: StructureTreeController?
    private(set) var outlineDetail: OutlineDetailController?
    /// The writing mode the author comes back to from a full-area view (Esc).
    private(set) var writingMode: Mode = .panels
    /// Synopsis and note of every section, for the Outline's hover text and note marks.
    var sectionTexts: [String: (synopsis: String?, note: String?)] = [:]
    private var panelsSplit: NSSplitViewController?
    let banner = UndoBannerView()
    /// What each structural change did, newest last: the snapshots from before and after it.
    struct StructureUndo { var name: String; var pre: SnapshotStore.Info; var post: SnapshotStore.Info? }
    var undoStack: [StructureUndo] = []
    /// What was undone and can be done again: `post` is the book as it was just before the undo.
    var redoStack: [StructureUndo] = []
    private var outerSplit: NSSplitViewController?
    private(set) var showsRightPanel: Bool
    private(set) lazy var rightPanel: RightPanelController = makeRightPanel()
    private(set) lazy var characters: CharacterStore = {
        let store = CharacterStore(book: folder)
        store.extraAliases = { [weak self] id in self?.eventStore.addedAliases(of: id) ?? [] }   // the names events add count for the text matcher
        return store
    }()
    private(set) var charactersView: CharactersViewController?
    private(set) lazy var relationships = RelationshipStore(book: folder)
    /// What the model found for Collect from the Book, waiting for the author.
    /// The request that is writing a continuation, if any, and where the status of the AI is shown (the window's status bar).
    var continueTask: Task<Void, Never>?
    var onAIStatus: ((String?) -> Void)?
    /// The conversation with the model about this book (a new one each time the book is opened).
    private(set) lazy var chatSession: ChatSession = { let c = ChatSession(); c.main = self; c.loadRecent(); return c }()
    private(set) lazy var collect: CollectSession = { let c = CollectSession(); c.main = self; return c }()
    private(set) lazy var worlds = WorldStore(book: folder)
    private(set) var worldView: WorldViewController?
    private(set) lazy var eventStore = EventStore(book: folder)
    private(set) var eventsView: EventsViewController?
    private(set) var graphView: GraphViewController?
    /// What the Graph view is set to (kept here, as the view is made again each time).
    var graphState = GraphViewState()
    /// A change that was emptied in the Events view, for the banner's Undo for a moment: what puts it back, and until when.
    var effectUndo: (until: Date, run: () -> Void)?
    /// The windows of the changes that are open, by event and target.
    var changeWindows: [String: ChangesWindowController] = [:]
    private(set) lazy var researchStore = ResearchStore(book: folder)
    private(set) var researchView: ResearchViewController?
    private(set) lazy var remindersStore = RemindersStore(book: folder)
    private(set) var remindersView: RemindersViewController?
    private var countsTimer: Timer?
    /// After a rebuild the text takes the focus, except when the author was working in the tree.
    var focusTextAfterRebuild = true
    var pendingTreeSelection: String?
    /// Back and Forward between views (`+History`).
    var backPlaces: [ViewPlace] = []
    var forwardPlaces: [ViewPlace] = []
    var isNavigatingHistory = false
    /// Which side of the split Book view the author was last in (0 left, 1 right): where a jump to a scene goes.
    var activeAreaIndex = 0
    /// The Jump to Scene list when it is shown over the window (the views that have no jump bar of their own).
    private var jumpPopover: NSPopover?
    private(set) var jumpListOverWindow: JumpListController?
    /// An interrupted move was finished when the book was opened (the banner says so once the view is there).
    private(set) var finishedInterruptedMove = false
    private var day: LocalBookState
    private var writingSplit: NSSplitViewController?
    /// Is the Book view split into two panes (kept for the book; it shows only in the Book view)?
    private(set) var isSplit = false
    var showsSplit: Bool { mode == .book && isSplit }
    private let container = NSView()
    /// The cursor moved: the scene's id and the place in it.
    var onCursorMoved: ((String, Int) -> Void)?
    var onChange: (() -> Void)?
    var pendingCursor: (scene: String, position: Int)?

    init(folder: URL, state: LocalBookState) throws {
        self.folder = folder
        // A move or renumbering that was interrupted (a crash, a failure) is finished before anything else reads the book.
        let journal = folder.appendingPathComponent(".quilland/journal.json")
        if (try? Renumber.recover(root: folder, journal: journal)) == true { finishedInterruptedMove = true }
        let structure = try BookStructure.load(folder: folder)
        session = BookSession(structure: structure)
        // (A book last left in the old Compare view opens in the Book view, split.)
        mode = state.mode == "compare" ? .book : (Mode(rawValue: state.mode) ?? .panels)
        isSplit = state.split || state.mode == "compare"
        graphState = GraphViewState(memory: state.graph)
        if [.panels, .book].contains(mode) { writingMode = mode }
        showsRightPanel = state.rightPanel
        day = state
        planFrom = state.planFrom
        super.init(nibName: nil, bundle: nil)
        if let scene = state.scene { pendingCursor = (scene, state.position) }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var conflictObserver: NSObjectProtocol?
    deinit { conflictObserver.map(NotificationCenter.default.removeObserver) }

    override func loadView() {
        // A scene that another program changed under this one: the other version was kept, and the author is told.
        conflictObserver = NotificationCenter.default.addObserver(forName: .sceneExternalConflict, object: nil, queue: .main) { [weak self] note in
            guard let self, let doc = note.object as? SceneDocument, self.session.documents.values.contains(where: { $0 === doc }) else { return }
            self.banner.show(L("“{title}” was changed by another program. Its other version is in the book's trash folder (.quilland/trash).", ["title": doc.title]), undoable: false)
        }
        // The area, and under it the bottom panel (Search and Replace), folded away until it is asked for.
        let holder = NSViewController()
        holder.view = container
        searchPanel.main = self
        searchPanel.onClose = { [weak self] in self?.hideSearch() }
        let split = NSSplitViewController()
        split.splitView.isVertical = false
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "QuillandBottom"
        let top = NSSplitViewItem(viewController: holder)
        top.minimumThickness = 200
        let bottom = NSSplitViewItem(viewController: searchPanel)
        bottom.minimumThickness = 170
        bottom.maximumThickness = 520
        bottom.holdingPriority = NSLayoutConstraint.Priority(260)
        bottom.isCollapsed = true
        split.addSplitViewItem(top)
        split.addSplitViewItem(bottom)
        addChild(split)
        bottomSplit = split
        bottomItem = bottom
        // The banner for the last structural change sits above everything.
        let wrapper = NSView()
        banner.onUndo = { [weak self] in self?.undoStructure() }
        banner.onRedo = { [weak self] in self?.redoStructure() }
        for v in [banner, split.view] { v.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(v) }
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: wrapper.topAnchor), banner.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), banner.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            split.view.topAnchor.constraint(equalTo: banner.bottomAnchor), split.view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            split.view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), split.view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        ])
        view = wrapper
        rebuild()
        if finishedInterruptedMove { banner.show(L("Finished a move that was interrupted."), undoable: false) }
    }

    // MARK: The bottom panel

    private(set) lazy var searchPanel = SearchPanelController()
    private var bottomSplit: NSSplitViewController?
    private var bottomItem: NSSplitViewItem?
    var isSearchOpen: Bool { bottomItem?.isCollapsed == false }

    /// The bottom panel's height (the strip at its top edge and the checks use it).
    var bottomPanelHeight: CGFloat { searchPanel.view.frame.height }

    /// Gives the bottom panel this height, within its limits.
    func setBottomPanelHeight(_ height: CGFloat) {
        guard let split = bottomSplit?.splitView, bottomItem?.isCollapsed == false else { return }
        let wanted = min(max(height, bottomItem?.minimumThickness ?? 0), bottomItem?.maximumThickness ?? height)
        split.setPosition(split.bounds.height - wanted - split.dividerThickness, ofDividerAt: 0)
    }

    /// ⌘F opens Search, ⌥⌘F Replace; the field is focused and takes the selected word. Focus Mode ends first.
    func showSearch(_ mode: SearchPanelController.Mode) {
        if focusMode { setFocusMode(false) }
        let selected = activeArea?.currentSheet.flatMap { sheet -> String? in
            let r = sheet.textView.selectedRange()
            return r.length > 0 && r.length < 120 ? (sheet.textView.string as NSString).substring(with: r) : nil
        }
        _ = searchPanel.view
        bottomItem?.isCollapsed = false
        if let selected, mode == .search || mode == .replace { searchPanel.prefill(selected) }
        searchPanel.setMode(mode)
        if mode == .search || mode == .replace { searchPanel.focusFind() }
    }

    func hideSearch() {
        bottomItem?.isCollapsed = true
        activeArea.map { c in
            if let id = c.currentSceneID, let tv = c.currentSheet?.textView { _ = id; view.window?.makeFirstResponder(tv) }
        }
    }

    /// ⌘G and ⇧⌘G.
    func searchStep(_ by: Int) {
        if !isSearchOpen { showSearch(.search); return }
        searchPanel.step(by)
    }

    /// Goes to a place in a scene's text and selects it (in the writing mode, which it returns to from the Outline or the Plan).
    func reveal(scene: String, range: NSRange?) {
        guard session.document(scene) != nil else { return }
        if ![.panels, .book].contains(mode) {
            // The writing view is made again and puts the cursor back where it was: it is told to put it here.
            pendingCursor = (scene, range?.location ?? 0)
            setMode(writingMode)
        }
        if mode == .panels {
            tree?.select(scene, notify: false)
            showScene(scene)
        }
        guard let c = activeArea else { return }
        c.focus(sceneID: scene)
        if let tv = c.currentSheet?.textView, let range, NSMaxRange(range) <= tv.string.utf16.count {
            tv.setSelectedRange(range)
            tv.showFindIndicator(for: range)
        }
        c.scrollToCursor()
    }

    /// Goes to a section's synopsis or note: the Outline shows it.
    func revealSection(_ id: String) {
        pendingTreeSelection = id
        if mode == .outline { tree?.select(id) } else { setMode(.outline) }
    }

    // MARK: Modes

    /// Splits the Book view into two panes, or closes the split: the left pane stays, with the cursor where it was in it (the cursor of the right pane
    /// goes to the left pane's place). Only the Book view can be split.
    func setSplit(_ on: Bool) {
        guard mode == .book, on != isSplit else { return }
        if focusMode { setFocusMode(false) }
        if let c = controllers.first, let id = c.currentSceneID, let tv = c.currentSheet?.textView { pendingCursor = (id, tv.selectedRange().location) }
        isSplit = on
        activeAreaIndex = 0
        rebuild()
        onModeChange?()
    }

    func setMode(_ new: Mode) {
        guard new != mode else { return }
        if focusMode { setFocusMode(false) }
        recordViewChange()
        remember()
        if [.panels, .book].contains(mode) { writingMode = mode }
        mode = new
        rebuild()
        onModeChange?()
    }

    /// The scene and the place of the cursor now, so that a rebuilt view can put it back.
    func remember() {
        if let c = activeArea, let id = c.currentSceneID, let tv = c.currentSheet?.textView {
            pendingCursor = (id, tv.selectedRange().location)
        }
    }

    /// What a mode shows: the view that fills the area, and the view controller behind it when there is one (the right panel is put beside it).
    private struct Built {
        var view: NSView
        var controller: NSViewController?
    }

    /// Makes the area again for the mode it is in: what was typed is saved, the old views go, the mode's views are made and put in, and the cursor goes back.
    func rebuild() {
        // What was typed in a card and still waits for its save timer is saved before the card goes (the timers do not outlive their views).
        commitPendingEdits()
        tearDownViews()
        guard let built = buildViews() else { return }
        var content = built.view
        if showsRightPanel, !focusMode, let main = built.controller { content = besideRightPanel(main) }
        show(content)
        restoreCursor()
        onChange?()
    }

    private func tearDownViews() {
        graphView?.captureViewport()
        container.subviews.forEach { $0.removeFromSuperview() }
        controllers = []
        writingSplit = nil
        panelsSplit = nil
        outerSplit = nil
        planController = nil
        tree = nil
        outlineDetail = nil
        charactersView = nil
        worldView = nil
        eventsView = nil
        graphView = nil
        researchView = nil
        remindersView = nil
    }

    private func buildViews() -> Built? {
        switch mode {
        case .panels: return buildPanels()
        case .outline: return buildOutline()
        case .characters: return buildCharacters()
        case .world: return buildWorld()
        case .events: return buildEvents()
        case .research: return buildResearch()
        case .reminders: return buildReminders()
        case .plan: return buildPlan()
        case .graph: return buildGraph()
        case .book: return buildWriting()
        }
    }

    // MARK: The views of each mode

    /// A tree on the left and a split with one more view beside it: Panels (the tree and a scene) and the Outline (the tree and the details of a section).
    private func twoPanes(left: NSViewController, right: NSViewController, autosave: String, leftMin: CGFloat, leftMax: CGFloat, rightMin: CGFloat) -> NSSplitViewController {
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = autosave
        let leftItem = NSSplitViewItem(viewController: left)
        leftItem.minimumThickness = leftMin
        leftItem.maximumThickness = leftMax
        leftItem.holdingPriority = NSLayoutConstraint.Priority(260)
        let rightItem = NSSplitViewItem(viewController: right)
        rightItem.minimumThickness = rightMin
        split.addSplitViewItem(leftItem)
        split.addSplitViewItem(rightItem)
        return split
    }

    /// What every structure tree does: the commands of its menu, its keys, Undo and Redo, and the + button.
    private func wireStructureCommands(_ list: StructureTreeController) {
        list.onRename = { [weak self] id, title in self?.rename(id, to: title) }
        list.onCommand = { [weak self] command, id in self?.treeCommand(command, id) }
        list.canDo = { [weak self] command in self?.treeCanDo(command) ?? true }
        list.onUndo = { [weak self] in self?.undoStructure() }
        list.canUndo = { [weak self] in self?.undoStack.isEmpty == false }
        list.onRedo = { [weak self] in self?.redoStructure() }
        list.canRedo = { [weak self] in self?.redoStack.isEmpty == false }
        list.onNew = { [weak self] kind, place in self?.add(kind, place: place, fromTree: true) }
    }

    private func buildPanels() -> Built {
        let scene = pendingCursor.map(\.scene).flatMap { session.document($0) != nil ? $0 : nil } ?? session.structure.scenes.first?.id
        let c = makeBookController(only: scene)
        controllers = [c]
        let list = StructureTreeController()
        _ = list.view
        list.reload(structure: session.structure, characters: { [weak self] in self?.session.document($0)?.counts.characters ?? 0 })
        if let selected = pendingTreeSelection ?? scene { list.select(selected, notify: false) }
        pendingTreeSelection = nil
        list.onSelectScene = { [weak self] id in self?.showScene(id) }
        list.onEnterText = { [weak self] in self?.enterText() }
        wireStructureCommands(list)
        tree = list
        let split = twoPanes(left: list, right: c, autosave: "QuillandPanels", leftMin: 170, leftMax: 480, rightMin: 360)
        panelsSplit = split
        return Built(view: split.view, controller: split)
    }

    private func buildOutline() -> Built {
        let list = StructureTreeController()
        list.isOutline = true
        _ = list.view
        loadSectionTexts()
        list.synopsisOf = { [weak self] in self?.sectionTexts[$0]?.synopsis }
        list.hasNote = { [weak self] in !(self?.sectionTexts[$0]?.note ?? "").isEmpty }
        list.reload(structure: session.structure, characters: { [weak self] in self?.sectionCharacters($0) ?? 0 })
        let detail = OutlineDetailController()
        _ = detail.view
        detail.info = { [weak self] in self?.sectionInfo($0) }
        detail.totalCharacters = { [weak self] ids in ids.reduce(0) { $0 + (self?.sectionCharacters($1) ?? 0) } }
        detail.onRename = { [weak self] id, title in self?.rename(id, to: title) }
        detail.onStatus = { [weak self] id, status in self?.setStatus(id, to: status) }
        detail.onTarget = { [weak self] id, target in self?.setTarget(id, target) }
        detail.onText = { [weak self] id, key, text in self?.setSectionText(id, key: key, text) }
        detail.onOpen = { [weak self] id in self?.openInEditor(id) }
        detail.onWriteSynopsis = { [weak self] in self?.writeSynopsis() }
        list.onSelectNode = { [weak detail] ids in detail?.show(ids) }
        list.onEnterText = { [weak self] in if let id = self?.tree?.selectedID { self?.openInEditor(id) } }
        list.onEscape = { [weak self] in self?.leaveOutline() }
        list.onMove = { [weak self] ids, parent, index in self?.moveSections(ids, parent: parent, index: index) }
        wireStructureCommands(list)
        let here = pendingTreeSelection ?? pendingCursor?.scene ?? session.structure.scenes.first?.id
        pendingTreeSelection = nil
        if let here { list.select(here, notify: false); detail.show([here]) }
        tree = list
        outlineDetail = detail
        let split = twoPanes(left: list, right: detail, autosave: "QuillandOutline", leftMin: 240, leftMax: 640, rightMin: 380)
        panelsSplit = split
        let focusTree = !focusTextAfterRebuild
        focusTextAfterRebuild = true
        DispatchQueue.main.async { [weak self] in if focusTree { self?.tree?.focus() } }
        return Built(view: split.view, controller: nil)
    }

    private func buildCharacters() -> Built {
        let view = CharactersViewController()
        view.store = characters
        view.relationships = relationships
        view.scenes = { [weak self] in self?.session.structure.sceneChoices ?? [] }
        view.mentions = { [weak self] id in self?.mentions(ofCharacter: id) ?? [:] }
        view.onOpenScene = { [weak self] id in self?.reveal(scene: id, range: nil) }
        view.events = { [weak self] in self?.eventChoices() ?? [] }
        view.eventLinks = { [weak self] character in
            Dictionary(uniqueKeysWithValues: (self?.eventStore.events ?? []).compactMap { e in e.id.flatMap { id in e.characters[character].map { (id, $0) } } })
        }
        view.setEventLink = { [weak self] event, character, text in
            try? self?.eventStore.update(event) { r in
                var l = r.characters
                if let text { l[character] = text } else { l.removeValue(forKey: character) }
                r.characters = l
            }
        }
        view.onOpenEvent = { [weak self] id in self?.setMode(.events); self?.eventsView?.select(id) }
        view.onChange = { [weak self] in self?.charactersChanged() }
        view.onMerge = { [weak self] source, target in self?.mergeCharacters(source, into: target) }
        view.onDelete = { [weak self] id in self?.deleteCharacter(id) }
        view.changes = { [weak self] id in self.map { $0.eventStore.changes(of: id, sceneOrder: $0.session.structure.scenes.map(\.id)) } ?? [] }
        view.changeTooltip = { [weak self] c in self?.changeTooltip(c) ?? c.eventTitle }
        view.onOpenChange = { [weak self] event, id in self?.openChanges(event: event, target: id, kind: .character) }
        view.worldName = { [weak self] id in self?.worlds.world(id)?.name ?? id }
        view.relationshipBricks = { [weak self] id in self?.relationshipBricks(of: id) ?? [] }
        view.onOpenRelationship = { [weak self] event in self?.setMode(.events); self?.eventsView?.select(event) }
        view.onEscape = { [weak self] in self?.leaveFullAreaView() }
        view.relationFilter.source = relationFilterSource()
        _ = view.view
        charactersView = view
        return Built(view: view.view, controller: nil)
    }

    private func buildWorld() -> Built {
        let view = WorldViewController()
        view.store = worlds
        view.scenes = { [weak self] in self?.session.structure.sceneChoices ?? [] }
        view.mentions = { [weak self] entry in self?.mentions(of: entry) ?? [:] }
        view.onOpenScene = { [weak self] id in self?.reveal(scene: id, range: nil) }
        view.eventStore = eventStore
        view.events = { [weak self] in self?.eventChoices() ?? [] }
        view.onOpenEvent = { [weak self] id in self?.setMode(.events); self?.eventsView?.select(id) }
        view.onChange = { [weak self] in self?.onChange?() }
        view.onMergePlace = { [weak self] source, target in self?.mergePlaces(source, into: target) }
        view.onMergeWorld = { [weak self] source, target in self?.mergeWorlds(source, into: target) }
        view.onDelete = { [weak self] id, isWorld in self?.deletePlace(id, isWorld: isWorld) }
        view.changes = { [weak self] id in self.map { $0.eventStore.changes(of: id, sceneOrder: $0.session.structure.scenes.map(\.id)) } ?? [] }
        view.changeTooltip = { [weak self] c in self?.changeTooltip(c) ?? c.eventTitle }
        view.onOpenChange = { [weak self] event, id in self?.openChanges(event: event, target: id, kind: .place) }
        view.onPlaceToWorld = { [weak self] id in self?.placeToWorld(id) }
        view.onWorldToPlace = { [weak self] world, into, parent in self?.worldToPlace(world, intoWorld: into, parent: parent) }
        view.onEscape = { [weak self] in self?.leaveFullAreaView() }
        view.relationFilter.source = relationFilterSource()
        _ = view.view
        worldView = view
        return Built(view: view.view, controller: nil)
    }

    private func buildEvents() -> Built {
        let view = EventsViewController()
        view.events = eventStore
        view.characters = characters
        view.worlds = worlds
        view.planStore = { [folder] in try? PlanStore(folder: folder) }
        view.scenes = { [weak self] in self?.session.structure.sceneChoices ?? [] }
        view.onOpenScene = { [weak self] id in self?.reveal(scene: id, range: nil) }
        view.onOpenPlace = { [weak self] id in self?.setMode(.world); self?.worldView?.select(id) }
        view.onOpenCharacter = { [weak self] id in self?.setMode(.characters); self?.charactersView?.select(id) }
        view.onShowPlan = { [weak self] in self?.setMode(.plan) }
        view.relationships = relationships
        view.onOpenChanges = { [weak self] event, target, kind in self?.openChanges(event: event, target: target, kind: kind) }
        view.changesWindowProvider = { [weak self] event, target in self?.changeWindows[event + "|" + target] }
        view.onDelete = { [weak self] id, started in self?.deleteEvent(id, started: started) }
        view.onChange = { [weak self] in self?.onChange?() }
        view.onEscape = { [weak self] in self?.leaveFullAreaView() }
        view.relationFilter.source = relationFilterSource()
        _ = view.view
        eventsView = view
        return Built(view: view.view, controller: nil)
    }

    private func buildGraph() -> Built {
        let view = GraphViewController()
        view.characters = characters
        view.worlds = worlds
        view.events = eventStore
        view.relationships = relationships
        view.plan = { [folder] in try? PlanStore(folder: folder) }
        view.store = GraphStore(folder: folder)
        view.structure = { [weak self] in self?.session.structure ?? BookStructure(folder: URL(fileURLWithPath: "/")) }
        view.index = { [weak self] in
            guard let self else { fatalError("the book is gone") }
            return self.relationFilterSource().index()
        }
        view.sections = { [weak self] in self?.planSectionChoices() ?? [] }
        view.state = graphState
        view.onOpen = { [weak self] kind, id in
            switch kind {
            case .character: self?.setMode(.characters); self?.charactersView?.select(id)
            case .place: self?.setMode(.world); self?.worldView?.select(id)
            case .event: self?.setMode(.events); self?.eventsView?.select(id)
            case .scene: self?.reveal(scene: id, range: nil)
            case .card: self?.setMode(.plan); self?.planController?.reveal(id)
            }
        }
        view.onStateChange = { [weak self] in self?.graphState = $0 }
        view.onViewChange = { [weak self] in self?.onStateChanged?() }
        view.onChange = { [weak self] in self?.onChange?() }
        view.onEscape = { [weak self] in self?.leaveFullAreaView() }
        _ = view.view
        graphView = view
        return Built(view: view.view, controller: nil)
    }

    private func buildResearch() -> Built {
        let view = ResearchViewController()
        view.research = researchStore
        view.characters = characters
        view.worlds = worlds
        view.events = eventStore
        view.bookID = { [folder] in (try? JSONParser.parseObject(Data(contentsOf: folder.appendingPathComponent("book.json"))))?.string("id") }
        view.scenes = { [weak self] in self?.session.structure.sceneChoices ?? [] }
        view.onOpenScene = { [weak self] id in self?.reveal(scene: id, range: nil) }
        view.onOpenPlace = { [weak self] id in self?.setMode(.world); self?.worldView?.select(id) }
        view.onOpenCharacter = { [weak self] id in self?.setMode(.characters); self?.charactersView?.select(id) }
        view.onOpenEvent = { [weak self] id in self?.setMode(.events); self?.eventsView?.select(id) }
        view.onChange = { [weak self] in self?.onChange?() }
        view.onEscape = { [weak self] in self?.leaveFullAreaView() }
        _ = view.view
        researchView = view
        return Built(view: view.view, controller: nil)
    }

    private func buildReminders() -> Built {
        let view = RemindersViewController()
        view.store = remindersStore
        view.onChange = { [weak self] in self?.onChange?() }
        view.onEscape = { [weak self] in self?.leaveFullAreaView() }
        _ = view.view
        remindersView = view
        return Built(view: view.view, controller: nil)
    }

    /// The Plan; nil when its files cannot be opened (the area stays empty, as it did).
    private func buildPlan() -> Built? {
        guard let store = try? PlanStore(folder: folder) else { return nil }
        let plan = PlanCanvasController(store: store)
        plan.showsControls = true
        _ = plan.view
        plan.sectionChoices = planSectionChoices()
        plan.hiddenFor = { [weak self, weak plan] section in
            guard let self, let plan, let scene = self.firstScene(of: section) else { return [] }
            return PlanFilter.hidden(store: plan.store, sceneOrder: self.session.structure.scenes.map(\.id), from: scene)
        }
        plan.changesFor = { [weak self] id in
            guard let self, let e = self.eventStore.event(id) else { return "" }
            return GraphTexts.summary(GraphBuilder.changes(of: e, characters: self.characters, worlds: self.worlds, relationships: self.relationships))
        }
        plan.eventOrder = { [weak self] in
            guard let self else { return [] }
            return self.eventStore.ordered(sceneOrder: self.session.structure.scenes.map(\.id)).compactMap(\.id)
        }
        plan.onOpenEvent = { [weak self] id in self?.setMode(.events); self?.eventsView?.select(id) }
        plan.onEventsChanged = { [weak self] in self?.eventStore.reload() }
        plan.onShowFromChanged = { [weak self] id in self?.planFrom = id }
        plan.showFrom = planFrom.flatMap { id in plan.sectionChoices.contains { $0.id == id } ? id : nil }
        plan.onChange = { [weak self] in self?.onChange?() }
        planController = plan
        return Built(view: plan.view, controller: nil)
    }

    /// Book mode: one area of sheets, or two of them side by side when the view is split.
    private func buildWriting() -> Built {
        let count = showsSplit ? 2 : 1
        for _ in 0..<count { controllers.append(makeBookController()) }
        guard showsSplit else { return Built(view: controllers[0].view, controller: controllers[0]) }
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        for c in controllers {
            let item = NSSplitViewItem(viewController: c)
            item.minimumThickness = 320
            split.addSplitViewItem(item)
        }
        writingSplit = split
        return Built(view: split.view, controller: split)
    }

    // MARK: Around the views

    /// The right panel beside the writing area (not in the Plan, which has its own view of things).
    private func besideRightPanel(_ main: NSViewController) -> NSView {
        let outer = NSSplitViewController()
        outer.splitView.isVertical = true
        outer.splitView.dividerStyle = .thin
        outer.splitView.autosaveName = "QuillandRight"
        let writing = NSSplitViewItem(viewController: main)
        writing.minimumThickness = 420
        let side = NSSplitViewItem(viewController: rightPanel)
        side.minimumThickness = 250
        side.maximumThickness = 560
        side.holdingPriority = NSLayoutConstraint.Priority(260)
        outer.addSplitViewItem(writing)
        outer.addSplitViewItem(side)
        outerSplit = outer
        applyPanelPreferences()
        rightPanel.refresh()
        return outer.view
    }

    private func show(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor), content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor), content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    /// Where the author left off: that scene, with the cursor at that place, after the first layout.
    private func restoreCursor() {
        // In the split view the cursor goes back to the side it was in.
        guard let c = controllers.indices.contains(activeAreaIndex) ? controllers[activeAreaIndex] : controllers.first else { return }
        let focusText = focusTextAfterRebuild
        focusTextAfterRebuild = true
        var scene = pendingCursor?.scene ?? session.structure.scenes.first?.id
        if let s = scene, session.document(s) == nil { scene = session.structure.scenes.first?.id }
        let position = pendingCursor?.position ?? 0
        DispatchQueue.main.async { [weak self] in
            guard let self, let scene, self.session.document(scene) != nil else { return }
            // The other side of the split shows the same scene (the author moves it from there); the keyboard stays where it was.
            for other in self.controllers where other !== c { other.show(sceneID: scene) }
            guard focusText else {
                c.select(sceneID: scene)
                self.tree?.focus()
                return
            }
            c.focus(sceneID: scene)
            if let tv = c.currentSheet?.textView {
                tv.setSelectedRange(NSRange(location: min(position, tv.textStorage?.length ?? 0), length: 0))
                c.scrollToCursor()
            }
        }
    }

    private func makeRightPanel() -> RightPanelController {
        let panel = RightPanelController()
        panel.characterStore = characters
        panel.worldStore = worlds
        panel.eventStore = eventStore
        panel.researchStore = researchStore
        panel.sceneOrder = { [weak self] in self?.session.structure.scenes.map(\.id) ?? [] }
        panel.onOpenPlace = { [weak self] id in self?.setMode(.world); self?.worldView?.select(id) }
        panel.onOpenEvent = { [weak self] id in self?.setMode(.events); self?.eventsView?.select(id) }
        panel.onOpenResearch = { [weak self] id in self?.setMode(.research); self?.researchView?.select(id) }
        panel.cursorScene = { [weak self] in self?.currentSceneID }
        let p = AppPreferences.shared.values
        panel.followDelay = p.followDelay
        panel.sceneInfo = { [weak self] id in
            guard let self, let e = self.session.structure.scenes.first(where: { $0.id == id }), let doc = self.session.document(id) else { return nil }
            let path = e.place
            return SceneInfo(id: id, title: doc.title, path: path, status: doc.status, characters: doc.counts.characters)
        }
        panel.sceneText = { [weak self] id in self?.session.document(id)?.storage.string ?? "" }
        panel.editor = { [weak self] in self.map { BookEditor(structure: $0.session.structure) } }
        panel.onChange = { [weak self] in self?.onChange?() }
        panel.onWriteSynopsis = { [weak self] in self?.writeSynopsis() }
        panel.chatSession = chatSession
        panel.chatMentions = { [weak self] in self?.chatMentionsMenu() ?? NSMenu() }
        panel.onSaveChatAnswer = { [weak self] in self?.saveChatAnswer() }
        panel.onSaveChatAction = { [weak self] in self?.saveChatAction() }
        return panel
    }

    /// The writing area the author is in: in the split view the side whose text has the keyboard focus, or else the side they were last in.
    var activeArea: BookViewController? {
        if let responder = view.window?.firstResponder as? EditorTextView, let c = controllers.first(where: { $0.stack.sheets.contains { $0.textView === responder } }) { return c }
        return controllers.indices.contains(activeAreaIndex) ? controllers[activeAreaIndex] : controllers.first
    }

    /// ⌘J: the list of scenes. Under the jump bar of the area where the cursor is (Book: in the split view the side that is active changes);
    /// in every other view, and in Focus Mode, which has no bar, over the top of the window.
    func openJump() {
        if mode == .book, !focusMode, let area = activeArea { area.openJumpList(); return }
        showJumpListOverWindow()
    }

    var isJumpListOpen: Bool { jumpPopover?.isShown == true || controllers.contains { $0.isJumpListOpen } }

    private func showJumpListOverWindow() {
        closeJumpListOverWindow()
        let list = JumpListController(structure: session.structure, characters: { [session] in session.document($0)?.counts.characters ?? 0 })
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = list
        list.onChoose = { [weak self] id in
            self?.closeJumpListOverWindow()
            self?.reveal(scene: id, range: nil)
        }
        list.onClose = { [weak self] in self?.closeJumpListOverWindow() }
        jumpPopover = pop
        jumpListOverWindow = list
        let bounds = container.bounds
        pop.show(relativeTo: NSRect(x: bounds.midX - 1, y: bounds.maxY - 1, width: 2, height: 1), of: container, preferredEdge: .minY)
        list.select(currentSceneID)
    }

    func closeJumpListOverWindow() {
        jumpPopover?.close()
        jumpPopover = nil
        jumpListOverWindow = nil
    }

    /// View ▸ Focus Mode. Typewriter scrolling is on while it lasts and goes back to what it was.
    func setFocusMode(_ on: Bool) {
        guard on != focusMode else { return }
        remember()
        if on {
            guard mode == .book else { return }
            beforeFocus = typewriter
            typewriter = true
            bottomItem?.isCollapsed = true
            focusMode = true
        } else {
            focusMode = false
            typewriter = beforeFocus ?? false
            beforeFocus = nil
        }
        rebuild()
        onFocusModeChange?(on)
    }

    func setRightPanel(_ on: Bool) {
        guard on != showsRightPanel else { return }
        remember()
        showsRightPanel = on
        if on, let id = currentSceneID { rightPanel.show(id) }
        rebuild()
    }

    private func makeBookController(only: String? = nil) -> BookViewController {
        let c = BookViewController(session: session, only: only)
        _ = c.view
        c.setTypewriter(typewriter)
        c.onRename = { [weak self] id, title in self?.rename(id, to: title) }
        c.onStatus = { [weak self] id, status in self?.setStatus(id, to: status) }
        c.focusChrome = focusMode
        c.escapeHandler = { [weak self] in
            guard self?.focusMode == true else { return false }
            self?.setFocusMode(false)
            return true
        }
        c.onSelectionChange = { [weak self, weak c] doc, position in
            if let c, let i = self?.controllers.firstIndex(where: { $0 === c }) { self?.activeAreaIndex = i }
            self?.onCursorMoved?(doc.id, position)
            self?.onChange?()
            self?.scheduleCountsRefresh()
            if self?.showsRightPanel == true { self?.rightPanel.cursorMoved(to: doc.id) }
        }
        return c
    }

    private func scheduleCountsRefresh() {
        guard countsTimer == nil else { return }
        // A moment after the author stops, the sizes in the tree and the status bar are brought up to date.
        countsTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            self?.countsTimer = nil
            self?.tree?.refreshCounts()
            self?.onChange?()
        }
    }

    // MARK: Panels: the tree and one scene

    private func showScene(_ id: String) {
        guard mode == .panels, let c = controllers.first, session.document(id) != nil else { return }
        c.show(only: id)
        c.select(sceneID: id)
        onChange?()
    }

    /// Double-click or Tab in the tree: the cursor goes into the text of the scene.
    private func enterText() {
        guard let c = controllers.first, let id = c.currentSceneID ?? tree?.selectedID else { return }
        c.focus(sceneID: id)
    }

    // MARK: The section the commands are about

    /// The section the commands are about: the tree's selection in Panels, otherwise the scene with the cursor.
    var selectedSectionID: String? { (mode == .panels || mode == .outline ? tree?.selectedID : nil) ?? currentSceneID }

    var treeHasFocus: Bool { (mode == .panels || mode == .outline) && tree?.isFirstResponder == true }

    // MARK: The Outline

    /// Back to the text from the Outline: the writing mode left, at the cursor where it was.
    func leaveOutline() { leaveFullAreaView() }

    /// Esc in a full-area view (the Outline, Characters): back to the writing mode.
    func leaveFullAreaView() { if [.outline, .characters, .world, .events, .research, .reminders, .graph].contains(mode) { setMode(writingMode) } }

    // The same for places and worlds (the World view): a snapshot before and after, so that Undo takes the change back.

    /// The book's window is closing: whatever the model is still doing for it (a continuation, a synopsis, a collection, a chat answer, a grammar check) is stopped, so
    /// that LM Studio is not left generating for a window that is gone.
    func stopAI() {
        continueTask?.cancel()
        collect.stop()
        chatSession.stop()
        searchPanel.proofView.stopGrammar()
    }

    // MARK: Settings that reach the area

    /// A preference changed: the text, the sheets, the right panel and the follow delay take it.
    func preferencesChanged() {
        session.preferencesChanged()
        controllers.forEach { $0.preferencesChanged() }
        applyPanelPreferences()
        onChange?()
    }

    func applyPanelPreferences() {
        let p = AppPreferences.shared.values
        let tabs = p.panelTabs.compactMap { name -> RightPanelController.Tab? in ["section": .section, "characters": .characters, "world": .world, "events": .events, "research": .research, "chat": .chat][name] }
        rightPanel.setVisibleTabs(tabs)
        rightPanel.followDelay = p.followDelay
    }

    /// Book Settings changed the language, the dictionary or the title.
    func bookSettingsChanged() {
        let s = BookSettings.load(book: folder)
        session.applyBookSettings(language: s.language, words: BookDictionary.load(book: folder))
        onChange?()
    }

    // MARK: Asked by the window and the menus

    func setTypewriter(_ on: Bool) {
        typewriter = on
        controllers.forEach { $0.setTypewriter(on) }
    }

    /// Characters written in the book today (negative when more was cut than written).
    var writtenToday: Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return day.written(today: f.string(from: Date()), total: session.totalCharacters)
    }

    /// Everything on screen that keeps typed text waiting for a timer of its own. A new editable view is added here: this is the one list that saving, rebuilding and
    /// closing go by (the self-test checks that each kind of editor is reached).
    private var pendingEditors: [PendingEdits] {
        let all: [PendingEdits?] = [showsRightPanel ? rightPanel : nil, outlineDetail, charactersView, worldView, eventsView, researchView, remindersView]
        return all.compactMap { $0 }
    }

    /// Tells every editor that holds typed text to save it now.
    func commitPendingEdits() { pendingEditors.forEach { $0.commitEdits() } }

    func saveAll() {
        session.saveAll()
        commitPendingEdits()
    }

    /// The scene of the area the author is in (in Compare, the side with the cursor).
    var currentSceneID: String? { activeArea?.currentSceneID ?? controllers.compactMap(\.currentSceneID).first }
    var currentDocument: SceneDocument? { currentSceneID.flatMap { session.document($0) } }

    /// The state to keep in `.quilland/state.json`.
    /// The section the Plan view starts from (what comes before it is hidden), kept with the book on this machine.
    private(set) var planFrom: String?

    /// Every part, chapter and scene, in the book's order, for the Plan view's "Show from" choice.
    func planSectionChoices() -> [(id: String, title: String, depth: Int)] {
        var out: [(id: String, title: String, depth: Int)] = []
        func walk(_ nodes: [BookStructure.Node], _ depth: Int) {
            for n in nodes { out.append((n.id, n.title, depth)); walk(n.children, depth + 1) }
        }
        walk(session.structure.roots, 0)
        return out
    }

    /// The first scene at or under a section.
    func firstScene(of id: String) -> String? { firstScene(of: id, in: session.structure) }

    func localState() -> LocalBookState {
        remember()
        graphView?.captureViewport()
        _ = writtenToday
        return LocalBookState(scene: pendingCursor?.scene, position: pendingCursor?.position ?? 0, mode: mode.rawValue, rightPanel: showsRightPanel, dayDate: day.dayDate, dayBaseline: day.dayBaseline, planFrom: planFrom, split: isSplit, graph: graphState.memory)
    }
}
