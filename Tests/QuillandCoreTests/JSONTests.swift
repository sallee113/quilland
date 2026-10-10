import Foundation
import Testing
@testable import QuillandCore

/// Experiment 2: JSON files that never lose data.
@Suite("JSON files")
struct JSONTests {

    // MARK: The corpus

    @Test("22 canonical files come back byte for byte (read, then write)")
    func canonicalFiles() throws {
        var failures: [String] = []
        let files = Corpus.files("json/canonical", suffix: ".json")
        for url in files {
            let data = try Data(contentsOf: url)
            let written = JSONWriter.data(try JSONParser.parseObject(data))
            if written != data {
                failures.append("\(url.lastPathComponent): \(describeDifference(String(decoding: data, as: UTF8.self), String(decoding: written, as: UTF8.self)))")
            }
        }
        #expect(files.count >= 22, "the corpus is missing")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("untidy files are read and come back canonical, and stay so")
    func nonCanonicalFiles() throws {
        var failures: [String] = []
        let inputs = Corpus.files("json/noncanonical", suffix: ".in.json")
        for url in inputs {
            let name = url.lastPathComponent.replacingOccurrences(of: ".in.json", with: "")
            let expected = Corpus.read(url.deletingLastPathComponent().appendingPathComponent("\(name).out.json"))
            let out = JSONWriter.write(try JSONParser.parseObject(try Data(contentsOf: url)))
            if out != expected { failures.append("\(name): \(describeDifference(expected, out))") }
            if JSONWriter.write(try JSONParser.parseObject(Data(out.utf8))) != out { failures.append("\(name): not stable") }
        }
        #expect(inputs.count >= 14, "the corpus is missing")
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("invalid files are refused, with the place of the fault")
    func invalidFiles() throws {
        var accepted: [String] = []
        var noPlace: [String] = []
        let files = Corpus.files("json/invalid", suffix: ".json")
        for url in files {
            do {
                _ = try JSONParser.parseObject(try Data(contentsOf: url))
                accepted.append(url.lastPathComponent)
            } catch let error as JSONError {
                if error.line < 1 || error.column < 1 { noPlace.append(url.lastPathComponent) }
            }
        }
        #expect(files.count >= 31, "the corpus is missing")
        #expect(accepted.isEmpty, "wrongly accepted: \(accepted)")
        #expect(noPlace.isEmpty, "no place given: \(noPlace)")
    }

    // MARK: Random values

    @Test("20,000 random values: write, read, the same; written again, the same bytes")
    func randomValues() throws {
        var rng = SplitMix64(seed: 2026)
        var problems: [String] = []
        for _ in 0..<20_000 {
            let value = JSONFuzz.object(&rng)
            let text = JSONWriter.write(value)
            let back = try JSONParser.parseObject(Data(text.utf8))
            if back != value {
                if problems.count < 5 { problems.append("changed: \(text.debugDescription)") }
            } else if JSONWriter.write(back) != text {
                if problems.count < 5 { problems.append("not stable: \(text.debugDescription)") }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    @Test("20,000 random values written in other styles are read to the same value and rewritten canonically")
    func randomStyles() throws {
        var rng = SplitMix64(seed: 99)
        var problems: [String] = []
        for _ in 0..<20_000 {
            let value = JSONFuzz.object(&rng)
            let style = JSONFuzz.Style.random(&rng)
            let text = JSONFuzz.render(.object(value), style: style, indent: 0, rng: &rng)
            do {
                let back = try JSONParser.parseObject(Data(text.utf8))
                if back != value {
                    if problems.count < 5 { problems.append("changed: \(text.debugDescription)") }
                } else if JSONWriter.write(back) != JSONWriter.write(value) {
                    if problems.count < 5 { problems.append("not canonical: \(text.debugDescription)") }
                }
            } catch {
                if problems.count < 5 { problems.append("refused \(error): \(text.debugDescription)") }
            }
        }
        #expect(problems.isEmpty, "\(problems.joined(separator: "\n"))")
    }

    // MARK: Speed

    @Test("a timeline of 5,000 entries and a character with 3,000 links")
    func speed() throws {
        var entries: [JSONValue] = []
        for i in 0..<5_000 {
            entries.append(.object(["event": .string(UUID().uuidString.lowercased()), "lane": .string("lane"), "start": .int(i * 100), "x_future": .object(["a": .int(i)])]))
        }
        let timeline: JSONObject = ["entries": .array(entries), "lanes": .array([])]
        var links: [String: JSONValue] = [:]
        for _ in 0..<3_000 { links[UUID().uuidString.lowercased()] = .string("Описание связи с коротким текстом.") }
        let character: JSONObject = ["id": .string("x"), "links": .object(links), "name": .string("Анна")]
        let started = Date()
        let timelineText = JSONWriter.data(timeline)
        let characterText = JSONWriter.data(character)
        let written = Date()
        let timelineBack = try JSONParser.parseObject(timelineText)
        let characterBack = try JSONParser.parseObject(characterText)
        let done = Date()
        print("JSON SPEED: write \(Int(written.timeIntervalSince(started) * 1000)) ms, read \(Int(done.timeIntervalSince(written) * 1000)) ms; timeline \(timelineText.count / 1024) KB, character \(characterText.count / 1024) KB")
        #expect(timelineBack == timeline)
        #expect(characterBack == character)
        #expect(done.timeIntervalSince(started) < 5)
    }
}

// MARK: Random JSON, and other ways of writing it

enum JSONFuzz {
    static let pieces = ["а", "ё", "й", "Z", "q", " ", "\"", "\\", "/", "\n", "\t", "\u{01}", "\u{7F}", "\u{00A0}", "\u{2028}", "😀", "🇷🇺", "*", "[", "]", "{", "}", ":", ",", "ж", "é"]

    static func string(_ rng: inout SplitMix64, maxLength: Int = 10) -> String {
        let n = Int.random(in: 0...maxLength, using: &rng)
        return (0..<n).map { _ in pieces.randomElement(using: &rng)! }.joined().precomposedStringWithCanonicalMapping
    }

    static func number(_ rng: inout SplitMix64) -> String {
        var text = Bool.random(using: &rng) ? "-" : ""
        text += Bool.random(using: &rng) ? "0" : String(Int.random(in: 1...999_999, using: &rng))
        if Int.random(in: 0..<3, using: &rng) == 0 { text += "." + String(Int.random(in: 0...999, using: &rng)) }
        if Int.random(in: 0..<6, using: &rng) == 0 { text += ["e", "E"].randomElement(using: &rng)! + ["", "+", "-"].randomElement(using: &rng)! + String(Int.random(in: 0...20, using: &rng)) }
        return text
    }

    static func value(_ rng: inout SplitMix64, depth: Int) -> JSONValue {
        let kinds = depth >= 4 ? 4 : 6
        switch Int.random(in: 0..<kinds, using: &rng) {
        case 0: return .null
        case 1: return .bool(Bool.random(using: &rng))
        case 2: return .number(number(&rng))
        case 3: return .string(string(&rng))
        case 4: return .array((0..<Int.random(in: 0...4, using: &rng)).map { _ in value(&rng, depth: depth + 1) })
        default: return .object(object(&rng, depth: depth + 1))
        }
    }

    static func object(_ rng: inout SplitMix64, depth: Int = 0) -> JSONObject {
        var out: JSONObject = [:]
        for _ in 0..<Int.random(in: 0...5, using: &rng) { out[string(&rng, maxLength: 6)] = value(&rng, depth: depth + 1) }
        return out
    }

    /// Ways of writing the same value that a reader must accept.
    struct Style {
        var spaces: Bool
        var newlines: Bool
        var indentWidth: Int
        var shuffleKeys: Bool
        var escapeNonASCII: Bool
        var escapeSlash: Bool
        var crlf: Bool
        static func random(_ rng: inout SplitMix64) -> Style {
            Style(spaces: Bool.random(using: &rng), newlines: Bool.random(using: &rng), indentWidth: [0, 1, 2, 4, 8].randomElement(using: &rng)!,
                  shuffleKeys: Bool.random(using: &rng), escapeNonASCII: Bool.random(using: &rng), escapeSlash: Bool.random(using: &rng), crlf: Bool.random(using: &rng))
        }
    }

    static func render(_ value: JSONValue, style: Style, indent: Int, rng: inout SplitMix64) -> String {
        let nl = style.newlines ? (style.crlf ? "\r\n" : "\n") : ""
        let pad = style.newlines ? String(repeating: " ", count: indent + style.indentWidth) : ""
        let closePad = style.newlines ? String(repeating: " ", count: indent) : ""
        let space = style.spaces ? " " : ""
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .string(let s): return quote(s, style: style)
        case .array(let items):
            if items.isEmpty { return "[]" }
            return "[" + nl + items.map { pad + render($0, style: style, indent: indent + style.indentWidth, rng: &rng) }.joined(separator: "," + nl + (style.newlines ? "" : space)) + nl + closePad + "]"
        case .object(let entries):
            if entries.isEmpty { return "{}" }
            var keys = Array(entries.keys)
            if style.shuffleKeys { keys.shuffle(using: &rng) }
            return "{" + nl + keys.map { pad + quote($0, style: style) + space + ":" + space + render(entries[$0]!, style: style, indent: indent + style.indentWidth, rng: &rng) }
                .joined(separator: "," + nl + (style.newlines ? "" : space)) + nl + closePad + "}"
        }
    }

    static func quote(_ s: String, style: Style) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "/": out += style.escapeSlash ? "\\/" : "/"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04X", scalar.value)
                } else if style.escapeNonASCII, scalar.value > 0x7E {
                    if scalar.value > 0xFFFF {
                        let v = scalar.value - 0x10000
                        out += String(format: "\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF))
                    } else {
                        out += String(format: "\\u%04x", scalar.value)
                    }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
