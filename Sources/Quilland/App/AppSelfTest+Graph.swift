import AppKit
import QuillandCore

/// The Graph view (⌘3): what it shows, its filters, moving nodes, opening a card.
extension AppSelfTest {
    func graphView() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes.map(\.id)
        guard scenes.count >= 2 else { check(false, "the book has two scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "Граф-Анна"), lev = try! main.characters.add(name: "Граф-Лев"), lone = try! main.characters.add(name: "Граф-Одинокий")
        let world = main.worlds.worlds[0].id!
        let manor = try! main.worlds.addEntry(name: "Граф-Усадьба", world: world), nowhere = try! main.worlds.addEntry(name: "Граф-Нигдевия", world: world)
        let arrival = try! main.eventStore.add(title: "Граф: приезд")
        try! main.eventStore.update(arrival) { $0.links = [scenes[0]: ""]; $0.places = [manor: ""] }
        try! main.characters.update(anna) { $0.links = [arrival: ""] }
        try! main.characters.update(lev) { $0.links = [arrival: ""] }
        let rel = try! main.relationships.add(characters: [anna, lev], kind: "граф-сёстры")
        let mine: Set<String> = [anna, lev, lone, manor, nowhere, arrival]

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph view shows"); return 1 }
        check(main.mode == .graph && again.window.title.hasSuffix(" — Graph"), "View ▸ Graph shows the graph", again.window.title)
        check(mine.isSubset(of: Set(gv.shownIDs)) && !gv.shownIDs.contains(scenes[0]), "all the characters, places and events are shown, and not the scenes")
        check(gv.graph.edges.contains { $0.kind == .relationship && $0.label == "граф-сёстры" } && gv.graph.edges.contains { $0.kind == .heldAt && Set([$0.a, $0.b]) == Set([arrival, manor]) }, "with their links, a relationship carrying its kind")
        check(gv.noteText.contains("nodes") && gv.noteText.contains("links"), "and the count of nodes and links is told", gv.noteText)
        check(gv.canvas.center(of: anna) != nil && gv.canvas.node(at: gv.canvas.center(of: anna)!)?.id == anna, "a node is found where it is drawn")

        // Looks and filters.
        gv.setLook(.social); spin(0.3)
        check(gv.graph.nodes.allSatisfy { $0.kind == .character } && gv.shownIDs.contains(anna) && gv.controlsEnabled.kinds == false && gv.controlsEnabled.focus == false, "the social graph is the characters, and the kind switches are off")
        gv.setShowUnlinked(false); spin(0.3)
        check(!gv.shownIDs.contains(lone) && gv.shownIDs.contains(anna), "unlinked characters can be hidden")
        gv.setShowUnlinked(true)
        gv.setLook(.neighbourhood); spin(0.3)
        check(gv.shownIDs.isEmpty && gv.emptyText == "Choose a thing to look at" && gv.controlsEnabled.focus && gv.controlsEnabled.depth, "a neighbourhood with nothing chosen says so")
        gv.focus(on: manor); spin(0.3)
        check(Set(gv.shownIDs) == [manor, arrival], "a neighbourhood: the place and its event", "\(gv.shownIDs.count)")
        gv.setDepth(2); spin(0.3)
        check(Set(gv.shownIDs) == [manor, arrival, anna, lev], "two steps out: the characters of the event too")
        gv.setLook(.whole); gv.setDepth(1); spin(0.3)
        gv.setKind(.scene, true); spin(0.3)
        check(gv.shownIDs.contains(scenes[0]) && gv.graph.edges.contains { $0.kind == .inScene && Set([$0.a, $0.b]) == Set([arrival, scenes[0]]) }, "the scenes can be switched on")
        gv.setKind(.scene, false)
        gv.setSection(scenes[0]); spin(0.3)
        check(gv.shownIDs.contains(arrival) && !gv.shownIDs.contains(nowhere), "a section limits what is shown", "\(gv.shownIDs.count)")
        gv.setSection(nil); spin(0.3)

        // Moving nodes.
        check(!gv.controlsEnabled.reset, "Reset Layout is off while nothing was moved")
        let a0 = gv.canvas.center(of: anna)!, l0 = gv.canvas.center(of: lev)!
        gv.canvas.drag(anna, to: CGPoint(x: a0.x + 180, y: a0.y + 140)); spin(0.2)
        gv.canvas.drag(lev, to: CGPoint(x: a0.x + 180, y: a0.y + 260)); spin(0.2)
        check(GraphStore(folder: main.folder).positions[anna] != nil && GraphStore(folder: main.folder).positions[lev] != nil, "a node that was moved is kept in the book")
        check(gv.canvas.pinned == [anna, lev] && gv.controlsEnabled.reset, "it is marked, and Reset Layout is on")
        let moved = gv.canvas.center(of: lev)! - gv.canvas.center(of: anna)!
        main.setMode(.characters); spin(0.3)
        main.setMode(.graph); spin(0.5)
        let gv2 = main.graphView!
        let after = gv2.canvas.center(of: lev)! - gv2.canvas.center(of: anna)!
        check(abs(after.dx - moved.dx) < 2 && abs(after.dy - moved.dy) < 2, "the places stay when the view is made again", "\(moved) \(after)")
        check(gv2.state.kinds == [.character, .place, .event], "and so do the settings")
        let node = gv2.canvas.graph.node(anna)!
        let items = gv2.canvas.menuProvider?(node)?.items.map(\.title) ?? []
        check(items.contains("Open") && items.contains("Focus on This") && items.contains("Release Position"), "a node's menu offers Open, Focus on This and Release Position", "\(items)")
        gv2.release(anna); spin(0.2)
        check(GraphStore(folder: main.folder).positions[anna] == nil && gv2.canvas.pinned == [lev], "Release Position frees one node")
        gv2.resetLayout(confirm: false); spin(0.2)
        check(GraphStore(folder: main.folder).positions.isEmpty && !gv2.controlsEnabled.reset, "Reset Layout frees all of them")

        // Opening.
        gv2.canvas.onOpen?(gv2.canvas.graph.node(anna)!); spin(0.4)
        check(main.mode == .characters && main.charactersView?.selected == anna, "opening a character shows its card")
        main.setMode(.graph); spin(0.4)
        main.graphView?.canvas.onOpen?(main.graphView!.canvas.graph.node(manor)!); spin(0.4)
        check(main.mode == .world && main.worldView?.selected == manor, "and a place its card")
        main.setMode(.graph); spin(0.4)
        main.graphView?.canvas.onOpen?(main.graphView!.canvas.graph.node(arrival)!); spin(0.4)
        check(main.mode == .events && main.eventsView?.selected == arrival, "and an event its card")
        main.setMode(.graph); spin(0.3)
        main.leaveFullAreaView(); spin(0.3)
        check(main.mode == main.writingMode, "Esc leaves the graph")

        for id in [anna, lev, lone] { try? main.characters.delete(id) }
        try? main.eventStore.delete(arrival)
        for id in [manor, nowhere] { try? main.worlds.deleteEntry(id) }
        try? main.relationships.delete(rel)
        main.setMode(main.writingMode); spin(0.3)
        _ = mine
        return nil
    }
}

private func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
