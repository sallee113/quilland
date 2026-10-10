import Foundation
import Testing
@testable import QuillandCore

@Suite("The demo book")
struct DemoBookTests {
    @Test("a demo book is whole: structure, characters, places, events, plan, export profiles and snapshots")
    func whole() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-demo-\(UUID().uuidString)")
        try DemoBook.write(into: folder, scenes: 40, paragraphs: 6)
        let structure = try BookStructure.load(folder: folder)
        #expect(structure.problems.isEmpty, "\(structure.problems)")
        #expect(structure.scenes.count == 41, "40 scenes and the epilogue")
        #expect(structure.roots.count == 5)
        #expect(Set(structure.scenes.compactMap(\.node.status)) == ["idea", "draft", "revised", "done"])
        #expect(CharacterStore(book: folder).characters.count == 12 && CharacterStore(book: folder).problems.isEmpty)
        let relationships = RelationshipStore(book: folder)
        #expect(relationships.relationships.count == 5 && relationships.problems.isEmpty, "\(relationships.problems)")
        let world = WorldStore(book: folder)
        #expect(world.worlds.count == 2 && world.entries.count == DemoBook.spots.count && world.problems.isEmpty)
        let events = EventStore(book: folder)
        #expect(events.events.count == 30 && events.problems.isEmpty)
        let plan = try PlanStore(folder: folder)
        #expect(plan.lines.count == 4 && plan.entries.count == 30 && plan.cards.count == 10 && plan.problems.isEmpty, "\(plan.problems)")
        #expect(BookDictionary.load(book: folder).count == DemoBook.words.count)
        #expect(ExportStore(book: folder).profiles.count == 3)
        #expect(SnapshotStore(bookFolder: folder).list().count == 2)
        // Every link points at a scene that exists.
        let ids = Set(structure.scenes.map(\.id))
        #expect(events.events.allSatisfy { $0.links.keys.allSatisfy(ids.contains) })
        #expect(CharacterStore(book: folder).characters.allSatisfy { $0.links.keys.allSatisfy(ids.contains) && $0.povScenes.allSatisfy(ids.contains) })
        try? FileManager.default.removeItem(at: folder)
    }
}
