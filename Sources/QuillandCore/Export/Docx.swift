import Foundation
import ImageIO

/// A Word document (.docx): a ZIP of XML parts, written without Word.
/// Real Word styles (Title, Heading 1–3, Quote, Footnote Text…) so a publisher can restyle the whole book,
/// real footnotes, a real contents field, page breaks before chapters, the cover as a picture.
public enum DocxExporter {
    public static func export(_ book: BookModel, options: ExportOptions, date: Date = Date()) -> Data {
        var builder = DocxBuilder(Resolver.resolve(book, options: options), date: date)
        return builder.build()
    }
}

private let wNamespaces = """
    xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
    """

private struct DocxBuilder {
    let book: Resolved
    let date: Date
    var body = ""
    var footnotes: [String] = []
    var contents: [(level: Int, text: String, bookmark: String)] = []
    var bookmarkCounter = 0
    var coverFile: (name: String, type: String, width: Int, height: Int)?

    init(_ book: Resolved, date: Date) {
        self.book = book
        self.date = date
        if let cover = book.cover, let source = CGImageSourceCreateWithData(cover as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            let isJPEG = (CGImageSourceGetType(source) as String?) == "public.jpeg"
            coverFile = (isJPEG ? "cover.jpeg" : "cover.png", isJPEG ? "image/jpeg" : "image/png", w, h)
        }
    }

    var language: String {
        switch book.language.lowercased() { case "ru": return "ru-RU"; case "en": return "en-US"; case "": return "en-US"; default: return book.language }
    }
    var contentsTitle: String { BookWords.contents(book.language) }

    // MARK: Runs

    func rPr(_ style: Style, extra: String = "") -> String {
        var inner = extra
        if style.contains(.bold) { inner += "<w:b/><w:bCs/>" }
        if style.contains(.italic) { inner += "<w:i/><w:iCs/>" }
        return inner.isEmpty ? "" : "<w:rPr>\(inner)</w:rPr>"
    }

    func textRun(_ text: String, _ style: Style) -> String {
        "<w:r>\(rPr(style))<w:t xml:space=\"preserve\">\(XML.escape(text))</w:t></w:r>"
    }

    mutating func runs(_ inlines: [Inline], base: Style = []) -> String {
        var out = ""
        for inline in inlines {
            switch inline {
            case .run(let run):
                if !run.text.isEmpty { out += textRun(run.text, run.style.union(base)) }
            case .lineBreak:
                out += "<w:r><w:br/></w:r>"
            case .note(let note):
                footnotes.append(note.content.map { textRun($0.text, $0.style) }.joined())
                out += "<w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:footnoteReference w:id=\"\(footnotes.count)\"/></w:r>"
            }
        }
        return out
    }

    func paragraph(style: String?, props: String = "", content: String) -> String {
        let pStyle = style.map { "<w:pStyle w:val=\"\($0)\"/>" } ?? ""
        let pPr = (pStyle + props).isEmpty ? "" : "<w:pPr>\(pStyle)\(props)</w:pPr>"
        return "<w:p>\(pPr)\(content)</w:p>"
    }

    // MARK: Pieces of the body

    mutating func heading(_ h: RHeading) {
        let toc = h.level <= (book.options.tocScenes ? 3 : 2)
        var content = runs(h.inlines)
        if toc {
            bookmarkCounter += 1
            let name = "_Toc\(100_000 + bookmarkCounter)"
            content = "<w:bookmarkStart w:id=\"\(bookmarkCounter)\" w:name=\"\(name)\"/>" + content + "<w:bookmarkEnd w:id=\"\(bookmarkCounter)\"/>"
            contents.append((h.level, h.plain, name))
        }
        body += paragraph(style: "Heading\(h.level)", props: h.newPage ? "<w:pageBreakBefore/>" : "", content: content)
    }

    mutating func block(_ block: Block, level: Int) {
        switch block {
        case .paragraph(let inlines):
            body += paragraph(style: nil, content: runs(inlines))
        case .heading(_, let inlines):
            // A heading typed in the middle of a text is a Heading 3 whatever its level (a proposal: levels inside a chapter are not the book's levels).
            body += paragraph(style: "Heading3", content: runs(inlines))
        case .quote(let paragraphs):
            let (rest, author) = splitAttribution(paragraphs)
            for p in rest { body += paragraph(style: "Quote", content: runs(p)) }
            if let author { body += paragraph(style: "QuoteAuthor", content: runs(author)) }
        case .sceneBreak:
            sceneSeparator(typed: true)
        case .emptyLine:
            body += paragraph(style: nil, content: "")
        case .fragment:
            break
        }
    }

    mutating func sceneSeparator(typed: Bool) {
        switch book.options.sceneBreak {
        case .mark: body += paragraph(style: "SceneBreak", content: textRun("* * *", []))
        case .blank: body += paragraph(style: "SceneBreak", content: "")
        case .none: if typed { body += paragraph(style: "SceneBreak", content: "") }
        }
    }

    func pageBreak() -> String { "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }

    func coverParagraph() -> String {
        guard let cover = coverFile else { return "" }
        let cx = 4_320_000 // 12 cm in EMU
        var cy = cx * cover.height / max(cover.width, 1)
        var width = cx
        if cy > 4_680_000 { width = width * 4_680_000 / cy; cy = 4_680_000 } // at most 13 cm tall, so cover, title and copyright fit one page
        let drawing = """
            <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(width)" cy="\(cy)"/>\
            <wp:docPr id="1" name="Cover" descr="Cover of \(XML.escape(book.title))"/>\
            <wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>\
            <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>\
            <pic:nvPicPr><pic:cNvPr id="0" name="\(cover.name)"/><pic:cNvPicPr/></pic:nvPicPr>\
            <pic:blipFill><a:blip r:embed="rIdCover"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
            <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
            </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
            """
        return paragraph(style: "TitlePageText", content: drawing)
    }

    mutating func titlePage() -> Bool {
        let opt = book.options
        guard opt.titlePage != .none else { return false }
        body += coverParagraph()
        if opt.titlePage == .manual, let blocks = book.titlePage {
            for b in blocks {
                switch b {
                case .paragraph(let i): body += paragraph(style: "TitlePageText", content: runs(i))
                case .heading(_, let i): body += paragraph(style: "Title", content: runs(i))
                case .quote(let ps): for p in ps { body += paragraph(style: "TitlePageText", content: runs(p)) }
                case .sceneBreak, .fragment, .emptyLine: break
                }
            }
        } else {
            body += paragraph(style: "Title", content: textRun(book.title, []))
            if !book.author.isEmpty { body += paragraph(style: "Subtitle", content: textRun(book.author, [])) }
            if !book.copyright.isEmpty { body += paragraph(style: "Copyright", content: textRun(book.copyright, [])) }
        }
        body += pageBreak()
        return true
    }

    // MARK: The whole document

    mutating func build() -> Data {
        let hasTitlePage = titlePage()
        let titleEnd = body
        body = ""

        for item in book.items {
            switch item {
            case .part(let part):
                if let h = part.heading { heading(h) }
                for b in part.own { block(b, level: 1) }
                for chapter in part.chapters { self.chapter(chapter) }
            case .chapter(let chapter):
                self.chapter(chapter)
            }
        }
        let main = body
        body = ""

        var front = titleEnd
        if book.options.toc, !contents.isEmpty {
            front += paragraph(style: "TOCHeading", content: textRun(contentsTitle, []))
            front += tocField()
            front += pageBreak()
        }
        let sectPr = """
            <w:sectPr><w:footerReference w:type="default" r:id="rIdFooter"/><w:footerReference w:type="first" r:id="rIdFooterFirst"/>\
            <w:pgSz w:w="\(book.options.layout.pageWidthTwips)" w:h="\(book.options.layout.pageHeightTwips)"/>\
            <w:pgMar w:top="\(book.options.layout.marginTwips)" w:right="\(book.options.layout.marginTwips)" w:bottom="\(book.options.layout.marginTwips)" w:left="\(book.options.layout.marginTwips)" w:header="709" w:footer="709" w:gutter="0"/>\
            \(hasTitlePage ? "<w:titlePg/>" : "")</w:sectPr>
            """
        let document = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:document \(wNamespaces)><w:body>\(front)\(main)\(sectPr)</w:body></w:document>"

        var zip = ZipWriter(date: date)
        zip.add("[Content_Types].xml", text: contentTypes())
        zip.add("_rels/.rels", text: rootRels())
        zip.add("docProps/core.xml", text: core())
        zip.add("docProps/app.xml", text: app())
        zip.add("word/document.xml", text: document)
        zip.add("word/_rels/document.xml.rels", text: documentRels())
        zip.add("word/styles.xml", text: styles())
        zip.add("word/settings.xml", text: settings())
        zip.add("word/footnotes.xml", text: footnotesXML())
        zip.add("word/footer1.xml", text: footer(withNumber: true))
        zip.add("word/footer2.xml", text: footer(withNumber: false))
        if let cover = coverFile, let data = book.cover { zip.add("word/media/\(cover.name)", data) }
        return zip.finish()
    }

    mutating func chapter(_ chapter: RChapter) {
        if let h = chapter.heading { heading(h) }
        for b in chapter.own { block(b, level: 2) }
        for (i, scene) in chapter.scenes.enumerated() {
            if i > 0 { sceneSeparator(typed: false) }
            if let h = scene.heading { heading(h) }
            for b in scene.blocks { block(b, level: 3) }
        }
    }

    func tocField() -> String {
        var out = ""
        let dirty = book.options.refreshContentsInWord ? " w:dirty=\"true\"" : ""
        for (i, entry) in contents.enumerated() {
            var content = ""
            if i == 0 {
                content += "<w:r><w:fldChar w:fldCharType=\"begin\"\(dirty)/></w:r><w:r><w:instrText xml:space=\"preserve\"> TOC \\o \"1-\(book.options.tocScenes ? 3 : 2)\" \\h \\z \\u </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
            }
            content += "<w:hyperlink w:anchor=\"\(entry.bookmark)\" w:history=\"1\">\(textRun(entry.text, []))</w:hyperlink>"
            out += paragraph(style: "TOC\(entry.level)", content: content)
        }
        out += "<w:p><w:r><w:fldChar w:fldCharType=\"end\"/></w:r></w:p>"
        return out
    }

    // MARK: The other parts

    func contentTypes() -> String {
        var s = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>
            """
        if let cover = coverFile { s += "<Default Extension=\"\(cover.name.hasSuffix("png") ? "png" : "jpeg")\" ContentType=\"\(cover.type)\"/>" }
        s += """
            <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
            <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
            <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>\
            <Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>\
            <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>\
            <Override PartName="/word/footer2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>\
            <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
            <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>\
            </Types>
            """
        return s
    }

    func rootRels() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>\
        </Relationships>
        """
    }

    func documentRels() -> String {
        var s = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
            <Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>\
            <Relationship Id="rIdFootnotes" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>\
            <Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>\
            <Relationship Id="rIdFooterFirst" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer2.xml"/>
            """
        if let cover = coverFile { s += "<Relationship Id=\"rIdCover\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(cover.name)\"/>" }
        return s + "</Relationships>"
    }

    func core() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let stamp = f.string(from: date)
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
            <dc:title>\(XML.escape(book.title))</dc:title><dc:creator>\(XML.escape(book.author))</dc:creator><dc:language>\(language)</dc:language>\
            <dcterms:created xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:modified>\
            </cp:coreProperties>
            """
    }

    func app() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Quilland</Application></Properties>
        """
    }

    func settings() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings \(wNamespaces)><w:defaultTabStop w:val="709"/>\
        <w:footnotePr><w:footnote w:id="-1"/><w:footnote w:id="0"/></w:footnotePr>\
        <w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>\
        <w:themeFontLang w:val="\(language)"/></w:settings>
        """
    }

    func footnotesXML() -> String {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:footnotes \(wNamespaces)>"
        s += "<w:footnote w:type=\"separator\" w:id=\"-1\"><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:separator/></w:r></w:p></w:footnote>"
        s += "<w:footnote w:type=\"continuationSeparator\" w:id=\"0\"><w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>"
        for (i, content) in footnotes.enumerated() {
            s += "<w:footnote w:id=\"\(i + 1)\"><w:p><w:pPr><w:pStyle w:val=\"FootnoteText\"/></w:pPr><w:r><w:rPr><w:rStyle w:val=\"FootnoteReference\"/></w:rPr><w:footnoteRef/></w:r><w:r><w:t xml:space=\"preserve\"> </w:t></w:r>\(content)</w:p></w:footnote>"
        }
        return s + "</w:footnotes>"
    }

    func footer(withNumber: Bool) -> String {
        let field = "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:ftr \(wNamespaces)><w:p><w:pPr><w:pStyle w:val=\"Footer\"/></w:pPr>\(withNumber ? field : "")</w:p></w:ftr>"
    }

    func styles() -> String {
        let l = book.options.layout
        func style(_ id: String, _ name: String, based: String? = "Normal", next: String? = nil, ppr: String = "", rpr: String = "", quick: Bool = true, outline: Int? = nil) -> String {
            let o = outline.map { "<w:outlineLvl w:val=\"\($0)\"/>" } ?? ""
            return "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/>\(based.map { "<w:basedOn w:val=\"\($0)\"/>" } ?? "")\(next.map { "<w:next w:val=\"\($0)\"/>" } ?? "")\(quick ? "<w:qFormat/>" : "")<w:pPr>\(ppr)\(o)</w:pPr>\(rpr.isEmpty ? "" : "<w:rPr>\(rpr)</w:rPr>")</w:style>"
        }
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:styles \(wNamespaces)>"
        s += """
            <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="\(l.font)" w:hAnsi="\(l.font)" w:eastAsia="\(l.font)" w:cs="\(l.font)"/>\
            <w:sz w:val="\(l.halfPoints)"/><w:szCs w:val="\(l.halfPoints)"/><w:lang w:val="\(language)" w:eastAsia="\(language)" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>\
            <w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="\(l.lineSpacing240)" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
            """
        s += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/><w:pPr><w:ind w:firstLine=\"\(l.firstLineIndentTwips)\"/><w:jc w:val=\"both\"/></w:pPr></w:style>"
        s += "<w:style w:type=\"character\" w:default=\"1\" w:styleId=\"DefaultParagraphFont\"><w:name w:val=\"Default Paragraph Font\"/><w:uiPriority w:val=\"1\"/><w:semiHidden/></w:style>"
        s += style("Title", "Title", next: "Normal", ppr: "<w:spacing w:before=\"1200\" w:after=\"240\" w:line=\"240\" w:lineRule=\"auto\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"center\"/>", rpr: "<w:b/><w:sz w:val=\"56\"/><w:szCs w:val=\"56\"/>")
        s += style("Subtitle", "Subtitle", next: "Normal", ppr: "<w:spacing w:after=\"240\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"center\"/>", rpr: "<w:sz w:val=\"32\"/><w:szCs w:val=\"32\"/>")
        s += style("TitlePageText", "Title Page Text", ppr: "<w:ind w:firstLine=\"0\"/><w:jc w:val=\"center\"/>")
        s += style("Copyright", "Copyright", ppr: "<w:spacing w:before=\"800\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"center\"/>", rpr: "<w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/>")
        for n in 1...3 {
            let size = [36, 30, 26][n - 1]
            s += style("Heading\(n)", "heading \(n)", next: "Normal", ppr: "<w:keepNext/><w:keepLines/><w:spacing w:before=\"\(n == 3 ? 360 : 480)\" w:after=\"240\" w:line=\"240\" w:lineRule=\"auto\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"\(n == 3 ? "left" : "center")\"/>", rpr: "<w:b/><w:bCs/><w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/>", outline: n - 1)
        }
        s += style("Quote", "Quote", next: "Normal", ppr: "<w:spacing w:before=\"120\" w:after=\"120\" w:line=\"276\" w:lineRule=\"auto\"/><w:ind w:left=\"1134\" w:right=\"567\" w:firstLine=\"0\"/><w:jc w:val=\"both\"/>", rpr: "<w:i/><w:iCs/>")
        s += style("QuoteAuthor", "Quote Author", based: "Quote", next: "Normal", ppr: "<w:jc w:val=\"right\"/>", rpr: "<w:i w:val=\"0\"/><w:iCs w:val=\"0\"/>")
        s += style("SceneBreak", "Scene Break", ppr: "<w:spacing w:before=\"240\" w:after=\"240\" w:line=\"240\" w:lineRule=\"auto\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"center\"/>")
        s += style("TOCHeading", "TOC Heading", next: "Normal", ppr: "<w:spacing w:after=\"360\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"center\"/>", rpr: "<w:b/><w:sz w:val=\"32\"/><w:szCs w:val=\"32\"/>")
        s += style("TOC1", "toc 1", ppr: "<w:tabs><w:tab w:val=\"right\" w:leader=\"dot\" w:pos=\"\(l.pageWidthTwips - 2 * l.marginTwips - 20)\"/></w:tabs><w:spacing w:before=\"120\" w:line=\"276\" w:lineRule=\"auto\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"left\"/>", rpr: "<w:b/>", quick: false)
        s += style("TOC3", "toc 3", ppr: "<w:tabs><w:tab w:val=\"right\" w:leader=\"dot\" w:pos=\"\(l.pageWidthTwips - 2 * l.marginTwips - 20)\"/></w:tabs><w:spacing w:line=\"276\" w:lineRule=\"auto\"/><w:ind w:left=\"568\" w:firstLine=\"0\"/><w:jc w:val=\"left\"/>", quick: false)
        s += style("TOC2", "toc 2", ppr: "<w:tabs><w:tab w:val=\"right\" w:leader=\"dot\" w:pos=\"\(l.pageWidthTwips - 2 * l.marginTwips - 20)\"/></w:tabs><w:spacing w:line=\"276\" w:lineRule=\"auto\"/><w:ind w:left=\"284\" w:firstLine=\"0\"/><w:jc w:val=\"left\"/>", quick: false)
        s += style("FootnoteText", "footnote text", ppr: "<w:spacing w:line=\"240\" w:lineRule=\"auto\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"both\"/>", rpr: "<w:sz w:val=\"20\"/><w:szCs w:val=\"20\"/>", quick: false)
        s += style("Footer", "footer", ppr: "<w:spacing w:line=\"240\" w:lineRule=\"auto\"/><w:ind w:firstLine=\"0\"/><w:jc w:val=\"center\"/>", quick: false)
        s += "<w:style w:type=\"character\" w:styleId=\"FootnoteReference\"><w:name w:val=\"footnote reference\"/><w:basedOn w:val=\"DefaultParagraphFont\"/><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr></w:style>"
        return s + "</w:styles>"
    }
}
