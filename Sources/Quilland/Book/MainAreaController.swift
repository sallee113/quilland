import AppKit
import QuillandCore

/// The main area of an open book's window: Panels (the tree and one scene), Book mode, Compare, or the Plan canvas (more views come later), for one book.
final class MainAreaController: NSViewController {
    enum Mode: String { case panels, book, compare, outline, characters, world, events, plan }

    let folder: URL
    private(set) var session: BookSession
    private(set) var mode: Mode
    private(set) var typewriter = false
    /// Focus Mode (Book mode only): only the text, the line with the cursor in the middle.
    private(set) var focusMode = false
    private var beforeFocus: Bool?
    var onFocusModeChange: ((Bool) -> Void)?
    private(set) var controllers: [BookViewController] = []
    private(set) var planController: PlanCanvasController?
    private(set) var tree: StructureTreeController?
    private(set) var outlineDetail: OutlineDetailController?
    /// The writing mode the author comes back to from a full-area view (Esc).
    private(set) var writingMode: Mode = .panels
    /// Synopsis and note of every section, for the Outline's hover text and note marks.
    private var sectionTexts: [String: (synopsis: String?, note: String?)] = [:]
    private var panelsSplit: NSSplitViewController?
    let banner = UndoBannerView()
    /// What each structural change did, newest last: the snapshots from before and after it.
    struct StructureUndo { var name: String; var pre: SnapshotStore.Info; var post: SnapshotStore.Info? }
    private(set) var undoStack: [StructureUndo] = []
    /// What was undone and can be done again: `post` is the book as it was just before the undo.
    private(set) var redoStack: [StructureUndo] = []
    private var outerSplit: NSSplitViewController?
    private(set) var showsRightPanel: Bool
    private(set) lazy var rightPanel: RightPanelController = makeRightPanel()
    private(set) lazy var characters = CharacterStore(book: folder)
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
    private var countsTimer: Timer?
    /// After a rebuild the text takes the focus, except when the author was working in the tree.
    private var focusTextAfterRebuild = true
    private var pendingTreeSelection: String?
    /// An interrupted move was finished when the book was opened (the banner says so once the view is there).
    private(set) var finishedInterruptedMove = false
    private var day: LocalBookState
    private var compareSplit: NSSplitViewController?
    private let container = NSView()
    /// The cursor moved: the scene's id and the place in it.
    var onCursorMoved: ((String, Int) -> Void)?
    var onChange: (() -> Void)?
    private var pendingCursor: (scene: String, position: Int)?

    init(folder: URL, state: LocalBookState) throws {
        self.folder = folder
        // A move or renumbering that was interrupted (a crash, a failure) is finished before anything else reads the book.
        let journal = folder.appendingPathComponent(".quilland/journal.json")
        if (try? Renumber.recover(root: folder, journal: journal)) == true { finishedInterruptedMove = true }
        let structure = try BookStructure.load(folder: folder)
        session = BookSession(structure: structure)
        mode = Mode(rawValue: state.mode) ?? .panels
        if [.panels, .book, .compare].contains(mode) { writingMode = mode }
        showsRightPanel = state.rightPanel
        day = state
        planFrom = state.planFrom
        super.init(nibName: nil, bundle: nil)
        if let scene = state.scene { pendingCursor = (scene, state.position) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
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

    /// ⌘F opens Search, ⌥⌘F Replace; the field is focused and takes the selected word. Focus Mode ends first.
    func showSearch(_ mode: SearchPanelController.Mode) {
        if focusMode { setFocusMode(false) }
        let selected = (controllers.first { $0.currentSceneID != nil } ?? controllers.first)?.currentSheet.flatMap { sheet -> String? in
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
        (controllers.first { $0.currentSceneID != nil } ?? controllers.first).map { c in
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
        if ![.panels, .book, .compare].contains(mode) { setMode(writingMode) }
        if mode == .panels {
            tree?.select(scene, notify: false)
            showScene(scene)
        }
        guard let c = controllers.first(where: { $0.currentSceneID != nil }) ?? controllers.first else { return }
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

    func setMode(_ new: Mode) {
        guard new != mode else { return }
        if focusMode { setFocusMode(false) }
        remember()
        if [.panels, .book, .compare].contains(mode) { writingMode = mode }
        mode = new
        rebuild()
    }

    /// The scene and the place of the cursor now, so that a rebuilt view can put it back.
    private func remember() {
        if let c = controllers.first(where: { $0.currentSceneID != nil }), let id = c.currentSceneID, let tv = c.currentSheet?.textView {
            pendingCursor = (id, tv.selectedRange().location)
        }
    }

    func rebuild() {
        container.subviews.forEach { $0.removeFromSuperview() }
        controllers = []
        compareSplit = nil
        panelsSplit = nil
        outerSplit = nil
        planController = nil
        tree = nil
        outlineDetail = nil
        charactersView = nil
        worldView = nil
        eventsView = nil
        var content: NSView
        var contentVC: NSViewController?
        switch mode {
        case .panels:
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
            list.onRename = { [weak self] id, title in self?.rename(id, to: title) }
            list.onCommand = { [weak self] command, id in self?.treeCommand(command, id) }
            list.canDo = { [weak self] command in self?.treeCanDo(command) ?? true }
            list.onUndo = { [weak self] in self?.undoStructure() }
            list.canUndo = { [weak self] in self?.undoStack.isEmpty == false }
            list.onRedo = { [weak self] in self?.redoStructure() }
            list.canRedo = { [weak self] in self?.redoStack.isEmpty == false }
            list.onNew = { [weak self] kind, place in self?.add(kind, place: place, fromTree: true) }
            tree = list
            let split = NSSplitViewController()
            split.splitView.isVertical = true
            split.splitView.dividerStyle = .thin
            split.splitView.autosaveName = "QuillandPanels"
            let left = NSSplitViewItem(viewController: list)
            left.minimumThickness = 170
            left.maximumThickness = 480
            left.holdingPriority = NSLayoutConstraint.Priority(260)
            let centre = NSSplitViewItem(viewController: c)
            centre.minimumThickness = 360
            split.addSplitViewItem(left)
            split.addSplitViewItem(centre)
            panelsSplit = split
            content = split.view
            contentVC = split
        case .outline:
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
            list.onSelectNode = { [weak detail] ids in detail?.show(ids) }
            list.onEnterText = { [weak self] in if let id = self?.tree?.selectedID { self?.openInEditor(id) } }
            list.onEscape = { [weak self] in self?.leaveOutline() }
            list.onRename = { [weak self] id, title in self?.rename(id, to: title) }
            list.onCommand = { [weak self] command, id in self?.treeCommand(command, id) }
            list.canDo = { [weak self] command in self?.treeCanDo(command) ?? true }
            list.onUndo = { [weak self] in self?.undoStructure() }
            list.canUndo = { [weak self] in self?.undoStack.isEmpty == false }
            list.onRedo = { [weak self] in self?.redoStructure() }
            list.canRedo = { [weak self] in self?.redoStack.isEmpty == false }
            list.onNew = { [weak self] kind, place in self?.add(kind, place: place, fromTree: true) }
            list.onMove = { [weak self] ids, parent, index in self?.moveSections(ids, parent: parent, index: index) }
            let here = pendingTreeSelection ?? pendingCursor?.scene ?? session.structure.scenes.first?.id
            pendingTreeSelection = nil
            if let here { list.select(here, notify: false); detail.show([here]) }
            tree = list
            outlineDetail = detail
            detail.onWriteSynopsis = { [weak self] in self?.writeSynopsis() }
            let split = NSSplitViewController()
            split.splitView.isVertical = true
            split.splitView.dividerStyle = .thin
            split.splitView.autosaveName = "QuillandOutline"
            let left = NSSplitViewItem(viewController: list)
            left.minimumThickness = 240
            left.maximumThickness = 640
            left.holdingPriority = NSLayoutConstraint.Priority(260)
            let right = NSSplitViewItem(viewController: detail)
            right.minimumThickness = 380
            split.addSplitViewItem(left)
            split.addSplitViewItem(right)
            panelsSplit = split
            content = split.view
            let focusTree = !focusTextAfterRebuild
            focusTextAfterRebuild = true
            DispatchQueue.main.async { [weak self] in if focusTree { self?.tree?.focus() } }
        case .characters:
            let view = CharactersViewController()
            view.store = characters
            view.relationships = relationships
            view.scenes = { [weak self] in
                self?.session.structure.scenes.map { e in
                    (e.id, [e.partTitle, e.chapterTitle, e.node.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › "))
                } ?? []
            }
            view.mentions = { [weak self] id in self?.mentions(ofCharacter: id) ?? [:] }
            view.onOpenScene = { [weak self] id in self?.reveal(scene: id, range: nil) }
            view.onChange = { [weak self] in self?.charactersChanged() }
            view.onEscape = { [weak self] in self?.leaveFullAreaView() }
            _ = view.view
            charactersView = view
            content = view.view
            contentVC = nil
        case .world:
            let view = WorldViewController()
            view.store = worlds
            view.scenes = { [weak self] in
                self?.session.structure.scenes.map { e in
                    (e.id, [e.partTitle, e.chapterTitle, e.node.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › "))
                } ?? []
            }
            view.mentions = { [weak self] entry in self?.mentions(of: entry) ?? [:] }
            view.onOpenScene = { [weak self] id in self?.reveal(scene: id, range: nil) }
            view.onChange = { [weak self] in self?.onChange?() }
            view.onEscape = { [weak self] in self?.leaveFullAreaView() }
            _ = view.view
            worldView = view
            content = view.view
            contentVC = nil
        case .events:
            let view = EventsViewController()
            view.events = eventStore
            view.characters = characters
            view.worlds = worlds
            view.planStore = { [folder] in try? PlanStore(folder: folder) }
            view.scenes = { [weak self] in
                self?.session.structure.scenes.map { e in
                    (e.id, [e.partTitle, e.chapterTitle, e.node.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › "))
                } ?? []
            }
            view.onOpenScene = { [weak self] id in self?.reveal(scene: id, range: nil) }
            view.onOpenPlace = { [weak self] id in self?.setMode(.world); self?.worldView?.select(id) }
            view.onOpenCharacter = { [weak self] id in self?.setMode(.characters); self?.charactersView?.select(id) }
            view.onShowPlan = { [weak self] in self?.setMode(.plan) }
            view.onChange = { [weak self] in self?.onChange?() }
            view.onEscape = { [weak self] in self?.leaveFullAreaView() }
            _ = view.view
            eventsView = view
            content = view.view
            contentVC = nil
        case .plan:
            guard let store = try? PlanStore(folder: folder) else { return }
            let plan = PlanCanvasController(store: store)
            plan.showsControls = true
            _ = plan.view
            plan.sectionChoices = planSectionChoices()
            plan.hiddenFor = { [weak self, weak plan] section in
                guard let self, let plan, let scene = self.firstScene(of: section) else { return [] }
                return PlanFilter.hidden(store: plan.store, sceneOrder: self.session.structure.scenes.map(\.id), from: scene)
            }
            plan.onOpenEvent = { [weak self] id in self?.setMode(.events); self?.eventsView?.select(id) }
            plan.onShowFromChanged = { [weak self] id in self?.planFrom = id }
            plan.showFrom = planFrom.flatMap { id in plan.sectionChoices.contains { $0.id == id } ? id : nil }
            plan.onChange = { [weak self] in self?.onChange?() }
            planController = plan
            content = plan.view
        case .book, .compare:
            let count = mode == .compare ? 2 : 1
            for _ in 0..<count { controllers.append(makeBookController()) }
            if mode == .compare {
                let split = NSSplitViewController()
                split.splitView.isVertical = true
                split.splitView.dividerStyle = .thin
                for c in controllers {
                    let item = NSSplitViewItem(viewController: c)
                    item.minimumThickness = 320
                    split.addSplitViewItem(item)
                }
                compareSplit = split
                content = split.view
                contentVC = split
            } else {
                content = controllers[0].view
                contentVC = controllers[0]
            }
        }
        if showsRightPanel, !focusMode, let main = contentVC {
            // The right panel beside the writing area (not in the Plan, which has its own view of things).
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
            content = outer.view
            applyPanelPreferences()
            rightPanel.refresh()
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor), content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor), content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        if let c = controllers.first {
            // Where the author left off: that scene, with the cursor at that place, after the first layout.
            let focusText = focusTextAfterRebuild
            focusTextAfterRebuild = true
            var scene = pendingCursor?.scene ?? session.structure.scenes.first?.id
            if let s = scene, session.document(s) == nil { scene = session.structure.scenes.first?.id }
            let position = pendingCursor?.position ?? 0
            DispatchQueue.main.async { [weak self] in
                guard let self, let scene, self.session.document(scene) != nil else { return }
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
        onChange?()
    }

    private func makeRightPanel() -> RightPanelController {
        let panel = RightPanelController()
        panel.characterStore = characters
        panel.worldStore = worlds
        panel.eventStore = eventStore
        panel.sceneOrder = { [weak self] in self?.session.structure.scenes.map(\.id) ?? [] }
        panel.onOpenPlace = { [weak self] id in self?.setMode(.world); self?.worldView?.select(id) }
        panel.onOpenEvent = { [weak self] id in self?.setMode(.events); self?.eventsView?.select(id) }
        panel.cursorScene = { [weak self] in self?.currentSceneID }
        let p = AppPreferences.shared.values
        panel.followDelay = p.followDelay
        panel.sceneInfo = { [weak self] id in
            guard let self, let e = self.session.structure.scenes.first(where: { $0.id == id }), let doc = self.session.document(id) else { return nil }
            let path = [e.partTitle, e.chapterTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › ")
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

    /// ⌘J: the jump list of the area where the cursor is (Book, Compare); in Panels and the Outline the tree takes the focus.
    func openJump() {
        switch mode {
        case .book, .compare: (controllers.first { $0.currentSceneID != nil } ?? controllers.first)?.openJumpList()
        case .panels, .outline: tree?.focus()
        case .characters, .world, .events, .plan: break
        }
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
        c.onSelectionChange = { [weak self] doc, position in
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

    // MARK: Changing the structure

    /// The section the commands are about: the tree's selection in Panels, otherwise the scene with the cursor.
    var selectedSectionID: String? { (mode == .panels || mode == .outline ? tree?.selectedID : nil) ?? currentSceneID }

    private func treeCommand(_ command: StructureTreeController.Command, _ id: String) {
        switch command {
        case .newSceneAfter: add(.scene, place: .after, anchor: id, fromTree: true)
        case .newSceneBefore: add(.scene, place: .before, anchor: id, fromTree: true)
        case .newChapter: add(.chapter, place: .after, anchor: id, fromTree: true)
        case .newPart: add(.part, place: .after, anchor: id, fromTree: true)
        case .moveUp: move(id, by: -1)
        case .moveDown: move(id, by: 1)
        case .delete: delete(id)
        case .status(let s): setStatus(id, to: s)
        case .mergeNext: merge(id, direction: 1)
        case .mergePrevious: merge(id, direction: -1)
        case .group: groupIntoPart()
        case .ungroup: ungroupPart(id)
        }
    }

    private var treeHasFocus: Bool { (mode == .panels || mode == .outline) && tree?.isFirstResponder == true }

    func add(_ kind: BookStructure.Kind, place: BookEditor.Place = .after, anchor: String? = nil, fromTree: Bool = false) {
        let inTree = fromTree || treeHasFocus
        restructure(focusText: !inTree, beginRename: inTree, undoName: L("New {kind}", ["kind": L(kind.rawValue.capitalized)])) { editor in
            try editor.add(kind, relativeTo: anchor ?? self.selectedSectionID, place: place)
        }
    }

    func move(_ id: String? = nil, by step: Int) {
        guard let id = id ?? selectedSectionID else { return }
        restructure(focusText: !treeHasFocus, undoName: L("Move")) { editor in
            try editor.moveAcrossChapters(id, by: step)
            return id
        }
    }

    func setStatus(_ id: String? = nil, to status: String) {
        guard let id = id ?? selectedSectionID, session.structure.scenes.contains(where: { $0.id == id }) else { return }
        do { try BookEditor(structure: session.structure).setStatus(id, to: status) } catch { report(error); return }
        session.applyInfo(id: id, status: status)
        afterInfoChange()
    }

    func rename(_ id: String, to title: String) {
        do { try BookEditor(structure: session.structure).rename(id, to: title) } catch { report(error); return }
        session.applyInfo(id: id, title: title)
        afterInfoChange()
    }

    private func afterInfoChange() {
        tree?.reload(structure: session.structure, characters: { [weak self] in self?.sectionCharacters($0) ?? 0 })
        outlineDetail?.refresh()
        controllers.forEach { $0.updateJumpBar() }
        onChange?()
    }

    // MARK: The Outline

    /// A synopsis or a note was changed from outside the views that show them (Replace): they read them again.
    func didChangeSectionTexts() {
        loadSectionTexts()
        tree?.refreshCounts()
        outlineDetail?.refresh()
        if showsRightPanel { rightPanel.refresh() }
        onChange?()
    }

    private func loadSectionTexts() {
        sectionTexts = [:]
        let editor = BookEditor(structure: session.structure)
        func visit(_ node: BookStructure.Node) {
            let record = editor.record(node.id)
            sectionTexts[node.id] = (record?.string("synopsis"), record?.string("note"))
            node.children.forEach(visit)
        }
        session.structure.roots.forEach(visit)
    }

    private func scenes(under id: String) -> [BookStructure.Node] {
        guard let node = findNode(id) else { return [] }
        func collect(_ n: BookStructure.Node) -> [BookStructure.Node] { n.kind == .scene ? [n] : n.children.flatMap(collect) }
        return collect(node)
    }

    /// The size of a scene, a chapter or a part, in characters.
    func sectionCharacters(_ id: String) -> Int { scenes(under: id).reduce(0) { $0 + (session.document($1.id)?.counts.characters ?? 0) } }

    func sectionInfo(_ id: String) -> SectionInfo? {
        guard let node = findNode(id) else { return nil }
        let entry = session.structure.scenes.first { $0.id == id }
        let path: String
        switch node.kind {
        case .scene: path = [entry?.partTitle, entry?.chapterTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › ")
        case .chapter: path = session.structure.scenes.first { $0.chapterID == id }?.partTitle ?? ""
        case .part: path = ""
        }
        let record = BookEditor(structure: session.structure).record(id)
        let list = scenes(under: id)
        let statuses = SceneRecord.knownStatuses.map { st in (status: st, count: list.filter { (session.document($0.id)?.status ?? "idea") == st }.count) }
        let matcher = ParadigmMatcher(entries: characters.entries)
        var found = Set<String>()
        for scene in list { found.formUnion(matcher.matches(in: session.document(scene.id)?.storage.string ?? "").map(\.entry)) }
        let names = characters.characters.filter { found.contains($0.id ?? "") }.compactMap(\.name)
        return SectionInfo(id: id, kind: node.kind, title: node.title, path: path, status: session.document(id)?.status ?? node.status,
                           characters: sectionCharacters(id), target: record?.int("target_characters"),
                           synopsis: record?.string("synopsis") ?? "", note: record?.string("note") ?? "",
                           sceneStatuses: statuses, sceneCount: list.count, characterNames: names)
    }

    func setSectionText(_ id: String, key: String, _ text: String) {
        do { try BookEditor(structure: session.structure).setText(id, key: key, to: text) } catch { report(error); return }
        var entry = sectionTexts[id] ?? (nil, nil)
        if key == "synopsis" { entry.synopsis = text.isEmpty ? nil : text } else { entry.note = text.isEmpty ? nil : text }
        sectionTexts[id] = entry
        tree?.refreshCounts()
        onChange?()
    }

    func setTarget(_ id: String, _ target: Int?) {
        do { try BookEditor(structure: session.structure).setTarget(id, to: target) } catch { report(error); return }
        outlineDetail?.refresh()
    }

    /// Back to the text from the Outline: the writing mode left, at the cursor where it was.
    func leaveOutline() { leaveFullAreaView() }

    /// Esc in a full-area view (the Outline, Characters): back to the writing mode.
    func leaveFullAreaView() { if [.outline, .characters, .world, .events].contains(mode) { setMode(writingMode) } }

    /// How many times a character's name is in each scene (only the scenes where it is).
    func mentions(ofCharacter id: String) -> [String: Int] {
        guard let record = characters.character(id), let name = record.name else { return [:] }
        return mentions(of: NameEntry(id: id, name: name, aliases: record.aliases))
    }

    /// How many times a name (or one of its aliases) is in each scene (only the scenes where it is).
    func mentions(of entry: NameEntry) -> [String: Int] {
        let matcher = ParadigmMatcher(entries: [entry])
        var out: [String: Int] = [:]
        for e in session.structure.scenes {
            let n = matcher.matches(in: session.document(e.id)?.storage.string ?? "").count
            if n > 0 { out[e.id] = n }
        }
        return out
    }

    /// A character was added, renamed or changed in the Characters view: the right panel reads it again.
    func charactersChanged() {
        if showsRightPanel { rightPanel.refresh() }
        onChange?()
    }

    /// Opens the section's first scene in the writing mode.
    func openInEditor(_ id: String) {
        guard let scene = firstScene(of: id, in: session.structure) else { return }
        pendingCursor = (scene, 0)
        if mode == .outline { setMode(writingMode) }
    }

    /// Rows were dropped in the Outline: they go before the sibling that was at the drop place (or to the end), in book order.
    func moveSections(_ ids: [String], parent: String?, index: Int?) {
        let siblings = parent.flatMap { findNode($0)?.children } ?? (parent == nil ? session.structure.roots : [])
        let anchor = index.flatMap { i in siblings.dropFirst(i).first { !ids.contains($0.id) }?.id }
        restructure(focusText: false, undoName: "Move") { [folder] _ in
            for id in ids {
                let fresh = try BookStructure.load(folder: folder)
                func find(_ target: String, in nodes: [BookStructure.Node]) -> BookStructure.Node? {
                    for n in nodes { if n.id == target { return n }; if let f = find(target, in: n.children) { return f } }
                    return nil
                }
                let list = parent.flatMap { find($0, in: fresh.roots)?.children } ?? fresh.roots
                let at = anchor.flatMap { a in list.firstIndex { $0.id == a } } ?? list.count
                try BookEditor(structure: fresh).move(id, toParent: parent, at: at)
            }
            return ids.first
        }
    }

    /// Rename from the menu: the tree edits in place; elsewhere a small window asks.
    func renameSelected() {
        guard let id = selectedSectionID else { return }
        if mode == .panels || mode == .outline, let tree { tree.focus(); tree.beginRename(); return }
        guard let node = findNode(id) else { return }
        let field = NSTextField(string: node.title)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = L("Rename")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { rename(id, to: title) }
    }

    func findNode(_ id: String) -> BookStructure.Node? {
        func search(_ nodes: [BookStructure.Node]) -> BookStructure.Node? {
            for n in nodes { if n.id == id { return n }; if let f = search(n.children) { return f } }
            return nil
        }
        return search(session.structure.roots)
    }

    /// Asks, then takes the section out of the book (into `.quilland/trash`). Cancel is the default.
    func delete(_ id: String? = nil, confirm: Bool = true) {
        guard let id = id ?? selectedSectionID, let node = findNode(id) else { return }
        let editor = BookEditor(structure: session.structure)
        let weight = editor.weight(of: id) { [session] in session.document($0)?.counts.characters ?? 0 }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            switch node.kind {
            case .scene: alert.messageText = L("Delete the scene “{title}”?", ["title": node.title])
            case .chapter: alert.messageText = L("Delete the chapter “{title}”?", ["title": node.title])
            case .part: alert.messageText = L("Delete the part “{title}”?", ["title": node.title])
            }
            let number = { (n: Int) in NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
            alert.informativeText = node.kind == .scene
                ? L("The scene has {size}. Its files go to the book's trash folder (.quilland/trash).", ["size": Lp("{n} character||text", "{n} characters||text", weight.characters)])
                : L("It holds {scenes} with {size} in all. Their files go to the book's trash folder (.quilland/trash).", ["scenes": Lp("{n} scene", "{n} scenes", weight.scenes), "size": Lp("{n} character||text", "{n} characters||text", weight.characters)])
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let remove = alert.addButton(withTitle: L("Delete"))
            remove.keyEquivalent = ""
            remove.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        // The cursor goes to the scene before the deleted one's place, or the next.
        let scenes = session.structure.scenes.map(\.id)
        var inside = Set<String>()
        func collect(_ n: BookStructure.Node) { if n.kind == .scene { inside.insert(n.id) }; n.children.forEach(collect) }
        collect(node)
        let first = scenes.firstIndex { inside.contains($0) } ?? 0
        let after = scenes.first { !inside.contains($0) && (scenes.firstIndex(of: $0) ?? 0) > first }
        let before = first > 0 ? scenes[first - 1] : nil
        let keep = inside.contains(currentSceneID ?? "") ? (before ?? after) : currentSceneID
        restructure(focusText: !treeHasFocus, cursorScene: keep, undoName: L("Delete “{title}”", ["title": node.title])) { editor in
            try editor.delete(id)
            return nil
        }
    }

    /// Does a structural change, then reads the book again: the files were renumbered, so every scene is loaded anew.
    private func restructure(focusText: Bool, beginRename: Bool = false, cursorScene: String? = nil, undoName: String = L("Change"), _ change: (BookEditor) throws -> String?) {
        saveAll()
        remember()
        // A change that touches files takes a snapshot first, and another after it, so that Undo can tell whether the book moved on since.
        let snapshots = SnapshotStore(bookFolder: folder)
        let pre = try? snapshots.take(.beforeOperation, reason: L("Before {action}", ["action": undoName]))
        let editor = BookEditor(structure: session.structure)
        let selectedID: String?
        do { selectedID = try change(editor) } catch { report(error); return }
        if let pre {
            let post = try? snapshots.take(.automatic, reason: L("After {action}", ["action": undoName]))
            undoStack.append(StructureUndo(name: undoName, pre: pre, post: post))
            redoStack.removeAll()
            if undoStack.count > 20 { undoStack.removeFirst() }
            banner.show(L("{action}.", ["action": undoName]), undoable: true)
        }
        // Merging moves links in the data files: the stores read them again.
        characters.reload()
        relationships.reload()
        worlds.reload()
        eventStore.reload()
        guard let structure = try? BookStructure.load(folder: folder) else { return }
        session = BookSession(structure: structure)
        // Where the cursor goes: the scene of the new or moved section (a chapter's or a part's first scene), otherwise where it was.
        if let cursorScene { pendingCursor = (cursorScene, 0) }
        else if mode != .outline, let id = selectedID, let scene = firstScene(of: id, in: structure) {
            pendingCursor = scene == pendingCursor?.scene ? pendingCursor : (scene, 0)
        }
        pendingTreeSelection = selectedID
        focusTextAfterRebuild = focusText
        rebuild()
        if beginRename { tree?.beginRename() }
    }

    // MARK: Undo of structure

    /// Puts the book back as it was before the last structural change (⌘Z in the tree or the Outline, or the banner's button).
    /// Anything written since is taken back too, so that is asked first; a safety snapshot is taken either way.
    func undoStructure(confirm: Bool = true) {
        guard let entry = undoStack.last else { return }
        saveAll()
        let snapshots = SnapshotStore(bookFolder: folder)
        if confirm, let post = entry.post, snapshots.changed(since: post) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Undo “{name}”?", ["name": entry.name])
            alert.informativeText = L("The book has changed since then (text written, or other changes). Undo takes the whole book back to how it was before “{name}”. A snapshot of the book as it is now is taken first, so nothing is lost.", ["name": entry.name])
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Undo"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let before: SnapshotStore.Info
        do { before = try snapshots.restoreAll(from: entry.pre) } catch { report(error); return }
        undoStack.removeLast()
        redoStack.append(StructureUndo(name: entry.name, pre: entry.pre, post: before))
        reloadFromDisk()
        banner.show(L("Undone: {name}.", ["name": entry.name]), undoable: false, redo: true)
    }

    /// Does again what Undo took back (⇧⌘Z in the tree or the Outline, or the banner's button): the book as it was just before the undo is put back.
    /// What was written since the undo is taken too, so that is asked first; a safety snapshot is taken either way.
    func redoStructure(confirm: Bool = true) {
        guard let entry = redoStack.last, let target = entry.post else { return }
        saveAll()
        let snapshots = SnapshotStore(bookFolder: folder)
        if confirm, snapshots.changed(since: entry.pre) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Redo “{name}”?", ["name": entry.name])
            alert.informativeText = L("The book has changed since the undo. Redo takes the whole book back to how it was before the undo. A snapshot of the book as it is now is taken first, so nothing is lost.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Redo"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        do { _ = try snapshots.restoreAll(from: target) } catch { report(error); return }
        redoStack.removeLast()
        undoStack.append(StructureUndo(name: entry.name, pre: entry.pre, post: target))
        reloadFromDisk()
        banner.show(L("Redone: {name}.", ["name": entry.name]), undoable: true)
    }

    /// Reads everything again from the files (after something was put back from a snapshot).
    func reloadFromDisk() {
        characters.reload()
        relationships.reload()
        worlds.reload()
        eventStore.reload()
        guard let structure = try? BookStructure.load(folder: folder) else { return }
        session = BookSession(structure: structure)
        pendingTreeSelection = nil
        focusTextAfterRebuild = !(tree?.isFirstResponder ?? false)
        rebuild()
    }

    // MARK: Importing

    /// A preference changed: the text, the sheets, the right panel and the follow delay take it.
    func preferencesChanged() {
        session.preferencesChanged()
        controllers.forEach { $0.preferencesChanged() }
        applyPanelPreferences()
        onChange?()
    }

    func applyPanelPreferences() {
        let p = AppPreferences.shared.values
        let tabs = p.panelTabs.compactMap { name -> RightPanelController.Tab? in ["section": .section, "characters": .characters, "world": .world, "events": .events, "chat": .chat][name] }
        rightPanel.setVisibleTabs(tabs)
        rightPanel.followDelay = p.followDelay
    }

    /// Book Settings changed the language, the dictionary or the title.
    func bookSettingsChanged() {
        let s = BookSettings.load(book: folder)
        session.applyBookSettings(language: s.language, words: BookDictionary.load(book: folder))
        onChange?()
    }

    // MARK: Importing

    /// Adds an imported text at the end of the book: a snapshot first, a banner offering Undo after.
    @discardableResult
    func performImport(_ plan: ImportPlan) -> Bool {
        var done = false
        restructure(focusText: true, undoName: "Import") { [folder] _ in
            let written = try TextImporter.write(plan, into: folder)
            done = true
            return written.firstSceneID
        }
        if done { banner.show(Lp("Imported {n} scene at the end of the book.", "Imported {n} scenes at the end of the book.", plan.sceneCount), undoable: true) }
        return done
    }

    // MARK: Splitting, merging, grouping

    /// Where a scene would be cut with the cursor at `caret`: at the start of a paragraph, that paragraph begins the new scene; anywhere else in it, the new
    /// scene begins after it. Nil when there is no text on one side of the cut.
    static func splitCut(in text: NSString, caret: Int) -> Int? {
        let place = min(max(0, caret), text.length)
        let paragraph = text.paragraphRange(for: NSRange(location: place, length: 0))
        let cut = place == paragraph.location ? paragraph.location : NSMaxRange(paragraph)
        let rest = cut < text.length ? text.substring(from: cut).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard cut > 0, !rest.isEmpty, !text.substring(to: cut).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return cut
    }

    /// ⌥⌘↩: the scene is cut between two paragraphs; everything after the cut becomes a new scene next to it.
    func splitSceneHere() {
        guard let area = controllers.first(where: { $0.currentSceneID != nil }), let id = area.currentSceneID, let doc = session.document(id), let tv = area.currentSheet?.textView,
              let entry = session.structure.scenes.first(where: { $0.id == id }) else { return }
        let text = doc.storage.string as NSString
        guard let cut = Self.splitCut(in: text, caret: tv.selectedRange().location) else {
            let alert = NSAlert()
            alert.messageText = L("Put the cursor between two paragraphs")
            alert.informativeText = L("A scene is split where there is text on both sides of the cut.")
            alert.runModal()
            return
        }
        let moved = NSMutableAttributedString(attributedString: doc.storage.attributedSubstring(from: NSRange(location: cut, length: text.length - cut)))
        // A fragment that goes on across the cut is divided: the second half gets a new id.
        var divided = false
        var lastBefore = false
        doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: cut)) { v, _, _ in if v != nil { lastBefore = true } }
        let startsWithMarker = moved.length > 0 && moved.attribute(.quillandFragment, at: 0, effectiveRange: nil) != nil
        if lastBefore && !startsWithMarker {
            var attrs = Styler.attributes(kind: BlockKind.fragment)
            attrs[.quillandFragment] = UUID().uuidString.lowercased()
            let marker = NSMutableAttributedString(string: AttributedBridge.object, attributes: attrs)
            marker.append(NSAttributedString(string: "\n", attributes: Styler.attributes(kind: BlockKind.fragment)))
            moved.insert(marker, at: 0)
            divided = true
        }
        let movedMarkdown = MarkdownWriter.write(AttributedBridge.document(from: moved))
        let title = entry.node.title + " 2"
        let status = doc.status ?? "idea"
        restructure(focusText: true, undoName: L("Split scene")) { [folder] editor in
            // The old scene is cut and saved before any renumbering, while its file still has its name.
            doc.storage.deleteCharacters(in: NSRange(location: cut, length: text.length - cut))
            doc.textDidChange()
            doc.updateCounts()
            _ = doc.saveNow()
            let newID = try editor.add(.scene, relativeTo: id, place: .after, title: title)
            let fresh = try BookStructure.load(folder: folder)
            try BookEditor(structure: fresh).setStatus(newID, to: status)
            guard let made = fresh.scenes.first(where: { $0.id == newID }) else { throw BookEditor.Failure(description: L("The new scene was not found.")) }
            try AtomicFile.write(Data(movedMarkdown.utf8), to: fresh.markdownURL(for: made.node))
            return newID
        }
        if divided { banner.show(L("Scene split. A fragment was divided: its links stay with the first half."), undoable: true) }
    }

    /// Merges a scene with the one after it (`direction` 1) or before it (-1). The first of the two survives.
    func merge(_ id: String? = nil, direction: Int, confirm: Bool = true) {
        guard let id = id ?? selectedSectionID else { return }
        // The scenes of its own chapter only: the neighbours in the same list.
        let ids = siblingScenes(of: id)
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + direction) else {
            banner.show(direction > 0 ? L("There is no scene after this one in the chapter.") : L("There is no scene before this one in the chapter."), undoable: false)
            return
        }
        let first = direction > 0 ? id : ids[i + direction]
        let second = direction > 0 ? ids[i + direction] : id
        mergeScenes(first: first, others: [second], confirm: confirm)
    }

    /// Outline: the chosen scenes (which must follow one another) are merged into the first.
    func mergeSelected(confirm: Bool = true) {
        let chosen = Set(tree?.selectedIDs ?? [])
        let picked = session.structure.scenes.map(\.id).filter { chosen.contains($0) }
        let ids = picked.first.map { siblingScenes(of: $0) } ?? []
        guard picked.count >= 2, let start = ids.firstIndex(of: picked[0]), start + picked.count <= ids.count, Array(ids[start..<(start + picked.count)]) == picked else {
            banner.show(L("Choose two or more scenes that follow one another in one chapter."), undoable: false)
            return
        }
        mergeScenes(first: picked[0], others: Array(picked.dropFirst()), confirm: confirm)
    }

    private func mergeScenes(first: String, others: [String], confirm: Bool) {
        if confirm {
            let name = { (id: String) in self.findNode(id)?.title ?? "" }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = others.count == 1 ? L("Merge “{second}” into “{first}”?", ["second": name(others[0]), "first": name(first)]) : L("Merge the chosen scenes into “{first}”?", ["first": name(first)])
            alert.informativeText = L("The text, synopsis, note and tags of the other scene are added after those of the first, the links to it point at the first, and the other scene goes to the book's trash folder (.quilland/trash). You can undo this.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Merge"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        restructure(focusText: !treeHasFocus, cursorScene: first, undoName: L("Merge scenes")) { [folder] _ in
            for other in others {
                let fresh = try BookStructure.load(folder: folder)
                try BookEditor(structure: fresh).merge(first, with: other)
            }
            return first
        }
    }

    /// Group into a New Part…: the chosen chapters (not yet in a part) move into a new part.
    func groupIntoPart() {
        let chosen = (mode == .outline ? tree?.selectedIDs : nil) ?? [selectedSectionID].compactMap { $0 }
        let loose = Set(session.structure.roots.filter { $0.kind == .chapter }.map(\.id))
        guard !chosen.isEmpty, chosen.allSatisfy({ loose.contains($0) }) else {
            banner.show(L("Choose one or more chapters that are not in a part."), undoable: false)
            return
        }
        let field = NSTextField(string: BookEditor(structure: session.structure).language == "ru" ? "Новая часть" : "New Part")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = L("Group into a new part")
        alert.informativeText = L("The title of the part:")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Group"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        groupChapters(chosen, titled: title)
    }

    func groupChapters(_ ids: [String], titled title: String) {
        restructure(focusText: !treeHasFocus, undoName: L("Group into a part")) { editor in try editor.group(ids, intoNewPart: title) }
    }

    /// Ungroup Part…: its chapters move up to where it was; the part's own title and text go to the trash folder. Asks first.
    func ungroupPart(_ id: String? = nil, confirm: Bool = true) {
        guard let id = id ?? selectedSectionID, let part = findNode(id), part.kind == .part else {
            banner.show(L("Choose a part."), undoable: false)
            return
        }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Ungroup the part “{title}”?", ["title": part.title])
            alert.informativeText = L("{chapters} move up to where the part was. The part's own title, text, synopsis and note go to the book's trash folder (.quilland/trash).", ["chapters": Lp("Its {n} chapter", "Its {n} chapters", part.children.count)])
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Ungroup"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        restructure(focusText: !treeHasFocus, cursorScene: currentSceneID, undoName: L("Ungroup “{title}”", ["title": part.title])) { editor in
            try editor.ungroup(id)
            return nil
        }
    }

    private func firstScene(of id: String, in structure: BookStructure) -> String? {
        if structure.scenes.contains(where: { $0.id == id }) { return id }
        return structure.scenes.first { $0.chapterID == id || $0.partID == id }?.id
    }

    private func report(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("That could not be done")
        alert.informativeText = "\(error)"
        alert.runModal()
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

    func saveAll() {
        session.saveAll()
        if showsRightPanel { rightPanel.commitEdits() }
        outlineDetail?.commitEdits()
        charactersView?.commitEdits()
        worldView?.commitEdits()
        eventsView?.commitEdits()
    }

    var currentSceneID: String? { controllers.compactMap(\.currentSceneID).first }
    var currentDocument: SceneDocument? { currentSceneID.flatMap { session.document($0) } }

    /// The state to keep in `.quilland/state.json`.
    /// The section the Plan view starts from (what comes before it is hidden), kept with the book on this machine.
    private(set) var planFrom: String?

    /// Every part, chapter and scene, in the book's order, for the Plan view's "Show from" choice.
    private func planSectionChoices() -> [(id: String, title: String, depth: Int)] {
        var out: [(id: String, title: String, depth: Int)] = []
        func walk(_ nodes: [BookStructure.Node], _ depth: Int) {
            for n in nodes { out.append((n.id, n.title, depth)); walk(n.children, depth + 1) }
        }
        walk(session.structure.roots, 0)
        return out
    }

    /// The first scene at or under a section.
    private func firstScene(of id: String) -> String? {
        func find(_ nodes: [BookStructure.Node]) -> BookStructure.Node? {
            for n in nodes { if n.id == id { return n }; if let f = find(n.children) { return f } }
            return nil
        }
        func first(_ n: BookStructure.Node) -> String? {
            if n.kind == .scene { return n.id }
            for c in n.children { if let s = first(c) { return s } }
            return nil
        }
        return find(session.structure.roots).flatMap(first)
    }

    func localState() -> LocalBookState {
        remember()
        _ = writtenToday
        return LocalBookState(scene: pendingCursor?.scene, position: pendingCursor?.position ?? 0, mode: mode.rawValue, rightPanel: showsRightPanel, dayDate: day.dayDate, dayBaseline: day.dayBaseline, planFrom: planFrom)
    }
}
