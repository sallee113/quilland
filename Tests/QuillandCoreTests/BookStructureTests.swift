import Foundation
import Testing
@testable import QuillandCore

@Suite("Book structure")
struct BookStructureTests {
    @Test("the sample book is read in book order, with parts, chapters, a loose chapter and statuses")
    func sample() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-structure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try SampleBook.write(into: url)
        let book = try BookStructure.load(folder: url)
        #expect(book.problems.isEmpty)
        #expect(book.roots.map(\.kind) == [.part, .part, .chapter])
        #expect(book.roots.map(\.title) == ["Дорога", "Дом", "Эпилог"])
        #expect(book.scenes.count == 8)
        #expect(book.scenes.map(\.node.title).prefix(3) == ["Платформа", "Письмо", "Третья ступенька"])
        #expect(book.scenes[0].partTitle == "Дорога" && book.scenes[0].chapterTitle == "Станция")
        #expect(book.scenes.last?.partTitle == nil && book.scenes.last?.chapterTitle == "Эпилог")
        #expect(book.scenes[0].node.status == "done")
        #expect(FileManager.default.fileExists(atPath: book.markdownURL(for: book.scenes[0].node).path))
    }

    @Test("a damaged scene file is reported and the rest is read")
    func damaged() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-structure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try SampleBook.write(into: url)
        try Data("{ not json".utf8).write(to: url.appendingPathComponent("manuscript/001-part/001-chapter/002-scene.json"))
        let book = try BookStructure.load(folder: url)
        #expect(book.problems.count == 1)
        #expect(book.scenes.count == 7)
    }
}
