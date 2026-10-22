import AppKit
import QuillandCore

/// `Quilland --selftest-app`: the first launch, a new book, writing, closing, reopening where the author left off.
/// Moves a pretend pointer over a window and tells every tracking area under it, as the system does: entered, moved, left.
final class PointerSimulator {
    let window: NSWindow
    private var inside: [ObjectIdentifier: (area: NSTrackingArea, view: NSView)] = [:]
    private(set) var unanswered: [String] = []
    private(set) var entered = 0

    init(window: NSWindow) { self.window = window }

    private func event(_ type: NSEvent.EventType, _ point: NSPoint, area: NSTrackingArea) -> NSEvent? {
        type == .mouseMoved
            ? NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
            : NSEvent.enterExitEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)
    }

    private func send(_ name: String, to area: NSTrackingArea, _ type: NSEvent.EventType, _ point: NSPoint) {
        guard let owner = area.owner as? NSObject, let e = event(type, point, area: area) else { return }
        if owner.responds(to: NSSelectorFromString(name)) { _ = owner.perform(NSSelectorFromString(name), with: e) } else { unanswered.append("\(Swift.type(of: owner)) \(name)") }
    }

    func move(to windowPoint: NSPoint) {
        guard let content = window.contentView else { return }
        func everyView(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(everyView) }
        var now: [ObjectIdentifier: (area: NSTrackingArea, view: NSView)] = [:]
        for v in everyView(content) where !v.isHiddenOrHasHiddenAncestor {
            let local = v.convert(windowPoint, from: nil)
            guard v.bounds.contains(local) else { continue }
            for area in v.trackingAreas { now[ObjectIdentifier(area)] = (area, v) }
        }
        for (key, item) in inside where now[key] == nil {
            if item.area.options.contains(.mouseEnteredAndExited) { send("mouseExited:", to: item.area, .mouseExited, windowPoint) }
        }
        for (key, item) in now {
            if inside[key] == nil {
                if item.area.options.contains(.mouseEnteredAndExited) { send("mouseEntered:", to: item.area, .mouseEntered, windowPoint); entered += 1 }
                if item.area.options.contains(.cursorUpdate) { send("cursorUpdate:", to: item.area, .cursorUpdate, windowPoint) }
            }
            if item.area.options.contains(.mouseMoved) { send("mouseMoved:", to: item.area, .mouseMoved, windowPoint) }
        }
        inside = now
    }
}

/// The application's own automatic checks (`Quilland --selftest-app`): the windows and views of the real application, driven in code. The checks come in order, each topic
/// in a file of its own (`AppSelfTest+<Topic>.swift`); a topic leaves the book in the state the next one expects, and what they share is kept in the properties below.
final class AppSelfTest {
    private(set) var passed = 0
    private(set) var failed = 0
    let app: AppDelegate
    let temp: URL

    // What the topics share: set by the topic that makes it, read by the ones after.
    var again: BookWindowController!
    var book: BookWindowController!
    var cv2: CharactersViewController!
    var folder: URL!
    var main: MainAreaController!
    var place: Int!
    var sc: [BookStructure.SceneEntry]!
    var sceneURL: URL!

    init(app: AppDelegate, temp: URL) {
        self.app = app
        self.temp = temp
    }

    func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
        if ok { passed += 1; print("  ok   \(what)") } else { failed += 1; print("  FAIL \(what) \(detail())") }
    }

    func spin(_ seconds: TimeInterval = 0.2) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    func create(title: String, plan: Bool) -> URL? {
        var created: URL?
        let dialog = NewBookWindowController(parentFolder: temp)
        dialog.titleField.stringValue = title
        dialog.authorField.stringValue = "Вадим Сульянов"
        dialog.languagePopup.selectItem(at: NewBookWindowController.languages.firstIndex { $0.0 == "ru" } ?? 0)
        dialog.onCreated = { [app] folder, startPlan in
            created = folder
            _ = app.openBook(at: folder, mode: startPlan ? .plan : .panels)
        }
        dialog.create(plan: plan)
        return created
    }

    /// Puts a text in a scene's document and saves it (the checks write their scenes this way).
    func setText(_ id: String, _ text: String) {
        let doc = main.session.document(id)!
        doc.storage.replaceCharacters(in: NSRange(location: 0, length: doc.storage.length), with: text)
        doc.textDidChange(); doc.updateCounts(); _ = doc.saveNow()
    }

    func text(_ id: String) -> String { main.session.document(id)!.storage.string }

    func run() -> Int32 {
        print("The first launch and a new book")
        app.showWelcome()
        spin()
        check(app.welcome.window.isVisible && app.bookWindows.isEmpty, "with no book the Welcome window is shown")
        check(app.welcome.visibleBooks.isEmpty, "and it lists no recent books")

        if let code = start() { return code }
        if let code = aiFeatures() { return code }
        if let code = panels() { return code }
        if let code = editing() { return code }
        if let code = records() { return code }
        if let code = safety() { return code }
        if let code = recordMerges() { return code }
        if let code = research() { return code }
        if let code = reminders() { return code }
        if let code = history() { return code }
        if let code = newRecords() { return code }
        if let code = compareSearch() { return code }
        if let code = fonts() { return code }
        if let code = emptyLines() { return code }
        if let code = planColors() { return code }
        if let code = eventOrder() { return code }
        if let code = relationFilters() { return code }
        if let code = eventLinks() { return code }
        if let code = graphView() { return code }
        if let code = eventChanges() { return code }
        if let code = cardChanges() { return code }
        if let code = deleting() { return code }
        if let code = eventMigration() { return code }
        if let code = outlineMoves() { return code }
        if let code = graphMemory() { return code }
        if let code = placeMenus() { return code }
        if let code = aiStatusEvents() { return code }
        if let code = structure() { return code }
        if let code = files() { return code }
        if let code = settings() { return code }
        if let code = startup() { return code }

        // Whatever the application caught on its own while all this ran (an exception AppKit would print and forget) is a failure.
        check(QuillandApplication.caught.isEmpty, "no exception was thrown while the application handled events", "\(QuillandApplication.caught.prefix(5))")
        print("\n\(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }
}
