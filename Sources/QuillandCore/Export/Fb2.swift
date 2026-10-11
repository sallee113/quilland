import Foundation
import ImageIO

/// A FictionBook 2.1 file (.fb2): one XML file. Parts, chapters are nested sections; the own text of a part
/// is its epigraph; a set-off block is a `cite` (an epigraph at the start of a chapter); verse is a `poem`;
/// a scene break is a centred `* * *` subtitle or an empty line; footnotes are links into a `notes` body;
/// the cover is a base64 `binary`.
public enum Fb2Exporter {
    public static func export(_ book: BookModel, options: ExportOptions, date: Date = Date()) -> Data {
        var builder = Fb2Builder(Resolver.resolve(book, options: options), date: date)
        return Data(builder.build().utf8)
    }

    /// The same, zipped as `.fb2.zip` (what many readers and stores take).
    public static func exportZipped(_ book: BookModel, options: ExportOptions, name: String, date: Date = Date()) -> Data {
        var zip = ZipWriter(date: date)
        zip.add(name, export(book, options: options, date: date))
        return zip.finish()
    }
}

private struct Fb2Builder {
    let book: Resolved
    let date: Date
    var notes: [String] = []

    init(_ book: Resolved, date: Date) {
        self.book = book
        self.date = date
    }

    // MARK: Inline

    mutating func inline(_ inlines: [Inline]) -> String {
        var out = ""
        for item in inlines {
            switch item {
            case .run(let run):
                if run.text.isEmpty { continue }
                var t = XML.escape(run.text)
                if run.style.contains(.italic) { t = "<emphasis>\(t)</emphasis>" }
                if run.style.contains(.bold) { t = "<strong>\(t)</strong>" }
                out += t
            case .lineBreak:
                out += " "
            case .note(let note):
                var content = ""
                for r in note.content where !r.text.isEmpty {
                    var t = XML.escape(r.text)
                    if r.style.contains(.italic) { t = "<emphasis>\(t)</emphasis>" }
                    if r.style.contains(.bold) { t = "<strong>\(t)</strong>" }
                    content += t
                }
                notes.append(content)
                out += "<a l:href=\"#n\(notes.count)\" type=\"note\">[\(notes.count)]</a>"
            }
        }
        return out
    }

    mutating func poem(_ inlines: [Inline]) -> String {
        "<poem><stanza>" + verseLines(inlines).map { "<v>\(inline($0))</v>" }.joined() + "</stanza></poem>"
    }

    // MARK: Blocks

    /// A paragraph, verse, subtitle, cite, empty line or break: what may stand in a section that has no subsections.
    mutating func content(_ block: Block) -> String {
        switch block {
        case .paragraph(let i):
            if hasLineBreak(i) { return poem(i) }
            let t = inline(i)
            return t.isEmpty ? "<empty-line/>" : "<p>\(t)</p>"
        case .heading(_, let i):
            return "<subtitle>\(inline(i))</subtitle>"
        case .quote(let paragraphs):
            let (rest, author) = splitAttribution(paragraphs)
            var s = "<cite>"
            for p in rest { s += hasLineBreak(p) ? poem(p) : "<p>\(inline(p))</p>" }
            if let author { s += "<text-author>\(inline(author))</text-author>" }
            return s + "</cite>"
        case .sceneBreak:
            return book.options.sceneBreak == .mark ? "<subtitle>* * *</subtitle>" : "<empty-line/>"
        case .fragment:
            return ""
        }
    }

    /// The own text of a part or chapter as an epigraph (content allowed in an epigraph: p, poem, cite, empty-line, then text-author).
    mutating func epigraph(_ blocks: [Block]) -> String {
        var s = ""
        for block in blocks {
            switch block {
            case .quote(let paragraphs):
                let (rest, author) = splitAttribution(paragraphs)
                for p in rest { s += hasLineBreak(p) ? poem(p) : "<p>\(inline(p))</p>" }
                if let author { s += "<text-author>\(inline(author))</text-author>" }
            case .paragraph(let i):
                s += hasLineBreak(i) ? poem(i) : "<p>\(inline(i))</p>"
            case .heading(_, let i):
                s += "<p><strong>\(inline(i))</strong></p>"
            case .sceneBreak, .fragment:
                break
            }
        }
        return s.isEmpty ? "" : "<epigraph>\(s)</epigraph>"
    }

    mutating func title(_ h: RHeading?) -> String {
        guard let h else { return "" }
        return "<title><p>\(inline(h.inlines))</p></title>"
    }

    mutating func chapter(_ chapter: RChapter) -> String {
        var s = "<section>"
        s += title(chapter.heading)
        // Quote blocks at the start of the chapter's own text are its epigraph; the rest is ordinary text.
        var own = chapter.own[...]
        var lead: [Block] = []
        while case .quote? = own.first { lead.append(own.removeFirst()) }
        s += epigraph(lead)
        var body = ""
        for b in own { body += content(b) }
        for (i, scene) in chapter.scenes.enumerated() {
            if i > 0 {
                switch book.options.sceneBreak {
                case .mark: body += "<subtitle>* * *</subtitle>"
                case .blank: body += "<empty-line/>"
                case .none: break
                }
            }
            if let h = scene.heading { body += "<subtitle>\(inline(h.inlines))</subtitle>" }
            for b in scene.blocks { body += content(b) }
        }
        if body.isEmpty { body = "<empty-line/>" }   // a section must have something in it
        return s + body + "</section>"
    }

    // MARK: The file

    var authorXML: String {
        let words = book.author.split(separator: " ").map(String.init)
        if words.count >= 2 {
            let middle = words.count > 2 ? "<middle-name>\(XML.escape(words[1..<(words.count - 1)].joined(separator: " ")))</middle-name>" : ""
            return "<author><first-name>\(XML.escape(words[0]))</first-name>\(middle)<last-name>\(XML.escape(words.last!))</last-name></author>"
        }
        return "<author><first-name>\(XML.escape(book.author))</first-name><last-name></last-name></author>"
    }

    var coverType: (id: String, mime: String)? {
        guard let cover = book.cover, let source = CGImageSourceCreateWithData(cover as CFData, nil) else { return nil }
        return (CGImageSourceGetType(source) as String?) == "public.jpeg" ? ("cover.jpg", "image/jpeg") : ("cover.png", "image/png")
    }

    mutating func build() -> String {
        var main = ""
        for item in book.items {
            switch item {
            case .part(let part):
                main += "<section>"
                main += title(part.heading)
                main += epigraph(part.own)
                var chapters = ""
                for c in part.chapters { chapters += chapter(c) }
                main += chapters.isEmpty ? "<empty-line/>" : chapters
                main += "</section>"
            case .chapter(let c):
                main += chapter(c)
            }
        }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let day = f.string(from: date)
        let year = String(Calendar(identifier: .gregorian).component(.year, from: date))
        var s = """
            <?xml version="1.0" encoding="UTF-8"?>
            <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
            <description><title-info><genre>prose_contemporary</genre>\(authorXML)<book-title>\(XML.escape(book.title))</book-title>
            """
        if let cover = coverType { s += "<coverpage><image l:href=\"#\(cover.id)\"/></coverpage>" }
        s += "<lang>\(XML.escape(book.language.isEmpty ? "en" : book.language))</lang></title-info>"
        s += "<document-info><author><nickname>Quilland</nickname></author><program-used>Quilland</program-used><date value=\"\(day)\">\(day)</date><id>\(XML.escape(book.id.isEmpty ? UUID().uuidString.lowercased() : book.id))</id><version>1.0</version></document-info>"
        if !book.copyright.isEmpty { s += "<publish-info><year>\(year)</year></publish-info>" }
        s += "</description>\n"
        s += "<body><title><p>\(XML.escape(book.title))</p></title>\(main)</body>\n"
        if !notes.isEmpty {
            s += "<body name=\"notes\"><title><p>\(BookWords.notes(book.language))</p></title>"
            for (i, note) in notes.enumerated() { s += "<section id=\"n\(i + 1)\"><title><p>\(i + 1)</p></title><p>\(note)</p></section>" }
            s += "</body>\n"
        }
        if let cover = coverType, let data = book.cover {
            s += "<binary id=\"\(cover.id)\" content-type=\"\(cover.mime)\">\(data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]))</binary>\n"
        }
        return s + "</FictionBook>\n"
    }
}
