import AppKit
import QuillandCore

/// Warnings on the graph: an event that changes something but has no scene, and a relationship whose order is broken.
extension AppSelfTest {
    func graphWarnings() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard scenes.count >= 2 else { check(false, "two scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "ГрВ-Анна"), lev = try! main.characters.add(name: "ГрВ-Лев")
        let e1 = try! main.eventStore.add(title: "ГрВ: первое"), e2 = try! main.eventStore.add(title: "ГрВ: второе"), loose = try! main.eventStore.add(title: "ГрВ: без сцены")
        try! main.eventStore.update(e1) { $0.links = [scenes[0].id: ""]; $0.characters = [anna: "", lev: ""] }
        try! main.eventStore.update(e2) { $0.links = [scenes[1].id: ""]; $0.characters = [anna: ""] }
        try! main.eventStore.update(loose) { $0.characters = [anna: ""]; $0.setEffect(.profile, of: anna, text: "Где-то.") }
        let rid = try! main.relationships.add(characters: [anna, lev], kind: "ГрВ-соседи")
        try! main.eventStore.update(e2) { var m = $0.relationships; m[rid] = "starts"; $0.relationships = m }
        try! main.eventStore.update(e1) { var m = $0.relationships; m[rid] = "ends"; $0.relationships = m }
        main.reloadStores()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph shows"); return 1 }
        gv.setAsOf(nil); gv.setChangesOnly(false); gv.setPlotLine(nil); gv.setColourByLine(false); spin(0.3)
        check(gv.graph.node(loose)?.doesNotApply == true && gv.graph.node(e1)?.doesNotApply == false, "an event with changes and no scene is marked")
        let line = gv.graph.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([anna, lev]) }
        check(line?.problems == [.endsBeforeStart(eventTitle: "ГрВ: первое")], "a relationship that ends before it starts is marked", "\(String(describing: line?.problems))")
        let tips = gv.canvas.toolTips.map(\.text)
        check(tips.contains { $0.contains("ГрВ: без сцены") && $0.contains("so its changes do not apply") } && tips.contains { $0.contains("It ends (in “ГрВ: первое”) before it starts.") }, "their tooltips say what is wrong", "\(tips)")
        check(gv.noteText.contains("warning"), "the count of warnings is in the note", gv.noteText)

        for id in [e1, e2, loose] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        try? BookIntegrity.deleteRelationship(rid, book: main.folder, snapshot: false)
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
