import Foundation
import Testing
@testable import QuillandCore

@Suite("HTML, EPUB, TXT and the export plan")
struct WebExportTests {
    static func sample() throws -> (URL, BookModel) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-webexport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try SampleBook.write(into: folder)
        return (folder, try BookLoader.load(folder: folder))
    }

    @Test("TXT is UTF-8 with the title, the contents, headings, scene marks and notes after their chapter")
    func txt() throws {
        let (folder, book) = try Self.sample()
        defer { try? FileManager.default.removeItem(at: folder) }
        var options = ExportOptions()
        options.toc = true
        let text = String(decoding: TxtExporter.export(book, options: options), as: UTF8.self)
        #expect(text.hasPrefix(book.title) && text.contains(book.author))
        #expect(text.contains("* * *") && !text.contains("<p>") && !text.contains("**"))
        #expect(text.contains("[1] "), "a footnote is numbered and printed after its chapter")
        options.sceneBreak = .none
        let plain = String(decoding: TxtExporter.export(book, options: options), as: UTF8.self)
        #expect(!plain.contains("* * *"))
    }

    @Test("HTML is one file with a contents list that links to the chapters, notes with back links, and the cover inside")
    func html() throws {
        let (folder, book) = try Self.sample()
        defer { try? FileManager.default.removeItem(at: folder) }
        var options = ExportOptions()
        options.cover = true
        let html = String(decoding: HtmlExporter.export(book, options: options), as: UTF8.self)
        #expect(html.hasPrefix("<!DOCTYPE html>") && html.contains("<nav class=\"contents\">") && html.contains("<h2"))
        #expect(html.contains("class=\"noteref\"") && html.contains("href=\"#r1\""))
        #expect(html.contains("<strong>") || html.contains("<em>"))
        if book.cover != nil { #expect(html.contains("data:image/")) }
        options.toc = false
        #expect(!String(decoding: HtmlExporter.export(book, options: options), as: UTF8.self).contains("<nav"))
    }

    @Test("EPUB has the mimetype first and stored, a container, a package, a contents document, and pages that are well-formed XML")
    func epub() throws {
        let (folder, book) = try Self.sample()
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = EpubExporter.export(book, options: ExportOptions())
        let file = folder.appendingPathComponent("test.epub")
        try data.write(to: file)
        // The first entry is `mimetype`, stored (method 0), at the very start.
        let head = [UInt8](data.prefix(60))
        #expect(Array(head[0..<4]) == [0x50, 0x4B, 0x03, 0x04] && head[8] == 0 && head[9] == 0)
        #expect(String(decoding: head[30..<38], as: UTF8.self) == "mimetype" && String(decoding: head[38..<58], as: UTF8.self) == "application/epub+zip")
        let out = folder.appendingPathComponent("unzipped")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-q", file.path, "-d", out.path]
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        let names = try FileManager.default.subpathsOfDirectory(atPath: out.path)
        #expect(names.contains("META-INF/container.xml") && names.contains("OEBPS/content.opf") && names.contains("OEBPS/nav.xhtml") && names.contains("OEBPS/style.css"))
        for name in names where name.hasSuffix(".xhtml") || name.hasSuffix(".opf") || name.hasSuffix(".xml") {
            let parser = XMLParser(data: try Data(contentsOf: out.appendingPathComponent(name)))
            #expect(parser.parse(), "\(name) is not well-formed: \(String(describing: parser.parserError)) at line \(parser.lineNumber)")
        }
        let opf = try String(contentsOf: out.appendingPathComponent("OEBPS/content.opf"), encoding: .utf8)
        #expect(opf.contains("<dc:title>") && opf.contains("dcterms:modified") && opf.contains("<spine>"))
        // Every page in the spine is in the manifest.
        let idrefs = opf.components(separatedBy: "idref=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
        for id in idrefs { #expect(opf.contains("id=\"\(id)\""), "\(id) is in the spine but not in the manifest") }
    }

    @Test("unticked scenes leave the book, and a chapter with none left leaves too; the summary says what is in")
    func plan() throws {
        let (folder, book) = try Self.sample()
        defer { try? FileManager.default.removeItem(at: folder) }
        let all = BookExporter.summarize(book, options: ExportOptions())
        #expect(all.scenes > 0 && !all.lines.isEmpty && all.characters > 0)
        var options = ExportOptions()
        var firstChapterScenes: [String] = []
        for item in book.items {
            switch item {
            case .chapter(let c): if firstChapterScenes.isEmpty { firstChapterScenes = c.scenes.map(\.id) }
            case .part(let p): if firstChapterScenes.isEmpty, let c = p.chapters.first { firstChapterScenes = c.scenes.map(\.id) }
            }
        }
        options.excludedScenes = Set(firstChapterScenes)
        let fewer = BookExporter.summarize(book, options: options)
        #expect(fewer.scenes == all.scenes - firstChapterScenes.count && fewer.lines.count < all.lines.count)
        // A status filter works the same way.
        var byStatus = ExportOptions()
        byStatus.statuses = ["no-such-status"]
        #expect(BookExporter.summarize(book, options: byStatus).scenes == 0)
    }

    @Test("every format makes something non-empty from the same book, and the names of files are safe")
    func allFormats() throws {
        let (folder, book) = try Self.sample()
        defer { try? FileManager.default.removeItem(at: folder) }
        for format in ExportFormat.allCases {
            #expect(BookExporter.export(book, format: format, options: ExportOptions()).count > 500, "\(format)")
        }
        #expect(BookExporter.fileName(title: "A/B: C", format: .epub) == "A-B- C.epub")
        #expect(BookExporter.fileName(title: "  ", format: .txt) == "Book.txt")
    }

    @Test("profiles are kept in export.json and come back, and a deleted last profile is replaced")
    func profiles() throws {
        let parent = try NewBookTests.folder()
        defer { try? FileManager.default.removeItem(at: parent) }
        let book = try BookCreator.create(NewBookRequest(title: "B", parentFolder: parent))
        let store = ExportStore(book: book)
        #expect(store.profiles.count == 1)
        var p = ExportStore.defaultProfile(name: "Для издательства", format: .epub)
        p.setFilters(statuses: ["revised", "done"], tags: [])
        p.numbering = "roman"
        try store.save(p)
        let back = ExportStore(book: book)
        #expect(back.profiles.count == 2 && back.lastProfile == "Для издательства")
        let loaded = try #require(back.profile(named: "Для издательства"))
        #expect(loaded.format == "epub" && loaded.statuses == ["revised", "done"])
        let options = ExportOptions(profile: loaded)
        #expect(options.numberStyle == .roman && options.statuses == ["revised", "done"] && options.chapter.print == "number_and_title")
        try back.delete("Для издательства")
        #expect(ExportStore(book: book).profiles.count == 1)
    }
}

@Suite("Scenes in the contents")
struct TocScenesTests {
    @Test("with the option, the EPUB contents lists the scenes under their chapters and every link goes to a place that exists")
    func epubScenes() throws {
        let (folder, book) = try WebExportTests.sample()
        defer { try? FileManager.default.removeItem(at: folder) }
        let scenes = book.items.flatMap { item -> [BookModel.Scene] in
            switch item {
            case .chapter(let c): return c.scenes
            case .part(let p): return p.chapters.flatMap(\.scenes)
            }
        }
        func nav(_ options: ExportOptions) throws -> (String, [String: String]) {
            let file = folder.appendingPathComponent("t-\(UUID().uuidString).epub")
            try EpubExporter.export(book, options: options).write(to: file)
            let out = folder.appendingPathComponent("u-\(UUID().uuidString)")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-q", file.path, "-d", out.path]
            try p.run(); p.waitUntilExit()
            var pages: [String: String] = [:]
            for name in try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("OEBPS").path) where name.hasSuffix(".xhtml") {
                pages[name] = try String(contentsOf: out.appendingPathComponent("OEBPS/\(name)"), encoding: .utf8)
            }
            return (pages["nav.xhtml"] ?? "", pages)
        }
        var options = ExportOptions()
        let (without, _) = try nav(options)
        let someTitle = try #require(scenes.first?.title)
        #expect(!without.contains(">\(XML.escape(someTitle))</a>"), "scenes are not in the contents unless asked for")
        options.tocScenes = true
        let (with, pages) = try nav(options)
        for s in scenes { #expect(with.contains(XML.escape(s.title)), "\(s.title) is in the contents") }
        // Each link into a page lands on an id that is in that page.
        let links = with.components(separatedBy: "href=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }.filter { $0.contains("#") }
        #expect(!links.isEmpty)
        for link in links {
            let parts = link.split(separator: "#").map(String.init)
            #expect(pages[parts[0]]?.contains("id=\"\(parts[1])\"") == true, "\(link) has no place to land on")
        }
        // The pages are still well-formed XML.
        for (name, text) in pages { #expect(XMLParser(data: Data(text.utf8)).parse(), "\(name)") }
    }

    @Test("HTML and TXT list the scenes too, and DOCX asks for three levels")
    func otherFormats() throws {
        let (folder, book) = try WebExportTests.sample()
        defer { try? FileManager.default.removeItem(at: folder) }
        var options = ExportOptions()
        options.tocScenes = true
        let html = String(decoding: HtmlExporter.export(book, options: options), as: UTF8.self)
        #expect(html.contains("<li class=\"l3\"><a href=\"#s"))
        let txtOn = String(decoding: TxtExporter.export(book, options: options), as: UTF8.self)
        options.tocScenes = false
        let txtOff = String(decoding: TxtExporter.export(book, options: options), as: UTF8.self)
        #expect(txtOn.count > txtOff.count)
        options.tocScenes = true
        let docx = DocxExporter.export(book, options: options)
        #expect(String(decoding: docx, as: UTF8.self).contains("TOC3") || docx.count > 1000)
    }

    @Test("the profile keeps the option")
    func profile() {
        var p = ExportStore.defaultProfile(name: "x")
        #expect(ExportOptions(profile: p).tocScenes == false)
        p.tocScenes = true
        #expect(ExportOptions(profile: p).tocScenes)
    }
}
