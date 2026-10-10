import Foundation
import Testing
@testable import QuillandCore

/// Experiment 3: finding Russian names, with their case endings, in a text.
///
/// Four matchers are measured on the same data (Corpus/names): 93 names with the forms
/// written out by hand (so the answer does not come from the rules under test), look-alike
/// words that must NOT match, and ordinary prose.
@Suite("Finding Russian names", .serialized)
struct NameTests {
    struct Spec: Decodable {
        var id: String
        var name: String
        var category: String
        var forms: [String]
    }

    struct Negatives: Decodable {
        struct Distractor: Decodable { var target: String; var sentence: String; var word: String; var kind: String }
        struct Ambiguous: Decodable { var target: String; var sentence: String }
        var distractors: [Distractor]
        var ambiguous: [Ambiguous]
    }

    struct Prose: Decodable { var text: String; var kind: String }

    struct Positive {
        var id: String
        var form: String
        var sentence: String
        var start: Int
        var count: Int
        var category: String
        var kind: String
    }

    static func load<T: Decodable>(_ file: String, as: T.Type) -> T {
        let url = Corpus.root.appendingPathComponent("names/\(file)")
        return try! JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static let specs = load("names.json", as: [Spec].self)
    static let negatives = load("negatives.json", as: Negatives.self)
    static let prose = load("prose.json", as: [Prose].self)
    static let heldOut = load("names-heldout.json", as: [Spec].self)

    /// The folded forms every entry really has (the answer key), to tell a wrong hit from a true ambiguity.
    static let truth: [String: Set<String>] = Dictionary(uniqueKeysWithValues: specs.map { spec in
        (spec.id, Set(spec.forms.map { Words.split($0).map(\.folded).joined(separator: " ") }))
    })

    static let templates = [
        "Вчера на вокзале появился {X} и сразу заговорил.",
        "Это письмо пришло от {X} утром.",
        "Она рассказала об этом {X} вчера.",
        "Они увидели {X} у окна.",
        "Он долго говорил с {X} о делах.",
        "Мы часто думали о {X} зимой.",
    ]

    static func positives(of specs: [Spec] = specs) -> [Positive] {
        var out: [Positive] = []
        func add(_ spec: Spec, _ form: String, template: String, kind: String) {
            let parts = template.components(separatedBy: "{X}")
            out.append(Positive(id: spec.id, form: form, sentence: parts[0] + form + parts[1],
                                start: Words.split(parts[0]).count, count: Words.split(form).count, category: spec.category, kind: kind))
        }
        for spec in specs {
            for (i, form) in spec.forms.enumerated() {
                add(spec, form, template: templates[i % templates.count], kind: "form")
                if i == 0 { add(spec, form, template: "{X} вошёл в комнату и огляделся.", kind: "sentence start") }
                if form.contains("ё") || form.contains("Ё") {
                    add(spec, form.replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: "Ё", with: "Е"),
                        template: templates[(i + 1) % templates.count], kind: "е for ё")
                }
                if i < 2 {
                    add(spec, stressed(form), template: templates[(i + 2) % templates.count], kind: "stress mark")
                    add(spec, form.uppercased(), template: "ГЛАВА ТРЕТЬЯ. {X}", kind: "capitals")
                }
            }
        }
        return out
    }

    /// A combining acute accent after the first vowel (Анна́).
    static func stressed(_ form: String) -> String {
        var out = ""
        var done = false
        for ch in form {
            out.append(ch)
            if !done, "аеёиоуыэюяАЕЁИОУЫЭЮЯ".contains(ch) { out.append("\u{0301}"); done = true }
        }
        return out
    }

    struct Report {
        var name: String
        var positives = 0
        var found = 0
        var missed: [String] = []
        var missedByKind: [String: Int] = [:]
        var totalByKind: [String: Int] = [:]
        var foundByCategory: [String: (found: Int, total: Int)] = [:]
        var crossTalk: [String] = []
        var distractorHits: [String] = []
        var commonWordHits: [String] = []
        var proseHits: [String] = []
        var ambiguousHits = 0
        var ambiguousTotal = 0
        var initialCapitalHits = 0
        var seconds = 0.0
    }

    static func evaluate(_ name: String, positivesOf: [Spec] = specs, entrySpecs: [Spec] = specs, extraCommonWords: [(target: String, words: String)] = [],
                         _ build: ([NameEntry]) -> NameMatcher) -> Report {
        let started = Date()
        let matcher = build(entrySpecs.map { NameEntry(id: $0.id, name: $0.name) })
        let truth: [String: Set<String>] = Dictionary(uniqueKeysWithValues: entrySpecs.map { spec in
            (spec.id, Set(spec.forms.map { Words.split($0).map(\.folded).joined(separator: " ") }))
        })
        var report = Report(name: name)
        for p in positives(of: positivesOf) {
            let matches = matcher.matches(in: p.sentence)
            report.positives += 1
            report.totalByKind[p.kind, default: 0] += 1
            var cat = report.foundByCategory[p.category] ?? (0, 0)
            cat.total += 1
            if matches.contains(where: { $0.entry == p.id && $0.words == p.start..<(p.start + p.count) }) {
                report.found += 1
                cat.found += 1
            } else {
                report.missed.append("\(p.id): \(p.form)  (\(p.kind))")
                report.missedByKind[p.kind, default: 0] += 1
            }
            report.foundByCategory[p.category] = cat
            let words = Words.split(p.sentence)
            for m in matches where m.entry != p.id {
                let text = words[m.words].map(\.folded).joined(separator: " ")
                if truth[m.entry]?.contains(text) != true { report.crossTalk.append("\(p.form) → \(m.entry)") }
            }
        }
        for d in negatives.distractors {
            let hit = matcher.matches(in: d.sentence).contains { $0.entry == d.target }
            if hit {
                if d.kind == "distractor" { report.distractorHits.append("\(d.target) ← \(d.word)") }
                else { report.commonWordHits.append("\(d.target) ← \(d.word)") }
            }
        }
        for extra in extraCommonWords {
            for word in extra.words.split(separator: " ") {
                for sentence in ["Вчера вечером он долго говорил о \(word) со всеми.", "Потом они искали \(word) в толпе."] {
                    if matcher.matches(in: sentence).contains(where: { $0.entry == extra.target }) { report.commonWordHits.append("\(extra.target) ← \(word)") }
                }
            }
        }
        for a in negatives.ambiguous {
            report.ambiguousTotal += 1
            if matcher.matches(in: a.sentence).contains(where: { $0.entry == a.target }) { report.ambiguousHits += 1 }
        }
        for sentence in prose {
            let words = Words.split(sentence.text)
            for m in matcher.matches(in: sentence.text) where m.entry != "доктор" { // a common noun that is an alias really occurs in prose
                if m.words.lowerBound == 0 { report.initialCapitalHits += 1 }
                else { report.proseHits.append("\(m.entry) ← \(words[m.words].map(\.text).joined(separator: " ")) in «\(sentence.text)»") }
            }
        }
        report.seconds = Date().timeIntervalSince(started)
        return report
    }

    static func print(_ r: Report) {
        let percent = { (a: Int, b: Int) in b == 0 ? "-" : String(format: "%.1f%%", Double(a) * 100 / Double(b)) }
        Swift.print("""
        NAMES \(r.name.padding(toLength: 9, withPad: " ", startingAt: 0)) found \(r.found)/\(r.positives) (\(percent(r.found, r.positives)))  \
        wrong-name hits \(r.crossTalk.count)  look-alike hits \(r.distractorHits.count)  common-word hits \(r.commonWordHits.count)  \
        prose false hits \(r.proseHits.count) (+\(r.initialCapitalHits) at a capitalised sentence start)  ambiguous \(r.ambiguousHits)/\(r.ambiguousTotal)  \(String(format: "%.1f", r.seconds)) s
        """)
        let cats = r.foundByCategory.sorted { $0.key < $1.key }.map { "\($0.key) \(percent($0.value.found, $0.value.total))" }.joined(separator: ", ")
        Swift.print("NAMES   by kind of name: \(cats)")
        let kinds = r.totalByKind.sorted { $0.key < $1.key }.map { "\($0.key) \(percent($0.value - (r.missedByKind[$0.key] ?? 0), $0.value))" }.joined(separator: ", ")
        Swift.print("NAMES   by spelling: \(kinds)")
    }

    // MARK: The measurement

    @Test("the answer key is sound: no look-alike is secretly a form of its target")
    func answerKeyIsSound() {
        for d in Self.negatives.distractors where d.kind == "distractor" {
            #expect(Self.truth[d.target]?.contains(Words.fold(d.word)) != true, "\(d.word) is a form of \(d.target)")
        }
        #expect(Self.specs.count >= 90)
        #expect(Self.positives().count > 900)
        for spec in Self.specs { #expect(spec.forms.count >= 1) }
    }

    @Test("held-out names, written before the rule was run on them: the same four matchers, all names in one book")
    func heldOut() {
        let all = Self.specs + Self.heldOut
        let extra: [(target: String, words: String)] = [
            ("Роман", "роман романа роману романом романе романы"), ("Вена", "вена вены вену веной вене"),
            ("Белый", "белый белого белому белым белом белая"), ("Лука", "лука луки луке луку"), ("Тихон", "тихо тихий тихая"),
            ("Ян", "яна"), ("Тула", "тула"), ("Нева", "нева"), ("Кира", "кира"), ("Алла", "алла"),
        ]
        let reports = [
            Self.evaluate("old rule", positivesOf: Self.heldOut, entrySpecs: all, extraCommonWords: extra, { StemMatcher(entries: $0) }),
            Self.evaluate("paradigm", positivesOf: Self.heldOut, entrySpecs: all, extraCommonWords: extra, { ParadigmMatcher(entries: $0) }),
            Self.evaluate("lemma", positivesOf: Self.heldOut, entrySpecs: all, extraCommonWords: extra, { LemmaMatcher(entries: $0) }),
            Self.evaluate("hybrid", positivesOf: Self.heldOut, entrySpecs: all, extraCommonWords: extra, { HybridMatcher(entries: $0) }),
        ]
        for r in reports {
            Swift.print("HELD-OUT ----------------------------------------------")
            Self.print(r)
            Swift.print("NAMES \(r.name): first misses: \(r.missed.prefix(14).joined(separator: "; "))")
            Swift.print("NAMES \(r.name): wrong-name hits: \(Array(Set(r.crossTalk)).sorted().prefix(8).joined(separator: "; "))")
            Swift.print("NAMES \(r.name): common-word hits: \(r.commonWordHits.prefix(8).joined(separator: "; "))")
        }
        #expect(reports.count == 4)
    }

    @Test("the four matchers on the same data")
    func compare() {
        let reports = [
            Self.evaluate("old rule", { StemMatcher(entries: $0) }),
            Self.evaluate("paradigm", { ParadigmMatcher(entries: $0) }),
            Self.evaluate("lemma", { LemmaMatcher(entries: $0) }),
            Self.evaluate("hybrid", { HybridMatcher(entries: $0) }),
        ]
        for r in reports { Self.print(r) }
        for r in reports {
            Swift.print("NAMES \(r.name): first misses: \(r.missed.prefix(12).joined(separator: "; "))")
            Swift.print("NAMES \(r.name): wrong-name hits: \(Array(Set(r.crossTalk)).sorted().prefix(10).joined(separator: "; "))")
            Swift.print("NAMES \(r.name): look-alike hits: \(r.distractorHits.prefix(12).joined(separator: "; "))")
            Swift.print("NAMES \(r.name): common-word hits: \(r.commonWordHits.prefix(12).joined(separator: "; "))")
            Swift.print("NAMES \(r.name): prose hits: \(r.proseHits.prefix(5).joined(separator: " | "))")
        }
        #expect(reports.count == 4)
    }

    // MARK: A capital letter at the start of a sentence

    @Test("the spell checker flags the names that are also ordinary words")
    @MainActor
    func ordinaryWords() {
        let dictionary = Uncertainty.Dictionary()
        let all = Self.specs + Self.heldOut
        var flagged: [String] = []
        for spec in all {
            let ordinary = spec.forms.filter { form in
                Words.split(form).count == 1 && dictionary.isOrdinaryWord(Words.fold(form).replacingOccurrences(of: "е", with: "е"))
            }
            if !ordinary.isEmpty { flagged.append("\(spec.id): \(ordinary.joined(separator: " "))") }
        }
        Swift.print("NAMES also ordinary words (lowercase form accepted by the spell checker): \(flagged.count) of \(all.count): \(flagged.joined(separator: "; "))")

        // The prose: what happens to the hits at a capitalised sentence start.
        let matcher = ParadigmMatcher(entries: all.map { NameEntry(id: $0.id, name: $0.name) })
        var initial = 0, flaggedInitial = 0, unflagged: [String] = []
        for sentence in Self.prose {
            let words = Words.split(sentence.text)
            for m in matcher.matches(in: sentence.text) where m.entry != "доктор" && m.words.lowerBound == 0 {
                initial += 1
                let folded = words[m.words].map(\.folded).joined(separator: " ")
                if dictionary.isOrdinaryWord(folded) { flaggedInitial += 1 } else { unflagged.append("\(m.entry) ← \(folded)") }
            }
        }
        Swift.print("NAMES prose hits at a sentence start: \(initial); flagged uncertain by the spell checker: \(flaggedInitial); NOT flagged: \(unflagged.count) \(Array(Set(unflagged)).sorted().prefix(10))")

        // The positives that start a sentence: how many true names would be called uncertain.
        var startTotal = 0, startUncertain: [String] = []
        for spec in all {
            for form in spec.forms where Words.split(form).count == 1 {
                startTotal += 1
                if dictionary.isOrdinaryWord(Words.fold(form)) { startUncertain.append(form) }
            }
        }
        Swift.print("NAMES true names at a sentence start that would be called uncertain: \(startUncertain.count) of \(startTotal) forms: \(Array(Set(startUncertain)).sorted().prefix(20))")
        #expect(true)
    }

    // MARK: What the chosen method must keep achieving

    @Test("the rules (the chosen method): every form of the first set, almost every form of the unseen set, no false hits")
    func chosenMethodMeetsTheBar() {
        let first = Self.evaluate("paradigm", { ParadigmMatcher(entries: $0) })
        #expect(first.found == first.positives, "first set: missed \(first.missed.prefix(5))")
        #expect(first.crossTalk.isEmpty && first.distractorHits.isEmpty && first.commonWordHits.isEmpty && first.proseHits.isEmpty)

        let all = Self.specs + Self.heldOut
        let held = Self.evaluate("paradigm", positivesOf: Self.heldOut, entrySpecs: all, { ParadigmMatcher(entries: $0) })
        #expect(Double(held.found) / Double(held.positives) >= 0.99, "unseen set: missed \(held.missed.prefix(8))")
        #expect(held.crossTalk.isEmpty && held.distractorHits.isEmpty && held.commonWordHits.isEmpty && held.proseHits.isEmpty)
        // The only misses are names whose stem changes in a way no rule shows (Египет -> Египта): an alias covers them.
        #expect(Set(held.missed.map { $0.components(separatedBy: ":")[0] }) == ["Египет"], "\(held.missed)")
    }

    @Test("an alias covers a name the rules cannot decline (Египет → Египта)")
    func aliasCoversIrregular() {
        func found(_ form: String, _ matcher: ParadigmMatcher) -> Bool {
            matcher.matches(in: "Они часто думали о \(form) зимой.").contains { $0.entry == "egypt" }
        }
        let without = ParadigmMatcher(entries: [NameEntry(id: "egypt", name: "Египет")])
        #expect(found("Египет", without))
        #expect(!found("Египта", without), "the vanishing vowel cannot be derived")
        #expect(!found("Египте", without))
        // The alias is the changed stem as a nominative (Египт); the rules decline it, so one alias covers every form.
        let with = ParadigmMatcher(entries: [NameEntry(id: "egypt", name: "Египет", aliases: ["Египт"])])
        for form in ["Египет", "Египта", "Египту", "Египтом", "Египте"] { #expect(found(form, with), "\(form)") }
        // An alias that is already a declined form (Египта) is declined again as if it were a name, and misses forms.
        let wrong = ParadigmMatcher(entries: [NameEntry(id: "egypt", name: "Египет", aliases: ["Египта"])])
        #expect(!found("Египтом", wrong), "advice for the author: give Египт, not Египта")
    }

    @Test("a book-sized text is searched for 216 names quickly")
    func speed() {
        let all = Self.specs + Self.heldOut
        let matcher = ParadigmMatcher(entries: all.map { NameEntry(id: $0.id, name: $0.name) })
        let text = Self.prose.map(\.text).joined(separator: " ")
        let started = Date()
        let matches = matcher.matches(in: text)
        let seconds = Date().timeIntervalSince(started)
        Swift.print("NAMES SPEED: \(text.count) characters, 216 names, \(matches.count) matches, \(Int(seconds * 1000)) ms")
        #expect(seconds < 5)
    }

    @Test("a multiword name, a hyphenated name, stress marks, capitals and all the forms of a name with an alias")
    func shapesOfNames() {
        let matcher = ParadigmMatcher(entries: [
            NameEntry(id: "anna", name: "Анна Петровна", aliases: ["Аня", "доктор"]),
            NameEntry(id: "ny", name: "Нью-Йорк"),
        ])
        func found(_ text: String) -> [String] { matcher.matches(in: text).map(\.entry).sorted() }
        #expect(found("Он говорил с Анной Петровной вчера.") == ["anna"])
        #expect(found("Он говорил с Анной вчера.") == [], "the first name alone is not the full name; an alias would cover it")
        #expect(found("Он говорил с Аней вчера.") == ["anna"])
        #expect(found("Он видел доктора и Доктор ответил.").count == 2, "an alias in lowercase matches in any case")
        #expect(found("Они жили в Нью-Йорке много лет.") == ["ny"])
        #expect(found("Она́ сказала Ане́.") == ["anna"], "stress marks are ignored")
        #expect(found("АНЯ ВЕРНУЛАСЬ.") == ["anna"], "capitals")
        #expect(found("мы говорили с аней.") == [], "a name written in lowercase is not the name")
    }
}
