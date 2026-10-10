import Foundation

// Experiment 7: from a book on disk to the things DOCX and FB2 need.
//
//   book folder --BookLoader--> BookModel --Resolver (profile, filters, numbering)--> Resolved --> DOCX / FB2
//
// Everything that is a decision about the book (which items are in, what each heading says, which typed
// heading wins, what separates scenes) is made once, in the Resolver, so the two formats cannot disagree.

public struct BookModel: Sendable {
    public struct Scene: Sendable { public var id: String; public var title: String; public var status: String?; public var tags: [String]; public var document: Document }
    public struct Chapter: Sendable { public var id: String; public var title: String; public var own: Document?; public var scenes: [Scene] }
    public struct Part: Sendable { public var id: String; public var title: String; public var own: Document?; public var chapters: [Chapter] }
    public enum Item: Sendable { case part(Part), chapter(Chapter) }

    public var id = ""
    public var title = ""
    public var author = ""
    public var copyright = ""
    public var language = ""
    /// The cover image file as it is (PNG or JPEG).
    public var cover: Data?
    /// The author's own title page (the first item of the manuscript), when there is one.
    public var titlePage: Document?
    public var items: [Item] = []
}

public enum BookLoader {
    public struct Failure: Error, CustomStringConvertible { public var description: String }

    private static func json(_ url: URL) throws -> JSONObject {
        do { return try JSONParser.parseObject(Data(contentsOf: url)) } catch { throw Failure(description: "\(url.lastPathComponent): \(error)") }
    }

    private static func document(_ url: URL) -> Document? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return MarkdownParser.parse(String(decoding: data, as: UTF8.self))
    }

    public static func load(folder: URL) throws -> BookModel {
        var book = BookModel()
        let info = try json(folder.appendingPathComponent("book.json"))
        book.id = info.string("id") ?? ""
        book.title = info.string("title") ?? ""
        book.author = info.string("author") ?? ""
        book.copyright = info.string("copyright") ?? ""
        book.language = info.string("language") ?? ""
        if let cover = info.string("cover") { book.cover = try? Data(contentsOf: folder.appendingPathComponent("assets/\(cover)")) }

        let manuscript = folder.appendingPathComponent("manuscript")
        let names = try FileManager.default.contentsOfDirectory(atPath: manuscript.path).sorted()
        for name in names {
            let url = manuscript.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if name == "001-title-page.json" { book.titlePage = document(manuscript.appendingPathComponent("001-title-page.md")) ?? Document() }
            guard isDirectory.boolValue else { continue }
            if name.hasSuffix("-part") {
                let meta = try json(url.appendingPathComponent("_part.json"))
                var part = BookModel.Part(id: meta.string("id") ?? "", title: meta.string("title") ?? "", own: document(url.appendingPathComponent("_part.md")), chapters: [])
                for sub in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() where sub.hasSuffix("-chapter") {
                    part.chapters.append(try chapter(url.appendingPathComponent(sub)))
                }
                book.items.append(.part(part))
            } else if name.hasSuffix("-chapter") {
                book.items.append(.chapter(try chapter(url)))
            }
        }
        return book
    }

    private static func chapter(_ url: URL) throws -> BookModel.Chapter {
        let meta = try json(url.appendingPathComponent("_chapter.json"))
        var chapter = BookModel.Chapter(id: meta.string("id") ?? "", title: meta.string("title") ?? "", own: document(url.appendingPathComponent("_chapter.md")), scenes: [])
        for file in try FileManager.default.contentsOfDirectory(atPath: url.path).sorted() where file.hasSuffix("-scene.json") && !file.hasSuffix(".notes.json") {
            let record = SceneRecord(object: try json(url.appendingPathComponent(file)))
            let md = url.appendingPathComponent(String(file.dropLast(5)) + ".md")
            chapter.scenes.append(BookModel.Scene(id: record.id ?? "", title: record.title ?? "", status: record.status, tags: record.tags, document: document(md) ?? Document()))
        }
        return chapter
    }
}

// MARK: Choices

public struct ExportOptions: Sendable {
    public enum TitlePage: String, Sendable { case auto, manual, none }
    public enum SceneBreak: String, Sendable { case mark, blank, none }
    public enum NumberStyle: String, Sendable { case arabic, roman }

    public var titlePage = TitlePage.auto
    public var toc = true
    /// Scenes are listed in the contents under their chapters (by their titles, even when no heading is printed for them).
    public var tocScenes = false
    public var cover = true
    public var sceneBreak = SceneBreak.mark
    public var numberStyle = NumberStyle.arabic
    public var restartNumberingInParts = false
    public var part = ExportFile.HeadingRule(print: "title", template: nil, newPage: true)
    public var chapter = ExportFile.HeadingRule(print: "number_and_title", template: "{number}. {title}", newPage: true)
    public var scene = ExportFile.HeadingRule(print: "none")
    public var statuses: [String] = []
    public var tags: [String] = []
    /// Scenes the author unticked in the export window (never stored in the profile).
    public var excludedScenes: Set<String> = []
    /// Word asks to refresh the contents when the file is opened (page numbers); Pages shows the stored lines.
    public var refreshContentsInWord = true
    public var layout = Layout()

    public struct Layout: Sendable {
        public var font = "Times New Roman"
        public var halfPoints = 24          // 12 pt
        public var lineSpacing240 = 480     // double
        public var firstLineIndentTwips = 709
        public var pageWidthTwips = 11906   // A4
        public var pageHeightTwips = 16838
        public var marginTwips = 1417       // 2.5 cm
        public init() {}
    }

    public init() {}

    public init(profile: ExportFile.Profile) {
        if let v = profile.titlePage.flatMap(TitlePage.init(rawValue:)) { titlePage = v }
        if let v = profile.sceneBreak.flatMap(SceneBreak.init(rawValue:)) { sceneBreak = v }
        toc = profile.toc ?? true
        tocScenes = profile.tocScenes ?? false
        if let v = profile.numbering.flatMap(NumberStyle.init(rawValue:)) { numberStyle = v }
        restartNumberingInParts = profile.restartInParts ?? false
        cover = profile.cover ?? false
        if let r = profile.headingRule("part") { part = r }
        if let r = profile.headingRule("chapter") { chapter = r }
        if let r = profile.headingRule("scene") { scene = r }
        statuses = profile.statuses
        tags = profile.tags
    }
}

// MARK: Resolving

/// A heading as it will print: the text with its styles, its level (1 part, 2 chapter, 3 scene), and whether a new page starts.
struct RHeading {
    var level: Int
    var inlines: [Inline]
    var newPage: Bool
    /// The author typed it in the text (it wins over the profile's heading).
    var typed: Bool
    var plain: String { Self.plain(inlines) }
    static func plain(_ inlines: [Inline]) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .run(let r): return r.text
            case .note: return ""
            case .lineBreak: return " "
            }
        }.joined()
    }
}

struct RScene { var title: String; var heading: RHeading?; var blocks: [Block] }
struct RChapter { var heading: RHeading?; var own: [Block]; var scenes: [RScene] }
struct RPart { var heading: RHeading?; var own: [Block]; var chapters: [RChapter] }
enum RItem { case part(RPart), chapter(RChapter) }

struct Resolved {
    var title: String
    var author: String
    var copyright: String
    var language: String
    var id: String
    var cover: Data?
    var titlePage: [Block]?
    var items: [RItem]
    var options: ExportOptions
}

enum Resolver {
    static func resolve(_ book: BookModel, options: ExportOptions) -> Resolved {
        var chapterNumber = 0
        var partNumber = 0
        func included(_ scene: BookModel.Scene) -> Bool {
            if options.excludedScenes.contains(scene.id) { return false }
            if !options.statuses.isEmpty, !options.statuses.contains(scene.status ?? "idea") { return false }
            if !options.tags.isEmpty {
                let have = Set(scene.tags.map { $0.lowercased() })
                if !options.tags.contains(where: { have.contains($0.lowercased()) }) { return false }
            }
            return true
        }
        let filtering = !options.statuses.isEmpty || !options.tags.isEmpty || !options.excludedScenes.isEmpty

        func blocks(of document: Document?) -> [Block] {
            (document?.blocks ?? []).filter { if case .fragment = $0 { return false } else { return true } }
        }

        /// The heading of an item: the typed one when the text starts with a heading, else the profile's.
        func heading(level: Int, rule: ExportFile.HeadingRule, title: String, number: Int, own: inout [Block]) -> RHeading? {
            let newPage = rule.newPage ?? false
            if case .heading(_, let inlines)? = own.first {
                own.removeFirst()
                return RHeading(level: level, inlines: inlines, newPage: newPage, typed: true)
            }
            guard let text = headingText(rule: rule, title: title, number: number, style: options.numberStyle) else { return nil }
            return RHeading(level: level, inlines: [.text(text)], newPage: newPage, typed: false)
        }

        func resolveChapter(_ chapter: BookModel.Chapter) -> RChapter? {
            let scenes = chapter.scenes.filter(included)
            if filtering, scenes.isEmpty { return nil }
            chapterNumber += 1
            var own = blocks(of: chapter.own)
            let head = heading(level: 2, rule: options.chapter, title: chapter.title, number: chapterNumber, own: &own)
            var resolved: [RScene] = []
            for (i, scene) in scenes.enumerated() {
                var body = blocks(of: scene.document)
                let h = heading(level: 3, rule: options.scene, title: scene.title, number: i + 1, own: &body)
                resolved.append(RScene(title: scene.title, heading: h, blocks: body))
            }
            return RChapter(heading: head, own: own, scenes: resolved)
        }

        var items: [RItem] = []
        for item in book.items {
            switch item {
            case .chapter(let c):
                if let r = resolveChapter(c) { items.append(.chapter(r)) }
            case .part(let p):
                if options.restartNumberingInParts { chapterNumber = 0 }
                let chapters = p.chapters.compactMap(resolveChapter)
                if filtering, chapters.isEmpty { continue }
                partNumber += 1
                var own = blocks(of: p.own)
                let head = heading(level: 1, rule: options.part, title: p.title, number: partNumber, own: &own)
                items.append(.part(RPart(heading: head, own: own, chapters: chapters)))
            }
        }
        var titlePage: [Block]?
        if options.titlePage == .manual, let doc = book.titlePage { titlePage = blocks(of: doc) }
        return Resolved(title: book.title, author: book.author, copyright: book.copyright, language: book.language, id: book.id,
                        cover: options.cover ? book.cover : nil, titlePage: titlePage, items: items, options: options)
    }

    static func headingText(rule: ExportFile.HeadingRule, title: String, number: Int, style: ExportOptions.NumberStyle) -> String? {
        let n = style == .roman ? roman(number) : String(number)
        switch rule.print {
        case "title": return title
        case "number": return rule.template.map { fill($0, number: n, title: title) } ?? n
        case "number_and_title": return fill(rule.template ?? "{number}. {title}", number: n, title: title)
        default: return nil
        }
    }

    private static func fill(_ template: String, number: String, title: String) -> String {
        template.replacingOccurrences(of: "{number}", with: number).replacingOccurrences(of: "{title}", with: title)
    }

    static func roman(_ value: Int) -> String {
        let table: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = value
        var out = ""
        for (v, s) in table { while n >= v { out += s; n -= v } }
        return out
    }
}

// MARK: Shared small helpers

enum XML {
    /// Escapes text for an element or attribute and drops the characters XML 1.0 cannot carry at all.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                let v = scalar.value
                if v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD) || v >= 0x10000 { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }
}

/// An attribution line of a set-off block: the last paragraph of two or more, starting with a dash.
func splitAttribution(_ paragraphs: [[Inline]]) -> (body: [[Inline]], author: [Inline]?) {
    guard paragraphs.count >= 2, let last = paragraphs.last, case .run(let first)? = last.first,
          first.text.hasPrefix("—") || first.text.hasPrefix("–") || first.text.hasPrefix("-") else { return (paragraphs, nil) }
    var author = last
    if case .run(var run)? = author.first {
        run.text = String(run.text.drop(while: { $0 == "—" || $0 == "–" || $0 == "-" || $0 == " " }))
        author[0] = .run(run)
    }
    return (Array(paragraphs.dropLast()), author)
}

/// Lines of a paragraph that has line breaks inside (verse).
func verseLines(_ inlines: [Inline]) -> [[Inline]] {
    var lines: [[Inline]] = [[]]
    for inline in inlines {
        if case .lineBreak = inline { lines.append([]) } else { lines[lines.count - 1].append(inline) }
    }
    return lines
}

func hasLineBreak(_ inlines: [Inline]) -> Bool { inlines.contains { if case .lineBreak = $0 { return true } else { return false } } }
