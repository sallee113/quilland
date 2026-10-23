import AppKit
import QuillandCore

/// A plan card realised by events: the menu, the line on the card and on the event, the Events view, and the cards on the graph.
extension AppSelfTest {
    func planRealised() -> Int32? {
        let main = self.main!
        let e1 = try! main.eventStore.add(title: "Реал: первое"), e2 = try! main.eventStore.add(title: "Реал: второе")
        app.modePlan(); spin(0.5)
        guard let plan = main.planController else { check(false, "the Plan shows"); return 1 }
        let line = plan.store.lines.first?.id ?? (try! plan.store.addLine(name: "Линия"))
        let card = try! plan.store.addCard(title: "Реал-идея", text: "Что-то случится.", line: line, start: 100, color: "teal")
        let idle = try! plan.store.addCard(title: "Реал-неписаная", line: line, start: 300)
        try! plan.store.placeEvent(e1, onLine: line, start: 100)
        try! plan.store.reload(); plan.reload(); spin(0.3)

        func menuTitles() -> [(String, Bool)] { (plan.realisedMenuItem(for: card).submenu?.items ?? []).map { ($0.title, $0.state == .on) } }
        check(menuTitles().contains { $0.0 == "Реал: первое" && !$0.1 } && menuTitles().contains { $0.0 == "Реал: второе" && !$0.1 }, "the card's menu lists the book's events, none ticked", "\(menuTitles())")
        plan.setRealised(card: card, by: e1, true); plan.setRealised(card: card, by: e2, true); spin(0.2)
        check(Set(plan.store.realisedBy(card)) == [e1, e2] && menuTitles().filter(\.1).count >= 2, "a card can be realised by several events, and the menu ticks them", "\(menuTitles())")
        check(PlanStore(folderOrNil: main.folder)?.realisedBy(card).count == 2, "the link is kept in the card's file")
        let cardView = plan.canvas.itemViews.first { $0.item.id == card }, eventView = plan.canvas.itemViews.first { $0.item.id == e1 }
        check(Set(cardView?.item.realised ?? []) == ["Реал: первое", "Реал: второе"] && cardView?.toolTip?.contains("Реал: второе") == true, "the card says by which events it was realised", "\(String(describing: cardView?.item.realised))")
        check(eventView?.item.plannedBy == ["Реал-идея"] && eventView?.toolTip?.contains("Реал-идея") == true, "and the event says which card planned it")
        if let cv = cardView, let menu = plan.menu(at: cv.frame.origin, over: cv) { check(menu.items.contains { $0.title == "Realised by" && $0.submenu != nil }, "the right-click menu of a card has Realised by") } else { check(false, "the card has a menu") }
        plan.setRealised(card: card, by: e2, false); spin(0.2)
        check(plan.store.realisedBy(card) == [e1], "unticking takes a link away")
        plan.undo(); spin(0.3)
        check(Set(plan.store.realisedBy(card)) == [e1, e2], "and Undo puts it back")

        main.setMode(.events); spin(0.4)
        if let ev = main.eventsView { ev.select(e1); spin(0.3); check(ev.planText.contains("Planned by: Реал-идея"), "the Events view says which card planned the event", ev.planText) }

        main.setMode(.graph); spin(0.5)
        if let gv = main.graphView {
            gv.setAsOf(nil); gv.setChangesOnly(false); gv.setColourByLine(false); gv.setPlotLine(nil); gv.setLook(.plan); spin(0.4)
            check(gv.shownIDs.contains(card) && gv.shownIDs.contains(idle) && gv.shownIDs.contains(e1), "the plan map shows the cards and the events on the plan")
            check(gv.graph.edges.contains { $0.kind == .realises && Set([$0.a, $0.b]) == Set([card, e1]) }, "a card is joined to the events that realised it")
            check(gv.graph.node(idle)?.hollow == true && gv.graph.node(card)?.hollow == false, "a card nobody has realised is hollow, a realised one is not")
            check(gv.canvas.allowsDragging == false && gv.controlsEnabled.kinds == false && !gv.shownIDs.contains(where: { main.characters.character($0) != nil }), "nothing is moved, the book graph's filters are off, and no characters are in it")
            check(GraphViewState(memory: gv.state.memory).look == .plan, "the look is remembered")
            gv.onOpen?(.card, card); spin(0.5)
            check(main.mode == .plan && main.planController?.selectedID == card, "opening a card goes to the Plan and chooses it", "\(main.mode) \(String(describing: main.planController?.selectedID))")
            main.setMode(.graph); spin(0.3)
            main.graphView?.setLook(.whole); spin(0.3)
            check(main.graphView?.shownIDs.contains(card) == false, "the book's graph has no cards")
        } else { check(false, "the Graph shows") }

        // Clean up.
        app.modePlan(); spin(0.3)
        for id in [card, idle] { try? main.planController?.store.deleteCard(id) }
        try? main.planController?.store.removeEntry(forEvent: e1)
        for id in [e1, e2] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}

private extension PlanStore {
    convenience init?(folderOrNil folder: URL) { try? self.init(folder: folder) }
}
