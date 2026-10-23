import AppKit
import QuillandCore

/// What the Graph view is set to (the owner keeps it, because the view is made again each time the author comes back to it).
struct GraphViewState {
    enum Look: Int { case whole, social, neighbourhood, arc }
    var look = Look.whole
    var kinds: Set<GraphKind> = [.character, .place, .event]
    var showUnlinked = true
    var showEnded = true
    var changesOnly = false
    /// The scene the graph is as of (nil: the whole book).
    var asOf: String?
    /// Colour by the plot line of the plan, and the one plot line shown (nil: all).
    var colourByLine = false
    var plotLine: String?
    var section: String?
    var focus: String?
    var depth = 1
    /// Where the view was looking: the zoom and the middle of what was in view, in the layout's own coordinates (nil: fit everything).
    var zoom: Double?
    var center: GraphPoint?

    init() {}

    init(memory m: GraphViewMemory?) {
        guard let m else { return }
        look = [Look.whole, .social, .neighbourhood, .arc].first { ["whole", "social", "neighbourhood", "arc"][$0.rawValue] == m.look } ?? .whole
        kinds = Set(m.kinds.compactMap(GraphKind.init(rawValue:)))
        showUnlinked = m.showUnlinked
        showEnded = m.showEnded; changesOnly = m.changesOnly; asOf = m.asOf
        colourByLine = m.colourBy == "plot_line"; plotLine = m.plotLine
        section = m.section; focus = m.focus; depth = max(1, min(3, m.depth))
        zoom = m.zoom
        if let x = m.centerX, let y = m.centerY { center = GraphPoint(x: x, y: y) }
    }

    var memory: GraphViewMemory {
        var m = GraphViewMemory()
        m.look = ["whole", "social", "neighbourhood", "arc"][look.rawValue]
        m.kinds = GraphKind.allCases.filter(kinds.contains).map(\.rawValue)
        m.showUnlinked = showUnlinked
        m.showEnded = showEnded; m.changesOnly = changesOnly; m.asOf = asOf
        m.colourBy = colourByLine ? "plot_line" : "kind"; m.plotLine = plotLine
        m.section = section; m.focus = focus; m.depth = depth
        m.zoom = zoom; m.centerX = center?.x; m.centerY = center?.y
        return m
    }
}

/// The Graph view: the characters, places, events and scenes of the book as nodes, with the links between them as lines. It only shows; the cards are where
/// links are made. The author can move nodes (they stay where they were put) and filter what is shown.
final class GraphViewController: NSViewController {
    var characters: CharacterStore!
    var worlds: WorldStore!
    var events: EventStore!
    var relationships: RelationshipStore!
    /// The plan as it is on disk (the cards and what realises them); nil when it cannot be read.
    var plan: () -> PlanStore? = { nil }
    var store: GraphStore!
    var structure: () -> BookStructure = { BookStructure(folder: URL(fileURLWithPath: "/")) }
    /// The index that tells what belongs to a section (for the section filter).
    var index: () -> RelationIndex = { fatalError("no index") }
    var sections: () -> [(id: String, title: String, depth: Int)] = { [] }
    var onOpen: ((GraphKind, String) -> Void)?
    var onEscape: (() -> Void)?
    var onChange: (() -> Void)?
    /// What the view is set to has changed (the owner keeps it).
    var onStateChange: ((GraphViewState) -> Void)?
    /// The place in view or a setting changed (the book's state is to be saved).
    var onViewChange: (() -> Void)?
    var state = GraphViewState()

    private(set) var graph = BookGraph()
    let canvas = GraphCanvasView()
    private let scroll = NSScrollView()
    private let lookControl = NSSegmentedControl(labels: [L("Whole book"), L("Social graph"), L("Neighbourhood"), L("Arc")], trackingMode: .selectOne, target: nil, action: nil)
    private let focusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let depthControl = NSSegmentedControl(labels: ["1", "2", "3"], trackingMode: .selectOne, target: nil, action: nil)
    private var kindBoxes: [GraphKind: NSButton] = [:]
    private let unlinkedBox = NSButton(checkboxWithTitle: L("Show unlinked"), target: nil, action: nil)
    private let endedBox = NSButton(checkboxWithTitle: L("Show ended relationships"), target: nil, action: nil)
    private let changesOnlyBox = NSButton(checkboxWithTitle: L("Changes only"), target: nil, action: nil)
    private let colourPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let linePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let legendRow = NSStackView()
    private let asOfSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let asOfBack = NSButton(title: "◀", target: nil, action: nil)
    private let asOfForward = NSButton(title: "▶", target: nil, action: nil)
    private let asOfLabel = NSTextField(labelWithString: "")
    private let sectionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomOutButton = NSButton(title: "−", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "+", target: nil, action: nil)
    private let fitButton = NSButton(title: L("Fit"), target: nil, action: nil)
    private let resetButton = NSButton(title: L("Reset Layout"), target: nil, action: nil)
    private let note = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private var magnificationObserver: NSKeyValueObservation?
    private var subscriptions: [Subscription] = []
    private static let margin: CGFloat = 500
    /// Where the layout puts the origin on the canvas, to turn canvas points into the book's own (what is saved).
    private var offset = CGPoint.zero

    override func loadView() {
        subscriptions.append(subscribe(to: .bookDataChanged) { [weak self] in self?.reload() })
        let root = NSView()
        lookControl.target = self; lookControl.action = #selector(lookChanged)
        lookControl.controlSize = .small
        depthControl.target = self; depthControl.action = #selector(depthChanged)
        depthControl.controlSize = .small
        focusPopup.target = self; focusPopup.action = #selector(focusChanged)
        focusPopup.controlSize = .small
        sectionPopup.target = self; sectionPopup.action = #selector(sectionChanged)
        sectionPopup.controlSize = .small
        lookControl.setAccessibilityLabel(L("What the graph shows"))
        focusPopup.setAccessibilityLabel(L("The thing to look at"))
        let kindTitles: [(GraphKind, String, String)] = [(.character, "●", L("Characters")), (.place, "■", L("Places")), (.event, "◆", L("Events")), (.scene, "•", L("Scenes")), (.card, "▭", L("Plan cards"))]
        for (kind, glyph, title) in kindTitles {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(kindChanged(_:)))
            let s = NSMutableAttributedString(string: glyph + " ", attributes: [.foregroundColor: GraphCanvasView.color(kind), .font: NSFont.systemFont(ofSize: 13)])
            s.append(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
            b.attributedTitle = s
            b.tag = Self.tag(kind)
            kindBoxes[kind] = b
        }
        unlinkedBox.target = self; unlinkedBox.action = #selector(unlinkedChanged)
        unlinkedBox.toolTip = L("Things with no line to anything shown: a place no event uses, a character in no event")
        endedBox.target = self; endedBox.action = #selector(endedChanged)
        endedBox.toolTip = L("A relationship that has ended is drawn dashed; its tooltip says from which event to which")
        changesOnlyBox.target = self; changesOnlyBox.action = #selector(changesOnlyChanged)
        changesOnlyBox.toolTip = L("Only the events that change something, with what they change: the turning points of the story")
        for (b, action) in [(zoomOutButton, #selector(zoomOutAction)), (zoomInButton, #selector(zoomInAction)), (fitButton, #selector(fitAction)), (resetButton, #selector(resetPressed))] {
            b.target = self; b.action = action; b.bezelStyle = .rounded; b.controlSize = .small
        }
        resetButton.toolTip = L("Forgets the places you gave the nodes: the layout arranges them all again")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let row1 = NSStackView(views: [lookControl, NSTextField(labelWithString: L("Look at")), focusPopup, NSTextField(labelWithString: L("Steps")), depthControl, NSTextField(labelWithString: L("Section")), sectionPopup])
        let row2 = NSStackView(views: [kindBoxes[.character]!, kindBoxes[.place]!, kindBoxes[.event]!, kindBoxes[.scene]!, kindBoxes[.card]!, unlinkedBox, zoomOutButton, zoomInButton, fitButton, resetButton, note])
        asOfSlider.target = self; asOfSlider.action = #selector(asOfChanged(_:)); asOfSlider.isContinuous = true
        asOfSlider.numberOfTickMarks = 0; asOfSlider.allowsTickMarkValuesOnly = true
        asOfSlider.controlSize = .small
        asOfSlider.toolTip = L("The book as it is after a scene: the relationships then, who has been met, who is a main character. The nodes stay where they are.")
        asOfSlider.setAccessibilityLabel(L("As of"))
        for (b, tip) in [(asOfBack, L("The scene before")), (asOfForward, L("The next scene"))] { b.target = self; b.action = #selector(asOfStep(_:)); b.bezelStyle = .rounded; b.controlSize = .small; b.toolTip = tip }
        asOfBack.tag = -1; asOfForward.tag = 1
        asOfLabel.font = .systemFont(ofSize: 11); asOfLabel.textColor = .secondaryLabelColor
        asOfLabel.lineBreakMode = .byTruncatingTail
        asOfSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        asOfLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
        colourPopup.addItems(withTitles: [L("Kind"), L("Plot line")])
        colourPopup.target = self; colourPopup.action = #selector(colourChanged); colourPopup.controlSize = .small
        colourPopup.setAccessibilityLabel(L("Colour by"))
        linePopup.target = self; linePopup.action = #selector(lineFilterChanged); linePopup.controlSize = .small
        linePopup.setAccessibilityLabel(L("Plot line"))
        legendRow.orientation = .horizontal; legendRow.spacing = 12; legendRow.alignment = .centerY
        let row3 = NSStackView(views: [endedBox, changesOnlyBox, NSTextField(labelWithString: L("As of")), asOfBack, asOfSlider, asOfForward, asOfLabel])
        let row4 = NSStackView(views: [NSTextField(labelWithString: L("Colour by")), colourPopup, NSTextField(labelWithString: L("Plot line")), linePopup, legendRow])
        for r in [row1, row2, row3, row4] { r.spacing = 10; r.alignment = .centerY }
        let bar = NSStackView(views: [row1, row2, row3, row4])
        bar.orientation = .vertical; bar.alignment = .leading; bar.spacing = 6
        bar.translatesAutoresizingMaskIntoConstraints = false

        canvas.onSelect = { [weak self] _ in self?.updateControls() }
        canvas.onMoved = { [weak self] id, point in self?.moved(id, to: point) }
        canvas.onOpen = { [weak self] node in self?.onOpen?(node.kind, node.id) }
        canvas.menuProvider = { [weak self] node in self?.menu(for: node) }
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.1; scroll.maxMagnification = 3
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        magnificationObserver = scroll.observe(\.magnification, options: [.new]) { [weak self] _, _ in self?.updateControls(); self?.captureSoon() }
        scroll.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in self?.captureSoon() }
        emptyLabel.font = .systemFont(ofSize: 15); emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(bar); root.addSubview(scroll); root.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8), bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        view = root
        syncControlsFromState()
        reload()
    }

    private static func tag(_ k: GraphKind) -> Int { GraphKind.allCases.firstIndex(of: k) ?? 0 }

    // MARK: Building

    private var options: GraphOptions {
        var o = GraphOptions()
        o.kinds = state.kinds
        o.showUnlinked = state.showUnlinked
        o.showEnded = state.showEnded
        o.changesOnly = state.changesOnly
        o.asOf = state.asOf
        o.plotLine = state.plotLine
        switch state.look {
        case .whole, .arc: o.mode = .whole
        case .social: o.mode = .social
        case .neighbourhood: o.mode = .neighbourhood(state.focus ?? "", depth: state.depth)
        }
        if let section = state.section {
            let i = index()
            var allowed = Set(i.scenes(inSection: section))
            for kind in [RelationIndex.Kind.character, .place, .event] { allowed.formUnion(i.matching(kind, anchors: [.section(section)]) ?? []) }
            o.allowed = allowed
        }
        return o
    }

    /// Makes the graph again from the book (after a filter changed, or the book did) and lays it out around the nodes the author has moved.
    func reload() {
        guard isViewLoaded else { return }
        // What was remembered may be gone (a deleted thing, a section that was removed).
        if let f = state.focus, characters.character(f) == nil, worlds.entry(f) == nil, events.event(f) == nil { state.focus = nil }
        if let sec = state.section, !sections().contains(where: { $0.id == sec }) { state.section = nil }
        if let line = state.plotLine, !(plan()?.lines.contains { $0.id == line } ?? false) { state.plotLine = nil }
        if let scene = state.asOf, !structure().scenes.contains(where: { $0.id == scene }) { state.asOf = nil }
        store.reload()
        let planStore = plan()
        // The arc is a graph of its own: the events of one character along a spine, with their places worked out (nothing is moved or kept).
        let arc: ArcGraph? = state.look == .arc ? state.focus.flatMap { characters.character($0) == nil ? nil : ArcBuilder.build(character: $0, characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure()) } : nil
        let isArc = state.look == .arc
        graph = isArc ? (arc?.graph ?? BookGraph()) : GraphBuilder.build(characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure(), options: options, plan: planStore)
        canvas.allowsDragging = !isArc
        canvas.lineStyles = Dictionary((planStore?.lines ?? []).compactMap { l in l.id.map { ($0, (name: l.name ?? "", color: l.color)) } }, uniquingKeysWith: { a, _ in a })
        canvas.colourByLine = state.colourByLine
        fillLinePopup(planStore?.lines ?? [])
        updateLegend()
        let ids = Set(graph.nodes.map(\.id))
        let pinned = isArc ? [:] : store.positions.filter { ids.contains($0.key) }
        // (As of a point only flags change, not the nodes and lines: the layout is not made again, so that the picture stays still while the point moves.)
        let key = graph.nodes.map(\.id).joined(separator: ",") + "|" + graph.edges.map { "\($0.a)-\($0.b)-\($0.kind.rawValue)-\($0.weight)" }.joined(separator: ",") + "|" + pinned.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.x),\($0.value.y)" }.joined(separator: ";")
        let placed: [String: GraphPoint]
        if isArc { placed = arc?.positions ?? [:] } else if key == lastLayoutKey, let kept = lastPlaced { placed = kept } else { placed = GraphLayout.layout(nodes: graph.nodes, edges: graph.edges, pinned: pinned); lastLayoutKey = key; lastPlaced = placed }
        let xs = placed.values.map(\.x), ys = placed.values.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0, maxX = xs.max() ?? 0, maxY = ys.max() ?? 0
        offset = CGPoint(x: Self.margin - minX, y: Self.margin - minY)
        canvas.frame = NSRect(x: 0, y: 0, width: max(maxX - minX + 2 * Self.margin, 1200), height: max(maxY - minY + 2 * Self.margin, 800))
        canvas.pinned = Set(pinned.keys)
        canvas.set(graph: graph, points: placed.mapValues { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) })
        fillFocusPopup()
        fillSectionPopup()
        updateControls()
        onStateChange?(state)
        onViewChange?()
        DispatchQueue.main.async { [weak self] in self?.fitIfFirstTime() }
    }

    /// What is in view is forgotten, so that the next picture is fitted to the window (a setting changed, or the layout was made again).
    private func resetViewport() { state.zoom = nil; state.center = nil; fitted = false }

    private var lastLayoutKey = ""
    private var lastPlaced: [String: GraphPoint]?
    private var fitted = false
    /// A picture opens where the author left it, or fitted to the window when there is nothing to go back to.
    private func fitIfFirstTime(tries: Int = 0) {
        guard !fitted, !graph.nodes.isEmpty else { return }
        // The view has to be in the window and laid out first, or the middle of what is in view is not what it will be.
        view.layoutSubtreeIfNeeded()
        if (view.window == nil || scroll.contentView.bounds.width < 50), tries < 40 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.fitIfFirstTime(tries: tries + 1) }
            return
        }
        fitted = true
        if let zoom = state.zoom, let center = state.center {
            let point = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
            if canvas.bounds.contains(point) {
                put(point, atZoom: CGFloat(zoom))
                return
            }
        }
        zoomToFit()
        captureSoon()
    }

    // MARK: Remembering where the view is looking

    /// Zooms to a magnification and puts a point of the canvas in the middle of what is in view (as far as the canvas allows).
    private func put(_ point: CGPoint, atZoom zoom: CGFloat) {
        scroll.magnification = min(max(zoom, scroll.minMagnification), scroll.maxMagnification)
        let clip = scroll.contentView
        let size = clip.bounds.size
        let wanted = NSRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size)
        clip.scroll(to: clip.constrainBoundsRect(wanted).origin)
        scroll.reflectScrolledClipView(clip)
    }

    private var captureTimer: Timer?
    private var boundsObserver: NSObjectProtocol?
    deinit { boundsObserver.map(NotificationCenter.default.removeObserver) }

    /// Notes the zoom and the middle of what is in view (in the layout's coordinates), a moment after the author stops scrolling or zooming.
    private func captureSoon() {
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.captureViewport() }
    }

    func captureViewport() {
        captureTimer?.invalidate()
        guard isViewLoaded, fitted, !graph.nodes.isEmpty, scroll.contentView.bounds.width > 0 else { return }
        let visible = scroll.contentView.bounds
        state.zoom = Double(scroll.magnification)
        state.center = GraphPoint(x: Double(visible.midX - offset.x), y: Double(visible.midY - offset.y))
        onStateChange?(state)
        onViewChange?()
    }

    private func moved(_ id: String, to point: CGPoint) {
        try? store.pin(id, at: GraphPoint(x: point.x - offset.x, y: point.y - offset.y))
        canvas.pinned.insert(id)
        updateControls()
        onChange?()
    }

    // MARK: Controls

    private func syncControlsFromState() {
        lookControl.selectedSegment = state.look.rawValue
        depthControl.selectedSegment = max(0, min(2, state.depth - 1))
        for (kind, box) in kindBoxes { box.state = state.kinds.contains(kind) ? .on : .off }
        unlinkedBox.state = state.showUnlinked ? .on : .off
        endedBox.state = state.showEnded ? .on : .off
        changesOnlyBox.state = state.changesOnly ? .on : .off
    }

    private func fillFocusPopup() {
        focusPopup.removeAllItems()
        focusPopup.addItem(withTitle: L("Choose…"))
        focusPopup.lastItem?.representedObject = ""
        let groups: [(String, [(String, String)])] = [
            (L("Characters"), characters.characters.compactMap { c in c.id.map { ($0, c.name ?? "") } }),
            (L("Places"), worlds.entries.compactMap { p in p.id.map { ($0, worlds.path(of: $0).dropFirst().joined(separator: " › ")) } }),
            (L("Events"), events.events.compactMap { e in e.id.map { ($0, e.title ?? "") } }),
        ]
        for (title, items) in groups where !items.isEmpty && (state.look != .arc || title == L("Characters")) {
            focusPopup.menu?.addItem(.separator())
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: ""); header.isEnabled = false
            focusPopup.menu?.addItem(header)
            for (id, name) in items.sorted(by: { $0.1.localizedLowercase < $1.1.localizedLowercase }) {
                focusPopup.addItem(withTitle: name); focusPopup.lastItem?.representedObject = id
            }
        }
        let current = state.focus ?? ""
        if let item = focusPopup.itemArray.first(where: { ($0.representedObject as? String) == current && !current.isEmpty }) { focusPopup.select(item) } else { focusPopup.selectItem(at: 0) }
    }

    private func fillSectionPopup() {
        sectionPopup.removeAllItems()
        sectionPopup.addItem(withTitle: L("Whole book"))
        sectionPopup.lastItem?.representedObject = ""
        for s in sections() {
            sectionPopup.addItem(withTitle: String(repeating: "   ", count: s.depth) + s.title)
            sectionPopup.lastItem?.representedObject = s.id
        }
        if let id = state.section, let item = sectionPopup.itemArray.first(where: { ($0.representedObject as? String) == id }) { sectionPopup.select(item) } else { sectionPopup.selectItem(at: 0) }
    }

    /// What can be used now is on; the rest is off.
    func updateControls() {
        guard isViewLoaded else { return }
        let hood = state.look == .neighbourhood, arcLook = state.look == .arc
        focusPopup.isEnabled = hood || arcLook
        depthControl.isEnabled = hood
        for box in kindBoxes.values { box.isEnabled = state.look != .social }
        zoomOutButton.isEnabled = scroll.magnification > scroll.minMagnification + 0.001
        zoomInButton.isEnabled = scroll.magnification < scroll.maxMagnification - 0.001
        fitButton.isEnabled = !graph.nodes.isEmpty
        resetButton.isEnabled = !store.positions.isEmpty
        updateAsOfControls()
        // (The arc is made of one character's events: the filters of the book's graph do not apply to it.)
        if arcLook {
            for box in kindBoxes.values { box.isEnabled = false }
            for c in [unlinkedBox, endedBox, changesOnlyBox, asOfBack, asOfForward] as [NSButton] { c.isEnabled = false }
            for p in [sectionPopup, colourPopup, linePopup] { p.isEnabled = false }
            asOfSlider.isEnabled = false
            resetButton.isEnabled = false
        } else {
            for c in [unlinkedBox, endedBox, changesOnlyBox] as [NSButton] { c.isEnabled = true }
            for p in [sectionPopup, colourPopup] { p.isEnabled = true }
        }
        note.stringValue = graph.nodes.isEmpty ? "" : Lp("{n} node", "{n} nodes", graph.nodes.count) + " · " + Lp("{n} link", "{n} links", graph.edges.filter { !$0.hidden }.count) + (graph.warningCount > 0 ? " · ⚠ " + Lp("{n} warning", "{n} warnings", graph.warningCount) : "")
        if graph.nodes.isEmpty {
            emptyLabel.stringValue = arcLook && (state.focus.flatMap { characters.character($0) } == nil) ? L("Choose a character to follow") : (hood && (state.focus ?? "").isEmpty ? L("Choose a thing to look at") : L("Nothing to show with these settings"))
        }
        emptyLabel.isHidden = !graph.nodes.isEmpty
    }

    @objc private func lookChanged() {
        state.look = GraphViewState.Look(rawValue: lookControl.selectedSegment) ?? .whole
        // "Neighbourhood" looks at what is chosen on the canvas when nothing was chosen before.
        if state.look == .neighbourhood, (state.focus ?? "").isEmpty, let s = canvas.selected { state.focus = s }
        // The arc follows a character: the one chosen on the canvas, else the one that was in focus.
        if state.look == .arc {
            if let s = canvas.selected, characters.character(s) != nil { state.focus = s } else if let f = state.focus, characters.character(f) == nil { state.focus = nil }
        }
        resetViewport()
        reload()
    }

    @objc private func depthChanged() { state.depth = depthControl.selectedSegment + 1; resetViewport(); reload() }

    @objc private func focusChanged() {
        let id = focusPopup.selectedItem?.representedObject as? String ?? ""
        state.focus = id.isEmpty ? nil : id
        resetViewport()
        reload()
    }

    @objc private func kindChanged(_ sender: NSButton) {
        guard let kind = GraphKind.allCases.first(where: { Self.tag($0) == sender.tag }) else { return }
        if sender.state == .on { state.kinds.insert(kind) } else { state.kinds.remove(kind) }
        resetViewport()
        reload()
    }

    // MARK: As of a scene

    private var asOfScenes: [(id: String, title: String)] { structure().scenes.map { ($0.id, $0.node.title) } }

    private func updateAsOfControls() {
        let scenes = asOfScenes
        asOfSlider.maxValue = Double(max(1, scenes.count))
        asOfSlider.isEnabled = !scenes.isEmpty
        let index = state.asOf.flatMap { id in scenes.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        asOfSlider.integerValue = index
        asOfBack.isEnabled = index > 0
        asOfForward.isEnabled = index < scenes.count
        asOfLabel.stringValue = index == 0 ? L("Whole book") : L("after “{scene}”", ["scene": scenes[index - 1].title])
    }

    /// Puts the graph as of the scene with this number (0: the whole book). The view stays where it is, and so do the nodes.
    private func setAsOf(index: Int) {
        let scenes = asOfScenes
        let i = max(0, min(scenes.count, index))
        let wanted = i == 0 ? nil : scenes[i - 1].id
        guard wanted != state.asOf else { updateAsOfControls(); return }
        state.asOf = wanted
        reload()
    }

    @objc private func asOfChanged(_ sender: NSSlider) { setAsOf(index: sender.integerValue) }
    @objc private func asOfStep(_ sender: NSButton) { setAsOf(index: asOfSlider.integerValue + sender.tag) }

    // MARK: Colour by plot line

    private func fillLinePopup(_ lines: [TimelineFile.Lane]) {
        linePopup.removeAllItems()
        linePopup.addItem(withTitle: L("Whole book")); linePopup.lastItem?.representedObject = ""
        for l in lines { linePopup.addItem(withTitle: l.name ?? ""); linePopup.lastItem?.representedObject = l.id; linePopup.lastItem?.image = PlanColors.swatch(l.color) }
        if let id = state.plotLine, let item = linePopup.itemArray.first(where: { ($0.representedObject as? String) == id }) { linePopup.select(item) } else { linePopup.selectItem(at: 0) }
        linePopup.isEnabled = !lines.isEmpty
        colourPopup.selectItem(at: state.colourByLine ? 1 : 0)
    }

    /// The colours of the plot lines that are on the graph, as chips (only when the nodes are coloured by plot line).
    private func updateLegend() {
        legendRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        legendRow.isHidden = !state.colourByLine
        guard state.colourByLine else { return }
        let used = Set(graph.nodes.flatMap(\.lines))
        var chips: [(String, NSColor)] = canvas.lineStyles.filter { used.contains($0.key) }.sorted { $0.value.name < $1.value.name }.map { ($0.value.name, PlanColors.color($0.value.color)) }
        if graph.nodes.contains(where: { $0.lines.isEmpty && $0.kind != .scene }) { chips.append((L("not on a plot line"), .systemGray)) }
        for (name, color) in chips {
            let box = NSView(); box.wantsLayer = true; box.layer?.cornerRadius = 3; box.layer?.backgroundColor = color.cgColor
            box.translatesAutoresizingMaskIntoConstraints = false
            box.widthAnchor.constraint(equalToConstant: 10).isActive = true; box.heightAnchor.constraint(equalToConstant: 10).isActive = true
            let label = NSTextField(labelWithString: name); label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            let chip = NSStackView(views: [box, label]); chip.spacing = 4
            legendRow.addArrangedSubview(chip)
        }
        legendTitles = chips.map(\.0)
    }

    private(set) var legendTitles: [String] = []

    @objc private func colourChanged() { state.colourByLine = colourPopup.indexOfSelectedItem == 1; reload() }

    @objc private func lineFilterChanged() {
        let id = linePopup.selectedItem?.representedObject as? String ?? ""
        state.plotLine = id.isEmpty ? nil : id
        resetViewport()
        reload()
    }

    @objc private func endedChanged() { state.showEnded = endedBox.state == .on; resetViewport(); reload() }
    @objc private func changesOnlyChanged() { state.changesOnly = changesOnlyBox.state == .on; resetViewport(); reload() }
    @objc private func unlinkedChanged() { state.showUnlinked = unlinkedBox.state == .on; resetViewport(); reload() }

    @objc private func sectionChanged() {
        let id = sectionPopup.selectedItem?.representedObject as? String ?? ""
        state.section = id.isEmpty ? nil : id
        resetViewport()
        reload()
    }

    // MARK: Zoom, layout

    func zoomIn() { scroll.setMagnification(min(scroll.maxMagnification, scroll.magnification * 1.25), centeredAt: visibleCenter) }
    func zoomOut() { scroll.setMagnification(max(scroll.minMagnification, scroll.magnification / 1.25), centeredAt: visibleCenter) }
    func zoomToFit() {
        guard !graph.nodes.isEmpty else { return }
        let pts = canvas.points.values
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(), let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return }
        let area = NSRect(x: minX - 80, y: minY - 60, width: maxX - minX + 160, height: maxY - minY + 140)
        scroll.magnify(toFit: area)
        // A few nodes are not blown up to fill the window.
        if scroll.magnification > 1.2 { scroll.setMagnification(1.2, centeredAt: NSPoint(x: area.midX, y: area.midY)) }
    }
    private var visibleCenter: NSPoint { NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY) }
    var zoom: CGFloat { scroll.magnification }
    @objc private func zoomOutAction() { zoomOut() }
    @objc private func zoomInAction() { zoomIn() }
    @objc private func fitAction() { zoomToFit() }

    @objc private func resetPressed() { resetLayout(confirm: true) }

    /// Forgets every place the author gave a node.
    func resetLayout(confirm: Bool) {
        guard !store.positions.isEmpty else { return }
        if confirm {
            let alert = NSAlert()
            alert.messageText = L("Reset the layout?")
            alert.informativeText = L("The places you gave the nodes are forgotten, and the layout arranges them all again.")
            alert.addButton(withTitle: L("Cancel")).keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Reset Layout"))
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        try? store.releaseAll()
        resetViewport()
        reload()
        onChange?()
    }

    func release(_ id: String) {
        try? store.release(id)
        reload()
        onChange?()
    }

    /// Shows the arc of a character: their events in the order of the book, the states they pass through, their relationships and places.
    func showArc(of id: String) {
        state.look = .arc
        state.focus = id
        syncControlsFromState()
        resetViewport()
        reload()
    }

    /// Looks at one thing and what is around it.
    func focus(on id: String) {
        state.look = .neighbourhood
        state.focus = id
        syncControlsFromState()
        resetViewport()
        reload()
    }

    // MARK: The menu

    private func menu(for node: GraphNode?) -> NSMenu? {
        let menu = NSMenu()
        if let node {
            menu.addItem(ClosureMenuItem(title: L("Open")) { [weak self] in self?.onOpen?(node.kind, node.id) })
            if node.kind != .scene, node.kind != .stage { menu.addItem(ClosureMenuItem(title: L("Focus on This")) { [weak self] in self?.focus(on: node.id) }) }
            if node.kind == .character { menu.addItem(ClosureMenuItem(title: L("Show the Arc")) { [weak self] in self?.showArc(of: node.id) }) }
            if store.positions[node.id] != nil { menu.addItem(ClosureMenuItem(title: L("Release Position")) { [weak self] in self?.release(node.id) }) }
            menu.addItem(.separator())
        }
        let reset = ClosureMenuItem(title: L("Reset Layout")) { [weak self] in self?.resetLayout(confirm: true) }
        reset.isEnabled = !store.positions.isEmpty
        menu.addItem(reset)
        return menu
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    // MARK: For the checks

    /// Where the view is looking now: the middle of what is in view, in the layout's own coordinates.
    var viewCenter: GraphPoint {
        let v = scroll.contentView.bounds
        return GraphPoint(x: Double(v.midX - offset.x), y: Double(v.midY - offset.y))
    }
    /// Looks at a place (in the layout's coordinates) at a zoom, and notes it.
    func lookAt(_ point: GraphPoint, zoom: Double) {
        put(CGPoint(x: point.x + offset.x, y: point.y + offset.y), atZoom: CGFloat(zoom))
        captureViewport()
    }

    var shownIDs: [String] { graph.nodes.map(\.id) }
    var noteText: String { note.stringValue }
    var controlsEnabled: (focus: Bool, depth: Bool, kinds: Bool, reset: Bool, zoomOut: Bool, zoomIn: Bool, fit: Bool) {
        (focusPopup.isEnabled, depthControl.isEnabled, kindBoxes.values.allSatisfy(\.isEnabled), resetButton.isEnabled, zoomOutButton.isEnabled, zoomInButton.isEnabled, fitButton.isEnabled)
    }
    var focusTitles: [String] { focusPopup.itemTitles.filter { !$0.isEmpty } }
    var emptyText: String? { emptyLabel.isHidden ? nil : emptyLabel.stringValue }
    func setLook(_ look: GraphViewState.Look) { state.look = look; syncControlsFromState(); resetViewport(); reload() }
    func setKind(_ kind: GraphKind, _ on: Bool) { if on { state.kinds.insert(kind) } else { state.kinds.remove(kind) }; syncControlsFromState(); resetViewport(); reload() }
    func setColourByLine(_ on: Bool) { state.colourByLine = on; reload() }
    func setPlotLine(_ id: String?) { state.plotLine = id; resetViewport(); reload() }
    func setAsOf(_ scene: String?) { state.asOf = scene; reload() }
    var asOfText: String { asOfLabel.stringValue }
    var asOfControls: (back: Bool, forward: Bool) { (asOfBack.isEnabled, asOfForward.isEnabled) }
    func stepAsOf(_ by: Int) { setAsOf(index: asOfSlider.integerValue + by) }
    func setShowEnded(_ on: Bool) { state.showEnded = on; syncControlsFromState(); resetViewport(); reload() }
    func setChangesOnly(_ on: Bool) { state.changesOnly = on; syncControlsFromState(); resetViewport(); reload() }
    func setShowUnlinked(_ on: Bool) { state.showUnlinked = on; syncControlsFromState(); resetViewport(); reload() }
    func setSection(_ id: String?) { state.section = id; resetViewport(); reload() }
    func setDepth(_ depth: Int) { state.depth = depth; syncControlsFromState(); resetViewport(); reload() }
}
