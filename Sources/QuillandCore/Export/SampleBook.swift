import Foundation
import CoreGraphics
import CoreText
import ImageIO

/// A small book written to disk for the export experiment: two parts, a loose chapter, an epigraph, a letter,
/// verse, footnotes, bold and italic, typed headings, scene breaks, a cover.
public enum SampleBook {
    public static let title = "Дом на Сосновой"
    public static let author = "Вадим Сульянов"

    struct Scene { var title: String; var status: String; var tags: [String]; var text: String }
    struct Chapter { var title: String; var own: String?; var scenes: [Scene] }
    struct Part { var title: String; var own: String?; var chapters: [Chapter] }

    static let parts: [Part] = [
        Part(title: "Дорога", own: """
            > Дорога не спрашивает, куда ты идёшь.
            >
            > — Народная мудрость
            """, chapters: [
            Chapter(title: "Станция", own: nil, scenes: [
                Scene(title: "Платформа", status: "done", tags: ["arrival"], text: """
                    Поезд ушёл, и на платформе осталась одна **Анна** с чемоданом, который был тяжелее, чем она ожидала.^[Чемодан достался ей от матери и пах нафталином.] Вокруг не было ни души, только ветер перебирал на столбе обрывки старых объявлений.

                    Она прочитала название станции вслух — «Сосновая» — и удивилась, как *тихо* оно прозвучало. Название было длиннее, чем сама станция.

                    — Вы к Вере Павловне? — спросил кто-то за спиной.

                    Анна обернулась. На скамейке сидел старик в фуражке и смотрел так, словно ждал её уже много лет.
                    """),
                Scene(title: "Письмо", status: "revised", tags: ["letter"], text: """
                    В кармане пальто лежал конверт, который она так и не решилась открыть в поезде. Теперь, под единственным фонарём, она разорвала край и достала листок.

                    > Дорогая Анна!
                    >
                    > Если ты читаешь это письмо, значит, дом всё-таки тебя дождался. Ключ лежит под третьей ступенькой, а не под второй, как все думают.
                    >
                    > — Твоя тётя Вера

                    Она перечитала последние строки дважды и сложила листок вчетверо.
                    """),
            ]),
            Chapter(title: "Ключ", own: nil, scenes: [
                Scene(title: "Третья ступенька", status: "draft", tags: [], text: """
                    Ступенек было пять. Анна присела и провела рукой под третьей — дерево было сырым и холодным, а потом пальцы наткнулись на металл.

                    Ключ оказался **тяжёлым** и совсем не старинным: простой, с пластмассовой биркой, на которой выцветшими чернилами было написано одно слово — *«подвал»*.

                    * * *

                    Дом стоял в конце улицы, и его окна, как ей показалось, были освещены изнутри.^[Позже выяснится, что свет шёл от лампы, оставленной на кухне ещё осенью.]
                    """),
                Scene(title: "Стихи на двери", status: "done", tags: ["verse"], text: """
                    На двери кто-то выцарапал гвоздём несколько строк:

                    Сосны шумят над крышей,\\
                    и ветер читает вслух\\
                    всё, что давно не слышно,\\
                    всё, что не сказано вслух.

                    Анна провела пальцем по буквам и почувствовала, что они совсем свежие.
                    """),
            ]),
        ]),
        Part(title: "Дом", own: nil, chapters: [
            Chapter(title: "Лестница", own: nil, scenes: [
                Scene(title: "Первая ночь", status: "revised", tags: ["night"], text: """
                    Первую ночь в доме Анна не спала. Каждая доска на лестнице говорила своим голосом, и к утру она научилась различать их по тону.

                    ## Заметка на полях

                    Тётя Вера вела дневник погоды: «12 марта. Ветер с севера, к вечеру снег». Записи шли без пропусков тридцать один год.

                    Когда за окном посветлело, Анна заметила, что последняя запись сделана **вчера**.
                    """),
            ]),
            Chapter(title: "Подвал", own: "# Подвал, в который не ходят", scenes: [
                Scene(title: "Дверь без ручки", status: "idea", tags: ["cellar"], text: """
                    Ключ с пластмассовой биркой подошёл к двери, у которой не было ручки. Замочная скважина пряталась под отставшей штукатуркой.

                    Внизу пахло квасцами и мокрым камнем. Анна подняла лампу и увидела длинный стол, а на столе — раскрытую книгу, страницы которой шевелились, хотя в подвале не было ни сквозняка, ни окон.
                    """),
                Scene(title: "Книга", status: "idea", tags: ["cellar", "letter"], text: """
                    Книга была написана её собственным почерком. Первая строчка гласила: «Поезд ушёл, и на платформе осталась одна Анна».

                    Она закрыла книгу и поднялась наверх, не оглядываясь.
                    """),
            ]),
        ]),
    ]

    static let epilogue = Chapter(title: "Эпилог", own: "# Эпилог, который можно пропустить", scenes: [
        Scene(title: "Утро", status: "done", tags: [], text: """
            Утром пришёл старик в фуражке и принёс молоко. Он не спросил ни о подвале, ни о книге, и Анна поняла, что остаётся.

            Над крышей шумели сосны.
            """),
    ])

    /// Writes the book into `folder` (which must exist and be empty).
    public static func write(into folder: URL) throws {
        let fm = FileManager.default
        func put(_ path: String, _ text: String) throws {
            let url = folder.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((text.hasSuffix("\n") ? text : text + "\n").utf8).write(to: url)
        }
        func putJSON(_ path: String, _ object: JSONObject) throws {
            let url = folder.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONWriter.data(object).write(to: url)
        }
        func markdown(_ text: String) -> String {
            // Canonical form, so the sample is a file the app itself could have written.
            MarkdownWriter.write(MarkdownParser.parse(text))
        }
        func uuid() -> JSONValue { .string(UUID().uuidString.lowercased()) }

        let coverName = UUID().uuidString.lowercased() + ".png"
        try putJSON("book.json", ["author": .string(author), "copyright": .string("© 2026 \(author)"), "cover": .string(coverName), "format": .int(1),
                                  "id": uuid(), "language": .string("ru"), "title": .string(title)])
        try fm.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try coverPNG(title: title, author: author).write(to: folder.appendingPathComponent("assets/\(coverName)"))

        func writeChapter(_ c: Chapter, dir: String) throws {
            try putJSON("\(dir)/_chapter.json", ["id": uuid(), "title": .string(c.title)])
            if let own = c.own { try put("\(dir)/_chapter.md", markdown(own)) }
            for (i, s) in c.scenes.enumerated() {
                let base = "\(dir)/" + String(format: "%03d-scene", i + 1)
                var object: JSONObject = ["id": uuid(), "status": .string(s.status), "title": .string(s.title)]
                if !s.tags.isEmpty { object["tags"] = .array(s.tags.map { .string($0) }) }
                try putJSON(base + ".json", object)
                try put(base + ".md", markdown(s.text))
            }
        }
        for (pi, part) in parts.enumerated() {
            let dir = "manuscript/" + String(format: "%03d-part", pi + 1)
            try putJSON("\(dir)/_part.json", ["id": uuid(), "title": .string(part.title)])
            if let own = part.own { try put("\(dir)/_part.md", markdown(own)) }
            for (ci, c) in part.chapters.enumerated() { try writeChapter(c, dir: dir + "/" + String(format: "%03d-chapter", ci + 1)) }
        }
        try writeChapter(epilogue, dir: "manuscript/" + String(format: "%03d-chapter", parts.count + 1))

        // Two saved profiles: a manuscript for a publisher and a reading copy.
        let publisher: JSONObject = [
            "cover": .bool(true), "footnotes": .string("page"), "format": .string("docx"),
            "headings": .object([
                "chapter": .object(["new_page": .bool(true), "print": .string("number_and_title"), "template": .string("Глава {number}. {title}")]),
                "part": .object(["new_page": .bool(true), "print": .string("number_and_title"), "template": .string("Часть {number}. {title}")]),
                "scene": .object(["print": .string("none")]),
            ]),
            "name": .string("Publisher DOCX"), "scene_break": .string("mark"), "title_page": .string("auto"), "toc": .bool(true),
        ]
        let reading: JSONObject = [
            "cover": .bool(true), "footnotes": .string("book"), "format": .string("fb2"),
            "headings": .object([
                "chapter": .object(["new_page": .bool(false), "print": .string("title")]),
                "part": .object(["new_page": .bool(false), "print": .string("title")]),
                "scene": .object(["print": .string("none")]),
            ]),
            "name": .string("Reading copy"), "scene_break": .string("mark"), "title_page": .string("auto"), "toc": .bool(true),
        ]
        try putJSON("export.json", ["format": .int(1), "last_profile": .string("Publisher DOCX"), "profiles": .array([.object(publisher), .object(reading)])])
    }

    /// A plain cover: a dark gradient with the title and the author, 800 × 1200 pixels.
    public static func coverPNG(title: String, author: String) -> Data {
        let width = 800, height = 1200
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.10, green: 0.18, blue: 0.16, alpha: 1), CGColor(red: 0.30, green: 0.42, blue: 0.34, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: height), options: [])
        func draw(_ text: String, size: CGFloat, y: CGFloat, bold: Bool) {
            let font = CTFontCreateWithName((bold ? "Georgia-Bold" : "Georgia") as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(red: 0.96, green: 0.93, blue: 0.84, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, [])
            context.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: y)
            CTLineDraw(line, context)
        }
        draw(title, size: 70, y: 700, bold: true)
        draw(author, size: 40, y: 140, bold: false)
        // A few pines.
        context.setFillColor(CGColor(red: 0.05, green: 0.10, blue: 0.08, alpha: 1))
        for i in 0..<7 {
            let x = CGFloat(80 + i * 110), base = CGFloat(300 + (i % 3) * 25)
            for tier in 0..<4 {
                let w = CGFloat(70 - tier * 12), y = base + CGFloat(tier) * 38
                context.move(to: CGPoint(x: x - w / 2, y: y)); context.addLine(to: CGPoint(x: x + w / 2, y: y)); context.addLine(to: CGPoint(x: x, y: y + 60)); context.fillPath()
            }
        }
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
