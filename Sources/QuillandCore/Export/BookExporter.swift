import Foundation

public enum ExportFormat: String, CaseIterable, Sendable {
    case docx, fb2, epub, html, txt, pdf

    public var label: String {
        switch self {
        case .docx: return L("DOCX (Word, Pages)")
        case .fb2: return "FB2"
        case .epub: return "EPUB"
        case .html: return "HTML"
        case .txt: return L("TXT (UTF-8)")
        case .pdf: return "PDF"
        }
    }

    public var fileExtension: String { rawValue }
}

/// What the book will have, worked out from the same plan the export uses (so the preview cannot disagree with the file).
public struct ExportSummary: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var level: Int
        public var text: String
        public var newPage: Bool
    }
    /// The titles the book will have, in order: parts, chapters, and scenes where they print a heading.
    public var lines: [Line] = []
    public var scenes = 0
    public var characters = 0
    public var footnotes = 0
    /// Parts, chapters and scenes whose heading is the one typed in their own text (the profile adds none).
    public var typedHeadings = 0
}

public enum BookExporter {
    public static func export(_ book: BookModel, format: ExportFormat, options: ExportOptions, date: Date = Date()) -> Data {
        switch format {
        case .docx: return DocxExporter.export(book, options: options, date: date)
        case .fb2: return Fb2Exporter.export(book, options: options, date: date)
        case .epub: return EpubExporter.export(book, options: options, date: date)
        case .html: return HtmlExporter.export(book, options: options)
        // The page layout of a PDF is done by the system's web engine in the application; here is the HTML it prints.
        case .pdf: return HtmlExporter.export(book, options: options, print: true)
        case .txt: return TxtExporter.export(book, options: options)
        }
    }

    /// A file name from the book's title: no slashes or colons.
    public static func fileName(title: String, format: ExportFormat) -> String {
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = "Book" }
        return "\(name).\(format.fileExtension)"
    }

    public static func summarize(_ book: BookModel, options: ExportOptions) -> ExportSummary {
        let r = Resolver.resolve(book, options: options)
        var out = ExportSummary()
        func notes(in blocks: [Block]) -> Int {
            var n = 0
            func count(_ inlines: [Inline]) { for i in inlines { if case .note = i { n += 1 } } }
            for b in blocks {
                switch b {
                case .paragraph(let i), .heading(_, let i): count(i)
                case .quote(let ps): ps.forEach(count)
                default: break
                }
            }
            return n
        }
        func chars(_ blocks: [Block]) -> Int {
            var n = 0
            for b in blocks {
                switch b {
                case .paragraph(let i), .heading(_, let i): n += RHeading.plain(i).count
                case .quote(let ps): n += ps.reduce(0) { $0 + RHeading.plain($1).count }
                default: break
                }
            }
            return n
        }
        func add(_ h: RHeading?) {
            guard let h else { return }
            out.lines.append(.init(level: h.level, text: h.plain, newPage: h.newPage))
            if h.typed { out.typedHeadings += 1 }
        }
        func chapter(_ c: RChapter) {
            add(c.heading)
            out.footnotes += notes(in: c.own)
            out.characters += chars(c.own)
            for s in c.scenes {
                out.scenes += 1
                add(s.heading)
                out.footnotes += notes(in: s.blocks)
                out.characters += chars(s.blocks)
            }
        }
        for item in r.items {
            switch item {
            case .chapter(let c): chapter(c)
            case .part(let p):
                add(p.heading)
                out.footnotes += notes(in: p.own)
                p.chapters.forEach(chapter)
            }
        }
        return out
    }
}

/// The export profiles of a book: `export.json` (quilland-format.md, section 16).
public final class ExportStore {
    public let book: URL
    public private(set) var file: ExportFile
    public var profiles: [ExportFile.Profile] { file.profiles }
    public var lastProfile: String? { file.object.string("last_profile") }

    public init(book: URL) {
        self.book = book
        let url = book.appendingPathComponent("export.json")
        file = ExportFile(object: (try? JSONParser.parseObject(Data(contentsOf: url))) ?? ["format": .int(1)])
        if file.profiles.isEmpty { file.profiles = [Self.defaultProfile(name: "Manuscript DOCX")] }
    }

    /// A profile with the author's usual defaults.
    public static func defaultProfile(name: String, format: ExportFormat = .docx) -> ExportFile.Profile {
        var p = ExportFile.Profile(object: [:])
        p.name = name
        p.format = format.rawValue
        p.toc = true
        p.cover = false
        p.footnotes = "page"
        p.sceneBreak = "mark"
        p.titlePage = "auto"
        p.setHeadingRule("part", .init(print: "title", template: nil, newPage: true))
        p.setHeadingRule("chapter", .init(print: "number_and_title", template: "{number}. {title}", newPage: true))
        p.setHeadingRule("scene", .init(print: "none", template: nil, newPage: nil))
        return p
    }

    public func profile(named name: String) -> ExportFile.Profile? { profiles.first { $0.name == name } }

    /// Saves one profile (replacing the one with its name, or adding it) and remembers it as the last used.
    public func save(_ profile: ExportFile.Profile) throws {
        var all = profiles
        if let i = all.firstIndex(where: { $0.name == profile.name }) { all[i] = profile } else { all.append(profile) }
        file.profiles = all
        file.object.setString("last_profile", profile.name)
        try write()
    }

    public func delete(_ name: String) throws {
        file.profiles = profiles.filter { $0.name != name }
        if file.profiles.isEmpty { file.profiles = [Self.defaultProfile(name: "Manuscript DOCX")] }
        if lastProfile == name { file.object.setString("last_profile", file.profiles.first?.name) }
        try write()
    }

    public func setLast(_ name: String) throws {
        file.object.setString("last_profile", name)
        try write()
    }

    private func write() throws {
        try AtomicFile.write(JSONWriter.data(file.object), to: book.appendingPathComponent("export.json"))
    }
}
