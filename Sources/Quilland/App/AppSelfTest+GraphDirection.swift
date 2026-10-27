import AppKit
import QuillandCore

/// The direction of the main line of the arc, the locations and the plan map: a setting on the second line of the bar, kept for the book, and a moved node is kept for the
/// direction it was moved in.
extension AppSelfTest {
    func graphDirection() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes
        guard scenes.count >= 2 else { check(false, "two scenes for the checks"); return 1 }
        let anna = try! main.characters.add(name: "Напр-Анна"), lev = try! main.characters.add(name: "Напр-Лев")
        let world = main.worlds.worlds[0].id!
        let hall = try! main.worlds.addEntry(name: "Напр-Зал", world: world), yard = try! main.worlds.addEntry(name: "Напр-Двор", world: world)
        let e1 = try! main.eventStore.add(title: "Напр: раз"), e2 = try! main.eventStore.add(title: "Напр: два")
        try! main.eventStore.update(e1) { $0.links = [scenes[0].id: ""]; $0.characters = [anna: "", lev: ""]; $0.places = [hall: "", yard: ""] }
        try! main.eventStore.update(e2) { $0.links = [scenes[1].id: ""]; $0.characters = [anna: ""]; $0.places = [hall: "", yard: ""] }
        let kin = try! main.relationships.add(characters: [anna, lev], kind: "Напр-родня")
        try! main.eventStore.update(main.eventStore.startEvent!.id!) { var m = $0.relationships; m[kin] = "starts"; $0.relationships = m }
        main.reloadStores()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph shows"); return 1 }
        gv.setAsOf(nil); gv.setColourByLine(false); gv.setPlotLine(nil); gv.setChangesOnly(false); gv.setLook(.whole); spin(0.3)
        gv.showArc(of: anna); spin(0.4)
        func at(_ id: String) -> CGPoint { gv.canvas.center(of: id)! }
        check(gv.direction == .diagonal && at(e1).x < at(e2).x && at(e1).y < at(e2).y, "the arc runs from the top left to the bottom right as it did, by default")
        check(gv.directionControlShown, "and the Main line setting is on the bar")
        gv.setDirection(.horizontal); spin(0.4)
        check(abs(at(e1).y - at(e2).y) < 1 && at(e1).x < at(e2).x, "left to right: the spine is level", "\(at(e1)) \(at(e2))")
        gv.setDirection(.vertical); spin(0.4)
        check(abs(at(e1).x - at(e2).x) < 1 && at(e1).y < at(e2).y, "top to bottom: the spine is upright", "\(at(e1)) \(at(e2))")
        check(GraphViewState(memory: gv.state.memory).direction == .vertical, "the direction is kept for the book")
        // A node moved in one direction is kept for that direction alone.
        let from = at(lev)
        gv.canvas.drag(lev, to: CGPoint(x: from.x + 50, y: from.y + 30)); spin(0.3)
        let keys = GraphStore(folder: main.folder).positions.keys.filter { $0.hasPrefix("arc|\(anna)") }
        check(keys.contains("arc|\(anna)@vertical#\(lev)") && !keys.contains("arc|\(anna)#\(lev)"), "a moved node is kept under the key of its direction", "\(keys)")
        gv.setDirection(.diagonal); spin(0.4)
        check(!gv.canvas.pinned.contains(lev), "in another direction it is not pinned")
        gv.setDirection(.vertical); spin(0.4)
        check(gv.canvas.pinned.contains(lev), "and back in that direction it is where it was put")
        gv.resetLayout(confirm: false); spin(0.4)

        // The other looks carry the setting, the place tree and the book's graph do not.
        gv.setLook(.locations); spin(0.4)
        check(gv.directionControlShown, "the locations have the setting")
        gv.setLook(.plan); spin(0.4)
        check(gv.directionControlShown, "and so has the plan map")
        gv.setLook(.places); spin(0.4)
        check(!gv.directionControlShown, "the place tree has none")
        gv.setLook(.whole); spin(0.4)
        check(!gv.directionControlShown, "and neither has the book's graph")
        gv.setDirection(.diagonal); spin(0.3)

        gv.setLook(.whole); spin(0.2)
        try? BookIntegrity.deleteRelationship(kin, book: main.folder, snapshot: false)
        for id in [e1, e2] { try? BookIntegrity.deleteEvent(id, book: main.folder, started: .deleteThem, snapshot: false) }
        for id in [hall, yard] { try? BookIntegrity.deletePlace(id, book: main.folder, snapshot: false) }
        for id in [anna, lev] { try? BookIntegrity.deleteCharacter(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
