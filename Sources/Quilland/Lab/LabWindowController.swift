import AppKit
import QuillandCore

/// A window for trying the pieces of the interface that the design depends on, before the screens around them are built:
/// Book mode (a stack of scene editors), Compare (two views on the same texts), typewriter scrolling.
final class LabWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let modeControl = NSSegmentedControl(labels: ["Book", "Compare", "Plan"], trackingMode: .selectOne, target: nil, action: nil)
    private let typewriterBox = NSButton(checkboxWithTitle: "Typewriter", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let container = NSView()
    private var session: BookSession?
    private var controllers: [BookViewController] = []
    private var compareController: NSSplitViewController?
    private(set) var planController: PlanCanvasController?
    private var currentFolder: URL?
    private let planModeControl = NSSegmentedControl(labels: ["Plan", "Events"], trackingMode: .selectOne, target: nil, action: nil)
    private let addLineButton = NSButton(title: "+ Line", target: nil, action: nil)
    private let addCardButton = NSButton(title: "+ Card", target: nil, action: nil)
    private let zoomOutButton = NSButton(title: "−", target: nil, action: nil)
    private let zoomInButton = NSButton(title: "+", target: nil, action: nil)
    private let fitButton = NSButton(title: "Fit", target: nil, action: nil)
    private lazy var planControls = NSStackView(views: [planModeControl, addLineButton, addCardButton, zoomOutButton, zoomInButton, fitButton])
    private var loadLine = ""
    private var statusTimer: Timer?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Quilland Lab"
        window.delegate = self
        window.contentMinSize = NSSize(width: 640, height: 400)
        window.setFrameAutosaveName("QuillandLab")
        if !window.setFrameUsingName("QuillandLab") { window.center() }

        modeControl.target = self; modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = 0
        typewriterBox.target = self; typewriterBox.action = #selector(typewriterChanged)
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        planModeControl.selectedSegment = 0
        planModeControl.target = self; planModeControl.action = #selector(planModeChanged)
        addLineButton.target = self; addLineButton.action = #selector(addLine)
        addCardButton.target = self; addCardButton.action = #selector(addCard)
        zoomOutButton.target = self; zoomOutButton.action = #selector(zoomOut)
        zoomInButton.target = self; zoomInButton.action = #selector(zoomIn)
        fitButton.target = self; fitButton.action = #selector(zoomFit)
        planControls.spacing = 8
        planControls.isHidden = true
        let bar = NSStackView(views: [modeControl, typewriterBox, planControls])
        bar.spacing = 14
        let content = NSView()
        for v in [bar, container, status] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            container.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -5),
        ])
        window.contentView = content
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshStatus() }
    }

    func show() { window.makeKeyAndOrderFront(nil) }

    // MARK: The book

    func load(folder: URL) {
        session?.saveAll()
        let started = CACurrentMediaTime()
        guard let structure = try? BookStructure.load(folder: folder) else { loadLine = "could not read \(folder.path)"; return }
        let read = CACurrentMediaTime()
        let session = BookSession(structure: structure)
        let loaded = CACurrentMediaTime()
        self.session = session
        rebuild()
        let built = CACurrentMediaTime()
        let ms = { (a: Double, b: Double) in Int((b - a) * 1000) }
        loadLine = "\(structure.scenes.count) scenes, \(NumberFormatter.localizedString(from: NSNumber(value: session.totalCharacters), number: .decimal)) characters: structure \(ms(started, read)) ms, texts \(ms(read, loaded)) ms, sheets \(ms(loaded, built)) ms"
        currentFolder = folder
        window.title = "Quilland Lab — \(folder.lastPathComponent)"
        refreshStatus()
    }

    func rebuild() {
        container.subviews.forEach { $0.removeFromSuperview() }
        planControls.isHidden = modeControl.selectedSegment != 2
        typewriterBox.isHidden = modeControl.selectedSegment == 2
        if modeControl.selectedSegment == 2 { showPlan(); return }
        planController = nil
        guard let session else { return }
        for c in controllers { c.view.removeFromSuperview() }
        controllers = []
        compareController = nil
        let compare = modeControl.selectedSegment == 1
        let count = compare ? 2 : 1
        for _ in 0..<count {
            let controller = BookViewController(session: session)
            _ = controller.view
            controller.setTypewriter(typewriterBox.state == .on)
            controller.onCurrentSceneChange = { [weak self] _ in self?.refreshStatus() }
            controllers.append(controller)
        }
        let content: NSView
        if compare {
            // Two equal areas side by side, each with its own scroll.
            let split = NSSplitViewController()
            split.splitView.isVertical = true
            split.splitView.dividerStyle = .thin
            for c in controllers {
                let item = NSSplitViewItem(viewController: c)
                item.minimumThickness = 320
                split.addSplitViewItem(item)
            }
            compareController = split
            content = split.view
        } else {
            compareController = nil
            content = controllers[0].view
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor), content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor), content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        if let first = session.structure.scenes.first, let c = controllers.first {
            DispatchQueue.main.async { c.focus(sceneID: first.id) }
        }
    }

    @objc private func modeChanged() { rebuild() }

    // MARK: The plan

    private func showPlan() {
        guard let folder = currentFolder, let store = try? PlanStore(folder: folder) else { return }
        if store.lines.isEmpty { try? LabPlanGenerator.generate(into: folder) }
        guard let store = try? PlanStore(folder: folder) else { return }
        let controller = PlanCanvasController(store: store)
        _ = controller.view
        controller.onChange = { [weak self] in self?.refreshStatus() }
        planController = controller
        let content = controller.view
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor), content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor), content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        planModeControl.selectedSegment = controller.mode == .plan ? 0 : 1
        refreshStatus()
    }

    func setPlanMode() { modeControl.selectedSegment = 2; rebuild() }
    func regeneratePlan() {
        guard let folder = currentFolder else { return }
        try? LabPlanGenerator.generate(into: folder)
        setPlanMode()
    }
    @objc private func planModeChanged() { planController?.setMode(planModeControl.selectedSegment == 0 ? .plan : .events) }
    @objc func addLine() { planController?.addLine() }
    @objc func addCard() { planController?.addCard() }
    @objc func zoomIn() { planController?.zoomIn(); refreshStatus() }
    @objc func zoomOut() { planController?.zoomOut(); refreshStatus() }
    @objc func zoomFit() { planController?.zoomToFit(); refreshStatus() }
    @objc func typewriterChanged() { controllers.forEach { $0.setTypewriter(typewriterBox.state == .on) } }

    func toggleTypewriter() { typewriterBox.state = typewriterBox.state == .on ? .off : .on; typewriterChanged() }

    private func refreshStatus() {
        if let plan = planController {
            let floating = plan.store.cards.values.filter(\.isFloating).count
            status.stringValue = "plan: \(plan.store.lines.count) lines, \(plan.store.cards.count) cards (\(floating) floating), \(plan.store.entries.count) real events    |    mode: \(plan.mode == .plan ? "Plan (cards on top)" : "Events (events on top)")    |    zoom \(Int(plan.zoom * 100))%"
            return
        }
        guard let session else { status.stringValue = "Choose Lab ▸ Open Sample Book"; return }
        let saves = session.documents.values.reduce(0) { $0 + $1.saveCount }
        let dirty = session.documents.values.filter(\.isDirty).count
        var line = loadLine
        if let id = controllers.compactMap(\.currentSceneID).first, let d = session.document(id) {
            line += "    |    in “\(d.title)” \(NumberFormatter.localizedString(from: NSNumber(value: d.counts.characters), number: .decimal)) characters"
        }
        if let c = controllers.first(where: { $0.currentSheet != nil }), let tv = c.currentSheet?.textView {
            let length = tv.textStorage?.length ?? 0
            let here = tv.caretRect(), end = tv.caretRect(at: length), first = tv.caretRect(at: 0)
            let onLast = (here != nil && end != nil) ? abs(here!.minY - end!.minY) < 1 : false
            let onFirst = (here != nil && first != nil) ? abs(here!.minY - first!.minY) < 1 : false
            line += "    |    cursor \(tv.selectedRange().location) of \(length)\(onLast ? ", on the last line" : "")\(onFirst ? ", on the first line" : "")\(tv.selectedRange().length > 0 ? ", selection \(tv.selectedRange().length)" : "")"
        }
        line += "    |    saved \(saves) times, \(dirty) unsaved"
        status.stringValue = line
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { session?.saveAll(); return true }
    func saveAll() { session?.saveAll() }

    /// Opens the sample book, shows the third scene with the cursor in it, and writes the window to a PNG.
    func snapshot(to path: String, compare: Bool, typewriter: Bool, plan: Bool = false) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("QuillandLab/Snapshot")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? SampleBook.write(into: folder)
        setMode(compare: compare)
        typewriterBox.state = typewriter ? .on : .off
        load(folder: folder)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        if plan {
            try? LabPlanGenerator.generate(into: folder)
            setPlanMode()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            planController?.zoomToFit()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } else if let c = controllers.first, let third = session?.structure.scenes[2] {
            c.focus(sceneID: third.id)
            c.setTypewriter(typewriter)
            if typewriter, let sheet = c.currentSheet { c.centerCaret(of: sheet.textView, animated: false) }
            else if let sheet = c.currentSheet { c.scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: max(0, sheet.frame.minY - 90))); c.scrollView.reflectScrolledClipView(c.scrollView.contentView) }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        if let c = controllers.first {
            print("window \(window.frame), content \(window.contentView!.frame), container \(container.frame), scroll \(c.scrollView.frame), clip \(c.scrollView.contentView.bounds), stack \(c.stack.frame), first sheet \(c.stack.sheets[0].frame)")
        }
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    var firstController: BookViewController? { controllers.first }
    var allControllers: [BookViewController] { controllers }
    var currentSession: BookSession? { session }
    func setMode(compare: Bool) { modeControl.selectedSegment = compare ? 1 : 0; rebuild() }
}
