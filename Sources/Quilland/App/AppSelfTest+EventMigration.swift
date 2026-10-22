import AppKit
import QuillandCore

/// Opening an old book: the author is asked before the links between characters and events move into the events; "Not now" leaves the book unopened and unchanged.
extension AppSelfTest {
    func eventMigration() -> Int32? {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-migration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let saved = app.migrationDecision
        defer { app.migrationDecision = saved }

        // An old book: the links are in the characters' files, and a relationship starts at no event.
        let old = try! BookCreator.create(NewBookRequest(title: "Старая", language: "ru", parentFolder: parent))
        let people = CharacterStore(book: old)
        let anna = try! people.add(name: "Анна"), lev = try! people.add(name: "Лев")
        let events = EventStore(book: old)
        let arrival = try! events.add(title: "Приезд")
        try! people.update(anna) { $0.links = [arrival: "выходит"] }
        try! people.update(lev) { $0.links = [arrival: "встречает"] }
        _ = try! RelationshipStore(book: old).add(characters: [anna, lev], kind: "сёстры")

        var asked: EventLinkMigration.Plan?
        app.migrationDecision = { plan, _ in asked = plan; return false }
        let windows = app.bookWindows.count
        let refused = !app.openBook(at: old)
        app.welcome.window.orderOut(nil)
        check(refused && app.bookWindows.count == windows, "\"Not now\" leaves the book unopened")
        check(asked == EventLinkMigration.Plan(links: 2, characters: 2, relationships: 1), "the author is told what will move", "\(String(describing: asked))")
        check(CharacterStore(book: old).character(anna)?.links[arrival] == "выходит" && EventStore(book: old).event(arrival)?.characters.isEmpty == true && SnapshotStore(bookFolder: old).list().isEmpty, "and nothing in the book was changed, not even a snapshot")

        app.migrationDecision = { plan, _ in asked = plan; return true }
        let opened = app.openBook(at: old)
        check(opened && app.bookWindows.count == windows + 1, "\"Start migration\" opens the book")
        let win = app.bookWindows.last
        check(win?.main.banner.text.contains("Moved") == true, "a line says what was moved", win?.main.banner.text ?? "")
        let after = EventStore(book: old)
        check(after.event(arrival)?.characters == [anna: "выходит", lev: "встречает"] && CharacterStore(book: old).character(anna)?.links.isEmpty == true, "the links are in the event now")
        check(after.startEvent?.relationships.count == 1 && !SnapshotStore(bookFolder: old).list().isEmpty, "the relationship starts at Book starts, and a snapshot was taken first")
        win?.window.close(); spin(0.3)

        // A book with nothing to move opens with no question.
        let clean = try! BookCreator.create(NewBookRequest(title: "Чистая", language: "ru", parentFolder: parent))
        var askedAgain = false
        app.migrationDecision = { _, _ in askedAgain = true; return true }
        check(app.openBook(at: clean) && !askedAgain, "a book with nothing to move opens with no question")
        app.bookWindows.last?.window.close(); spin(0.3)
        // (The books made here are not to stay in the list of recent books, and the book of the checks is the one to reopen.)
        for folder in [old, clean] { app.settings.forget(path: folder.standardizedFileURL.path) }
        app.settings.noteOpened(folder: self.main.folder, name: app.bookWindows.first?.bookTitle ?? "")
        return nil
    }
}
