import AppKit
import QuillandCore

/// The arc of a character as a graph of its own: the look, what it is made of, where things are, the controls it switches off, opening a state.
extension AppSelfTest {
    func graphArc() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard scenes.count >= 2 else { check(false, "two scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "Дуга-Анна"), lev = try! main.characters.add(name: "Дуга-Лев"), vera = try! main.characters.add(name: "Дуга-Вера")
        try! main.characters.setProfile(anna, "Тихая девочка.")
        let world = main.worlds.worlds[0].id!
        let manor = try! main.worlds.addEntry(name: "Дуга-Усадьба", world: world)
        let e1 = try! main.eventStore.add(title: "Дуга: приезд"), e2 = try! main.eventStore.add(title: "Дуга: отъезд")
        try! main.eventStore.update(e1) { $0.links = [scenes[0].id: ""]; $0.characters = [anna: "", lev: ""]; $0.places = [manor: ""]; $0.setEffect(.profile, of: anna, text: "Теперь капитан."); $0.setEffectFlag(of: anna, true) }
        try! main.eventStore.update(e2) { $0.links = [scenes[1].id: ""]; $0.characters = [anna: ""] }
        let friends = try! main.relationships.add(characters: [anna, vera], kind: "Дуга-друзья"), sisters = try! main.relationships.add(characters: [anna, lev], kind: "Дуга-сёстры")
        let start = main.eventStore.startEvent!.id!
        try! main.eventStore.update(start) { $0.relationships = [friends: "starts", sisters: "starts"] }
        try! main.eventStore.update(e2) { var m = $0.relationships; m[friends] = "ends"; $0.relationships = m }
        main.reloadStores()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph shows"); return 1 }
        gv.setAsOf(nil); gv.setColourByLine(false); gv.setPlotLine(nil); gv.setChangesOnly(false); gv.setLook(.whole); spin(0.3)
        gv.setLook(.arc); spin(0.3)
        check(gv.graph.nodes.isEmpty && gv.emptyText == "Choose a character to follow", "the arc with no character chosen says so", "\(String(describing: gv.emptyText))")
        gv.showArc(of: anna); spin(0.4)
        let state1 = ArcBuilder.stateID(e1), state0 = ArcBuilder.stateID(nil)
        check(Set(gv.shownIDs) == [anna, e1, e2, state0, state1, lev, vera, manor], "the arc is a graph of its own: the character, their events, their states, those they are tied to, the places", "\(gv.graph.nodes.map(\.title))")
        func at(_ id: String) -> CGPoint { gv.canvas.center(of: id)! }
        check(at(anna).x < at(e1).x && at(e1).x < at(e2).x && at(anna).y < at(e1).y && at(e1).y < at(e2).y, "the spine runs from the top left to the bottom right")
        check(at(state1).y < at(e1).y && at(lev).y > at(anna).y && at(manor).y > at(e1).y, "states above, relationships and places below")
        check(gv.graph.node(state1)?.isMain == true && gv.graph.node(state0)?.isMain == false && gv.graph.node(state1)?.title.contains("Теперь капитан.") == true, "the states are the card's text, then what the event makes of it")
        check(gv.canvas.allowsDragging == false && gv.controlsEnabled.kinds == false && gv.controlsEnabled.reset == false, "nothing is moved in the arc, and the filters of the book's graph are off")
        check(gv.focusTitles.contains("Дуга-Анна") && gv.focusTitles.contains("Дуга-Лев") && !gv.focusTitles.contains("Дуга-Усадьба") && !gv.focusTitles.contains("Дуга: приезд"), "the popup lists characters only", "\(gv.focusTitles)")
        check(gv.canvas.toolTips.contains { $0.text.contains("Теперь капитан.") }, "a state's tooltip has its full text")
        check(GraphViewState(memory: gv.state.memory).look == .arc && GraphViewState(memory: gv.state.memory).focus == anna, "the look and the character are remembered")
        gv.onOpen?(.stage, state1); spin(0.4)
        check(main.mode == .events && main.eventsView?.selected == e1, "opening a state opens the event that makes it")
        main.setMode(.graph); spin(0.4)
        main.graphView?.setLook(.whole); spin(0.3)
        check(main.graphView?.canvas.allowsDragging == true && main.graphView?.controlsEnabled.kinds == true, "back to the whole book, everything is on again")

        for id in [e1, e2] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        for id in [friends, sisters] { try? BookIntegrity.deleteRelationship(id, book: main.folder, snapshot: false) }
        for id in [anna, lev, vera] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        try? BookIntegrity.deletePlace(manor, book: main.folder, snapshot: false)
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
