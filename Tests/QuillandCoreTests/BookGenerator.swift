import Foundation
@testable import QuillandCore

/// A made-up book on disk, the size of a novel: 4 parts, 5 chapters each, 5 scenes each (100 scenes, about 500,000
/// characters), and 30 characters whose names come up in the text in all their case forms.
struct GeneratedBook {
    struct Character { var id: String; var name: String; var forms: [String]; var aliases: [String] }

    let root: URL
    var sceneIDs: [String] = []
    var sceneFiles: [String] = []          // paths relative to the book, without extension
    var characters: [Character] = []

    static let nouns = ["дорога", "река", "ветер", "лес", "дом", "окно", "письмо", "ночь", "город", "камень", "огонь", "море", "тропа", "мост", "стена",
                        "голос", "тень", "свет", "дверь", "рука", "дождь", "снег", "поле", "гора", "небо", "улица", "площадь", "вокзал", "корабль", "книга"]
    static let adjectives = ["тёмный", "долгий", "тихий", "холодный", "старый", "далёкий", "горячий", "пустой", "узкий", "светлый", "мокрый", "тяжёлый"]
    static let verbs = ["шёл", "говорил", "смотрел", "ждал", "молчал", "вспоминал", "искал", "слушал", "думал", "видел", "помнил", "боялся"]
    static let glue = ["и", "но", "потом", "тогда", "однако", "снова", "вдруг", "всё же", "наконец"]
    static let tails = ["у самой воды", "на краю города", "в этот час", "после долгой зимы", "за соседней дверью", "перед рассветом", "без единого слова"]

    static func sentence(_ rng: inout SplitMix64, names: [Character]) -> String {
        func pick(_ array: [String]) -> String { array.randomElement(using: &rng)! }
        var parts: [String] = []
        if Int.random(in: 0..<7, using: &rng) == 0, let c = names.randomElement(using: &rng) {
            parts.append(c.forms.randomElement(using: &rng)!)
            parts.append(pick(verbs))
        } else {
            parts.append(pick(adjectives).capitalizedFirst + " " + pick(nouns))
            parts.append(pick(verbs))
        }
        for _ in 0..<Int.random(in: 1...3, using: &rng) {
            parts.append(pick(glue))
            parts.append(pick(adjectives) + " " + pick(nouns))
            if Int.random(in: 0..<3, using: &rng) == 0 { parts.append(pick(tails)) }
        }
        var text = parts.joined(separator: " ")
        if Int.random(in: 0..<25, using: &rng) == 0 { text = text.replacingOccurrences(of: pick(nouns), with: "*" + pick(nouns) + "*") }
        if Int.random(in: 0..<60, using: &rng) == 0 { text += "^[Так тогда говорили.]" }
        if Int.random(in: 0..<80, using: &rng) == 0 { text += " Ёлка стояла у окна." }
        return text + "."
    }

    static func scene(_ rng: inout SplitMix64, names: [Character], sentences: Int = 66) -> String {
        var paragraphs: [String] = []
        var left = sentences
        while left > 0 {
            let n = min(left, Int.random(in: 3...6, using: &rng))
            paragraphs.append((0..<n).map { _ in sentence(&rng, names: names) }.joined(separator: " "))
            left -= n
        }
        return paragraphs.joined(separator: "\n\n") + "\n"
    }

    init(in root: URL, seed: UInt64 = 1, sentencesPerScene: Int = 66) throws {
        self.root = root
        var rng = SplitMix64(seed: seed)
        let fm = FileManager.default
        let specs = NameTests.specs.filter { $0.category == "person" }.prefix(30)
        for (i, spec) in specs.enumerated() {
            characters.append(Character(id: UUID().uuidString.lowercased(), name: spec.name, forms: spec.forms, aliases: i % 5 == 0 ? ["Хозяйка"] : []))
        }
        try fm.createDirectory(at: root.appendingPathComponent("bible/characters"), withIntermediateDirectories: true)
        var n = 0
        for part in 1...4 {
            for chapter in 1...5 {
                let dir = String(format: "manuscript/%03d-part/%03d-chapter", part, chapter)
                try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
                for scene in 1...5 {
                    n += 1
                    let base = dir + String(format: "/%03d-scene", scene)
                    let id = UUID().uuidString.lowercased()
                    let object: JSONObject = ["id": .string(id), "status": .string("draft"), "title": .string("Сцена \(n)")]
                    try JSONWriter.data(object).write(to: root.appendingPathComponent(base + ".json"))
                    try Data(Self.scene(&rng, names: characters, sentences: sentencesPerScene).utf8).write(to: root.appendingPathComponent(base + ".md"))
                    sceneIDs.append(id)
                    sceneFiles.append(base)
                }
            }
        }
        for (i, c) in characters.enumerated() {
            var record = CharacterRecord(object: [:])
            record.id = c.id
            record.name = c.name
            record.aliases = c.aliases
            record.notes = ["Любит \(GeneratedBook.nouns[i % GeneratedBook.nouns.count]) и не любит дождь."]
            record.povScenes = [sceneIDs[i], sceneIDs[i + 30]]
            var links: [String: String] = [:]
            links[characters[(i + 1) % 30].id] = "Знакомы с детства."
            links[characters[(i + 7) % 30].id] = "Спорили о наследстве."
            record.links = links
            try JSONWriter.data(record.object).write(to: root.appendingPathComponent("bible/characters/\(c.id).json"))
            try Data("Длинное описание героя \(c.name).\n".utf8).write(to: root.appendingPathComponent("bible/characters/\(c.id).md"))
        }
    }

    func path(_ relative: String) -> URL { root.appendingPathComponent(relative) }
    var entries: [NameEntry] { characters.map { NameEntry(id: $0.id, name: $0.name, aliases: $0.aliases) } }

    var totalCharacters: Int {
        sceneFiles.reduce(0) { $0 + TextStats.count(MarkdownParser.parse(Corpus.read(path($1 + ".md")))).characters }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
