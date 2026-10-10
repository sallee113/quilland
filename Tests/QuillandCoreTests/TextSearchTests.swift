import Foundation
import Testing
@testable import QuillandCore

@Suite("Searching a text")
struct TextSearchTests {
    func found(_ q: String, _ text: String, _ o: SearchOptions = SearchOptions()) -> [String] {
        let ns = text as NSString
        return TextSearch.ranges(of: q, in: text, options: o).map { ns.substring(with: $0) }
    }

    @Test("case, ё and е, whole words")
    func options() {
        let text = "Ёлка и елка. Анна, анна, Аннабель."
        #expect(found("елка", text) == ["Ёлка", "елка"])
        #expect(found("елка", text, SearchOptions(yoAsYe: false)) == ["елка"])
        #expect(found("анна", text) == ["Анна", "анна", "Анна"])
        #expect(found("анна", text, SearchOptions(matchCase: true)) == ["анна"])
        #expect(found("анна", text, SearchOptions(wholeWords: true)) == ["Анна", "анна"])
        #expect(found("", text).isEmpty)
    }

    @Test("word endings find the case forms of a name")
    func endings() {
        let text = "Вашингтон спал. Они вернулись в Вашингтоне, к Вашингтону и от Вашингтона."
        #expect(found("Вашингтон", text, SearchOptions(wholeWords: true)) == ["Вашингтон"])
        #expect(found("Вашингтон", text, SearchOptions(endings: true)).count == 4)
        let two = TextSearch.ranges(of: "Анна Петровна", in: "Он видел Анну Петровну.", options: SearchOptions(endings: true))
        #expect(two.count == 1)
    }

    @Test("a range limits the search, and offsets are UTF-16 even after an emoji")
    func within() {
        let text = "😀 слово слово слово"
        let all = TextSearch.ranges(of: "слово", in: text)
        #expect(all.count == 3 && all[0].location == 3)
        let limited = TextSearch.ranges(of: "слово", in: text, within: NSRange(location: 9, length: 11))
        #expect(limited.count == 2)
        let end = TextSearch.ranges(of: "слово", in: text, options: SearchOptions(endings: true))
        #expect(end == all)
    }

    @Test("replacing gives the new text and where the new pieces are")
    func replacing() {
        let text = "кот и кот и кот"
        let r = TextSearch.ranges(of: "кот", in: text)
        let (new, places) = TextSearch.replace(r, in: text, with: "пёс")
        #expect(new == "пёс и пёс и пёс" && places.count == 3 && places[2] == NSRange(location: 12, length: 3))
        let (gone, _) = TextSearch.replace(r, in: text, with: "")
        #expect(gone == " и  и ")
        let (longer, spots) = TextSearch.replace(r, in: text, with: "котёнок")
        #expect((longer as NSString).substring(with: spots[2]) == "котёнок")
    }

    @Test("a context line is one line with ellipses where it was cut")
    func context() {
        let text = String(repeating: "а", count: 100) + "\nнужное слово\n" + String(repeating: "б", count: 100)
        let r = TextSearch.ranges(of: "слово", in: text)[0]
        let (before, after) = TextSearch.context(of: r, in: text, radius: 10)
        #expect(before.hasPrefix("…") && after.hasSuffix("…") && !before.contains("\n") && !after.contains("\n"))
    }

    @Test("a whole book is searched at once, quickly")
    func speed() {
        var text = ""
        for i in 0..<9000 { text += "Это длинная строка номер \(i) про Анну Петровну и её собаку. " }
        let start = Date()
        let hits = TextSearch.ranges(of: "собаку", in: text)
        let hitsEnd = TextSearch.ranges(of: "анна", in: text, options: SearchOptions(endings: true))
        #expect(hits.count == 9000 && hitsEnd.count > 0)
        #expect(Date().timeIntervalSince(start) < 1.5, "\(Date().timeIntervalSince(start)) s for \(text.count) characters")
    }
}

@Suite("Names that are ordinary words")
struct CommonNounNameTests {
    @Test("a place typed in lowercase or with a capital is found in its case forms, in lowercase text")
    func commonNoun() {
        let text = "В кемпинге стояла гробовая тишина. Из кемпинга никто не вышел. Кемпинг опустел."
        // A place or a thing ignores capitals; a character's name does not (every "вера" would be Vera).
        for name in ["кемпинг", "Кемпинг"] {
            let m = ParadigmMatcher(entries: [NameEntry(id: "k", name: name, ignoresCapitals: true)]).matches(in: text)
            #expect(m.count == 3, "\(name): \(m.count) of 3")
        }
        #expect(ParadigmMatcher(entries: [NameEntry(id: "k", name: "Кемпинг")]).matches(in: text).count == 1)
        #expect(StemMatcher(entries: [NameEntry(id: "k", name: "Кемпинг", ignoresCapitals: true)]).matches(in: text).count == 3)
        let ns = text as NSString
        let found = TextSearch.ranges(of: "кемпинг", in: text, options: SearchOptions(endings: true)).map { ns.substring(with: $0) }
        #expect(found == ["кемпинге", "кемпинга", "Кемпинг"], "\(found)")
    }
}
