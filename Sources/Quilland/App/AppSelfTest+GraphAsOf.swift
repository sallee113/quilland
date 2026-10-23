import AppKit
import QuillandCore

/// The Graph as of a scene: the slider and its buttons, what is flagged, the nodes staying where they are, the point being remembered.
extension AppSelfTest {
    func graphAsOf() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard scenes.count >= 2 else { check(false, "two scenes for the checks"); return 1 }
        let s0 = scenes[0].id, s1 = scenes[1].id
        let anna = try! main.characters.add(name: "ГрТ-Анна"), lev = try! main.characters.add(name: "ГрТ-Лев"), vera = try! main.characters.add(name: "ГрТ-Вера")
        let e1 = try! main.eventStore.add(title: "ГрТ: первое"), e2 = try! main.eventStore.add(title: "ГрТ: второе")
        try! main.eventStore.update(e1) { $0.links = [s0: ""]; $0.characters = [anna: "", lev: ""]; $0.setEffectFlag(of: anna, true) }
        try! main.eventStore.update(e2) { $0.links = [s1: ""]; $0.characters = [vera: ""] }
        let friends = try! main.relationships.add(characters: [anna, vera], kind: "ГрТ-друзья")
        let start = main.eventStore.startEvent!.id!
        try! main.eventStore.update(start) { $0.relationships = [friends: "starts"] }
        try! main.eventStore.update(e2) { var m = $0.relationships; m[friends] = "ends"; $0.relationships = m }
        main.reloadStores()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph shows"); return 1 }
        gv.setAsOf(nil); gv.setShowEnded(true); gv.setChangesOnly(false); spin(0.3)
        check(gv.asOfText == "Whole book" && gv.asOfControls == (false, true), "with no point, the label says the whole book and ◀ is off", "\(gv.asOfText) \(gv.asOfControls)")
        let before = [anna, lev, vera, e1, e2].compactMap { gv.canvas.center(of: $0) }
        gv.stepAsOf(1); spin(0.3)
        check(gv.state.asOf == s0 && gv.asOfText.hasPrefix("after “") && gv.asOfControls.back, "▶ goes to the first scene", "\(gv.asOfText)")
        check(gv.graph.node(e2)?.notYet == true && gv.graph.node(vera)?.notYet == true && gv.graph.node(anna)?.isMain == true && gv.graph.node(e1)?.notYet == false, "an event and a character that come later are flagged, and Анна is a main character by then")
        check([anna, lev, vera, e1, e2].compactMap { gv.canvas.center(of: $0) } == before, "the nodes stay exactly where they were")
        let line = gv.graph.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([anna, vera]) }
        check(line?.ended == false && line?.hidden == false, "friends have not ended yet")
        gv.stepAsOf(1); spin(0.3)
        let later = gv.graph.edges.first { $0.kind == .relationship && Set([$0.a, $0.b]) == Set([anna, vera]) }
        check(gv.state.asOf == s1 && later?.ended == true && gv.graph.node(e2)?.notYet == false, "after the second scene they have ended, and the event has come")
        check(GraphViewState(memory: gv.state.memory).asOf == s1, "the point is remembered with the other settings")
        gv.stepAsOf(-1); spin(0.3)
        check(gv.state.asOf == s0, "◀ goes back")
        gv.setAsOf(nil); spin(0.3)
        check(gv.state.asOf == nil && gv.asOfText == "Whole book" && gv.graph.nodes.allSatisfy { !$0.notYet }, "and the whole book again")

        for id in [e1, e2] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        try? BookIntegrity.deleteRelationship(friends, book: main.folder, snapshot: false)
        for id in [anna, lev, vera] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
