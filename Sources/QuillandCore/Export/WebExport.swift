import Foundation
import ImageIO

// HTML, EPUB and plain text, made from the same resolved plan as DOCX and FB2 (`Resolver`): what is in, what each heading says, which
// typed heading wins and what separates scenes are decided once, so no format can disagree with another.

/// One part of the book as a page of its own (a part's heading and own text, or a chapter), with where it goes in the contents.
struct WebPage {
    struct SceneEntry { var anchor: String; var title: String }
    var id: String
    var level: Int
    var title: String
    var html: String
    var newPage: Bool
    /// The chapter's scenes, for the contents when the profile asks for them.
    var scenes: [SceneEntry] = []
}

struct WebBuilder {
    let book: Resolved
    let epub: Bool
    var noteCount = 0
    private(set) var footnoteTotal = 0

    init(_ book: Resolved, epub: Bool) {
        self.book = book
        self.epub = epub
    }

    // MARK: Inline and blocks

    mutating func inline(_ inlines: [Inline], notes: inout [String]) -> String {
        var out = ""
        for item in inlines {
            switch item {
            case .run(let run):
                if run.text.isEmpty { continue }
                var t = XML.escape(run.text)
                if run.style.contains(.italic) { t = "<em>\(t)</em>" }
                if run.style.contains(.bold) { t = "<strong>\(t)</strong>" }
                out += t
            case .lineBreak:
                out += "<br/>"
            case .note(let note):
                noteCount += 1
                footnoteTotal += 1
                var content = ""
                for r in note.content where !r.text.isEmpty {
                    var t = XML.escape(r.text)
                    if r.style.contains(.italic) { t = "<em>\(t)</em>" }
                    if r.style.contains(.bold) { t = "<strong>\(t)</strong>" }
                    content += t
                }
                notes.append(content)
                let type = epub ? " epub:type=\"noteref\"" : ""
                out += "<a class=\"noteref\" id=\"r\(noteCount)\" href=\"#n\(noteCount)\"\(type)>[\(noteCount)]</a>"
            }
        }
        return out
    }

    mutating func block(_ block: Block, notes: inout [String]) -> String {
        switch block {
        case .paragraph(let i):
            let t = inline(i, notes: &notes)
            if t.isEmpty { return "" }
            return hasLineBreak(i) ? "<p class=\"verse\">\(t)</p>\n" : "<p>\(t)</p>\n"
        case .heading(let level, let i):
            return "<h\(min(6, level + 3)) class=\"inner\">\(inline(i, notes: &notes))</h\(min(6, level + 3))>\n"
        case .quote(let paragraphs):
            let (rest, author) = splitAttribution(paragraphs)
            var s = "<blockquote>\n"
            for p in rest { s += (hasLineBreak(p) ? "<p class=\"verse\">" : "<p>") + inline(p, notes: &notes) + "</p>\n" }
            if let author { s += "<p class=\"attribution\">— \(inline(author, notes: &notes))</p>\n" }
            return s + "</blockquote>\n"
        case .sceneBreak:
            return book.options.sceneBreak == .mark ? "<p class=\"break\">* * *</p>\n" : "<p class=\"gap\">&#160;</p>\n"
        case .fragment:
            return ""
        }
    }

    mutating func heading(_ h: RHeading?, notes: inout [String], id: String? = nil) -> String {
        guard let h else { return "" }
        let idAttr = id.map { " id=\"\($0)\"" } ?? ""
        return "<h\(h.level)\(idAttr)>\(inline(h.inlines, notes: &notes))</h\(h.level)>\n"
    }

    func notesHTML(_ notes: [String], firstNumber: Int) -> String {
        guard !notes.isEmpty else { return "" }
        var s = "<aside class=\"notes\">\n<hr/>\n"
        for (i, n) in notes.enumerated() {
            let number = firstNumber + i
            let type = epub ? " epub:type=\"footnote\"" : ""
            s += "<p id=\"n\(number)\"\(type)><a href=\"#r\(number)\">[\(number)]</a> \(n)</p>\n"
        }
        return s + "</aside>\n"
    }

    // MARK: Pages

    mutating func chapterBody(_ chapter: RChapter, notes: inout [String], pageID: String, entries: inout [WebPage.SceneEntry]) -> String {
        var s = ""
        for b in chapter.own { s += block(b, notes: &notes) }
        for (i, scene) in chapter.scenes.enumerated() {
            if i > 0 {
                switch book.options.sceneBreak {
                case .mark: s += "<p class=\"break\">* * *</p>\n"
                case .blank: s += "<p class=\"gap\">&#160;</p>\n"
                case .none: break
                }
            }
            // A scene that is in the contents has a place to link to: its heading when it prints one, else an empty mark.
            let anchor = "s\(pageID)_\(i + 1)"
            if book.options.tocScenes {
                let title = scene.heading?.plain ?? scene.title
                entries.append(.init(anchor: anchor, title: title.isEmpty ? scene.title : title))
                if scene.heading == nil { s += "<span id=\"\(anchor)\"></span>\n" }
            }
            if let h = scene.heading { s += heading(h, notes: &notes, id: book.options.tocScenes ? anchor : nil) }
            for b in scene.blocks { s += block(b, notes: &notes) }
        }
        return s
    }

    mutating func pages() -> [WebPage] {
        var out: [WebPage] = []
        var n = 0
        func page(_ level: Int, _ title: String, _ newPage: Bool, _ make: (inout WebBuilder, inout [String], String, inout [WebPage.SceneEntry]) -> String) {
            n += 1
            let id = "p\(n)"
            var notes: [String] = []
            var entries: [WebPage.SceneEntry] = []
            let first = noteCount + 1
            let body = make(&self, &notes, id, &entries)
            out.append(WebPage(id: id, level: level, title: title, html: body + notesHTML(notes, firstNumber: first), newPage: newPage, scenes: entries))
        }
        for item in book.items {
            switch item {
            case .chapter(let c):
                page(2, c.heading?.plain ?? "", c.heading?.newPage ?? true) { me, notes, id, entries in
                    "<section id=\"\(id)\">\n" + me.heading(c.heading, notes: &notes) + me.chapterBody(c, notes: &notes, pageID: id, entries: &entries) + "</section>\n"
                }
            case .part(let p):
                page(1, p.heading?.plain ?? "", p.heading?.newPage ?? true) { me, notes, id, _ in
                    var s = "<section id=\"\(id)\" class=\"part\">\n" + me.heading(p.heading, notes: &notes)
                    for b in p.own { s += me.block(b, notes: &notes) }
                    return s + "</section>\n"
                }
                for c in p.chapters {
                    page(2, c.heading?.plain ?? "", c.heading?.newPage ?? true) { me, notes, id, entries in
                        "<section id=\"\(id)\">\n" + me.heading(c.heading, notes: &notes) + me.chapterBody(c, notes: &notes, pageID: id, entries: &entries) + "</section>\n"
                    }
                }
            }
        }
        return out
    }

    /// The title page as HTML: the author's own, or one made from the book's data (nothing when the profile says none).
    mutating func titlePageHTML() -> String {
        var notes: [String] = []
        switch book.options.titlePage {
        case .none: return ""
        case .manual:
            if let blocks = book.titlePage {
                return "<section class=\"titlepage\">\n" + blocks.map { block($0, notes: &notes) }.joined() + "</section>\n"
            }
            fallthrough
        case .auto:
            var s = "<section class=\"titlepage\">\n<h1 class=\"title\">\(XML.escape(book.title))</h1>\n"
            if !book.author.isEmpty { s += "<p class=\"author\">\(XML.escape(book.author))</p>\n" }
            if !book.copyright.isEmpty { s += "<p class=\"copyright\">\(XML.escape(book.copyright))</p>\n" }
            return s + "</section>\n"
        }
    }

    /// What turns the page into a book page: the paper, the margins, the font and spacing of the profile's layout, chapters on new pages, the cover alone on its page.
    static func printCSS(_ layout: ExportOptions.Layout) -> String {
        let mm = { (twips: Int) in String(format: "%.1f", Double(twips) / 56.6929) + "mm" }
        let size = Double(layout.halfPoints) / 2
        let spacing = min(1.7, max(1.15, Double(layout.lineSpacing240) / 240 * 0.8))
        let indent = String(format: "%.2f", Double(layout.firstLineIndentTwips) / 20 / max(1, size)) + "em"
        return """
        @page { size: \(mm(layout.pageWidthTwips)) \(mm(layout.pageHeightTwips)); margin: \(mm(layout.marginTwips)); }
        html { -webkit-print-color-adjust: exact; }
        body { font-family: "\(layout.font)", "Times New Roman", Georgia, serif; font-size: \(size)pt; line-height: \(spacing); max-width: none; margin: 0; padding: 0; }
        p { text-indent: \(indent); orphans: 2; widows: 2; }
        h1 + p, h2 + p, h3 + p, p.break + p, p.gap + p, blockquote + p { text-indent: 0; }
        .cover { break-after: page; page-break-after: always; margin: 0; } .cover img { max-width: 100%; max-height: 240mm; }
        .titlepage { break-after: page; page-break-after: always; margin-top: 30%; }
        nav.contents { break-after: page; page-break-after: always; }
        h1, h2, h3 { break-after: avoid; page-break-after: avoid; }
        aside.notes { break-inside: avoid; }
        a { color: inherit; text-decoration: none; }
        """
    }

    static var css: String {
        """
        body { font-family: Georgia, "Times New Roman", serif; line-height: 1.55; margin: 0 auto; max-width: 40em; padding: 2em 1.2em; }
        h1, h2, h3 { font-weight: normal; text-align: center; line-height: 1.25; }
        h1 { font-size: 1.8em; margin: 2.2em 0 1em; } h2 { font-size: 1.45em; margin: 2em 0 1em; } h3 { font-size: 1.15em; margin: 1.6em 0 .8em; }
        h4, h5, h6 { font-size: 1em; font-style: italic; }
        p { margin: 0; text-indent: 1.4em; text-align: justify; }
        h1 + p, h2 + p, h3 + p, p.break + p, p.gap + p, blockquote + p { text-indent: 0; }
        p.break { text-align: center; text-indent: 0; margin: 1.2em 0; letter-spacing: .4em; }
        p.gap { text-indent: 0; margin: 1.2em 0; }
        p.verse { text-indent: 0; text-align: left; margin: .8em 0; }
        blockquote { margin: 1em 2em; font-size: .95em; } blockquote p { text-indent: 0; }
        p.attribution { text-align: right; font-style: italic; }
        .titlepage { text-align: center; margin: 6em 0 4em; } .titlepage .title { font-size: 2.4em; margin: 0 0 .6em; }
        .titlepage p { text-indent: 0; text-align: center; } .author { font-size: 1.3em; }
        .cover { text-align: center; } .cover img { max-width: 100%; max-height: 95vh; }
        nav.contents ol { list-style: none; padding-left: 0; } nav.contents li.l1 { margin-top: .8em; font-weight: bold; } nav.contents li.l2 { margin-left: 1.2em; } nav.contents li.l3 { margin-left: 1.2em; font-weight: normal; } nav.contents ol ol { margin: 0; padding-left: 0; }
        a.noteref { font-size: .75em; vertical-align: super; text-decoration: none; }
        aside.notes { font-size: .85em; margin-top: 2em; } aside.notes p { text-indent: 0; text-align: left; }
        @media print { section { break-inside: auto; } h1, h2 { break-after: avoid; } }
        """
    }
}

// MARK: Plain text

/// A text file, always UTF-8: titles, paragraphs separated by a blank line, `* * *` between scenes, notes after their chapter.
public enum TxtExporter {
    public static func export(_ book: BookModel, options: ExportOptions) -> Data {
        let r = Resolver.resolve(book, options: options)
        var out = ""
        func text(_ inlines: [Inline], _ notes: inout [String]) -> String {
            var s = ""
            for i in inlines {
                switch i {
                case .run(let run): s += run.text
                case .lineBreak: s += "\n"
                case .note(let n):
                    notes.append(n.content.map(\.text).joined())
                    s += "[\(noteNumber(notes.count))]"
                }
            }
            return s
        }
        var counter = 0
        func noteNumber(_ local: Int) -> Int { counter + local }
        func blocks(_ list: [Block], _ notes: inout [String]) -> String {
            var s = ""
            for b in list {
                switch b {
                case .paragraph(let i): let t = text(i, &notes); if !t.isEmpty { s += t + "\n\n" }
                case .heading(_, let i): s += text(i, &notes) + "\n\n"
                case .quote(let ps): for p in ps { s += "    " + text(p, &notes).replacingOccurrences(of: "\n", with: "\n    ") + "\n\n" }
                case .sceneBreak: s += (options.sceneBreak == .mark ? "* * *" : "") + "\n\n"
                case .fragment: break
                }
            }
            return s
        }
        func chapter(_ c: RChapter) -> String {
            var notes: [String] = []
            var s = ""
            if let h = c.heading { s += text(h.inlines, &notes) + "\n\n" }
            s += blocks(c.own, &notes)
            for (i, scene) in c.scenes.enumerated() {
                if i > 0 { switch options.sceneBreak { case .mark: s += "* * *\n\n"; case .blank: s += "\n"; case .none: break } }
                if let h = scene.heading { s += text(h.inlines, &notes) + "\n\n" }
                s += blocks(scene.blocks, &notes)
            }
            if !notes.isEmpty {
                s += "\n"
                for (k, n) in notes.enumerated() { s += "[\(counter + k + 1)] \(n)\n" }
                s += "\n"
                counter += notes.count
            }
            return s
        }
        if r.options.titlePage != .none {
            out += r.title + "\n"
            if !r.author.isEmpty { out += r.author + "\n" }
            if !r.copyright.isEmpty { out += r.copyright + "\n" }
            out += "\n\n"
        }
        func addChapter(_ c: RChapter, indent: String, _ lines: inout [String]) {
            if let h = c.heading?.plain { lines.append(indent + h) }
            guard options.tocScenes else { return }
            for scene in c.scenes {
                let title = scene.heading?.plain ?? scene.title
                if !title.isEmpty { lines.append(indent + "  " + title) }
            }
        }
        if r.options.toc {
            var lines: [String] = []
            for item in r.items {
                switch item {
                case .chapter(let c): addChapter(c, indent: "  ", &lines)
                case .part(let p):
                    if let h = p.heading?.plain { lines.append(h) }
                    for c in p.chapters { addChapter(c, indent: "  ", &lines) }
                }
            }
            if !lines.isEmpty { out += (BookWords.contents(r.language)) + "\n\n" + lines.joined(separator: "\n") + "\n\n\n" }
        }
        for item in r.items {
            switch item {
            case .chapter(let c): out += chapter(c) + "\n"
            case .part(let p):
                var notes: [String] = []
                if let h = p.heading { out += text(h.inlines, &notes).uppercased() + "\n\n" }
                out += blocks(p.own, &notes)
                for c in p.chapters { out += chapter(c) + "\n" }
            }
        }
        while out.hasSuffix("\n\n\n") { out.removeLast() }
        return Data(out.utf8)
    }
}

// MARK: HTML

/// One self-contained HTML file: the styles inline, the cover inside as a data address, a contents list that links to the chapters.
public enum HtmlExporter {
    public static func export(_ book: BookModel, options: ExportOptions, print: Bool = false) -> Data {
        let r = Resolver.resolve(book, options: options)
        var b = WebBuilder(r, epub: false)
        let title = b.titlePageHTML()
        let pages = b.pages()
        var s = "<!DOCTYPE html>\n<html lang=\"\(XML.escape(r.language.isEmpty ? "en" : r.language))\">\n<head>\n<meta charset=\"utf-8\"/>\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>\n"
        s += "<title>\(XML.escape(r.title))</title>\n<style>\n\(WebBuilder.css)\n\(print ? WebBuilder.printCSS(r.options.layout) : "")</style>\n</head>\n<body>\n"
        if let cover = r.cover { s += "<div class=\"cover\"><img alt=\"\" src=\"data:\(mime(of: cover));base64,\(cover.base64EncodedString())\"/></div>\n" }
        s += title
        if r.options.toc {
            s += "<nav class=\"contents\">\n<h2>\(BookWords.contents(r.language))</h2>\n<ol>\n"
            for p in pages where !p.title.isEmpty {
                s += "<li class=\"l\(p.level)\"><a href=\"#\(p.id)\">\(XML.escape(p.title))</a>"
                if r.options.tocScenes, !p.scenes.isEmpty {
                    s += "\n<ol>\n" + p.scenes.map { "<li class=\"l3\"><a href=\"#\($0.anchor)\">\(XML.escape($0.title))</a></li>\n" }.joined() + "</ol>\n"
                }
                s += "</li>\n"
            }
            s += "</ol>\n</nav>\n"
        }
        for p in pages {
            s += p.newPage ? "<div style=\"break-before: page\"></div>\n" : ""
            s += p.html
        }
        return Data((s + "</body>\n</html>\n").utf8)
    }

    static func mime(of image: Data) -> String {
        guard let source = CGImageSourceCreateWithData(image as CFData, nil) else { return "image/png" }
        return (CGImageSourceGetType(source) as String?) == "public.jpeg" ? "image/jpeg" : "image/png"
    }
}

// MARK: EPUB

/// An EPUB 3: a ZIP with the contents document, one file per part or chapter, the styles and the cover.
public enum EpubExporter {
    public static func export(_ book: BookModel, options: ExportOptions, date: Date = Date()) -> Data {
        let r = Resolver.resolve(book, options: options)
        var b = WebBuilder(r, epub: true)
        let titleHTML = b.titlePageHTML()
        let pages = b.pages()
        let language = XML.escape(r.language.isEmpty ? "en" : r.language)
        let identifier = "urn:uuid:" + (r.id.isEmpty ? UUID().uuidString.lowercased() : r.id)
        let stamp: String = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: date)
        }()
        func xhtml(_ title: String, _ body: String) -> String {
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(language)" xml:lang="\(language)">
            <head><meta charset="utf-8"/><title>\(XML.escape(title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
            <body>
            \(body)</body>
            </html>
            """
        }
        var zip = ZipWriter(date: date)
        zip.add("mimetype", Data("application/epub+zip".utf8))
        zip.add("META-INF/container.xml", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
            """.utf8))
        zip.add("OEBPS/style.css", Data(WebBuilder.css.utf8))

        var manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n<item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>\n"
        var spine = ""
        var coverFile: String?
        if let cover = r.cover {
            let isJPEG = HtmlExporter.mime(of: cover) == "image/jpeg"
            let name = isJPEG ? "cover.jpg" : "cover.png"
            coverFile = name
            zip.add("OEBPS/\(name)", cover)
            manifest += "<item id=\"cover-image\" href=\"\(name)\" media-type=\"\(HtmlExporter.mime(of: cover))\" properties=\"cover-image\"/>\n"
            zip.add("OEBPS/cover.xhtml", Data(xhtml(r.title, "<div class=\"cover\"><img alt=\"\" src=\"\(name)\"/></div>\n").utf8))
            manifest += "<item id=\"cover\" href=\"cover.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"cover\" linear=\"no\"/>\n"
        }
        if !titleHTML.isEmpty {
            zip.add("OEBPS/title.xhtml", Data(xhtml(r.title, titleHTML).utf8))
            manifest += "<item id=\"title\" href=\"title.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"title\"/>\n"
        }
        for p in pages {
            zip.add("OEBPS/\(p.id).xhtml", Data(xhtml(p.title.isEmpty ? r.title : p.title, p.html).utf8))
            manifest += "<item id=\"\(p.id)\" href=\"\(p.id).xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "<itemref idref=\"\(p.id)\"/>\n"
        }
        // The contents document (always there: a reading system needs it; `toc` decides whether it is also a page of the book).
        var nav = "<nav epub:type=\"toc\" id=\"toc\" class=\"contents\">\n<h2>\(BookWords.contents(r.language))</h2>\n<ol>\n"
        for p in pages where !p.title.isEmpty {
            nav += "<li class=\"l\(p.level)\"><a href=\"\(p.id).xhtml\">\(XML.escape(p.title))</a>"
            if r.options.tocScenes, !p.scenes.isEmpty {
                nav += "\n<ol>\n" + p.scenes.map { "<li class=\"l3\"><a href=\"\(p.id).xhtml#\($0.anchor)\">\(XML.escape($0.title))</a></li>\n" }.joined() + "</ol>\n"
            }
            nav += "</li>\n"
        }
        if pages.allSatisfy({ $0.title.isEmpty }) { nav += "<li><a href=\"\(pages.first?.id ?? "title").xhtml\">\(XML.escape(r.title))</a></li>\n" }
        nav += "</ol>\n</nav>\n"
        zip.add("OEBPS/nav.xhtml", Data(xhtml(BookWords.contents(r.language), nav).utf8))
        if r.options.toc { spine += "<itemref idref=\"nav\" linear=\"no\"/>\n" }
        let creator = r.author.isEmpty ? "" : "<dc:creator>\(XML.escape(r.author))</dc:creator>\n"
        let rights = r.copyright.isEmpty ? "" : "<dc:rights>\(XML.escape(r.copyright))</dc:rights>\n"
        let coverMeta = coverFile == nil ? "" : "<meta name=\"cover\" content=\"cover-image\"/>\n"
        zip.add("OEBPS/content.opf", Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="\(language)">
            <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">\(identifier)</dc:identifier>
            <dc:title>\(XML.escape(r.title))</dc:title>
            <dc:language>\(language)</dc:language>
            \(creator)\(rights)<meta property="dcterms:modified">\(stamp)</meta>
            \(coverMeta)</metadata>
            <manifest>
            \(manifest)</manifest>
            <spine>
            \(spine)</spine>
            </package>
            """.utf8))
        return zip.finish()
    }
}
