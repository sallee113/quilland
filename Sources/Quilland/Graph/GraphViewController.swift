import AppKit
import QuillandCore

/// What the Graph view is set to (the owner keeps it, because the view is made again each time the author comes back to it).
struct GraphViewState {
    enum Look: Int { case whole, social, neighbourhood }
    var look = Look.whole
    var kinds: Set<GraphKind> = [.character, .place, .event]
    var showUnlinked = true
    var section: String?
    var focus: String?
    var depth = 1
}

/// The Graph view: the characters, places, events and scenes of the book as nodes, with the links between them as lines. It only shows; the cards are where
/// links are made. The author can move nodes (they stay where they were put) and filter what is shown.
final class GraphViewController: NSViewController {
    var characters: CharacterStore!
    var worlds: WorldStore!
    var events: EventStore!
    var relationships: RelationshipStore!
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
    var state = GraphViewState()

    private(set) var graph = BookGraph()
    let canvas = GraphCanvasView()
    private let scroll = NSScrollView()
    private let lookControl = NSSegmentedControl(labels: [L("Whole book"), L("Social graph"), L("Neighbourhood")], trackingMode: .selectOne, target: nil, action: nil)
    private let focusPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let depthControl = NSSegmentedControl(labels: ["1", "2", "3"], trackingMode: .selectOne, target: nil, action: nil)
    private var kindBoxes: [GraphKind: NSButton] = [:]
    private let unlinkedBox = NSButton(checkboxWithTitle: L("Show unlinked"), target: nil, action: nil)
    private let sectionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let zoomOutButton = NSButton(title: "−", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "+", target: nil, action: nil)
    private let fitButton = NSButton(title: L("Fit"), target: nil, action: nil)
    private let resetButton = NSButton(title: L("Reset Layout"), target: nil, action: nil)
    private let note = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private var magnificationObserver: NSKeyValueObservation?
    private static let margin: CGFloat = 500
    /// Where the layout puts the origin on the canvas, to turn canvas points into the book's own (what is saved).
    private var offset = CGPoint.zero

    override func loadView() {
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
        unlinkedBox.target = self; unlinkedBox.action = #selector(unlinkedChanged)
        unlinkedBox.toolTip = L("Things with no line to anything shown: a place no event uses, a character in no event")
        for (b, action) in [(zoomOutButton, #selector(zoomOutAction)), (zoomInButton, #selector(zoomInAction)), (fitButton, #selector(fitAction)), (resetButton, #selector(resetPressed))] {
            b.target = self; b.action = action; b.bezelStyle = .rounded; b.controlSize = .small
        }
        resetButton.toolTip = L("Forgets the places you gave the nodes: the layout arranges them all again")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)

        let row1 = NSStackView(views: [lookControl, NSTextField(labelWithString: L("Look at")), focusPopup, NSTextField(labelWithString: L("Steps")), depthControl, NSTextField(labelWithString: L("Section")), sectionPopup])
        let row2 = NSStackView(views: [kindBoxes[.character]!, kindBoxes[.place]!, kindBoxes[.event]!, kindBoxes[.scene]!, unlinkedBox, zoomOutButton, zoomInButton, fitButton, resetButton, note])
        for r in [row1, row2] { r.spacing = 10; r.alignment = .centerY }
        let bar = NSStackView(views: [row1, row2])
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
        magnificationObserver = scroll.observe(\.magnification, options: [.new]) { [weak self] _, _ in self?.updateControls() }
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
        switch state.look {
        case .whole: o.mode = .whole
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
        store.reload()
        graph = GraphBuilder.build(characters: characters, worlds: worlds, events: events, relationships: relationships, structure: structure(), options: options)
        let ids = Set(graph.nodes.map(\.id))
        let pinned = store.positions.filter { ids.contains($0.key) }
        let placed = GraphLayout.layout(nodes: graph.nodes, edges: graph.edges, pinned: pinned)
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
        DispatchQueue.main.async { [weak self] in self?.fitIfFirstTime() }
    }

    private var fitted = false
    private func fitIfFirstTime() {
        guard !fitted, !graph.nodes.isEmpty else { return }
        fitted = true
        zoomToFit()
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
        for (title, items) in groups where !items.isEmpty {
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
        let hood = state.look == .neighbourhood
        focusPopup.isEnabled = hood
        depthControl.isEnabled = hood
        for box in kindBoxes.values { box.isEnabled = state.look != .social }
        zoomOutButton.isEnabled = scroll.magnification > scroll.minMagnification + 0.001
        zoomInButton.isEnabled = scroll.magnification < scroll.maxMagnification - 0.001
        fitButton.isEnabled = !graph.nodes.isEmpty
        resetButton.isEnabled = !store.positions.isEmpty
        note.stringValue = graph.nodes.isEmpty ? "" : Lp("{n} node", "{n} nodes", graph.nodes.count) + " · " + Lp("{n} link", "{n} links", graph.edges.count)
        if graph.nodes.isEmpty {
            emptyLabel.stringValue = hood && (state.focus ?? "").isEmpty ? L("Choose a thing to look at") : L("Nothing to show with these settings")
        }
        emptyLabel.isHidden = !graph.nodes.isEmpty
    }

    @objc private func lookChanged() {
        state.look = GraphViewState.Look(rawValue: lookControl.selectedSegment) ?? .whole
        // "Neighbourhood" looks at what is chosen on the canvas when nothing was chosen before.
        if state.look == .neighbourhood, (state.focus ?? "").isEmpty, let s = canvas.selected { state.focus = s }
        fitted = false
        reload()
    }

    @objc private func depthChanged() { state.depth = depthControl.selectedSegment + 1; fitted = false; reload() }

    @objc private func focusChanged() {
        let id = focusPopup.selectedItem?.representedObject as? String ?? ""
        state.focus = id.isEmpty ? nil : id
        fitted = false
        reload()
    }

    @objc private func kindChanged(_ sender: NSButton) {
        guard let kind = GraphKind.allCases.first(where: { Self.tag($0) == sender.tag }) else { return }
        if sender.state == .on { state.kinds.insert(kind) } else { state.kinds.remove(kind) }
        fitted = false
        reload()
    }

    @objc private func unlinkedChanged() { state.showUnlinked = unlinkedBox.state == .on; fitted = false; reload() }

    @objc private func sectionChanged() {
        let id = sectionPopup.selectedItem?.representedObject as? String ?? ""
        state.section = id.isEmpty ? nil : id
        fitted = false
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
        fitted = false
        reload()
        onChange?()
    }

    func release(_ id: String) {
        try? store.release(id)
        reload()
        onChange?()
    }

    /// Looks at one thing and what is around it.
    func focus(on id: String) {
        state.look = .neighbourhood
        state.focus = id
        syncControlsFromState()
        fitted = false
        reload()
    }

    // MARK: The menu

    private func menu(for node: GraphNode?) -> NSMenu? {
        let menu = NSMenu()
        if let node {
            menu.addItem(ClosureMenuItem(title: L("Open")) { [weak self] in self?.onOpen?(node.kind, node.id) })
            if node.kind != .scene { menu.addItem(ClosureMenuItem(title: L("Focus on This")) { [weak self] in self?.focus(on: node.id) }) }
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

    var shownIDs: [String] { graph.nodes.map(\.id) }
    var noteText: String { note.stringValue }
    var controlsEnabled: (focus: Bool, depth: Bool, kinds: Bool, reset: Bool, zoomOut: Bool, zoomIn: Bool, fit: Bool) {
        (focusPopup.isEnabled, depthControl.isEnabled, kindBoxes.values.allSatisfy(\.isEnabled), resetButton.isEnabled, zoomOutButton.isEnabled, zoomInButton.isEnabled, fitButton.isEnabled)
    }
    var emptyText: String? { emptyLabel.isHidden ? nil : emptyLabel.stringValue }
    func setLook(_ look: GraphViewState.Look) { state.look = look; syncControlsFromState(); fitted = false; reload() }
    func setKind(_ kind: GraphKind, _ on: Bool) { if on { state.kinds.insert(kind) } else { state.kinds.remove(kind) }; syncControlsFromState(); reload() }
    func setShowUnlinked(_ on: Bool) { state.showUnlinked = on; syncControlsFromState(); reload() }
    func setSection(_ id: String?) { state.section = id; reload() }
    func setDepth(_ depth: Int) { state.depth = depth; syncControlsFromState(); fitted = false; reload() }
}
