import Foundation
import Testing
@testable import QuillandCore

@Suite("Research documents")
struct ResearchStoreTests {
    static func book() throws -> (URL, URL) {
        let parent = try NewBookTests.folder()
        return (parent, try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent)))
    }

    @Test("a document keeps its title, source, typed text and links, and reads them again")
    func roundTrip() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = ResearchStore(book: book)
        let id = try store.add(title: "Music education in the USA")
        try store.update(id) { $0.source = "Mark, M. A History of American Music Education"; $0.links = ["scene-a": "the school board scene"] }
        try store.setText(id, "Lowell Mason brought singing into Boston schools in 1838.")
        let again = ResearchStore(book: book)
        #expect(again.documents.count == 1 && again.problems.isEmpty)
        #expect(again.document(id)?.source.hasPrefix("Mark") == true)
        #expect(again.document(id)?.links == ["scene-a": "the school board scene"])
        #expect(again.text(id).contains("Lowell Mason"))
        #expect(again.linked(to: "scene-a").count == 1 && again.linked(to: "scene-b").isEmpty)
    }

    @Test("an embedded file is copied into the book with its size and hash, and comes out with the document")
    func embedded() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let source = parent.appendingPathComponent("hearings.txt")
        try Data("hello".utf8).write(to: source)
        let store = ResearchStore(book: book)
        let id = try store.add(title: "Hearings")
        #expect(store.fileState(id) == .none)
        try store.attach(id, file: source, embed: true)
        try store.setText(id, "notes")
        let file = try #require(store.document(id)?.file)
        #expect(file.embedded && file.name == "hearings.txt" && file.size == 5 && file.hash.hasPrefix("sha256:") && file.path == nil)
        #expect(store.fileURL(id)?.path == book.appendingPathComponent("research/\(id).file/hearings.txt").path)
        #expect(store.fileState(id) == .present)
        try FileManager.default.removeItem(at: source)
        #expect(store.fileState(id) == .present)
        try store.delete(id)
        let research = (try? FileManager.default.contentsOfDirectory(atPath: book.appendingPathComponent("research").path)) ?? []
        #expect(research.isEmpty && store.documents.isEmpty)
        let trash = try FileManager.default.subpathsOfDirectory(atPath: book.appendingPathComponent(".quilland/trash").path)
        #expect(trash.contains { $0.hasSuffix("\(id).file/hearings.txt") } && trash.contains { $0.hasSuffix("\(id).md") } && trash.contains { $0.hasSuffix("\(id).json") })
    }

    @Test("an external file stays where it is; if it goes, the document says it is missing and keeps everything else")
    func external() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let source = parent.appendingPathComponent("outside.pdf")
        try Data("pdf".utf8).write(to: source)
        let store = ResearchStore(book: book)
        let id = try store.add(title: "Outside")
        try store.attach(id, file: source, embed: false)
        #expect(store.document(id)?.file?.embedded == false && store.fileState(id) == .present)
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent("research/\(id).file/outside.pdf").path))
        try FileManager.default.removeItem(at: source)
        #expect(store.fileState(id) == .missing)
        #expect(ResearchStore(book: book).document(id)?.file?.name == "outside.pdf")
        try store.delete(id)
    }

    @Test("a new file replaces the old one; taking the file off keeps the text")
    func replaceAndDetach() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let a = parent.appendingPathComponent("a.txt"), b = parent.appendingPathComponent("b.md")
        try Data("one".utf8).write(to: a); try Data("two!".utf8).write(to: b)
        let store = ResearchStore(book: book)
        let id = try store.add(title: "Two files")
        try store.setText(id, "typed")
        try store.attach(id, file: a, embed: true)
        try store.attach(id, file: b, embed: true)
        #expect(!FileManager.default.fileExists(atPath: book.appendingPathComponent("research/\(id).file/a.txt").path))
        #expect(store.fileURL(id)?.lastPathComponent == "b.md" && store.fileState(id) == .present && store.text(id) == "typed")
        try store.detachFile(id)
        #expect(store.document(id)?.file == nil && store.text(id) == "typed")
        #expect(throws: ResearchStore.FileError.notFound) { try store.attach(id, file: parent.appendingPathComponent("none.txt"), embed: true) }
    }

    @Test("searching looks in the title, source, remarks, file name and text, ignoring case")
    func search() throws {
        let (parent, book) = try Self.book()
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = ResearchStore(book: book)
        let one = try store.add(title: "Conservatories")
        let two = try store.add(title: "School bands")
        try store.setText(one, "The Oberlin Conservatory opened in 1865.")
        try store.update(two) { $0.source = "Journal of Band Research" }
        #expect(store.matching("oberlin").compactMap(\.id) == [one])
        #expect(store.matching("BAND").compactMap(\.id) == [two])
        #expect(store.matching("").count == 2 && store.matching("xyz").isEmpty)
    }
}
