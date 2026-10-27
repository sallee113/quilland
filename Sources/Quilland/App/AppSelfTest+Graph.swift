import AppKit
import QuillandCore

/// The Graph view (⌘6): what it shows, its filters, moving nodes, opening a card.
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
        try! main.eventStore.update(arrival) { $0.characters = [anna: "", lev: ""] }
        let rel = try! main.relationships.add(characters: [anna, lev], kind: "граф-сёстры")
        let mine: Set<String> = [anna, lev, lone, manor, nowhere, arrival]

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph view shows"); return 1 }
        check(main.mode == .graph && again.window.title.hasSuffix(" — Graph"), "View ▸ Graph shows the graph", again.window.title)
        check(mine.isSubset(of: Set(gv.shownIDs)) && !gv.shownIDs.contains(scenes[0]), "all the characters, places and events are shown, and not the scenes")
        check(gv.graph.edges.contains { $0.kind == .relationship && $0.label == "граф-сёстры" } && gv.graph.edges.contains { $0.kind == .heldAt && Set([$0.a, $0.b]) == Set([arrival, manor]) }, "with their links, a relationship carrying its kind")
        check(gv.graph.node(anna)?.isMain == false, "an ordinary character has no thick border")
        try! main.characters.update(anna) { $0.main = true }
        gv.reload(); spin(0.2)
        check(gv.graph.node(anna)?.isMain == true && gv.graph.node(lev)?.isMain == false && gv.graph.node(manor)?.isMain == false, "a main character is marked in the graph, and no other node")
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

/// The Graph view comes back as it was left: its settings, its zoom and the place it was looking at.
extension AppSelfTest {
    func graphMemory() -> Int32? {
        let main = self.main!
        let anna = try! main.characters.add(name: "Память-Анна"), lev = try! main.characters.add(name: "Память-Лев")
        let arrival = try! main.eventStore.add(title: "Память: приезд")
        let extra = (0..<30).map { try! main.characters.add(name: "Память-\($0)") }
        try! main.eventStore.update(arrival) { r in var l: [String: String] = [anna: "", lev: ""]; for c in extra { l[c] = "" }; r.characters = l }

        main.setMode(.graph); spin(0.6)
        guard let gv = main.graphView else { check(false, "the Graph view shows"); return 1 }
        gv.setLook(.neighbourhood); gv.focus(on: arrival); gv.setDepth(2); gv.setShowUnlinked(false); spin(0.8)
        gv.lookAt(GraphPoint(x: 40, y: -30), zoom: 1.5); spin(0.2)
        let seen = gv.viewCenter
        check(abs(gv.zoom - 1.5) < 0.01, "the zoom is set", "\(gv.zoom)")

        // Away and back: the same settings, the same zoom, the same place.
        main.setMode(.characters); spin(0.4)
        main.setMode(.graph); spin(0.8)
        guard let back = main.graphView else { check(false, "the Graph view shows again"); return 1 }
        check(back.state.look == .neighbourhood && back.state.focus == arrival && back.state.depth == 2 && !back.state.showUnlinked, "coming back, the settings are as they were")
        check(abs(back.zoom - 1.5) < 0.01 && abs(back.viewCenter.x - seen.x) < 4 && abs(back.viewCenter.y - seen.y) < 4, "and so are the zoom and the place in view", "\(back.zoom) \(back.viewCenter) \(seen)")

        // After a restart: the state read from the book's file gives the same.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("graph-memory-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        main.localState().save(book: tmp)
        let restored = GraphViewState(memory: LocalBookState.load(book: tmp).graph)
        try? FileManager.default.removeItem(at: tmp)
        check(restored.look == .neighbourhood && restored.focus == arrival && restored.depth == 2 && !restored.showUnlinked && restored.kinds == back.state.kinds, "the settings are kept in the book's local state")
        check(restored.zoom.map { abs($0 - 1.5) < 0.01 } == true && restored.center.map { abs($0.x - seen.x) < 4 && abs($0.y - seen.y) < 4 } == true, "with the zoom and the place in view", "\(String(describing: restored.zoom)) \(String(describing: restored.center))")

        // A setting that changes the picture fits it again.
        back.setLook(.whole); spin(0.2)
        check(back.state.zoom == nil && back.state.center == nil, "changing a setting forgets the old place")
        spin(1.2)
        check(back.state.zoom != nil, "and the new picture is noted once it is fitted")

        // What was remembered may be gone.
        back.setLook(.neighbourhood); back.focus(on: arrival); spin(0.5)
        try? main.eventStore.delete(arrival)
        main.eventStore.reload()
        back.reload(); spin(0.3)
        check(back.state.focus == nil, "a focus that was deleted is forgotten")

        for id in [anna, lev] + extra { try? main.characters.delete(id) }
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
