import AppKit
import QuillandCore

/// What the Graph view is set to (the owner keeps it, because the view is made again each time the author comes back to it).
struct GraphViewState {
    enum Look: Int { case whole, social, neighbourhood, arc, places, locations, plan }
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
    /// Which way the main line of the arc, the locations and the plan map runs.
    var direction = GraphDirection.diagonal
    /// Where the view was looking: the zoom and the middle of what was in view, in the layout's own coordinates (nil: fit everything).
    var zoom: Double?
    var center: GraphPoint?

    init() {}

    init(memory m: GraphViewMemory?) {
        guard let m else { return }
        look = [Look.whole, .social, .neighbourhood, .arc, .places, .locations, .plan].first { ["whole", "social", "neighbourhood", "arc", "places", "locations", "plan"][$0.rawValue] == m.look } ?? .whole
        kinds = Set(m.kinds.compactMap(GraphKind.init(rawValue:)))
        showUnlinked = m.showUnlinked
        showEnded = m.showEnded; changesOnly = m.changesOnly; asOf = m.asOf
        colourByLine = m.colourBy == "plot_line"; plotLine = m.plotLine
        section = m.section; focus = m.focus; depth = max(1, min(3, m.depth))
        direction = GraphDirection(rawValue: m.direction) ?? .diagonal
        zoom = m.zoom
        if let x = m.centerX, let y = m.centerY { center = GraphPoint(x: x, y: y) }
    }

    var memory: GraphViewMemory {
        var m = GraphViewMemory()
        m.look = ["whole", "social", "neighbourhood", "arc", "places", "locations", "plan"][look.rawValue]
        m.kinds = GraphKind.allCases.filter(kinds.contains).map(\.rawValue)
        m.showUnlinked = showUnlinked
        m.showEnded = showEnded; m.changesOnly = changesOnly; m.asOf = asOf
        m.colourBy = colourByLine ? "plot_line" : "kind"; m.plotLine = plotLine
        m.section = section; m.focus = focus; m.depth = depth
        m.direction = direction.rawValue
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
    private let lookControl = NSSegmentedControl(labels: [L("Whole book"), L("Social graph"), L("Neighbourhood"), L("Arc"), L("Place tree"), L("Locations"), L("Plan map")], trackingMode: .selectOne, target: nil, action: nil)
    private let focusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let depthControl = NSSegmentedControl(labels: ["1", "2", "3"], trackingMode: .selectOne, target: nil, action: nil)
    private var kindBoxes: [GraphKind: NSButton] = [:]
    /// "Show ▾": the yes/no options that apply to the look chosen.
    private let showButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let settingsFlow = FlowView()
    private var kindsGroup = RowView([]), sectionGroup = RowView([]), colourGroup = RowView([]), showGroup = RowView([]), asOfGroup = RowView([])
    private var focusGroup = RowView([]), stepsGroup = RowView([]), directionGroup = RowView([])
    private let directionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let focusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let colourPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let linePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let legendRow = RowView([], spacing: 12)
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
        let kindTitles: [(GraphKind, String, String)] = [(.character, "●", L("Characters")), (.place, "■", L("Places")), (.event, "◆", L("Events")), (.scene, "•", L("Scenes"))]
        for (kind, glyph, title) in kindTitles {
            let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(kindChanged(_:)))
            let s = NSMutableAttributedString(string: glyph + " ", attributes: [.foregroundColor: GraphCanvasView.color(kind), .font: NSFont.systemFont(ofSize: 13)])
            s.append(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
            b.attributedTitle = s
            b.tag = Self.tag(kind)
            kindBoxes[kind] = b
        }
        showButton.controlSize = .small
        showButton.setAccessibilityLabel(L("Show"))
        for (b, action) in [(zoomOutButton, #selector(zoomOutAction)), (zoomInButton, #selector(zoomInAction)), (fitButton, #selector(fitAction)), (resetButton, #selector(resetPressed))] {
            b.target = self; b.action = action; b.bezelStyle = .rounded; b.controlSize = .small
        }
        resetButton.toolTip = L("Forgets the places you gave the nodes: the layout arranges them all again")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        asOfSlider.target = self; asOfSlider.action = #selector(asOfChanged(_:)); asOfSlider.isContinuous = true
        asOfSlider.numberOfTickMarks = 0; asOfSlider.allowsTickMarkValuesOnly = true
        asOfSlider.controlSize = .small
        asOfSlider.toolTip = L("The book as it is after a scene: the relationships then, who has been met, who is a main character. The nodes stay where they are.")
        asOfSlider.setAccessibilityLabel(L("As of"))
        for (b, tip) in [(asOfBack, L("The scene before")), (asOfForward, L("The next scene"))] { b.target = self; b.action = #selector(asOfStep(_:)); b.bezelStyle = .rounded; b.controlSize = .small; b.toolTip = tip }
        asOfBack.tag = -1; asOfForward.tag = 1
        asOfLabel.font = .systemFont(ofSize: 11); asOfLabel.textColor = .secondaryLabelColor
        asOfLabel.lineBreakMode = .byTruncatingTail
        colourPopup.addItems(withTitles: [L("Kind"), L("Plot line")])
        colourPopup.target = self; colourPopup.action = #selector(colourChanged); colourPopup.controlSize = .small
        colourPopup.setAccessibilityLabel(L("Colour by"))
        linePopup.target = self; linePopup.action = #selector(lineFilterChanged); linePopup.controlSize = .small
        linePopup.setAccessibilityLabel(L("Plot line"))
        // The bar has two lines. The first: the views, and what is the picture's own (zoom, layout, the count). The second: only the settings of the view chosen; they
        // wrap on to a line more when the window is too narrow for them all.
        func group(_ views: [NSView], caps: [NSView: CGFloat] = [:]) -> RowView { RowView(views, spacing: 6, caps: caps) }
        func caption(_ text: String) -> NSTextField { let l = NSTextField(labelWithString: text); l.font = .systemFont(ofSize: 11); l.textColor = .secondaryLabelColor; return l }
        kindsGroup = group(GraphKind.allCases.compactMap { kindBoxes[$0] })
        sectionGroup = group([caption(L("Section")), sectionPopup])
        colourGroup = group([caption(L("Colour by")), colourPopup, caption(L("Plot line")), linePopup])
        directionPopup.addItems(withTitles: [L("Diagonal"), L("Left to right"), L("Top to bottom")])
        directionPopup.target = self; directionPopup.action = #selector(directionChanged); directionPopup.controlSize = .small
        directionPopup.setAccessibilityLabel(L("Main line"))
        directionPopup.toolTip = L("Which way the main line runs: from the top left to the bottom right, from the left to the right, or from the top to the bottom")
        directionGroup = group([caption(L("Main line")), directionPopup])
        showGroup = group([showButton])
        asOfGroup = group([caption(L("As of")), asOfBack, asOfSlider, asOfForward, asOfLabel], caps: [asOfSlider: 130, asOfLabel: 200])
        focusLabel.font = .systemFont(ofSize: 11); focusLabel.textColor = .secondaryLabelColor
        focusGroup = group([focusLabel, focusPopup])
        stepsGroup = group([caption(L("Steps")), depthControl])
        hintLabel.font = .systemFont(ofSize: 11); hintLabel.textColor = .secondaryLabelColor
        hintLabel.stringValue = L("Each plot line is a strand; a hollow card has not been realised by an event yet")
        settingsFlow.set([focusGroup, stepsGroup, directionGroup, kindsGroup, sectionGroup, colourGroup, showGroup, asOfGroup, legendRow, hintLabel])
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        note.lineBreakMode = .byTruncatingTail
        note.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        let row1 = NSStackView(views: [lookControl, spacer, zoomOutButton, zoomInButton, fitButton, resetButton, note])
        row1.spacing = 8; row1.alignment = .centerY
        let bar = NSStackView(views: [row1, settingsFlow])
        bar.orientation = .vertical; bar.alignment = .leading; bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false

        canvas.onSelect = { [weak self] _ in self?.updateControls() }
        canvas.onMoved = { [weak self] id, point in self?.moved(id, to: point) }
        canvas.onOpen = { [weak self] node in
            guard !node.id.hasPrefix("plan:") else { return }   // (the head of a strand of the plan map is no card or event)
            // A node of a scene's bush stands for something real: a place with its scene opens the scene (the timeline is scenes), the rest what they stand for.
            if node.kind == .place, let scene = node.scene { self?.onOpen?(.scene, scene) } else { self?.onOpen?(node.kind, node.ref ?? node.id) }
        }
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
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            row1.widthAnchor.constraint(equalTo: bar.widthAnchor), settingsFlow.widthAnchor.constraint(equalTo: bar.widthAnchor),
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
        case .whole, .arc, .places, .locations, .plan: o.mode = .whole
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
        if let f = state.focus, characters.character(f) == nil, worlds.entry(f) == nil, worlds.world(f) == nil, events.event(f) == nil { state.focus = nil }
        if let sec = state.section, !sections().contains(where: { $0.id == sec }) { state.section = nil }
        if let line = state.plotLine, !(plan()?.lines.contains { $0.id == line } ?? false) { state.plotLine = nil }
        if let scene = state.asOf, !structure().scenes.contains(where: { $0.id == scene }) { state.asOf = nil }
        store.reload()
        let planStore = plan()
        // The arc is a graph of its own: the events of one character along a spine, with their places worked out (nothing is moved or kept).
        let arc: ArcGraph? = state.look == .arc ? state.focus.flatMap { characters.character($0) == nil ? nil : ArcBuilder.build(character: $0, characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure()) } : nil
        // The place tree is a graph of its own too: the worlds and the places inside them, from the left to the right.
        let tree: ArcGraph? = state.look == .places ? PlaceTreeBuilder.build(only: state.focus.flatMap { worlds.world($0) == nil ? nil : $0 }, characters: characters, worlds: worlds, events: events, relationships: relationships) : nil
        // The locations along the book: the scenes that places are linked to, each a bush of its places and their characters (one character, or everyone).
        let locations: ArcGraph? = state.look == .locations ? LocationsBuilder.build(only: state.focus.flatMap { characters.character($0) == nil ? nil : $0 }, characters: characters, worlds: worlds, events: events, structure: structure()) : nil
        // The plan map: a strand for each plot line, with its cards and events, and the cards joined to the events that realised them.
        let planMap: ArcGraph? = state.look == .plan ? planStore.map { PlanMapBuilder.build(plan: $0, events: events) } : nil
        let isArc = state.look == .arc || state.look == .places || state.look == .locations || state.look == .plan
        let direction = state.direction
        let turned = { (g: ArcGraph?) in g?.rotated(direction) }   // (the main line runs the way the setting says)
        graph = isArc ? (arc?.graph ?? tree?.graph ?? locations?.graph ?? planMap?.graph ?? BookGraph()) : GraphBuilder.build(characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure(), options: options, plan: planStore)
        canvas.allowsDragging = true
        canvas.lineStyles = Dictionary((planStore?.lines ?? []).compactMap { l in l.id.map { ($0, (name: l.name ?? "", color: l.color)) } }, uniquingKeysWith: { a, _ in a })
        canvas.colourByLine = state.colourByLine
        fillLinePopup(planStore?.lines ?? [])
        updateLegend()
        let ids = Set(graph.nodes.map(\.id))
        let pinned = isArc ? [:] : store.positions.filter { ids.contains($0.key) }
        // In a computed view only what hangs on the main axis can be moved, and where it was put is kept for this view and subject (never for the book's graph).
        var movedHere: [String: GraphPoint] = [:]
        if isArc, let sc = scope { for (k, v) in store.positions where k.hasPrefix(sc + "#") { let id = String(k.dropFirst(sc.count + 1)); if graph.node(id)?.anchored == false { movedHere[id] = v } } }
        // (As of a point only flags change, not the nodes and lines: the layout is not made again, so that the picture stays still while the point moves.)
        let key = graph.nodes.map(\.id).joined(separator: ",") + "|" + graph.edges.map { "\($0.a)-\($0.b)-\($0.kind.rawValue)-\($0.weight)" }.joined(separator: ",") + "|" + pinned.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value.x),\($0.value.y)" }.joined(separator: ";")
        let placed: [String: GraphPoint]
        if isArc { placed = (turned(arc)?.positions ?? tree?.positions ?? turned(locations)?.positions ?? turned(planMap)?.positions ?? [:]).merging(movedHere) { _, moved in moved } } else if key == lastLayoutKey, let kept = lastPlaced { placed = kept } else { placed = GraphLayout.layout(nodes: graph.nodes, edges: graph.edges, pinned: pinned); lastLayoutKey = key; lastPlaced = placed }
        let xs = placed.values.map(\.x), ys = placed.values.map(\.y)
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0, maxX = xs.max() ?? 0, maxY = ys.max() ?? 0
        offset = CGPoint(x: Self.margin - minX, y: Self.margin - minY)
        canvas.frame = NSRect(x: 0, y: 0, width: max(maxX - minX + 2 * Self.margin, 1200), height: max(maxY - minY + 2 * Self.margin, 800))
        canvas.pinned = Set(pinned.keys).union(movedHere.keys)
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

    /// The views that are worked out (not the book's graph) keep where nodes were moved under their own keys: the view and its subject, then the node.
    private var scope: String? {
        switch state.look {
        // (A moved node is kept for the direction of the main line it was moved in: the picture is turned with it.)
        case .arc: return "arc|" + (state.focus ?? "") + directionKey
        case .places: return "places|" + (state.focus ?? "")
        case .locations: return "locations|" + (state.focus ?? "") + directionKey
        case .plan: return "plan|" + directionKey
        default: return nil
        }
    }
    private var directionKey: String { state.direction == .diagonal ? "" : "@" + state.direction.rawValue }
    private func key(_ id: String) -> String { (scope.map { $0 + "#" } ?? "") + id }
    /// Where the author has put nodes in the view shown (the book's graph, or the view and subject).
    private var pinKeys: [String] {
        if let sc = scope { return store.positions.keys.filter { $0.hasPrefix(sc + "#") } }
        return store.positions.keys.filter { !$0.contains("#") }
    }

    private func moved(_ id: String, to point: CGPoint) {
        try? store.pin(key(id), at: GraphPoint(x: point.x - offset.x, y: point.y - offset.y))
        canvas.pinned.insert(id)
        updateControls()
        onChange?()
    }

    // MARK: Controls

    private func syncControlsFromState() {
        lookControl.selectedSegment = state.look.rawValue
        depthControl.selectedSegment = max(0, min(2, state.depth - 1))
        for (kind, box) in kindBoxes { box.state = state.kinds.contains(kind) ? .on : .off }
        fillShowMenu()
    }

    private func fillFocusPopup() {
        focusPopup.removeAllItems()
        focusPopup.addItem(withTitle: L("Choose…"))
        focusPopup.lastItem?.representedObject = ""
        let groups: [(String, [(String, String)])] = [
            (L("Characters"), characters.characters.compactMap { c in c.id.map { ($0, c.name ?? "") } }),
            (L("Places"), worlds.entries.compactMap { p in p.id.map { ($0, worlds.path(of: $0).dropFirst().joined(separator: " › ")) } }),
            (L("Events"), events.events.compactMap { e in e.id.map { ($0, e.title ?? "") } }),
            (L("Worlds"), worlds.worlds.compactMap { w in w.id.map { ($0, w.name ?? "") } }),
        ]
        // (The arc follows a character, the place tree shows a world or all of them; the others look at anything but a world.)
        for (title, items) in groups where !items.isEmpty && (state.look == .arc || state.look == .locations ? title == L("Characters") : (state.look == .places ? title == L("Worlds") : (state.look != .plan && title != L("Worlds")))) {
            focusPopup.menu?.addItem(.separator())
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: ""); header.isEnabled = false
            focusPopup.menu?.addItem(header)
            focusPopup.addChoices(items.sorted(by: { $0.1.localizedLowercase < $1.1.localizedLowercase }).map { (title: $0.1, value: $0.0) })
        }
        let current = state.focus ?? ""
        if let item = focusPopup.itemArray.first(where: { ($0.representedObject as? String) == current && !current.isEmpty }) { focusPopup.select(item) } else { focusPopup.selectItem(at: 0) }
    }

    private func fillSectionPopup() {
        sectionPopup.removeAllItems()
        sectionPopup.addItem(withTitle: L("Whole book"))
        sectionPopup.lastItem?.representedObject = ""
        sectionPopup.addChoices(sections().map { (title: String(repeating: "   ", count: $0.depth) + $0.title, value: $0.id) })
        if let id = state.section, let item = sectionPopup.itemArray.first(where: { ($0.representedObject as? String) == id }) { sectionPopup.select(item) } else { sectionPopup.selectItem(at: 0) }
    }

    /// What can be used now is on; what does not belong to the look chosen is not shown.
    func updateControls() {
        guard isViewLoaded else { return }
        let hood = state.look == .neighbourhood, own = [GraphViewState.Look.arc, .places, .locations, .plan].contains(state.look)
        let book = !own   // (the looks of the book's graph: whole, social, neighbourhood)
        // The second line: the settings of this look.
        focusGroup.isHidden = !(hood || [.arc, .places, .locations].contains(state.look))
        focusLabel.stringValue = hood ? L("Look at") : (state.look == .places ? L("World") : L("Character"))
        stepsGroup.isHidden = !hood
        directionGroup.isHidden = ![.arc, .locations, .plan].contains(state.look)
        directionPopup.selectItem(at: GraphDirection.allCases.firstIndex(of: state.direction) ?? 0)
        kindsGroup.isHidden = !(state.look == .whole || hood)
        sectionGroup.isHidden = !book
        colourGroup.isHidden = !book
        asOfGroup.isHidden = !book
        fillShowMenu()
        showGroup.isHidden = !book || showButton.menu?.items.count ?? 0 < 2
        legendRow.isHidden = !(book && state.colourByLine)
        hintLabel.isHidden = state.look != .plan
        settingsFlow.needsLayout = true
        focusPopup.isEnabled = hood || [.arc, .places, .locations].contains(state.look)
        depthControl.isEnabled = hood
        for box in kindBoxes.values { box.isEnabled = true }
        zoomOutButton.isEnabled = scroll.magnification > scroll.minMagnification + 0.001
        zoomInButton.isEnabled = scroll.magnification < scroll.maxMagnification - 0.001
        fitButton.isEnabled = !graph.nodes.isEmpty
        resetButton.isEnabled = !pinKeys.isEmpty
        updateAsOfControls()
        note.stringValue = graph.nodes.isEmpty ? "" : Lp("{n} node", "{n} nodes", graph.nodes.count) + " · " + Lp("{n} link", "{n} links", graph.edges.filter { !$0.hidden }.count) + (graph.warningCount > 0 ? " · ⚠ " + Lp("{n} warning", "{n} warnings", graph.warningCount) : "")
        if graph.nodes.isEmpty {
            emptyLabel.stringValue = state.look == .arc && (state.focus.flatMap { characters.character($0) } == nil) ? L("Choose a character to follow") : (state.look == .plan ? L("The plan is empty") : state.look == .locations ? L("No scene is linked to a place yet") : (hood && (state.focus ?? "").isEmpty ? L("Choose a thing to look at") : L("Nothing to show with these settings")))
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
        // The place tree shows every world, or the one that was chosen.
        if state.look == .places, let f = state.focus, worlds.world(f) == nil { state.focus = nil }
        // The locations follow one character, or everyone.
        if state.look == .locations, let f = state.focus, characters.character(f) == nil { state.focus = nil }
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
        for (title, l) in zip(PopupTitles.distinct(lines.map { $0.name ?? "" }), lines) { linePopup.addChoice(title, value: l.id).image = PlanColors.swatch(l.color) }
        if let id = state.plotLine, let item = linePopup.itemArray.first(where: { ($0.representedObject as? String) == id }) { linePopup.select(item) } else { linePopup.selectItem(at: 0) }
        linePopup.isEnabled = !lines.isEmpty
        colourPopup.selectItem(at: state.colourByLine ? 1 : 0)
    }

    /// The colours of the plot lines that are on the graph, as chips (only when the nodes are coloured by plot line).
    private func updateLegend() {
        var chipViews: [NSView] = []
        legendRow.isHidden = !state.colourByLine
        guard state.colourByLine else { return }
        let used = Set(graph.nodes.flatMap(\.lines))
        var chips: [(String, NSColor)] = canvas.lineStyles.filter { used.contains($0.key) }.sorted { $0.value.name < $1.value.name }.map { ($0.value.name, PlanColors.color($0.value.color)) }
        if graph.nodes.contains(where: { $0.lines.isEmpty && $0.kind != .scene }) { chips.append((L("not on a plot line"), .systemGray)) }
        for (name, color) in chips {
            let label = NSTextField(labelWithString: name); label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            chipViews.append(RowView([Swatch(color), label], spacing: 4))
        }
        legendRow.set(chipViews)
        legendTitles = chips.map(\.0)
    }

    private(set) var legendTitles: [String] = []

    @objc private func directionChanged() {
        state.direction = GraphDirection.allCases.indices.contains(directionPopup.indexOfSelectedItem) ? GraphDirection.allCases[directionPopup.indexOfSelectedItem] : .diagonal
        resetViewport(); reload()
    }

    /// For the checks: sets the direction of the main line.
    func setDirection(_ d: GraphDirection) { state.direction = d; resetViewport(); reload() }
    var direction: GraphDirection { state.direction }
    var directionControlShown: Bool { !directionGroup.isHidden }

    @objc private func colourChanged() { state.colourByLine = colourPopup.indexOfSelectedItem == 1; reload() }

    @objc private func lineFilterChanged() {
        let id = linePopup.selectedItem?.representedObject as? String ?? ""
        state.plotLine = id.isEmpty ? nil : id
        resetViewport()
        reload()
    }

    /// "Show ▾": the yes/no options the look chosen has, each ticked when on.
    private func fillShowMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("Show"), action: nil, keyEquivalent: ""))   // (the button's own title)
        func option(_ title: String, _ tip: String, _ on: Bool, _ change: @escaping () -> Void) {
            let item = ClosureMenuItem(title: title) { [weak self] in change(); self?.resetViewport(); self?.reload() }
            item.state = on ? .on : .off
            item.toolTip = tip
            menu.addItem(item)
        }
        let look = state.look
        if look == .whole || look == .social {
            option(L("Show unlinked"), L("Things with no line to anything shown: a place no event uses, a character in no event"), state.showUnlinked) { [weak self] in self?.state.showUnlinked.toggle() }
        }
        if look == .whole || look == .social || look == .neighbourhood {
            option(L("Show ended relationships"), L("A relationship that has ended is drawn dashed; its tooltip says from which event to which"), state.showEnded) { [weak self] in self?.state.showEnded.toggle() }
        }
        if look == .whole || look == .neighbourhood {
            option(L("Changes only"), L("Only the events that change something, with what they change: the turning points of the story"), state.changesOnly) { [weak self] in self?.state.changesOnly.toggle() }
        }
        showButton.menu = menu
    }

    /// For the checks: the options of the Show menu, and whether each is ticked.
    var showOptions: [(title: String, on: Bool)] { (showButton.menu?.items.dropFirst() ?? []).map { ($0.title, $0.state == .on) } }

    @objc private func sectionChanged() {
        let id = sectionPopup.selectedItem?.representedObject as? String ?? ""
        state.section = id.isEmpty ? nil : id
        resetViewport()
        reload()
    }

    // MARK: Zoom, layout

    func zoomIn() { zoom(to: min(scroll.maxMagnification, scroll.magnification * 1.25)) }
    func zoomOut() { zoom(to: max(scroll.minMagnification, scroll.magnification / 1.25)) }

    /// Zooms to a magnification. With a node chosen, the zoom is round that node: it stays where it is in the window (a node that is out of view is brought to the middle
    /// first), so that it is what you look closer at or farther from. With none chosen, the zoom is round the middle of what is in view.
    private func zoom(to target: CGFloat) {
        guard let id = canvas.selected, let p = canvas.center(of: id) else { scroll.setMagnification(target, centeredAt: visibleCenter); return }
        let clip = scroll.contentView
        let seen = clip.bounds
        var fx = (p.x - seen.minX) / max(seen.width, 1), fy = (p.y - seen.minY) / max(seen.height, 1)
        if !(0...1).contains(fx) || !(0...1).contains(fy) { fx = 0.5; fy = 0.5 }
        scroll.magnification = target
        let size = clip.bounds.size
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: CGPoint(x: p.x - fx * size.width, y: p.y - fy * size.height), size: size)).origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// For the checks: where a node is in what is in view, as fractions (0 to 1, from the top left), or nil when it is not in view.
    func viewFraction(of id: String) -> CGPoint? {
        guard let p = canvas.center(of: id) else { return nil }
        let seen = scroll.contentView.bounds
        let f = CGPoint(x: (p.x - seen.minX) / seen.width, y: (p.y - seen.minY) / seen.height)
        return (0...1).contains(f.x) && (0...1).contains(f.y) ? f : nil
    }
    func selectForTest(_ id: String?) { canvas.select(id) }
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
        guard !pinKeys.isEmpty else { return }
        if confirm {
            let alert = NSAlert()
            alert.messageText = L("Reset the layout?")
            alert.informativeText = L("The places you gave the nodes are forgotten, and the layout arranges them all again.")
            alert.addButton(withTitle: L("Cancel")).keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Reset Layout"))
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        for k in pinKeys { try? store.release(k) }   // (only the nodes of the view shown)
        resetViewport()
        reload()
        onChange?()
    }

    func release(_ id: String) {
        try? store.release(key(id))
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
            menu.addItem(ClosureMenuItem(title: L("Open")) { [weak self] in self?.canvas.onOpen?(node) })
            if node.kind == .place, node.scene != nil, let place = node.ref { menu.addItem(ClosureMenuItem(title: L("Open the Place")) { [weak self] in self?.onOpen?(.place, place) }) }
            if node.kind != .scene, node.kind != .stage, node.kind != .card { menu.addItem(ClosureMenuItem(title: L("Focus on This")) { [weak self] in self?.focus(on: node.ref ?? node.id) }) }
            if node.kind == .character { menu.addItem(ClosureMenuItem(title: L("Show the Arc")) { [weak self] in self?.showArc(of: node.ref ?? node.id) }) }
            if store.positions[key(node.id)] != nil { menu.addItem(ClosureMenuItem(title: L("Release Position")) { [weak self] in self?.release(node.id) }) }
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
        (!focusGroup.isHidden && focusPopup.isEnabled, !stepsGroup.isHidden && depthControl.isEnabled, !kindsGroup.isHidden && kindBoxes.values.allSatisfy(\.isEnabled), resetButton.isEnabled, zoomOutButton.isEnabled, zoomInButton.isEnabled, fitButton.isEnabled)
    }
    func setFocusForTest(_ id: String?) { state.focus = id; resetViewport(); reload() }
    /// For the checks: is each kind checkbox as wide as its title needs (the titles are not squeezed out)?
    var settingsWidthsForTest: [CGFloat] { view.layoutSubtreeIfNeeded(); settingsFlow.layoutSubtreeIfNeeded(); return GraphKind.allCases.compactMap { kindBoxes[$0]?.frame.width } }
    var settingsTitlesAreWholeForTest: Bool { view.layoutSubtreeIfNeeded(); settingsFlow.layoutSubtreeIfNeeded(); return kindBoxes.values.allSatisfy { $0.frame.width >= $0.attributedTitle.size().width + 12 } && asOfSlider.frame.width >= 100 }
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
