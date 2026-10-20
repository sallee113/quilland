import AppKit
import QuillandCore

/// The Events list: grouped by scene, events of one scene put in order by hand, and the "By hand" order across scenes.
extension AppSelfTest {
    func eventOrder() -> Int32? {
        let main = self.main!
        let scenes = main.session.structure.scenes.map(\.id)
        let sceneTitle = { (id: String) in main.session.structure.sceneChoices.first { $0.id == id }!.title }
        let first = try! main.eventStore.add(title: "Альфа"), second = try! main.eventStore.add(title: "Бета"), third = try! main.eventStore.add(title: "Гамма"), alone = try! main.eventStore.add(title: "Дельта")
        try! main.eventStore.update(first) { $0.links = [scenes[0]: ""] }
        try! main.eventStore.update(second) { $0.links = [scenes[0]: ""] }
        try! main.eventStore.update(third) { $0.links = [scenes[1]: ""] }
        app.modeEvents(); spin(0.5)
        guard let ev = main.eventsView else { check(false, "the Events view shows"); return 1 }
        ev.reload()
        let mine = ["Альфа", "Бета", "Гамма", "Дельта"]
        let titles = ev.listTitles
        func mineOnly(_ list: [String]) -> [String] { list.filter { mine.contains($0) || $0.hasPrefix("— ") } }
        check(titles.contains("— " + sceneTitle(scenes[0])) && titles.contains("— " + sceneTitle(scenes[1])) && titles.contains("— not in a scene yet"), "the list has a heading for each scene, and one for the events of no scene", "\(titles)")
        func order(_ a: String, _ b: String) -> Bool { (titles.firstIndex(of: a) ?? 0) < (titles.firstIndex(of: b) ?? 0) }
        check(order("— " + sceneTitle(scenes[0]), "Альфа") && order("Альфа", "Бета") && order("Бета", "— " + sceneTitle(scenes[1])) && order("Гамма", "Дельта"), "each scene's events are under its heading, in the order of the book", "\(mineOnly(titles))")

        // Two events of one scene: the second goes first.
        ev.select(second)
        ev.move(by: -1); spin(0.2)
        var now = ev.listTitles
        check((now.firstIndex(of: "Бета") ?? 99) < (now.firstIndex(of: "Альфа") ?? 0), "Move Up puts an event of the scene before the one above it", "\(mineOnly(now))")
        check(ev.selected == second, "and it stays chosen")
        check(EventStore(book: main.folder).ordered(sceneOrder: scenes).compactMap(\.title).filter { mine.contains($0) } == ["Бета", "Альфа", "Гамма", "Дельта"], "the order is on disk")
        // The first of its scene cannot go above its heading.
        ev.select(second)
        ev.move(by: -1)
        now = ev.listTitles
        check((now.firstIndex(of: "Бета") ?? 99) > (now.firstIndex(of: "— " + sceneTitle(scenes[0])) ?? 99) && (now.firstIndex(of: "Бета") ?? 99) < (now.firstIndex(of: "— " + sceneTitle(scenes[1])) ?? 0), "an event cannot leave its scene by being moved")
        // Dragging: dropped above the other one, and not into another scene's group.
        let rowOfFirst = now.firstIndex(of: "Альфа")!
        check(ev.dropAllowed(second, aboveRow: rowOfFirst + 1), "a drop inside the scene's group is allowed (after the last one too)")
        check(!ev.dropAllowed(second, aboveRow: now.firstIndex(of: "Гамма")!), "and a drop into another scene's group is not")
        check(ev.performDrop(second, aboveRow: rowOfFirst + 1), "the drop is carried out")
        now = ev.listTitles
        check((now.firstIndex(of: "Альфа") ?? 99) < (now.firstIndex(of: "Бета") ?? 0), "dragged below the other one, it is second again", "\(mineOnly(now))")

        // The scene is the heading: a row is its title alone.
        check(ev.rowTexts.filter { mine.contains($0) }.count == 4 && !ev.rowTexts.contains { $0.contains("\n") }, "a row shows the title alone, on one line, since the heading says the scene", "\(ev.rowTexts)")
        check(!ev.listTitles.contains { $0.hasPrefix("— ") && $0.contains("By") }, "and there is no choice of mode any more")
        // Moving down, and to a given place inside the group.
        ev.select(first)
        ev.move(by: 1); spin(0.2)
        check((ev.listTitles.firstIndex(of: "Бета") ?? 99) < (ev.listTitles.firstIndex(of: "Альфа") ?? 0), "Move Down puts an event after the one below it", "\(mineOnly(ev.listTitles))")
        ev.moveEvent(first, toIndex: 0); spin(0.2)
        check((ev.listTitles.firstIndex(of: "Альфа") ?? 99) < (ev.listTitles.firstIndex(of: "Бета") ?? 0), "and an event can be put at a given place in its group")
        ev.select(alone)
        ev.move(by: 1)
        check(ev.listTitles.last == "Дельта" || ev.listTitles.contains("Дельта"), "the last event of the last group cannot go further down")
        // The order of the other scenes is untouched by moves in this one.
        check(EventStore(book: main.folder).event(third)?.order == nil, "the events of another scene were not numbered")

        // Editing the chosen event's card must not move the choice to another event (the list has headings above it).
        let helper = try! main.characters.add(name: "Помощник")
        let spot = try! main.worlds.addEntry(name: "Помощь-град", world: main.worlds.worlds[0].id!)
        for (what, act) in [("adding a character", { ev.addCharacter(helper) }), ("adding a place", { ev.addPlace(spot) }), ("adding a scene", { ev.addScene(scenes[scenes.count - 1]) })] as [(String, () -> Void)] {
            ev.select(alone)
            act(); spin(0.2)
            check(ev.selected == alone, "\(what) to the event keeps the same event chosen", "\(String(describing: ev.selected)) instead of \(alone)")
        }
        ev.select(alone)
        ev.removeConnection(row: 0); spin(0.2)
        check(ev.selected == alone, "and so does taking a link away")
        try? main.characters.delete(helper)
        try? main.worlds.deleteEntry(spot)

        // A filter turns ordering off.
        ev.filterField.stringValue = "Перв"
        ev.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: ev.filterField))
        check(!ev.dropAllowed(first, aboveRow: 0), "with a filter on, the list cannot be reordered")
        ev.filterField.stringValue = ""
        ev.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: ev.filterField))
        for id in [first, second, third, alone] { try? main.eventStore.delete(id) }
        ev.reload()
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
