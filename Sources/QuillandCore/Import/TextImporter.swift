import Foundation

public enum ImportSource: String, CaseIterable, Sendable {
    case markdown, text, html
    public static func guess(extension ext: String) -> ImportSource {
        switch ext.lowercased() {
        case "md", "markdown", "mdown": return .markdown
        case "html", "htm", "xhtml": return .html
        default: return .text
        }
    }
}

public enum ImportEncoding: String, CaseIterable, Sendable {
    case utf8, windows1251
    public var label: String { self == .utf8 ? "UTF-8" : "Windows-1251" }
}

/// What a kind of line becomes: a part, a chapter, a scene (these start a new section), or nothing special.
public enum ImportRole: String, CaseIterable, Sendable {
    case part, chapter, scene, none
    public var label: String {
        switch self {
        case .part: return L("Part")
        case .chapter: return L("Chapter")
        case .scene: return L("Scene")
        case .none: return L("Not a title")
        }
    }
}

/// A kind of line that could be a title: how many there are, examples, and what it becomes by default.
public struct TitleKind: Equatable, Sendable {
    public var id: String
    public var label: String
    public var count: Int
    public var examples: [String]
    public var defaultRole: ImportRole
    /// Scene breaks are not titles: the option "split a chapter into scenes at the scene breaks" decides what they do.
    public var isBreak: Bool { id == "break" }
}

public struct ImportOptions: Equatable, Sendable {
    public var splitAtSceneBreaks = true
    /// Lines of a hard-wrapped text are joined into paragraphs (a text where a line break is only where the line ended).
    public var joinWrappedLines = false
    /// The role chosen for a kind, by kind id; kinds not in it take their default.
    public var roles: [String: ImportRole] = [:]
    public var language = "en"
    public init() {}
}

/// The result of reading a text: a tree of parts, chapters and scenes with Markdown bodies.
public struct ImportPlan: Equatable, Sendable {
    public struct Scene: Equatable, Sendable { public var title: String; public var markdown: String; public var characters: Int }
    public struct Chapter: Equatable, Sendable { public var title: String; public var scenes: [Scene]; public var characters: Int { scenes.reduce(0) { $0 + $1.characters } } }
    public struct Part: Equatable, Sendable { public var title: String; public var chapters: [Chapter]; public var characters: Int { chapters.reduce(0) { $0 + $1.characters } } }
    public enum Item: Equatable, Sendable { case part(Part), chapter(Chapter) }
    public var items: [Item] = []
    public init() {}

    public var partCount: Int { items.reduce(0) { if case .part = $1 { return $0 + 1 }; return $0 } }
    public var chapterCount: Int { items.reduce(0) { switch $1 { case .part(let p): return $0 + p.chapters.count; case .chapter: return $0 + 1 } } }
    public var sceneCount: Int {
        items.reduce(0) { switch $1 { case .part(let p): return $0 + p.chapters.reduce(0) { $0 + $1.scenes.count }; case .chapter(let c): return $0 + c.scenes.count } }
    }
    public var characters: Int { items.reduce(0) { switch $1 { case .part(let p): return $0 + p.characters; case .chapter(let c): return $0 + c.characters } } }
}

public enum TextImporter {
    // MARK: Reading the bytes

    /// The text of a file in the given encoding; nil when the bytes are not valid in it (the window then offers the other one).
    public static func decode(_ data: Data, encoding: ImportEncoding) -> String? {
        switch encoding {
        case .utf8:
            var bytes = data
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
            return String(data: bytes, encoding: .utf8)
        case .windows1251:
            return String(data: data, encoding: .windowsCP1251)
        }
    }

    // MARK: HTML to Markdown-like text

    static func entities(_ s: String) -> String {
        var out = s
        let named = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&laquo;": "«", "&raquo;": "»", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        let re = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        let ns = out as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            if let n = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10), let u = Unicode.Scalar(n) { result.unicodeScalars.append(u) }
            last = NSMaxRange(m.range)
        }
        return result + ns.substring(from: last)
    }

    /// Headings, paragraphs, bold, italic and rules of an HTML file as Markdown text; everything else is dropped.
    static func htmlToMarkdown(_ html: String) -> String {
        var s = html
        for tag in ["script", "style", "head"] {
            s = s.replacingOccurrences(of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: "", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
        for level in 1...6 {
            s = s.replacingOccurrences(of: "<h\(level)[^>]*>", with: "\n\n\(String(repeating: "#", count: min(level, 3))) ", options: [.regularExpression, .caseInsensitive])
            s = s.replacingOccurrences(of: "</h\(level)>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "<(b|strong)(\\s[^>]*)?>", with: "**", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(b|strong)>", with: "**", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<(i|em)(\\s[^>]*)?>", with: "*", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</(i|em)>", with: "*", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<hr[^>]*>", with: "\n\n* * *\n\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</?(p|div|section|article|blockquote|li|ul|ol|tr|table)[^>]*>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return entities(s)
    }

    // MARK: Paragraphs

    struct Paragraph: Equatable {
        var text: String
        /// 1...3 for a Markdown heading, nil otherwise.
        var heading: Int?
    }

    /// Lists, tables, links, images and footnote marks of a Markdown text become what the format has: plain paragraphs, inline footnotes.
    static func simplify(_ lines: [String]) -> [String] {
        // Footnote definitions `[^1]: text` are taken out and their marks `[^1]` become inline notes `^[text]`.
        var definitions: [String: String] = [:]
        var rest: [String] = []
        for line in lines {
            if let m = line.range(of: "^\\[\\^([^\\]]+)\\]:\\s*(.*)$", options: .regularExpression) {
                let body = String(line[m])
                let key = body.drop { $0 != "^" }.dropFirst().prefix { $0 != "]" }
                let text = body.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
                definitions[String(key)] = text
            } else { rest.append(line) }
        }
        var out: [String] = []
        for var line in rest {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "^\\|?[\\s:|-]+\\|[\\s:|-]*$", options: .regularExpression) != nil, trimmed.contains("-") { continue }   // a table's rule
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") { line = trimmed.dropFirst().dropLast().split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
            line = line.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            if let bullet = line.range(of: "^\\s*[-+•]\\s+(?=\\S)", options: .regularExpression), !isBreakLine(line) { line.removeSubrange(bullet) }
            else if let star = line.range(of: "^\\s*\\*\\s+(?=[^*\\s])", options: .regularExpression), !isBreakLine(line) { line.removeSubrange(star) }
            for (key, text) in definitions { line = line.replacingOccurrences(of: "[^\(key)]", with: "^[\(text)]") }
            out.append(line)
        }
        return out
    }

    static func isBreakLine(_ line: String) -> Bool {
        line.range(of: "^\\s*([*#~=_\\-+•·]\\s*){3,}$", options: .regularExpression) != nil
    }

    /// The paragraphs of a text: a blank line separates them; with `join` the lines inside one are joined with a space, without it every
    /// line is a paragraph (plain texts usually break a line only at the end of a paragraph).
    static func paragraphs(from raw: String, source: ImportSource, join: Bool) -> [Paragraph] {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        if source == .html { text = htmlToMarkdown(text) }
        let lines = simplify(text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ").union(.controlCharacters.subtracting(.newlines))) })
        var out: [Paragraph] = []
        var current: [String] = []
        func flush() {
            guard !current.isEmpty else { return }
            let joined = current.joined(separator: " ")
            out.append(Paragraph(text: joined, heading: nil))
            current = []
        }
        func add(_ line: String) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let m = t.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                flush()
                let level = min(3, t[m].filter { $0 == "#" }.count)
                out.append(Paragraph(text: String(t[m.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "# ")), heading: level))
            } else if isBreakLine(t) {
                flush()
                out.append(Paragraph(text: "* * *", heading: nil))
            } else {
                current.append(t)
                if !join && source == .text { flush() }
            }
        }
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush() } else { add(line) }
        }
        flush()
        return out
    }

    // MARK: Kinds of lines

    private static let ordinal = "(?:\\d{1,3}|[IVXLCDM]{1,7}|[а-яёa-z]{3,12})"
    private static let kindPatterns: [(id: String, label: String, pattern: String)] = [
        ("part", "Part N", "^(часть|part|книга|book)\\s+\(ordinal)(?:\\s*[.:—–-].*|\\s*)$"),
        ("chapter", "Chapter N", "^(глава|chapter|гл\\.)\\s*\(ordinal)(?:\\s*[.:—–-].*|\\s*)$"),
        ("special", "Prologue, epilogue…", "^(пролог|эпилог|предисловие|послесловие|вступление|интерлюдия|prologue|epilogue|preface|afterword|introduction|interlude)\\b.{0,40}$"),
        ("number", "A number alone", "^(\\d{1,3}|[IVXLCDM]{1,7})[.)]?$"),
        ("numbered", "Numbered line", "^\\d{1,3}[.)]\\s+\\S.{0,70}$"),
    ]

    static func kind(of p: Paragraph) -> String? {
        if let h = p.heading { return "h\(h)" }
        let t = p.text
        if t == "* * *" { return "break" }
        guard t.count <= 90, !t.contains("^[") else { return nil }
        for (id, _, pattern) in kindPatterns where t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
            // "number" must not be a year or a stray figure: allowed only when short (checked by the pattern); Roman numerals must be capitals.
            if id == "number", t.range(of: "^[IVXLCDM]+[.)]?$", options: .regularExpression) == nil, t.range(of: "^\\d{1,3}[.)]?$", options: .regularExpression) == nil { continue }
            return id
        }
        let letters = t.filter(\.isLetter)
        if letters.count >= 3, t.count <= 60, letters == letters.uppercased(), !t.hasSuffix("."), !t.hasSuffix(",") { return "caps" }
        return nil
    }

    static func label(for id: String) -> String {
        switch id {
        case "h1": return "Heading 1 (#)"
        case "h2": return "Heading 2 (##)"
        case "h3": return "Heading 3 (###)"
        case "break": return "Scene break (* * *)"
        case "caps": return "SHORT CAPITALS LINE"
        default: return kindPatterns.first { $0.id == id }?.label ?? id
        }
    }

    /// The kinds of title-like lines in a text, each with a count, examples and the role it takes unless the author chooses another.
    public static func analyze(_ raw: String, source: ImportSource, joinWrappedLines: Bool) -> (kinds: [TitleKind], suggestedTitle: String?) {
        let paras = paragraphs(from: raw, source: source, join: joinWrappedLines)
        var counts: [String: Int] = [:]
        var examples: [String: [String]] = [:]
        var order: [String] = []
        for p in paras {
            guard let k = kind(of: p) else { continue }
            if counts[k] == nil { order.append(k) }
            counts[k, default: 0] += 1
            if (examples[k]?.count ?? 0) < 3 { examples[k, default: []].append(p.text) }
        }
        let wanted = ["h1", "h2", "h3", "part", "chapter", "special", "number", "numbered", "caps", "break"]
        let ids = wanted.filter { counts[$0] != nil }
        // Default roles.
        var roles: [String: ImportRole] = [:]
        let heads = ids.filter { $0.hasPrefix("h") && $0.count == 2 }
        var suggestedTitle: String?
        var headRoles: [ImportRole] = []
        switch heads.count {
        case 3: headRoles = [.part, .chapter, .scene]
        case 2:
            // "# Title" once, then "## chapters": the single H1 is the book's title.
            if counts[heads[0]] == 1, heads[0] == "h1" { headRoles = [.none, .chapter] }
            else if ids.contains("part") { headRoles = [.chapter, .scene] }
            else if heads == ["h2", "h3"] { headRoles = [.chapter, .scene] }
            else { headRoles = [.part, .chapter] }
        case 1: headRoles = [.chapter]
        default: break
        }
        for (i, h) in heads.enumerated() { roles[h] = headRoles[i] }
        if heads.contains("h1"), roles["h1"] == ImportRole.none { suggestedTitle = examples["h1"]?.first }
        roles["part"] = .part
        roles["chapter"] = .chapter
        roles["special"] = .chapter
        let hasChapterRole = roles.values.contains(.chapter)
        roles["number"] = hasChapterRole ? .scene : .chapter
        roles["numbered"] = hasChapterRole ? .scene : .chapter
        roles["caps"] = .none
        roles["break"] = .none
        let kinds = ids.map { id in TitleKind(id: id, label: label(for: id), count: counts[id] ?? 0, examples: examples[id] ?? [], defaultRole: roles[id] ?? .none) }
        return (kinds, suggestedTitle)
    }

    // MARK: The plan

    public static func plan(_ raw: String, source: ImportSource, options: ImportOptions) -> ImportPlan {
        let paras = paragraphs(from: raw, source: source, join: options.joinWrappedLines)
        let analysis = analyze(raw, source: source, joinWrappedLines: options.joinWrappedLines)
        var roles: [String: ImportRole] = [:]
        for k in analysis.kinds { roles[k.id] = options.roles[k.id] ?? k.defaultRole }
        let sceneWord = ["ru": "Сцена", "fr": "Scène"][options.language] ?? "Scene"

        var plan = ImportPlan()
        var part: (title: String, chapters: [ImportPlan.Chapter])?
        var chapter: (title: String, scenes: [ImportPlan.Scene])?
        var sceneTitle: String?
        var body: [String] = []
        var sceneNumber = 0
        var titleSkipped = false

        func closeScene() {
            let text = body.joined(separator: "\n\n")
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sceneTitle != nil {
                if chapter == nil { chapter = (BookWords.beginning(options.language), []) }
                sceneNumber += 1
                let markdown = normalize(text)
                chapter?.scenes.append(.init(title: sceneTitle ?? "\(sceneWord) \(sceneNumber)", markdown: markdown, characters: TextStats.count(MarkdownParser.parse(markdown)).characters))
            }
            body = []
            sceneTitle = nil
        }
        func closeChapter() {
            closeScene()
            sceneNumber = 0
            guard let c = chapter else { return }
            let finished = ImportPlan.Chapter(title: c.title, scenes: c.scenes.isEmpty ? [.init(title: "\(sceneWord) 1", markdown: "", characters: 0)] : c.scenes)
            if part != nil { part?.chapters.append(finished) } else { plan.items.append(.chapter(finished)) }
            chapter = nil
        }
        func closePart() {
            closeChapter()
            if let p = part { plan.items.append(.part(.init(title: p.title, chapters: p.chapters))) }
            part = nil
        }

        for p in paras {
            let k = kind(of: p)
            let role = k.flatMap { roles[$0] } ?? .none
            // The one H1 of the text is the book's title (it goes to a new book's title), not a part of the text.
            if k == "h1", role == .none, analysis.suggestedTitle != nil, !titleSkipped { titleSkipped = true; continue }
            if k == "break" {
                if options.splitAtSceneBreaks { closeScene() } else { body.append("* * *") }
                continue
            }
            switch role {
            case .part:
                closePart()
                part = (p.text, [])
            case .chapter:
                closeChapter()
                chapter = (p.text, [])
            case .scene:
                closeScene()
                if chapter == nil { chapter = (BookWords.beginning(options.language), []) }
                sceneTitle = p.text
            case .none:
                if let h = p.heading { body.append(String(repeating: "#", count: h) + " " + p.text) } else { body.append(p.text) }
            }
        }
        closePart()
        return plan
    }

    /// A body through the format's own reader and writer, so what is written is exactly what the app would write.
    static func normalize(_ markdown: String) -> String {
        MarkdownWriter.write(MarkdownParser.parse(markdown))
    }

    // MARK: Writing into a book

    public struct Written: Equatable, Sendable {
        public var parts = 0, chapters = 0, scenes = 0
        public var firstSceneID: String?
    }

    /// Adds the plan at the end of the book (its parts and loose chapters after what is there). With `replacingEmptyStart`, a book that has
    /// only the empty first chapter a new book starts with loses it, so the import begins at number 1.
    @discardableResult
    public static func write(_ plan: ImportPlan, into book: URL, replacingEmptyStart: Bool = false) throws -> Written {
        let fm = FileManager.default
        let manuscript = book.appendingPathComponent("manuscript")
        try fm.createDirectory(at: manuscript, withIntermediateDirectories: true)
        if replacingEmptyStart {
            let structure = try BookStructure.load(folder: book)
            if structure.roots.count == 1, structure.scenes.count == 1,
               (try? Data(contentsOf: structure.markdownURL(for: structure.scenes[0].node)))?.isEmpty ?? true {
                try fm.removeItem(at: book.appendingPathComponent(structure.roots[0].base))
            }
        }
        var written = Written()
        var next = (try Renumber.scan(manuscript)).count + 1
        func uuid() -> String { UUID().uuidString.lowercased() }
        func put(_ url: URL, _ object: JSONObject) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AtomicFile.write(JSONWriter.data(object), to: url)
        }
        func chapter(_ c: ImportPlan.Chapter, in parent: URL, number: Int) throws {
            let folder = parent.appendingPathComponent(String(format: "%03d-chapter", number))
            try put(folder.appendingPathComponent("_chapter.json"), ["id": .string(uuid()), "title": .string(c.title)])
            written.chapters += 1
            for (i, s) in c.scenes.enumerated() {
                let base = String(format: "%03d-scene", i + 1)
                let id = uuid()
                if written.firstSceneID == nil { written.firstSceneID = id }
                try put(folder.appendingPathComponent(base + ".json"), ["id": .string(id), "status": .string("draft"), "title": .string(s.title)])
                try AtomicFile.write(Data(s.markdown.utf8), to: folder.appendingPathComponent(base + ".md"))
                written.scenes += 1
            }
        }
        for item in plan.items {
            switch item {
            case .chapter(let c):
                try chapter(c, in: manuscript, number: next)
            case .part(let p):
                let folder = manuscript.appendingPathComponent(String(format: "%03d-part", next))
                try put(folder.appendingPathComponent("_part.json"), ["id": .string(uuid()), "title": .string(p.title)])
                written.parts += 1
                for (i, c) in p.chapters.enumerated() { try chapter(c, in: folder, number: i + 1) }
            }
            next += 1
        }
        return written
    }
}
