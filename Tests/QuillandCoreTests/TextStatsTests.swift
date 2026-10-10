import Testing
@testable import QuillandCore

@Suite("Counting the size of a text")
struct TextStatsTests {
    @Test("words and characters, with and without spaces")
    func basics() {
        let c = TextStats.count("Анна вошла в комнату.")
        #expect(c.words == 4)
        #expect(c.characters == 21)
        #expect(c.charactersWithoutSpaces == 18)
    }

    @Test("a word keeps its inner hyphen and apostrophe; punctuation, digits and spaces are handled")
    func words() {
        #expect(TextStats.count("что-то O'Neil «да», — нет… 2026 год").words == 6)
        #expect(TextStats.count("слово - слово").words == 2, "a spaced hyphen is not inside a word")
        #expect(TextStats.count("").words == 0)
        #expect(TextStats.count("   ").characters == 3)
        #expect(TextStats.count("   ").charactersWithoutSpaces == 0)
    }

    @Test("invisible characters and combining marks do not count as characters; stress marks stay in their word")
    func invisibles() {
        #expect(TextStats.count("ко\u{00AD}мната").characters == 7)
        #expect(TextStats.count("уда\u{0301}рение").characters == 8, "the accent belongs to the letter before it")
        #expect(TextStats.count("уда\u{0301}рение").words == 1)
        #expect(TextStats.count("а\u{200B}б").characters == 2)
    }

    @Test("a document: headings, footnotes and quotes count; scene breaks and fragment markers do not")
    func document() {
        let doc = MarkdownParser.parse("""
        # Глава

        Слово^[Сноска из трёх слов.] ещё.

        * * *

        <!-- fragment: 3f2504e0-4f89-41d3-9a0c-0305e82c3301 -->

        > Цитата здесь.
        """)
        let c = TextStats.count(doc)
        #expect(c.words == 1 + 1 + 4 + 1 + 2)
        #expect(c.characters == "Глава".count + "Слово".count + "Сноска из трёх слов.".count + " ещё.".count + "Цитата здесь.".count)
    }

    @Test("an author's sheet is 40,000 characters with spaces")
    func sheets() {
        #expect(TextCounts(words: 0, characters: 40_000, charactersWithoutSpaces: 0).sheets == 1.0)
        #expect(TextCounts(words: 0, characters: 10_000, charactersWithoutSpaces: 0).sheets == 0.25)
    }
}
