import Foundation
import Testing
@testable import QuillandCore

@Suite("Merging and converting places and worlds")
struct WorldMergeTests {
    @Test("two places become one: names, notes, links and text go to the kept one, what was inside it moves to it, and references follow")
    func mergePlaces() throws {
        let (parent, book) = try CharacterMergeTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(book: book)
        let world = store.worlds[0].id!
        let kept = try store.addEntry(name: "Дом на Сосновой", world: world)
        let other = try store.addEntry(name: "Старый дом", world: world)
        let room = try store.addEntry(name: "Чердак", world: world, parent: other)
        try store.updateEntry(kept) { $0.aliases = ["Дом"]; $0.notes = ["Двухэтажный."]; $0.links = ["scene-a": "ужин"] }
        try store.updateEntry(other) { $0.aliases = ["Особняк", "дом"]; $0.notes = ["Двухэтажный.", "Скрипят полы."]; $0.links = ["scene-a": "гроза", "scene-b": "приезд"] }
        try store.setText(kept, "Большой дом.")
        try store.setText(other, "Стоит на холме.")
        // A character who lives at the other house, and an event there.
        let chars = CharacterStore(book: book)
        let anna = try chars.add(name: "Анна")
        try chars.update(anna) { $0.worlds = [other, "x"] }
        let eventDir = book.appendingPathComponent("bible/events")
        try FileManager.default.createDirectory(at: eventDir, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(["id": .string("ev"), "title": .string("Ужин"), "places": .object([other: .string("накрыт стол")])]), to: eventDir.appendingPathComponent("ev.json"))

        let report = try WorldMerger.mergePlaces(other, into: kept, book: book)

        let after = WorldStore(book: book)
        let now = try #require(after.entry(kept))
        #expect(after.entry(other) == nil && after.entry(room)?.parent == kept)
        #expect(now.aliases == ["Дом", "Старый дом", "Особняк"] && now.notes == ["Двухэтажный.", "Скрипят полы."])
        #expect(now.links == ["scene-a": "ужин гроза", "scene-b": "приезд"])
        #expect(after.text(kept) == "Большой дом.\n\n**Старый дом**\n\nСтоит на холме.")
        #expect(CharacterStore(book: book).character(anna)?.worlds == [kept, "x"])
        let event = try JSONParser.parseObject(Data(contentsOf: eventDir.appendingPathComponent("ev.json")))
        #expect(event.stringMap("places") == [kept: "накрыт стол"])
        #expect(report.placesMoved == 1 && report.linksRepointed == 2 && report.aliasesAdded == ["Старый дом", "Особняк"])
        #expect(WorldStore(book: book).problems.isEmpty)
    }

    @Test("a place cannot be merged into itself or into a place inside it")
    func refused() throws {
        let (parent, book) = try CharacterMergeTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(book: book)
        let world = store.worlds[0].id!
        let outer = try store.addEntry(name: "Город", world: world)
        let inner = try store.addEntry(name: "Улица", world: world, parent: outer)
        #expect(throws: (any Error).self) { try WorldMerger.mergePlaces(outer, into: outer, book: book) }
        #expect(throws: (any Error).self) { try WorldMerger.mergePlaces(outer, into: inner, book: book) }
        #expect(WorldStore(book: book).entries.count == 2, "nothing was removed")
    }

    @Test("two worlds become one: the entries of the first are at the top of the second")
    func mergeWorlds() throws {
        let (parent, book) = try CharacterMergeTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(book: book)
        let first = store.worlds[0].id!
        let second = try store.addWorld(name: "Земля")
        let city = try store.addEntry(name: "Город", world: second)
        let street = try store.addEntry(name: "Улица", world: second, parent: city)
        try store.updateWorld(first) { $0.notes = ["Главный мир."] }
        try store.updateWorld(second) { $0.aliases = ["Старая Земля"]; $0.notes = ["Давно."] }
        let report = try WorldMerger.mergeWorlds(second, into: first, book: book)
        let after = WorldStore(book: book)
        #expect(after.world(second) == nil && after.worlds.count == 1)
        #expect(after.entry(city)?.world == first && after.entry(street)?.world == first && after.entry(street)?.parent == city && after.entry(city)?.parent == nil)
        #expect(after.world(first)?.aliases.contains("Земля") == true && after.world(first)?.aliases.contains("Старая Земля") == true && after.world(first)?.notes == ["Главный мир.", "Давно."])
        #expect(report.placesMoved == 2 && after.problems.isEmpty)
    }

    @Test("a place that is a whole world becomes a world, with what was inside it at the top")
    func placeToWorld() throws {
        let (parent, book) = try CharacterMergeTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(book: book)
        let home = store.worlds[0].id!
        let planet = try store.addEntry(name: "Тэра", world: home)
        let land = try store.addEntry(name: "Север", world: home, parent: planet)
        let town = try store.addEntry(name: "Хольм", world: home, parent: land)
        let other = try store.addEntry(name: "Кухня", world: home)
        try store.updateEntry(planet) { $0.aliases = ["Старая Тэра"]; $0.notes = ["Далёкая."]; $0.links = ["scene-a": "упоминается"] }
        try store.setText(planet, "Планета с двумя лунами.")
        let chars = CharacterStore(book: book)
        let anna = try chars.add(name: "Анна")
        try chars.update(anna) { $0.worlds = [planet] }

        let result = try WorldMerger.placeToWorld(planet, book: book)

        let after = WorldStore(book: book)
        let world = try #require(after.world(result.world))
        #expect(after.entry(planet) == nil && world.name == "Тэра" && world.aliases == ["Старая Тэра"] && world.notes == ["Далёкая."])
        #expect(after.text(result.world) == "Планета с двумя лунами." && world.object.stringMap("links") == ["scene-a": "упоминается"])
        #expect(after.entry(land)?.world == result.world && after.entry(land)?.parent == nil && after.entry(town)?.world == result.world && after.entry(town)?.parent == land)
        #expect(after.entry(other)?.world == home, "an unrelated place stays")
        #expect(CharacterStore(book: book).character(anna)?.worlds == [result.world])
        #expect(result.report.placesMoved == 2 && after.problems.isEmpty)
    }

    @Test("a world that is really a place becomes a place in another world, with its entries inside it")
    func worldToPlace() throws {
        let (parent, book) = try CharacterMergeTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(book: book)
        let home = store.worlds[0].id!
        let island = try store.addWorld(name: "Остров")
        let bay = try store.addEntry(name: "Бухта", world: island)
        let cove = try store.addEntry(name: "Бухточка", world: island, parent: bay)
        let region = try store.addEntry(name: "Побережье", world: home)
        try store.updateWorld(island) { $0.aliases = ["Островок"]; $0.notes = ["Маленький."] }
        try store.setText(island, "Остров в море.")

        let result = try WorldMerger.worldToPlace(island, intoWorld: home, parent: region, book: book)

        let after = WorldStore(book: book)
        let place = try #require(after.entry(result.entry))
        #expect(after.world(island) == nil && place.name == "Остров" && place.world == home && place.parent == region && place.aliases == ["Островок"] && place.notes == ["Маленький."])
        #expect(after.text(result.entry) == "Остров в море.")
        #expect(after.entry(bay)?.world == home && after.entry(bay)?.parent == result.entry && after.entry(cove)?.parent == bay)
        #expect(after.problems.isEmpty && result.report.placesMoved == 2)
        // The last world cannot be turned into a place (there is nowhere for it to go).
        #expect(throws: (any Error).self) { try WorldMerger.worldToPlace(home, intoWorld: home, parent: nil, book: book) }
    }
}

@Suite("The world files")
struct WorldFileTests {
    @Test("a new book's default world is a file named by its id, so changing it does not make a second file")
    func defaultWorld() throws {
        let (parent, book) = try CharacterMergeTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = WorldStore(book: book)
        let id = try #require(store.worlds.first?.id)
        #expect(FileManager.default.fileExists(atPath: book.appendingPathComponent("bible/worlds/\(id).json").path))
        try store.updateWorld(id) { $0.notes = ["Главный мир."] }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent("bible/worlds").path)) ?? []).filter { $0.hasSuffix(".json") }
        #expect(files == ["\(id).json"] && WorldStore(book: book).worlds.count == 1)
    }

    @Test("a book made by the older version, with a world file not named by its id, is read once and written again in the same file")
    func olderBook() throws {
        let (parent, book) = try CharacterMergeTests.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let dir = book.appendingPathComponent("bible/worlds")
        let id = try #require(WorldStore(book: book).worlds.first?.id)
        // As the older version left it: the file under another name.
        try FileManager.default.moveItem(at: dir.appendingPathComponent("\(id).json"), to: dir.appendingPathComponent("old-name.json"))
        let store = WorldStore(book: book)
        #expect(store.worlds.count == 1)
        try store.updateWorld(id) { $0.notes = ["Изменено."] }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".json") }
        #expect(files == ["old-name.json"] && WorldStore(book: book).worlds.count == 1 && WorldStore(book: book).worlds[0].notes == ["Изменено."], "\(files)")
        // And one that already has the two files (a world edited by the older version): one world, the changed one.
        try FileManager.default.copyItem(at: dir.appendingPathComponent("old-name.json"), to: dir.appendingPathComponent("\(id).json"))
        let changed = WorldStore(book: book)
        try changed.updateWorld(id) { $0.notes = ["Ещё раз."] }
        let healed = WorldStore(book: book)
        #expect(healed.worlds.count == 1 && healed.worlds[0].notes == ["Ещё раз."])
    }
}
