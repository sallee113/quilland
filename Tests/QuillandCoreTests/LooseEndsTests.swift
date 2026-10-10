import Foundation
import Testing
@testable import QuillandCore

@Suite("Loose ends: links to nothing and damaged files")
struct LooseEndsTests {
    func demo() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-loose-\(UUID().uuidString)")
        try DemoBook.write(into: folder, scenes: 12, paragraphs: 3)
        return folder
    }

    @Test("a whole book has none; a link to a deleted scene is found, and can be removed or re-pointed")
    func links() throws {
        let book = try demo()
        let ends = LooseEnds(book: book)
        #expect(ends.scan().isEmpty, "\(ends.scan().map { "\($0.file) \($0.field) \($0.target)" })")
        let structure = try BookStructure.load(folder: book)
        let gone = structure.scenes[3].id, other = structure.scenes[0].id
        // Delete a scene with the editor, as the app would; the data files keep their links to it.
        try BookEditor(structure: structure).delete(gone)
        let found = ends.scan()
        #expect(!found.isEmpty && found.allSatisfy { $0.kind == .missingLink && $0.target == gone })
        let first = found[0]
        try ends.repoint(first, to: other)
        #expect(ends.scan().count == found.count - 1)
        for end in ends.scan() { try ends.remove(end) }
        #expect(ends.scan().isEmpty, "everything removed")
        let characters = CharacterStore(book: book)
        #expect(characters.problems.isEmpty && characters.characters.count == 12, "the other fields stay")
    }

    @Test("a damaged file is listed, and the newest readable copy comes back from a snapshot")
    func damaged() throws {
        let book = try demo()
        let characters = CharacterStore(book: book)
        let victim = characters.characters[0]
        let file = "bible/characters/\(victim.id!).json"
        let url = book.appendingPathComponent(file)
        let good = try Data(contentsOf: url)
        try Data("{ not json".utf8).write(to: url)
        let ends = LooseEnds(book: book)
        let found = ends.scan()
        #expect(found.count == 1 && found[0].kind == .damagedFile && found[0].file == file)
        let info = try ends.restoreDamaged(found[0])
        #expect(try Data(contentsOf: url) == good && !info.id.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("damaged").path), "the damaged one is kept")
        try FileManager.default.removeItem(at: url.appendingPathExtension("damaged"))
        #expect(ends.scan().isEmpty)
    }

    @Test("Keep it is remembered per link, on this machine")
    func ignoring() throws {
        let book = try demo()
        let ends = LooseEnds(book: book)
        let structure = try BookStructure.load(folder: book)
        try BookEditor(structure: structure).delete(structure.scenes[2].id)
        let all = ends.scan()
        #expect(all.count >= 1)
        LooseEnds.ignore(all[0], book: book)
        #expect(ends.scan(ignoring: LooseEnds.ignored(book: book)).count == all.count - 1)
    }
}
