import Foundation
import Testing
@testable import QuillandCore

/// Experiment 1: the Markdown round trip. See quilland-spike-plan.md.
@Suite("Markdown round trip")
struct RoundTripTests {

    // MARK: The corpus

    @Test("canonical files come back byte for byte (file -> model -> file)")
    func canonicalThroughModel() {
        var failures: [String] = []
        let files = Corpus.files("canonical", suffix: ".md")
        for url in files {
            let text = Corpus.read(url)
            let (out, report) = MarkdownWriter.writeWithReport(MarkdownParser.parse(text))
            if out != text || !report.simplified.isEmpty {
                failures.append("\(url.lastPathComponent): \(describeDifference(text, out)); simplified blocks \(report.simplified)")
            }
        }
        #expect(files.count >= 40, "the corpus is missing")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("canonical files come back byte for byte through the editor's styled text")
    func canonicalThroughEditor() {
        var failures: [String] = []
        for url in Corpus.files("canonical", suffix: ".md") {
            let text = Corpus.read(url)
            let styled = AttributedBridge.attributedString(from: MarkdownParser.parse(text))
            let out = MarkdownWriter.write(AttributedBridge.document(from: styled))
            if out != text { failures.append("\(url.lastPathComponent): \(describeDifference(text, out))") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("files that are not canonical are read and come back canonical, and stay so")
    func nonCanonical() {
        var failures: [String] = []
        let inputs = Corpus.files("noncanonical", suffix: ".in.md")
        for url in inputs {
            let name = url.lastPathComponent.replacingOccurrences(of: ".in.md", with: "")
            let expected = Corpus.read(url.deletingLastPathComponent().appendingPathComponent("\(name).out.md"))
            let out = MarkdownWriter.write(MarkdownParser.parse(Corpus.read(url)))
            if out != expected { failures.append("\(name): \(describeDifference(expected, out))") }
            let again = MarkdownWriter.write(MarkdownParser.parse(out))
            if again != out { failures.append("\(name): not stable when written twice: \(describeDifference(out, again))") }
        }
        #expect(inputs.count >= 20, "the corpus is missing")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // MARK: Random input

    @Test("20,000 realistic documents: written and read back identical; styling simplified only very rarely, never text")
    func realisticDocuments() {
        var rng = SplitMix64(seed: 20_261_004)
        var problems: [String] = []
        var simplified = 0
        var blocks = 0
        for _ in 0..<20_000 {
            let model = Normalizer.normalize(Fuzz.realisticDocument(&rng))
            let (text, report) = MarkdownWriter.writeWithReport(model)
            blocks += model.blocks.count
            simplified += report.simplified.count
            let back = MarkdownParser.parse(text)
            if report.simplified.isEmpty {
                if !sameDocument(back, model) {
                    if problems.count < 10 { problems.append("changed: \(text.debugDescription): \(compact(model)) became \(compact(back))") }
                }
            } else if unstyled(back) != unstyled(model) {
                if problems.count < 10 { problems.append("TEXT LOST: \(text.debugDescription) from \(compact(model))") }
            }
            if MarkdownWriter.write(back) != text {
                if problems.count < 10 { problems.append("not stable: \(text.debugDescription)") }
            }
            if AttributedBridge.document(from: AttributedBridge.attributedString(from: model)) != model {
                if problems.count < 10 { problems.append("changed by the editor's styled text: \(compact(model))") }
            }
        }
        print("REALISTIC: \(simplified) of \(blocks) blocks needed their styling simplified (\(String(format: "%.3f", Double(simplified) * 100 / Double(blocks))) %)")
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
        #expect(Double(simplified) / Double(blocks) < 0.001)
    }

    @Test("20,000 adversarial documents (no spaces, many stars): never wrong, never text lost, simplification reported")
    func adversarialDocuments() {
        var rng = SplitMix64(seed: 20_261_003)
        var simplified = 0
        var total = 0
        var wrong: [String] = []
        for _ in 0..<20_000 {
            let model = Normalizer.normalize(Fuzz.document(&rng))
            let (text, report) = MarkdownWriter.writeWithReport(model)
            total += model.blocks.count
            simplified += report.simplified.count
            let back = MarkdownParser.parse(text)
            if report.simplified.isEmpty {
                if !sameDocument(back, model) {
                    if wrong.count < 10 { wrong.append("\(text.debugDescription): \(compact(model)) became \(compact(back))") }
                }
            } else if unstyled(back) != unstyled(model) {
                if wrong.count < 10 { wrong.append("TEXT LOST: \(text.debugDescription) from \(compact(model))") }
            }
            if MarkdownWriter.write(back) != text {
                if wrong.count < 10 { wrong.append("not stable: \(text.debugDescription)") }
            }
        }
        print("ADVERSARIAL: \(simplified) of \(total) blocks needed their styling simplified (\(String(format: "%.2f", Double(simplified) * 100 / Double(total))) %)")
        #expect(wrong.isEmpty, "\(wrong.joined(separator: "\n"))")
        #expect(Double(simplified) / Double(total) < 0.05)
    }

    @Test("20,000 random texts: nothing is lost, and the result is stable")
    func randomSources() {
        var rng = SplitMix64(seed: 77)
        var failures: [String] = []
        var simplified = 0
        for _ in 0..<20_000 {
            let source = Fuzz.source(&rng)
            let first = MarkdownParser.parse(source)
            let (text, report) = MarkdownWriter.writeWithReport(first)
            simplified += report.simplified.count
            let second = MarkdownParser.parse(text)
            if report.simplified.isEmpty ? !sameDocument(second, first) : unstyled(second) != unstyled(first) {
                if failures.count < 10 { failures.append("\(source.debugDescription) -> \(text.debugDescription): \(compact(first)) vs \(compact(second))") }
            } else if MarkdownWriter.write(second) != text {
                if failures.count < 10 { failures.append("not stable: \(source.debugDescription)") }
            }
        }
        print("RANDOM TEXTS: \(simplified) blocks simplified")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // MARK: Speed

    @Test("a book of 300,000 characters is read and written quickly")
    func speed() {
        let scene = Corpus.read(Corpus.files("canonical", suffix: "43-realistic-scene.md").first!)
        let book = String(repeating: scene + "\n", count: 500)
        let started = Date()
        let document = MarkdownParser.parse(book)
        let parsed = Date()
        let text = MarkdownWriter.write(document)
        let done = Date()
        print("SPEED: \(book.count) characters; read \(Int(parsed.timeIntervalSince(started) * 1000)) ms, write \(Int(done.timeIntervalSince(parsed) * 1000)) ms")
        #expect(!text.isEmpty)
        #expect(done.timeIntervalSince(started) < 5, "slow")
    }
}
