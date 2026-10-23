import AppKit
import QuillandCore

/// The Graph coloured by the plot lines of the plan: colours, dots for what is on several lines, the legend, the plot line filter.
extension AppSelfTest {
    func graphLines() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard scenes.count >= 2 else { check(false, "two scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "ГрЛ-Анна"), lev = try! main.characters.add(name: "ГрЛ-Лев")
        let e1 = try! main.eventStore.add(title: "ГрЛ: первое"), e2 = try! main.eventStore.add(title: "ГрЛ: второе"), loose = try! main.eventStore.add(title: "ГрЛ: нигде")
        try! main.eventStore.update(e1) { $0.links = [scenes[0].id: ""]; $0.characters = [anna: "", lev: ""] }
        try! main.eventStore.update(e2) { $0.links = [scenes[1].id: ""]; $0.characters = [anna: ""] }
        try! main.eventStore.update(loose) { $0.characters = [lev: ""] }
        app.modePlan(); spin(0.5)
        guard let plan = main.planController else { check(false, "the Plan shows"); return 1 }
        let one = try! plan.store.addLine(name: "ГрЛ-Усадьба", color: "teal"), two = try! plan.store.addLine(name: "ГрЛ-Дорога", color: "amber")
        try! plan.store.placeEvent(e1, onLine: one, start: 100); try! plan.store.placeEvent(e2, onLine: two, start: 200)
        try! plan.store.reload()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph shows"); return 1 }
        gv.setAsOf(nil); gv.setChangesOnly(false); gv.setPlotLine(nil); gv.setColourByLine(false); spin(0.3)
        let canvas = gv.canvas
        func node(_ id: String) -> GraphNode { gv.graph.node(id)! }
        check(canvas.fill(of: node(e1)) == GraphCanvasView.color(.event) && canvas.dotLines(of: node(anna)).isEmpty, "coloured by kind, nothing changes")
        gv.setColourByLine(true); spin(0.3)
        check(canvas.fill(of: node(e1)) == PlanColors.color("teal") && canvas.fill(of: node(e2)) == PlanColors.color("amber"), "by plot line, an event has the colour of its line")
        check(canvas.fill(of: node(lev)) == PlanColors.color("teal") && canvas.dotLines(of: node(lev)).isEmpty, "a character on one line has its colour")
        check(canvas.dotLines(of: node(anna)) == [one, two] && canvas.fill(of: node(anna)) == GraphCanvasView.color(.character), "one on two lines keeps its own colour and gets a dot for each line")
        check(canvas.fill(of: node(loose)) == NSColor.systemGray, "an event on no line is grey")
        check(gv.legendTitles.contains("ГрЛ-Усадьба") && gv.legendTitles.contains("ГрЛ-Дорога") && gv.legendTitles.contains("not on a plot line"), "the legend names the lines and the grey", "\(gv.legendTitles)")
        check(canvas.toolTips.contains { $0.text.contains("Plot lines: ГрЛ-Усадьба, ГрЛ-Дорога") }, "the tooltip of a node on several lines lists them")
        check(GraphViewState(memory: gv.state.memory).colourByLine, "the choice is remembered")

        gv.setPlotLine(one); spin(0.3)
        check(Set(gv.shownIDs).isSuperset(of: [e1, anna, lev]) && !gv.shownIDs.contains(e2) && !gv.shownIDs.contains(loose), "one plot line: its events and who is in them, nothing of the other line", "\(gv.shownIDs.count)")
        check(GraphViewState(memory: gv.state.memory).plotLine == one, "and it is remembered")
        gv.setPlotLine(two); spin(0.3)
        check(gv.shownIDs.contains(e2) && !gv.shownIDs.contains(e1), "the other line shows its event")
        gv.setPlotLine(nil); gv.setColourByLine(false); spin(0.3)
        check(gv.shownIDs.contains(e1) && gv.shownIDs.contains(e2), "and the whole book again")

        app.modePlan(); spin(0.3)
        for l in [one, two] { try? main.planController?.store.deleteLine(l, floatingAt: [:]) }
        for id in [e1, e2, loose] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
