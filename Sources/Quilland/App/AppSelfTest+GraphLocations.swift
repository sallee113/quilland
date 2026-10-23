import AppKit
import QuillandCore

/// The locations along the book: the scenes that places are linked to, each a bush of its places and their characters.
extension AppSelfTest {
    func graphLocations() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard scenes.count >= 2 else { check(false, "two scenes for the checks"); return 1 }
        let s0 = scenes[0].id, s1 = scenes[1].id
        let anna = try! main.characters.add(name: "Лок-Анна"), lev = try! main.characters.add(name: "Лок-Лев")
        let world = main.worlds.worlds[0].id!
        let manor = try! main.worlds.addEntry(name: "Лок-Усадьба", world: world), port = try! main.worlds.addEntry(name: "Лок-Порт", world: world)
        let e1 = try! main.eventStore.add(title: "Лок: приезд"), e2 = try! main.eventStore.add(title: "Лок: отъезд")
        try! main.eventStore.update(e1) { $0.links = [s0: ""]; $0.characters = [anna: "", lev: ""]; $0.places = [manor: "", port: ""] }
        try! main.eventStore.update(e2) { $0.links = [s1: ""]; $0.characters = [anna: ""]; $0.places = [port: ""] }
        main.reloadStores()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph shows"); return 1 }
        gv.setAsOf(nil); gv.setChangesOnly(false); gv.setPlotLine(nil); gv.setColourByLine(false); gv.setLook(.whole); spin(0.3)
        gv.setFocusForTest(nil); gv.setLook(.locations); spin(0.4)
        let bush0 = "bush:\(s0)|\(manor)", bush1 = "bush:\(s0)|\(port)", stay = "bush:\(s1)|\(port)"
        check(gv.shownIDs.contains(s0) && gv.shownIDs.contains(bush0) && gv.shownIDs.contains(bush1) && gv.shownIDs.contains(stay), "a scene with two places is a node with both places hanging from it; one with a single place is that place", "\(gv.shownIDs.count)")
        check(gv.graph.nodes.filter { $0.ref == port }.count == 2 && gv.graph.nodes.filter { $0.ref == anna }.count == 3, "nothing is shared between scenes: the same place or person is a new node in each bush")
        func at(_ id: String) -> CGPoint { gv.canvas.center(of: id)! }
        check(at(s0).x < at(stay).x && at(s0).y < at(stay).y && at(bush0).y > at(s0).y, "the scenes run from the top left to the bottom right, the places hang below")
        check(gv.canvas.allowsDragging == false && gv.controlsEnabled.kinds == false, "nothing is moved, and the book graph's filters are off")
        // A place inside another: the parent place (not the world) is a node in the chain above it.
        let planet = try! main.worlds.addEntry(name: "Лок-Планета", world: world)
        try! main.worlds.updateEntry(manor) { $0.parent = planet }
        main.reloadStores(); gv.setFocusForTest(nil); spin(0.4)
        let chain = "bush:\(s0)|\(planet)"
        check(gv.shownIDs.contains(chain) && gv.graph.edges.contains { $0.kind == .contains && $0.a == chain && $0.b == bush0 } && gv.graph.node(chain)?.isContext == true, "the parent place is a node in the chain: scene → parent → place → characters")
        check(!gv.graph.nodes.contains { $0.title == main.worlds.worlds[0].name && $0.kind != .character }, "and the world is not")
        gv.setFocusForTest(lev); spin(0.4)
        check(gv.graph.nodes.filter { $0.kind == .character }.allSatisfy { $0.ref == lev } && !gv.shownIDs.contains(stay), "one character: only the scenes where they are at a place, and only they")
        gv.setFocusForTest(nil); spin(0.3)
        gv.onOpen?(.scene, s0); spin(0.3)
        check(GraphViewState(memory: gv.state.memory).look == .locations, "the look is remembered")
        main.setMode(.graph); spin(0.3)
        main.graphView?.setFocusForTest(nil); main.graphView?.setLook(.whole); spin(0.3)
        check(main.graphView?.canvas.allowsDragging == true, "back to the whole book")

        for id in [e1, e2] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        for id in [manor, port, planet] { try? BookIntegrity.deletePlace(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
