import Foundation
import Testing
@testable import QuillandCore

@Suite("Kinds of books and their size")
struct BookKindsTests {
    @Test("a kind gives its length in characters by the language: the same novel is longer in Russian")
    func characters() throws {
        let novel = try #require(BookKinds.kind("novel"))
        #expect(BookKinds.characters(of: novel, language: "en") == 540_000)
        #expect(BookKinds.characters(of: novel, language: "ru") == 630_000)
        #expect(BookKinds.characters(of: novel, language: "xx") == 540_000)
        // The kinds go from short to long, and their ranges meet.
        let kinds = BookKinds.all
        #expect(kinds.map(\.typicalWords) == kinds.map(\.typicalWords).sorted())
        for (a, b) in zip(kinds, kinds.dropFirst()) { #expect(a.maxWords == b.minWords) }
        #expect(kinds.allSatisfy { k in k.typicalWords > (k.minWords ?? 0) && k.typicalWords <= (k.maxWords ?? Int.max) })
    }

    @Test("words, author's sheets and percent follow from the characters")
    func conversions() {
        #expect(BookKinds.words(fromCharacters: 630_000, language: "ru") == 90_000)
        #expect(BookKinds.authorSheets(fromCharacters: 630_000) == 15.75)
        #expect(BookKinds.usesAuthorSheets("ru") && BookKinds.usesAuthorSheets("UK") && !BookKinds.usesAuthorSheets("en"))
        #expect(BookKinds.percent(characters: 135_000, target: 540_000) == 25)
        #expect(BookKinds.percent(characters: 600_000, target: 540_000) == 111)
        #expect(BookKinds.percent(characters: 5, target: nil) == nil && BookKinds.percent(characters: 5, target: 0) == nil)
    }

    @Test("the kind is kept in book.json beside the target, and goes when it is cleared")
    func saved() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        var s = BookSettings.load(book: book)
        #expect(s.kind == nil && s.targetCharacters == nil)
        s.kind = "novel"; s.targetCharacters = 630_000
        try s.save(book: book)
        #expect(BookSettings.load(book: book).kind == "novel" && BookSettings.load(book: book).targetCharacters == 630_000)
        s.kind = nil
        try s.save(book: book)
        let o = try JSONParser.parseObject(Data(contentsOf: book.appendingPathComponent("book.json")))
        #expect(o["book_type"] == nil && o.int("target_characters") == 630_000)
    }
}
