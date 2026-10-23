import AppKit
import QuillandCore

/// What events change, on the graph: the Δ on events and lines, ended relationships dashed, the two switches.
extension AppSelfTest {
    func graphChanges() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes.map(\.id)
        guard scenes.count >= 2 else { check(false, "two scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "ГрИзм-Анна"), lev = try! main.characters.add(name: "ГрИзм-Лев"), lone = try! main.characters.add(name: "ГрИзм-Одинокий")
        let e1 = try! main.eventStore.add(title: "ГрИзм: первое"), e2 = try! main.eventStore.add(title: "ГрИзм: второе"), quiet = try! main.eventStore.add(title: "ГрИзм: тихое")
        try! main.eventStore.update(e1) { $0.links = [scenes[0]: ""]; $0.characters = [anna: "", lev: ""]; $0.setEffect(.profile, of: anna, text: "Стала старше.") }
        try! main.eventStore.update(e2) { $0.links = [scenes[1]: ""]; $0.characters = [anna: ""] }
        try! main.eventStore.update(quiet) { $0.links = [scenes[1]: ""]; $0.characters = [lev: ""] }
        let rid = try! main.relationships.add(characters: [anna, lev], kind: "ГрИзм-друзья")
        let start = main.eventStore.startEvent!.id!
        try! main.eventStore.update(start) { $0.relationships = [rid: "starts"] }
        try! main.eventStore.update(e2) { $0.relationships = [rid: "ends"] }
        main.reloadStores()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph view shows"); return 1 }
        gv.setShowEnded(true); gv.setChangesOnly(false); spin(0.3)
        let tips = gv.canvas.toolTips.map(\.text)
        check(gv.graph.node(e1)?.changes.isEmpty == false && gv.graph.node(quiet)?.changes.isEmpty == true, "an event that changes something is marked, and one that does not is not")
        check(tips.contains { $0.contains("ГрИзм: первое") && $0.contains("ГрИзм-Анна: profile") } && tips.contains { $0 == "ГрИзм-Анна: profile" }, "a tooltip on the event and one on the line say what changes", "\(tips)")
        check(gv.canvas.responds(to: #selector(NSViewToolTipOwner.view(_:stringForToolTip:point:userData:))), "the canvas answers AppKit as the owner of its tooltips (or the tooltip would show the owner's name)")
        check(!gv.shownIDs.contains(start), "Book starts is not drawn")
        let line = gv.graph.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([anna, lev]) }
        check(line?.ended == true && tips.contains { $0.contains("to “ГрИзм: второе”") }, "a relationship that has ended is dashed, and its tooltip says where it ended", "\(tips)")

        let ids = [anna, lev, e1, e2]; let pts = ids.compactMap { gv.canvas.center(of: $0) }
        gv.setShowEnded(false); spin(0.3)
        check(!gv.graph.edges.contains { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([anna, lev]) }, "Show ended relationships off: it is not drawn")
        gv.setShowEnded(true)
        gv.setChangesOnly(true); spin(0.3)
        check(Set(gv.shownIDs) == [e1, e2, anna, lev] && !gv.shownIDs.contains(quiet) && !gv.shownIDs.contains(lone), "Changes only: the events that change something and what they change", "\(gv.graph.nodes.map(\.title))")
        check(GraphViewState(memory: gv.state.memory).changesOnly && GraphViewState(memory: gv.state.memory).showEnded, "both switches are remembered")
        gv.setChangesOnly(false); spin(0.3)
        check(gv.shownIDs.contains(quiet) && gv.shownIDs.contains(lone), "and off again, everything is back")

        // The Plan: a Δ and a tooltip on an event that changes something; Book starts is not there.
        app.modePlan(); spin(0.5)
        if let plan = main.planController {
            let line = plan.store.lines.first?.id ?? (try! plan.store.addLine(name: "Линия"))
            try! plan.store.placeEvent(e1, onLine: line, start: 100); try! plan.store.placeEvent(quiet, onLine: line, start: 200)
            try! plan.store.reload(); plan.reload(); spin(0.3)
            let items = plan.canvas.itemViews
            let changing = items.first { $0.item.id == e1 }, still = items.first { $0.item.id == quiet }
            check(changing?.item.changes.contains("ГрИзм-Анна: profile") == true && changing?.toolTip?.contains("ГрИзм-Анна: profile") == true, "an event that changes something has the Δ and says what in a tooltip", changing?.item.changes ?? "nil")
            check(still != nil && still?.item.changes.isEmpty == true && still?.toolTip == nil, "an event that changes nothing has neither")
            check(plan.store.events[start] == nil, "Book starts is not an event of the plan")
            try? plan.store.removeEntry(forEvent: e1); try? plan.store.removeEntry(forEvent: quiet)
        } else { check(false, "the Plan shows") }

        for id in [e1, e2, quiet] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        try? BookIntegrity.deleteRelationship(rid, book: main.folder, snapshot: false)
        for id in [anna, lev, lone] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
