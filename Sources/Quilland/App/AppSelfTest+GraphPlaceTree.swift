import AppKit
import QuillandCore

/// The place tree: the worlds and the places inside them as a graph of its own, from the left to the right.
extension AppSelfTest {
    func graphPlaceTree() -> Int32? {
        let main = self.main!
        let world = try! main.worlds.addWorld(name: "Дер-Земля")
        let country = try! main.worlds.addEntry(name: "Дер-Страна", world: world)
        let city = try! main.worlds.addEntry(name: "Дер-Город", world: world, parent: country), village = try! main.worlds.addEntry(name: "Дер-Деревня", world: world, parent: country)
        let house = try! main.worlds.addEntry(name: "Дер-Дом", world: world, parent: city)
        let other = try! main.worlds.addWorld(name: "Дер-Флора"), capital = try! main.worlds.addEntry(name: "Дер-Столица", world: other)
        main.reloadStores()

        main.setMode(.graph); spin(0.5)
        guard let gv = main.graphView else { check(false, "the Graph shows"); return 1 }
        gv.setAsOf(nil); gv.setColourByLine(false); gv.setPlotLine(nil); gv.setChangesOnly(false); gv.setLook(.whole); spin(0.3)
        gv.setLook(.places); spin(0.4)
        let mine: Set<String> = [world, country, city, village, house, other, capital]
        check(mine.isSubset(of: Set(gv.shownIDs)) && !gv.shownIDs.contains(where: { main.characters.character($0) != nil }), "the place tree is worlds and places, and no one else", "\(gv.shownIDs.count)")
        func at(_ id: String) -> CGPoint { gv.canvas.center(of: id)! }
        check(at(world).x < at(country).x && at(country).x < at(city).x && at(city).x < at(house).x && at(city).x == at(village).x, "it runs from the left to the right, a column for each depth")
        check(gv.graph.edges.contains { $0.kind == .contains && $0.a == country && $0.b == city } && gv.graph.edges.contains { $0.kind == .contains && $0.a == world && $0.b == country }, "each place is joined to what it is inside, the first to its world")
        check(gv.canvas.allowsDragging == false && gv.controlsEnabled.kinds == false, "nothing is moved, and the book graph's filters are off")
        check(gv.focusTitles.contains("Дер-Земля") && gv.focusTitles.contains("Дер-Флора") && !gv.focusTitles.contains("Дер-Страна") && !gv.focusTitles.contains("Анечка"), "the popup lists the worlds", "\(gv.focusTitles)")
        gv.setFocusForTest(other); spin(0.4)
        check(Set(gv.shownIDs) == [other, capital], "choosing a world shows its tree alone", "\(gv.shownIDs.count)")
        check(GraphViewState(memory: gv.state.memory).look == .places, "the look is remembered")
        gv.onOpen?(.world, world); spin(0.4)
        check(main.mode == .world && main.worldView?.selected == world, "a world opens in the World view", "\(main.mode)")
        main.setMode(.graph); spin(0.4)
        main.graphView?.setFocusForTest(nil); main.graphView?.setLook(.whole); spin(0.3)
        check(main.graphView?.canvas.allowsDragging == true && main.graphView?.shownIDs.contains(world) == false, "back to the whole book")

        for id in [house, village, city, country, capital] { try? BookIntegrity.deletePlace(id, book: main.folder, snapshot: false) }
        for id in [world, other] { try? BookIntegrity.deleteWorld(id, book: main.folder, snapshot: false) }
        main.reloadStores(); main.setMode(main.writingMode); spin(0.4)
        return nil
    }
}
