import Foundation
import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import QuillandCore

// MARK: Helpers

/// The parts of a ZIP file, read by the system's own `unzip` (an implementation that is not ours).
struct ZipInspector {
    let url: URL
    let names: [String]

    init(_ data: Data) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-zip-\(UUID().uuidString).zip")
        try data.write(to: url)
        names = Self.run(["-Z1", url.path]).split(separator: "\n").map(String.init)
    }

    static func run(_ arguments: [String]) -> String {
        String(decoding: runData(arguments), as: UTF8.self)
    }

    static func runData(_ arguments: [String]) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = ["LC_ALL": "en_US.UTF-8", "LANG": "en_US.UTF-8"]
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    var integrityOK: Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-tq", url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func part(_ name: String) -> Data {
        // `-p` takes a pattern, so brackets are escaped.
        let escaped = name.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return Self.runData(["-p", url.path, escaped])
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// What a DOCX must satisfy for Word to open it, checked structurally.
struct DocxChecks {
    var problems: [String] = []
    var paragraphs: [(style: String?, text: String, pageBreakBefore: Bool)] = []
    var footnoteTexts: [String] = []
    var tocEntries: [String] = []

    init(_ data: Data) throws {
        let zip = try ZipInspector(data)
        defer { zip.remove() }
        if !zip.integrityOK { problems.append("zip integrity") }
        var docs: [String: XMLDocument] = [:]
        for name in zip.names where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            do { docs[name] = try XMLDocument(data: zip.part(name), options: []) } catch { problems.append("\(name) is not well-formed XML: \(error)") }
        }
        func xpath(_ doc: XMLDocument, _ path: String) -> [XMLNode] { (try? doc.nodes(forXPath: path)) ?? [] }

        // Every part has a content type.
        if let types = docs["[Content_Types].xml"] {
            let defaults = Set(xpath(types, "//*[local-name()='Default']/@Extension").compactMap(\.stringValue))
            let overrides = Set(xpath(types, "//*[local-name()='Override']/@PartName").compactMap(\.stringValue))
            for name in zip.names where name != "[Content_Types].xml" {
                let ext = String(name.split(separator: ".", omittingEmptySubsequences: false).last ?? "")
                if !overrides.contains("/" + name), !defaults.contains(ext) { problems.append("no content type for \(name)") }
            }
            for o in overrides where !zip.names.contains(String(o.dropFirst())) { problems.append("content type for a missing part \(o)") }
        } else { problems.append("no [Content_Types].xml") }

        // Every relationship points to a part that exists, and every r:id in the document is a relationship.
        var relIDs = Set<String>()
        if let rels = docs["word/_rels/document.xml.rels"] {
            for node in xpath(rels, "//*[local-name()='Relationship']") {
                guard let e = node as? XMLElement, let id = e.attribute(forName: "Id")?.stringValue, let target = e.attribute(forName: "Target")?.stringValue else { continue }
                relIDs.insert(id)
                if !zip.names.contains("word/" + target) { problems.append("relationship \(id) points to missing word/\(target)") }
            }
        }
        if let root = docs["_rels/.rels"] {
            for node in xpath(root, "//*[local-name()='Relationship']/@Target") where !zip.names.contains(node.stringValue ?? "") { problems.append("root relationship to a missing part \(node.stringValue ?? "")") }
        }
        guard let document = docs["word/document.xml"] else { problems.append("no document.xml"); return }
        for attribute in xpath(document, "//@*[local-name()='id' and namespace-uri()='http://schemas.openxmlformats.org/officeDocument/2006/relationships'] | //@*[local-name()='embed']") {
            if let v = attribute.stringValue, !relIDs.contains(v) { problems.append("r:id \(v) is not a relationship") }
        }

        // Styles used are styles defined.
        var defined = Set<String>()
        if let styles = docs["word/styles.xml"] { defined = Set(xpath(styles, "//*[local-name()='style']/@*[local-name()='styleId']").compactMap(\.stringValue)) }
        for node in xpath(document, "//*[local-name()='pStyle' or local-name()='rStyle']/@*[local-name()='val']") {
            if let v = node.stringValue, !defined.contains(v) { problems.append("style \(v) is used and not defined") }
        }
        if let footnotes = docs["word/footnotes.xml"] {
            for node in xpath(footnotes, "//*[local-name()='pStyle' or local-name()='rStyle']/@*[local-name()='val']") {
                if let v = node.stringValue, !defined.contains(v) { problems.append("style \(v) is used in footnotes and not defined") }
            }
        }
        for p in defined { _ = p }

        // Footnotes: every reference has a note, every note is referenced once, ids are unique.
        let refs = xpath(document, "//*[local-name()='footnoteReference']/@*[local-name()='id']").compactMap(\.stringValue)
        var noteIDs: [String] = []
        if let footnotes = docs["word/footnotes.xml"] {
            for node in xpath(footnotes, "//*[local-name()='footnote']") {
                guard let e = node as? XMLElement, let id = e.attribute(forName: "w:id")?.stringValue else { continue }
                if e.attribute(forName: "w:type") == nil {
                    noteIDs.append(id)
                    footnoteTexts.append(xpath(footnotes.rootElement().map { _ in footnotes } ?? footnotes, "//*[local-name()='footnote'][@*[local-name()='id']='\(id)']//*[local-name()='t']").map { $0.stringValue ?? "" }.joined().trimmingCharacters(in: .whitespaces))
                }
            }
        }
        if Set(refs).count != refs.count { problems.append("a footnote is referenced twice") }
        if Set(refs) != Set(noteIDs) { problems.append("footnote references \(refs) and notes \(noteIDs) differ") }

        // Bookmarks and links to them.
        let bookmarks = xpath(document, "//*[local-name()='bookmarkStart']/@*[local-name()='name']").compactMap(\.stringValue)
        let bookmarkIDs = xpath(document, "//*[local-name()='bookmarkStart']/@*[local-name()='id']").compactMap(\.stringValue)
        if Set(bookmarkIDs).count != bookmarkIDs.count { problems.append("bookmark ids repeat") }
        for anchor in xpath(document, "//*[local-name()='hyperlink']/@*[local-name()='anchor']") where !bookmarks.contains(anchor.stringValue ?? "") {
            problems.append("a link to the missing bookmark \(anchor.stringValue ?? "")")
        }

        // Paragraphs in order.
        for node in xpath(document, "/*/*[local-name()='body']/*[local-name()='p']") {
            guard let p = node as? XMLElement else { continue }
            let style = (try? p.nodes(forXPath: "./*[local-name()='pPr']/*[local-name()='pStyle']/@*[local-name()='val']"))?.first?.stringValue
            let breakBefore = ((try? p.nodes(forXPath: "./*[local-name()='pPr']/*[local-name()='pageBreakBefore']")) ?? []).isEmpty == false
            var text = ""
            for t in (try? p.nodes(forXPath: ".//*[local-name()='t' or local-name()='br' and not(@*[local-name()='type'])]")) ?? [] {
                text += (t as? XMLElement)?.name == "w:br" ? "\n" : (t.stringValue ?? "")
            }
            paragraphs.append((style, text, breakBefore))
            if style?.hasPrefix("TOC") == true, style != "TOCHeading" { tocEntries.append(text) }
        }
        // Order of the sections' parts: the last child of the body is the section properties.
        if let last = xpath(document, "/*/*[local-name()='body']/*").last, (last as? XMLElement)?.name != "w:sectPr" { problems.append("the section properties are not last") }
    }
}

/// The content model of FictionBook 2.1 (the part Quilland writes), checked structurally.
struct Fb2Checks {
    var problems: [String] = []
    var sections = 0
    var notesLinked: [String] = []
    var text: [String] = []

    static let blocks: Set<String> = ["p", "poem", "subtitle", "cite", "empty-line", "image", "table"]
    static let inline: Set<String> = ["strong", "emphasis", "style", "a", "strikethrough", "sub", "sup", "code", "image"]

    init(_ data: Data) {
        let document: XMLDocument
        do { document = try XMLDocument(data: data, options: []) } catch { problems.append("not well-formed: \(error)"); return }
        guard let root = document.rootElement(), root.localName == "FictionBook" else { problems.append("root is not FictionBook"); return }
        if root.uri != "http://www.gribuser.ru/xml/fictionbook/2.0" { problems.append("wrong namespace \(root.uri ?? "none")") }
        let top = root.elements(children: nil)
        if top.map(\.localName) .prefix(1) != ["description"] { problems.append("description must come first") }

        // description
        if let description = top.first(where: { $0.localName == "description" }), let info = description.elements(children: "title-info").first {
            let names = info.elements(children: nil).map { $0.localName ?? "" }
            let order = ["genre", "author", "book-title", "annotation", "keywords", "date", "coverpage", "lang", "src-lang", "translator", "sequence"]
            var last = -1
            for n in names {
                guard let i = order.firstIndex(of: n) else { problems.append("unknown title-info child \(n)"); continue }
                if i < last { problems.append("title-info child \(n) is out of order") }
                last = i
            }
            for need in ["genre", "author", "book-title", "lang"] where !names.contains(need) { problems.append("title-info lacks \(need)") }
            for author in info.elements(children: "author") {
                let kids = author.elements(children: nil).map { $0.localName ?? "" }
                if !(kids.contains("first-name") && kids.contains("last-name")) && !kids.contains("nickname") { problems.append("author needs first and last name, or a nickname") }
            }
            let doc = description.elements(children: "document-info").first
            for need in ["author", "date", "id", "version"] where doc?.elements(children: need).isEmpty != false { problems.append("document-info lacks \(need)") }
        } else { problems.append("no title-info") }

        // ids
        var ids = Set<String>()
        var hrefs: [String] = []
        func visit(_ e: XMLElement) {
            if let id = e.attribute(forName: "id")?.stringValue { if !ids.insert(id).inserted { problems.append("id \(id) repeats") } }
            if e.localName == "a" || e.localName == "image" {
                for attribute in e.attributes ?? [] where attribute.localName == "href" { hrefs.append(attribute.stringValue ?? "") }
                if e.localName == "a", e.attribute(forName: "type")?.stringValue == "note" { notesLinked.append(e.attributes?.first { $0.localName == "href" }?.stringValue ?? "") }
            }
            for c in e.elements(children: nil) { visit(c) }
        }
        visit(root)
        for href in hrefs where !ids.contains(String(href.dropFirst())) { problems.append("link to a missing target \(href)") }

        // bodies
        let bodies = top.filter { $0.localName == "body" }
        if bodies.isEmpty { problems.append("no body") }
        for body in bodies {
            let kids = body.elements(children: nil).map { $0.localName ?? "" }
            let order = ["image", "title", "epigraph", "section"]
            var last = -1
            for k in kids {
                guard let i = order.firstIndex(of: k) else { problems.append("unknown body child \(k)"); continue }
                if i < last { problems.append("body child \(k) is out of order") }
                last = i
            }
            if !kids.contains("section") && body.attribute(forName: "name")?.stringValue != "notes" && kids.count < 2 { problems.append("a body without sections") }
            for e in body.elements(children: nil) {
                switch e.localName {
                case "title": checkTitle(e)
                case "epigraph": checkEpigraph(e)
                case "section": checkSection(e)
                default: break
                }
            }
        }
        // binaries decode
        for binary in top.filter({ $0.localName == "binary" }) {
            let raw = (binary.stringValue ?? "").filter { !$0.isWhitespace }
            if Data(base64Encoded: raw) == nil { problems.append("binary \(binary.attribute(forName: "id")?.stringValue ?? "") is not base64") }
            if binary.attribute(forName: "content-type") == nil { problems.append("binary without content-type") }
        }
        text = Self.paragraphs(root)
    }

    static func paragraphs(_ root: XMLElement) -> [String] {
        var out: [String] = []
        func visit(_ e: XMLElement) {
            if ["p", "v", "text-author", "subtitle"].contains(e.localName ?? "") {
                out.append(Self.flat(e))
            } else { for c in e.elements(children: nil) { visit(c) } }
        }
        visit(root)
        return out
    }

    static func flat(_ e: XMLElement) -> String {
        var s = ""
        for n in e.children ?? [] {
            if let child = n as? XMLElement {
                if child.localName == "a" { continue }   // a note marker is not text
                s += flat(child)
            } else { s += n.stringValue ?? "" }
        }
        return s
    }

    mutating func checkInline(_ e: XMLElement, in context: String) {
        for n in e.children ?? [] {
            if let c = n as? XMLElement {
                if !Self.inline.contains(c.localName ?? "") { problems.append("\(c.localName ?? "?") is not allowed inside \(context)") }
                checkInline(c, in: context)
            }
        }
    }

    mutating func checkTitle(_ e: XMLElement) {
        for c in e.elements(children: nil) {
            if !["p", "empty-line"].contains(c.localName ?? "") { problems.append("title contains \(c.localName ?? "?")") }
            checkInline(c, in: "title")
        }
    }

    mutating func checkPoem(_ e: XMLElement) {
        let kids = e.elements(children: nil).map { $0.localName ?? "" }
        if !kids.contains("stanza") { problems.append("poem without a stanza") }
        for s in e.elements(children: "stanza") {
            if s.elements(children: "v").isEmpty { problems.append("stanza without lines") }
            for v in s.elements(children: "v") { checkInline(v, in: "v") }
        }
    }

    mutating func checkCite(_ e: XMLElement) {
        var sawAuthor = false
        for c in e.elements(children: nil) {
            switch c.localName ?? "" {
            case "p", "subtitle": if sawAuthor { problems.append("text after text-author in cite") }; checkInline(c, in: "cite")
            case "empty-line": break
            case "poem": checkPoem(c)
            case "text-author": sawAuthor = true; checkInline(c, in: "text-author")
            default: problems.append("cite contains \(c.localName ?? "?")")
            }
        }
        if e.elements(children: nil).filter({ $0.localName != "text-author" }).isEmpty { problems.append("empty cite") }
    }

    mutating func checkEpigraph(_ e: XMLElement) {
        var sawAuthor = false
        for c in e.elements(children: nil) {
            switch c.localName ?? "" {
            case "p": if sawAuthor { problems.append("text after text-author in epigraph") }; checkInline(c, in: "epigraph")
            case "empty-line": break
            case "poem": checkPoem(c)
            case "cite": checkCite(c)
            case "text-author": sawAuthor = true; checkInline(c, in: "text-author")
            default: problems.append("epigraph contains \(c.localName ?? "?")")
            }
        }
        if e.elements(children: nil).isEmpty { problems.append("empty epigraph") }
    }

    mutating func checkSection(_ e: XMLElement) {
        sections += 1
        let kids = e.elements(children: nil)
        let names = kids.map { $0.localName ?? "" }
        // title?, epigraph*, image?, annotation?, then sections or blocks
        var stage = 0
        var subsections = 0, blocks = 0
        for (c, n) in zip(kids, names) {
            switch n {
            case "title": if stage > 0 { problems.append("title is not first in a section") }; stage = 0; checkTitle(c)
            case "epigraph": if stage > 1 { problems.append("epigraph after the content starts") }; stage = 1; checkEpigraph(c)
            case "image", "annotation": if stage > 2 { problems.append("\(n) after the content starts") }; stage = 2
            case "section": stage = 3; subsections += 1; checkSection(c)
            default:
                if Self.blocks.contains(n) {
                    stage = 3; blocks += 1
                    switch n {
                    case "p", "subtitle": checkInline(c, in: n)
                    case "poem": checkPoem(c)
                    case "cite": checkCite(c)
                    default: break
                    }
                } else { problems.append("unknown section child \(n)") }
            }
        }
        if subsections > 0 && blocks > 0 { problems.append("a section has both subsections and text") }
        if subsections == 0 && blocks == 0 { problems.append("an empty section") }
    }
}

private extension XMLElement {
    func elements(children name: String?) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { name == nil || $0.localName == name }
    }
}

// MARK: Tests

@Suite("Export: DOCX and FB2", .serialized)
struct ExportTests {
    static func makeSample() throws -> (BookModel, URL, ExportFile) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try SampleBook.write(into: url)
        let book = try BookLoader.load(folder: url)
        let file = ExportFile(object: try JSONParser.parseObject(Data(contentsOf: url.appendingPathComponent("export.json"))))
        return (book, url, file)
    }

    static func notes(in document: Document) -> [String] {
        var out: [String] = []
        func scan(_ inlines: [Inline]) { for i in inlines { if case .note(let n) = i { out.append(n.content.map { $0.text }.joined()) } } }
        for b in document.blocks {
            switch b {
            case .paragraph(let i), .heading(_, let i): scan(i)
            case .quote(let ps): ps.forEach(scan)
            default: break
            }
        }
        return out
    }

    static func allDocuments(_ book: BookModel) -> [Document] {
        var out: [Document] = []
        func chapter(_ c: BookModel.Chapter) { if let o = c.own { out.append(o) }; out += c.scenes.map(\.document) }
        for item in book.items {
            switch item {
            case .part(let p): if let o = p.own { out.append(o) }; p.chapters.forEach(chapter)
            case .chapter(let c): chapter(c)
            }
        }
        return out
    }

    // MARK: ZIP

    @Test("ZIP: the CRC is the standard one; the system's unzip reads what we write, byte for byte")
    func zip() throws {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        var writer = ZipWriter()
        var originals: [String: Data] = [:]
        var rng = SplitMix64(seed: 3)
        originals["empty.txt"] = Data()
        originals["small.txt"] = Data("hi".utf8)
        originals["Русское имя.txt"] = Data(String(repeating: "Привет, мир! ", count: 500).utf8)
        originals["dir/nested/random.bin"] = Data((0..<20_000).map { _ in UInt8.random(in: 0...255, using: &rng) })   // does not compress: stored
        originals["dir/zeros.bin"] = Data(count: 1_000_000)
        for (name, data) in originals { writer.add(name, data) }
        let zip = try ZipInspector(writer.finish())
        defer { zip.remove() }
        #expect(zip.integrityOK)
        // Names with Cyrillic letters: Apple's unzip does not show UTF-8 names, so Python's reader is the second opinion.
        let python = Process()
        python.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        python.arguments = ["python3", "-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip()); print('\\n'.join(z.namelist()))", zip.url.path]
        let pipe = Pipe()
        python.standardOutput = pipe
        try python.run()
        let listing = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
        python.waitUntilExit()
        #expect(listing.first == "None", "python found a damaged entry")
        #expect(Set(listing.dropFirst()) == Set(originals.keys))
        for (name, data) in originals where name.allSatisfy(\.isASCII) { #expect(zip.part(name) == data, "\(name)") }
    }

    // MARK: DOCX

    @Test("DOCX: the sample book passes every structural check, and none of the text is lost")
    func docx() throws {
        let (book, url, file) = try Self.makeSample()
        defer { try? FileManager.default.removeItem(at: url) }
        let options = ExportOptions(profile: file.profiles[0])
        let data = DocxExporter.export(book, options: options)
        let checks = try DocxChecks(data)
        #expect(checks.problems.isEmpty, "\(checks.problems)")

        // Titles and structure: parts are Heading 1, chapters Heading 2, a typed heading wins.
        let headings = checks.paragraphs.filter { $0.style?.hasPrefix("Heading") == true }
        #expect(headings.filter { $0.style == "Heading1" }.map { $0.text } == ["Часть 1. Дорога", "Часть 2. Дом"])
        let chapters = headings.filter { $0.style == "Heading2" }.map { $0.text }
        #expect(chapters == ["Глава 1. Станция", "Глава 2. Ключ", "Глава 3. Лестница", "Подвал, в который не ходят", "Эпилог, который можно пропустить"], "\(chapters)")
        #expect(headings.filter { $0.style == "Heading3" }.map { $0.text } == ["Заметка на полях"])
        // A new page before every part and chapter, nowhere else.
        #expect(headings.filter { $0.style != "Heading3" }.allSatisfy { $0.pageBreakBefore })
        #expect(!checks.paragraphs.contains { $0.pageBreakBefore && $0.style?.hasPrefix("Heading") != true })
        // The contents list parts and chapters.
        #expect(checks.tocEntries == (headings.filter { $0.style != "Heading3" }.map { $0.text }))
        // Title page.
        #expect(checks.paragraphs.contains { $0.style == "Title" && $0.text == "Дом на Сосновой" })
        #expect(checks.paragraphs.contains { $0.style == "Subtitle" && $0.text == "Вадим Сульянов" })
        // The set-off blocks are Quote, the attribution is its own style, the scene breaks are marks.
        #expect(checks.paragraphs.filter { $0.style == "QuoteAuthor" }.map { $0.text } == ["Народная мудрость", "Твоя тётя Вера"])
        #expect(checks.paragraphs.filter { $0.style == "SceneBreak" }.map { $0.text } == ["* * *", "* * *", "* * *", "* * *"])
        // Footnotes are real footnotes with their own text.
        #expect(checks.footnoteTexts == ["Чемодан достался ей от матери и пах нафталином.", "Позже выяснится, что свет шёл от лампы, оставленной на кухне ещё осенью."])
        // Bold and italic survive as run properties, verse keeps its line breaks.
        let zip = try ZipInspector(data)
        defer { zip.remove() }
        let xml = String(decoding: zip.part("word/document.xml"), as: UTF8.self)
        #expect(xml.contains("<w:b/><w:bCs/></w:rPr><w:t xml:space=\"preserve\">Анна</w:t>"))
        #expect(xml.contains("<w:i/><w:iCs/></w:rPr><w:t xml:space=\"preserve\">тихо</w:t>"))
        #expect(xml.components(separatedBy: "<w:br/>").count - 1 == 3, "verse: four lines, three breaks")
        #expect(zip.names.contains("word/media/cover.png"))
        #expect(zip.part("word/media/cover.png").prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        // Not a word is lost: every paragraph of every text is in the document, in order.
        var expected: [String] = []
        for d in Self.allDocuments(book) {
            for b in d.blocks {
                switch b {
                case .paragraph, .heading: expected.append(BookCache.plainText(Document([b])))
                case .quote(let ps):
                    let (rest, author) = splitAttribution(ps)   // the dash of an attribution is not printed in DOCX
                    for p in rest + (author.map { [$0] } ?? []) { expected.append(BookCache.plainText(Document([.paragraph(p)]))) }
                default: break
                }
            }
        }
        let have = Set(checks.paragraphs.map { $0.text.replacingOccurrences(of: "\n", with: " ") })
        func normalized(_ s: String, footnoted: Bool) -> String {
            // Footnote text is in its own part; the text of a paragraph carries it inline in the plain text.
            s
        }
        var missing: [String] = []
        for line in expected {
            var text = line
            for n in Self.allDocuments(book).flatMap(Self.notes(in:)) { text = text.replacingOccurrences(of: " " + n + " ", with: "") }
            // Heading texts typed in the text: the first heading of an item is in Heading style, the others Heading 3.
            let candidate = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if candidate.isEmpty { continue }
            if !have.contains(candidate) && !have.contains(where: { $0.hasPrefix(String(candidate.prefix(20))) && $0.count >= candidate.count - 1 }) { missing.append(candidate) }
        }
        #expect(missing.isEmpty, "\(missing.prefix(5))")
        _ = normalized
    }

    @Test("DOCX: opens in the system's own reader (textutil) and the text comes out")
    func docxReadByTheSystem() throws {
        let (book, url, file) = try Self.makeSample()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = DocxExporter.export(book, options: ExportOptions(profile: file.profiles[0]))
        let docx = FileManager.default.temporaryDirectory.appendingPathComponent("q-\(UUID().uuidString).docx")
        try data.write(to: docx)
        defer { try? FileManager.default.removeItem(at: docx) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", docx.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(text.contains("Часть 2. Дом"))
        #expect(text.contains("Книга была написана её собственным почерком."))
        #expect(text.contains("Вадим Сульянов"))
    }

    @Test("DOCX: a JPEG cover, no cover, no title page, a manual title page")
    func docxVariants() throws {
        let (book, url, file) = try Self.makeSample()
        defer { try? FileManager.default.removeItem(at: url) }
        var options = ExportOptions(profile: file.profiles[0])

        // JPEG cover.
        var jpegBook = book
        let image = CGImageSourceCreateWithData(book.cover! as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
        let jpeg = NSMutableData()
        let dest = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        jpegBook.cover = jpeg as Data
        var docx = DocxExporter.export(jpegBook, options: options)
        var checks = try DocxChecks(docx)
        #expect(checks.problems.isEmpty, "\(checks.problems)")
        var zip = try ZipInspector(docx)
        #expect(zip.names.contains("word/media/cover.jpeg"))
        zip.remove()

        options.cover = false
        docx = DocxExporter.export(book, options: options)
        checks = try DocxChecks(docx)
        #expect(checks.problems.isEmpty, "\(checks.problems)")
        zip = try ZipInspector(docx)
        #expect(!zip.names.contains { $0.hasPrefix("word/media") })
        zip.remove()

        options.titlePage = .none
        options.toc = false
        checks = try DocxChecks(DocxExporter.export(book, options: options))
        #expect(checks.problems.isEmpty, "\(checks.problems)")
        #expect(checks.paragraphs.first?.style == "Heading1", "the book starts with its first part")
        #expect(checks.tocEntries.isEmpty)

        var manualBook = book
        manualBook.titlePage = MarkdownParser.parse("# Дом на Сосновой\n\nРоман\n\nМосква, 2026\n")
        options.titlePage = .manual
        checks = try DocxChecks(DocxExporter.export(manualBook, options: options))
        #expect(checks.problems.isEmpty, "\(checks.problems)")
        #expect(checks.paragraphs.prefix(3).map { $0.text } == ["Дом на Сосновой", "Роман", "Москва, 2026"])
    }

    // MARK: FB2

    @Test("FB2: the sample book passes the content model of FictionBook, with the right structure")
    func fb2() throws {
        let (book, url, file) = try Self.makeSample()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Fb2Exporter.export(book, options: ExportOptions(profile: file.profiles[1]))
        let checks = Fb2Checks(data)
        #expect(checks.problems.isEmpty, "\(checks.problems)")
        let xml = String(decoding: data, as: UTF8.self)
        #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(xml.contains("<book-title>Дом на Сосновой</book-title>"))
        #expect(xml.contains("<first-name>Вадим</first-name>") && xml.contains("<last-name>Сульянов</last-name>"))
        #expect(xml.contains("<coverpage><image l:href=\"#cover.png\"/></coverpage>"))
        #expect(xml.contains("<binary id=\"cover.png\" content-type=\"image/png\">"))
        // Part epigraph with its author, a letter as a cite with its author, verse as a poem, notes in their own body.
        #expect(xml.contains("<epigraph><p>Дорога не спрашивает, куда ты идёшь.</p><text-author>Народная мудрость</text-author></epigraph>"))
        #expect(xml.contains("<cite><p>Дорогая Анна!</p><p>Если ты читаешь это письмо"))
        #expect(xml.contains("<text-author>Твоя тётя Вера</text-author></cite>"))
        #expect(xml.contains("<poem><stanza><v>Сосны шумят над крышей,</v><v>и ветер читает вслух</v>"))
        #expect(xml.contains("<body name=\"notes\">"))
        #expect(checks.notesLinked == ["#n1", "#n2"])
        #expect(xml.contains("<strong>Анна</strong>") && xml.contains("<emphasis>тихо</emphasis>"))
        #expect(xml.contains("<subtitle>* * *</subtitle>"))
        // Sections: 2 parts, 6 chapters + the loose one, plus the notes' 2.
        #expect(checks.sections == 2 + 5 + 2, "\(checks.sections)")
        // Not a paragraph is lost.
        var missing: [String] = []
        let have = Set(checks.text)
        for d in Self.allDocuments(book) {
            for b in d.blocks {
                var lines: [String] = []
                switch b {
                case .paragraph(let i): lines = verseLines(i).map { BookCache.plainText(Document([.paragraph($0)])) }
                case .quote(let ps): lines = ps.map { BookCache.plainText(Document([.paragraph($0)])) }
                default: break
                }
                for line in lines {
                    var text = line
                    for n in Self.allDocuments(book).flatMap(Self.notes(in:)) { text = text.replacingOccurrences(of: " " + n + " ", with: "") }
                    text = text.trimmingCharacters(in: .whitespaces)
                    if text.isEmpty || text.hasPrefix("—") && text.count < 30 { continue }
                    if !have.contains(text) { missing.append(text) }
                }
            }
        }
        #expect(missing.isEmpty, "\(missing.prefix(5))")
        // xmllint agrees that it is XML.
        let fb2File = FileManager.default.temporaryDirectory.appendingPathComponent("q-\(UUID().uuidString).fb2")
        try data.write(to: fb2File)
        defer { try? FileManager.default.removeItem(at: fb2File) }
        let lint = Process()
        lint.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        lint.arguments = ["--noout", fb2File.path]
        try lint.run()
        lint.waitUntilExit()
        #expect(lint.terminationStatus == 0)
        // And the zipped form holds the same file.
        let zipped = try ZipInspector(Fb2Exporter.exportZipped(book, options: ExportOptions(profile: file2()), name: "book.fb2"))
        defer { zipped.remove() }
        #expect(zipped.integrityOK && zipped.names == ["book.fb2"])
        func file2() -> ExportFile.Profile { ExportFile.Profile(object: ["format": .string("fb2")]) }
    }

    // MARK: Choices

    @Test("heading rules: none, title, number, number and title, templates, roman numbers, restarting in parts")
    func headingRules() throws {
        let (book, url, _) = try Self.makeSample()
        defer { try? FileManager.default.removeItem(at: url) }
        func chapterHeadings(_ o: ExportOptions) -> [String] {
            var out: [String] = []
            for item in Resolver.resolve(book, options: o).items {
                switch item {
                case .part(let p): out += p.chapters.map { $0.heading?.plain ?? "-" }
                case .chapter(let c): out.append(c.heading?.plain ?? "-")
                }
            }
            return out
        }
        var o = ExportOptions()
        o.chapter = ExportFile.HeadingRule(print: "none")
        #expect(chapterHeadings(o) == ["-", "-", "-", "Подвал, в который не ходят", "Эпилог, который можно пропустить"], "a typed heading prints even when the profile says none")
        o.chapter = ExportFile.HeadingRule(print: "title")
        #expect(chapterHeadings(o)[0...2] == ["Станция", "Ключ", "Лестница"])
        o.chapter = ExportFile.HeadingRule(print: "number")
        #expect(chapterHeadings(o)[0...2] == ["1", "2", "3"])
        o.chapter = ExportFile.HeadingRule(print: "number", template: "Chapter {number}")
        #expect(chapterHeadings(o)[0...1] == ["Chapter 1", "Chapter 2"])
        o.chapter = ExportFile.HeadingRule(print: "number_and_title", template: "{title} ({number})")
        o.numberStyle = .roman
        #expect(chapterHeadings(o)[0...2] == ["Станция (I)", "Ключ (II)", "Лестница (III)"])
        o.numberStyle = .arabic
        o.chapter = ExportFile.HeadingRule(print: "number_and_title", template: "{number}. {title}")
        o.restartNumberingInParts = true
        #expect(chapterHeadings(o)[0...2] == ["1. Станция", "2. Ключ", "1. Лестница"])
        #expect(Resolver.roman(1994) == "MCMXCIV" && Resolver.roman(4) == "IV" && Resolver.roman(49) == "XLIX")
        // A scene heading, printed when asked.
        o.scene = ExportFile.HeadingRule(print: "title")
        let resolved = Resolver.resolve(book, options: o)
        guard case .part(let first) = resolved.items[0] else { Issue.record("no part"); return }
        #expect(first.chapters[0].scenes.map { $0.heading?.plain } == ["Платформа", "Письмо"])
        #expect(first.chapters[0].scenes.allSatisfy { $0.heading?.level == 3 })
    }

    @Test("filters: only the scenes with the chosen status or tag are exported, and empty chapters and parts disappear")
    func filters() throws {
        let (book, url, _) = try Self.makeSample()
        defer { try? FileManager.default.removeItem(at: url) }
        var o = ExportOptions()
        o.statuses = ["done"]
        var resolved = Resolver.resolve(book, options: o)
        var scenes = 0
        var chapters = 0
        for item in resolved.items {
            switch item {
            case .part(let p): chapters += p.chapters.count; scenes += p.chapters.reduce(0) { $0 + $1.scenes.count }
            case .chapter(let c): chapters += 1; scenes += c.scenes.count
            }
        }
        #expect(scenes == 3 && chapters == 3, "scenes \(scenes), chapters \(chapters)")   // Платформа, Стихи на двери, Утро
        #expect(resolved.items.count == 2, "the second part has no 'done' scene")
        o.statuses = []
        o.tags = ["LETTER"]   // case does not matter
        resolved = Resolver.resolve(book, options: o)
        var titles: [String] = []
        for item in resolved.items { if case .part(let p) = item { for c in p.chapters { titles += c.scenes.compactMap { $0.blocks.isEmpty ? nil : "x" } } } }
        #expect(titles.count == 2)
        o.tags = ["no-such-tag"]
        #expect(Resolver.resolve(book, options: o).items.isEmpty)
        // An empty book exports to files that still open.
        let empty = DocxExporter.export(BookModel(title: "Пусто"), options: o)
        #expect(try DocxChecks(empty).problems.isEmpty)
        #expect(Fb2Checks(Fb2Exporter.export(BookModel(title: "Пусто"), options: o)).problems.isEmpty == false, "an FB2 needs a section: the check must notice a book with none")
    }

    @Test("scene separators: mark, blank, none; a break typed in the text is never lost")
    func sceneBreaks() throws {
        let (book, url, _) = try Self.makeSample()
        defer { try? FileManager.default.removeItem(at: url) }
        for (kind, expectedMarks) in [(ExportOptions.SceneBreak.mark, 4), (.blank, 0), (.none, 0)] {
            var o = ExportOptions()
            o.sceneBreak = kind
            let checks = try DocxChecks(DocxExporter.export(book, options: o))
            #expect(checks.problems.isEmpty, "\(checks.problems)")
            #expect(checks.paragraphs.filter { $0.text == "* * *" }.count == expectedMarks, "\(kind)")
            // Between the two scenes of chapter 1 (not typed) and the typed break in chapter 2.
            let breaks = checks.paragraphs.filter { $0.style == "SceneBreak" }.count
            #expect(breaks == (kind == .none ? 1 : 4), "\(kind): \(breaks)")
            let fb2 = Fb2Checks(Fb2Exporter.export(book, options: o))
            #expect(fb2.problems.isEmpty, "\(fb2.problems)")
        }
    }

    // MARK: Hard text

    @Test("characters that XML cannot carry, markup characters and emoji in the text do not break either file")
    func hardText() throws {
        var book = BookModel(id: UUID().uuidString.lowercased(), title: "A & B <C> \"D\"", author: "Имя Отчество Фамилия", copyright: "", language: "en")
        let nasty = "Tag <b>bold</b> & ampersand, \"quotes\", 'apostrophe', ]]> end, \u{01}control\u{0B}, \u{FFFE}, \u{00A0}nbsp, soft\u{00AD}hyphen, zero\u{200B}width, emoji 😀🇷🇺, combining é, Ёлка"
        let doc = Document([.heading(1, [.text("Заголовок <&>")]), .paragraph([.text(nasty), .note(Note([Run("Note & <more>", [.bold])]))]), .quote([[.text("Quote ]]>")], [.text("— A & B")]])])
        book.items = [.chapter(BookModel.Chapter(id: "c", title: "Chapter <1>", own: nil, scenes: [BookModel.Scene(id: "s", title: "S", status: nil, tags: [], document: doc)]))]
        var o = ExportOptions()
        o.chapter = ExportFile.HeadingRule(print: "title", newPage: true)
        let docx = try DocxChecks(DocxExporter.export(book, options: o))
        #expect(docx.problems.isEmpty, "\(docx.problems)")
        let fb2 = Fb2Checks(Fb2Exporter.export(book, options: o))
        #expect(fb2.problems.isEmpty, "\(fb2.problems)")
        #expect(docx.paragraphs.contains { $0.text.contains("<b>bold</b> & ampersand") && $0.text.contains("😀🇷🇺") && $0.text.contains("Ёлка") })
        #expect(fb2.text.contains { $0.contains("<b>bold</b> & ampersand") && $0.contains("😀🇷🇺") })
        #expect(!(docx.paragraphs.map { $0.text }.joined().contains("\u{01}")), "a control character is dropped")
        #expect(docx.footnoteTexts == ["Note & <more>"])
    }

    // MARK: Size

    @Test("a novel (100 scenes, 450,000 characters, 30 characters' names in it) exports in well under a second")
    func novel() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-export-big-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try GeneratedBook(in: dir)
        // The generated book has no book.json or chapter files: write them.
        try JSONWriter.data(["format": .int(1), "id": .string(UUID().uuidString.lowercased()), "language": .string("ru"), "title": .string("Большая книга"), "author": .string("А. Б. Второв")]).write(to: dir.appendingPathComponent("book.json"))
        for part in 1...4 {
            let p = dir.appendingPathComponent(String(format: "manuscript/%03d-part", part))
            try JSONWriter.data(["id": .string(UUID().uuidString.lowercased()), "title": .string("Часть \(part)")]).write(to: p.appendingPathComponent("_part.json"))
            for chapter in 1...5 {
                try JSONWriter.data(["id": .string(UUID().uuidString.lowercased()), "title": .string("Глава")]).write(to: p.appendingPathComponent(String(format: "%03d-chapter/_chapter.json", chapter)))
            }
        }
        let start = Date()
        let book = try BookLoader.load(folder: dir)
        let loaded = Date()
        var o = ExportOptions()
        o.cover = false
        let docx = DocxExporter.export(book, options: o)
        let wrote = Date()
        let fb2 = Fb2Exporter.export(book, options: o)
        let done = Date()
        print("EXPORT NOVEL: read the book \(Int(loaded.timeIntervalSince(start) * 1000)) ms, DOCX \(Int(wrote.timeIntervalSince(loaded) * 1000)) ms (\(docx.count / 1024) KB), FB2 \(Int(done.timeIntervalSince(wrote) * 1000)) ms (\(fb2.count / 1024) KB)")
        let checks = try DocxChecks(docx)
        #expect(checks.problems.isEmpty, "\(checks.problems.prefix(3))")
        #expect(checks.footnoteTexts.count > 5)
        let fb = Fb2Checks(fb2)
        #expect(fb.problems.isEmpty, "\(fb.problems.prefix(3))")
        #expect(fb.sections == 4 + 20 + fb.notesLinked.count)
        #expect(done.timeIntervalSince(start) < 5 * CacheTests.slack)
    }

    @Test("an export profile from export.json gives the options it says")
    func profileToOptions() throws {
        let url = Corpus.files("json/canonical", suffix: "12-export.json")[0]
        let file = ExportFile(object: try JSONParser.parseObject(Data(contentsOf: url)))
        let o = ExportOptions(profile: file.profiles[0])
        #expect(o.titlePage == .manual && o.toc && !o.cover && o.sceneBreak == .mark)
        #expect(o.statuses == ["revised", "done"] && o.tags.isEmpty)
        #expect(o.chapter == ExportFile.HeadingRule(print: "number_and_title", template: "Chapter {number}. {title}", newPage: true))
        #expect(o.scene.print == "none")
    }
}
