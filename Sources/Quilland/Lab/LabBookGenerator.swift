import Foundation
import QuillandCore

/// A made-up book for trying the interface at the size of a novel.
enum LabBookGenerator {
    static let nouns = ["дорога", "река", "ветер", "лес", "дом", "окно", "письмо", "ночь", "город", "камень", "огонь", "море", "тропа", "мост", "стена", "голос", "тень", "свет", "дверь", "рука"]
    static let adjectives = ["тёмный", "долгий", "тихий", "холодный", "старый", "далёкий", "горячий", "пустой", "узкий", "светлый"]
    static let verbs = ["шёл", "говорил", "смотрел", "ждал", "молчал", "вспоминал", "искал", "слушал", "думал", "видел"]

    static func sentence(_ rng: inout SystemRandomNumberGenerator) -> String {
        func pick(_ a: [String]) -> String { a.randomElement(using: &rng)! }
        var text = pick(adjectives).prefix(1).uppercased() + pick(adjectives).dropFirst() + " " + pick(nouns) + " " + pick(verbs)
        for _ in 0..<Int.random(in: 1...3, using: &rng) { text += ", и " + pick(adjectives) + " " + pick(nouns) }
        if Int.random(in: 0..<20, using: &rng) == 0 { text = text.replacingOccurrences(of: pick(nouns), with: "*" + pick(nouns) + "*") }
        return text + "."
    }

    /// Writes `scenes` scenes in 4 parts of chapters of 5 scenes.
    static func generate(into folder: URL, scenes: Int = 100, sentences: Int = 66) throws {
        var rng = SystemRandomNumberGenerator()
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONWriter.data(["format": .int(1), "id": .string(UUID().uuidString.lowercased()), "language": .string("ru"), "title": .string("Большая книга")]).write(to: folder.appendingPathComponent("book.json"))
        var n = 0
        var part = 0
        while n < scenes {
            part += 1
            let partDir = folder.appendingPathComponent(String(format: "manuscript/%03d-part", part))
            try fm.createDirectory(at: partDir, withIntermediateDirectories: true)
            try JSONWriter.data(["id": .string(UUID().uuidString.lowercased()), "title": .string("Часть \(part)")]).write(to: partDir.appendingPathComponent("_part.json"))
            for chapter in 1...5 where n < scenes {
                let dir = partDir.appendingPathComponent(String(format: "%03d-chapter", chapter))
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try JSONWriter.data(["id": .string(UUID().uuidString.lowercased()), "title": .string("Глава \(chapter)")]).write(to: dir.appendingPathComponent("_chapter.json"))
                for scene in 1...5 where n < scenes {
                    n += 1
                    let base = dir.appendingPathComponent(String(format: "%03d-scene", scene))
                    let status = ["idea", "draft", "revised", "done"][n % 4]
                    try JSONWriter.data(["id": .string(UUID().uuidString.lowercased()), "status": .string(status), "title": .string("Сцена \(n)")]).write(to: base.appendingPathExtension("json"))
                    var paragraphs: [String] = []
                    var left = sentences
                    while left > 0 {
                        let count = min(left, Int.random(in: 3...6, using: &rng))
                        paragraphs.append((0..<count).map { _ in sentence(&rng) }.joined(separator: " "))
                        left -= count
                    }
                    try Data((paragraphs.joined(separator: "\n\n") + "\n").utf8).write(to: base.appendingPathExtension("md"))
                }
            }
        }
    }
}
