import AppKit
import QuillandCore

/// Back and Forward between views, as in a browser: every change of the view is remembered with the card that was chosen in it (the character, place, event,
/// document or section) or, in the writing views, the scene and the cursor; View ▸ Back (⌘[) and Forward (⌘]) go along that history.
extension MainAreaController {
    /// A view and where the author was in it.
    struct ViewPlace: Equatable {
        var mode: Mode
        var card: String?
        var scene: String?
        var position: Int
    }

    private static let historyLimit = 50

    /// Where the author is now.
    func currentPlace() -> ViewPlace {
        var scene: String?
        var position = 0
        if let c = controllers.first(where: { $0.currentSceneID != nil }), let id = c.currentSceneID, let tv = c.currentSheet?.textView {
            scene = id
            position = tv.selectedRange().location
        }
        let card: String?
        switch mode {
        case .characters: card = charactersView?.selected
        case .world: card = worldView?.selected
        case .events: card = eventsView?.selected
        case .research: card = researchView?.selected
        case .outline: card = tree?.selectedIDs.first
        case .panels, .book, .compare, .plan, .reminders: card = nil
        }
        return ViewPlace(mode: mode, card: card, scene: scene, position: position)
    }

    /// The view is about to change by the author's doing: where they are is put on the way back, and the way forward is dropped.
    func recordViewChange() {
        guard !isNavigatingHistory else { return }
        let here = currentPlace()
        if backPlaces.last != here { backPlaces.append(here) }
        if backPlaces.count > Self.historyLimit { backPlaces.removeFirst(backPlaces.count - Self.historyLimit) }
        forwardPlaces = []
    }

    var canGoBack: Bool { !backPlaces.isEmpty }
    var canGoForward: Bool { !forwardPlaces.isEmpty }

    func goBack() {
        guard let target = backPlaces.popLast() else { return }
        forwardPlaces.append(currentPlace())
        go(to: target)
    }

    func goForward() {
        guard let target = forwardPlaces.popLast() else { return }
        backPlaces.append(currentPlace())
        go(to: target)
    }

    /// For the checks: the history starts again.
    func clearHistory() { backPlaces = []; forwardPlaces = [] }

    private func go(to place: ViewPlace) {
        isNavigatingHistory = true
        defer { isNavigatingHistory = false }
        if place.mode == .outline, let card = place.card { pendingTreeSelection = card }
        if place.mode != mode { setMode(place.mode) }
        switch place.mode {
        case .characters: if let card = place.card, characters.character(card) != nil { charactersView?.select(card) }
        case .world: if let card = place.card, worlds.world(card) != nil || worlds.entry(card) != nil { worldView?.select(card) }
        case .events: if let card = place.card, eventStore.event(card) != nil { eventsView?.select(card) }
        case .research: if let card = place.card, researchStore.document(card) != nil { researchView?.select(card) }
        case .outline: if let card = place.card { tree?.select(card) }
        case .panels, .book, .compare:
            if let scene = place.scene, session.document(scene) != nil { reveal(scene: scene, range: NSRange(location: place.position, length: 0)) }
        case .plan, .reminders: break
        }
    }
}
