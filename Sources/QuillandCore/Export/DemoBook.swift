import Foundation

/// A big book with everything the application can hold, for trying and testing: parts, chapters and scenes in every status (with synopses, notes, tags,
/// targets), text with bold, italic, footnotes, quotes, verse, headings and scene breaks, characters with aliases and links, two worlds of places,
/// events linked to scenes and places, a plan with lines and cards, a dictionary, export profiles, a cover and snapshots.
/// Every number comes from a fixed seed, so the same call writes the same book (apart from the ids).
public enum DemoBook {
    public static let title = "Большая демо-книга"

    struct Person { var nom: String; var gen: String; var dat: String; var ins: String; var female: Bool; var aliases: [String]; var role: String }
    struct Spot { var name: String; var inside: String; var of: String; var parent: Int?; var world: Int; var type: String; var aliases: [String] }

    static let people: [Person] = [
        Person(nom: "Анна", gen: "Анны", dat: "Анне", ins: "Анной", female: true, aliases: ["Аня"], role: "приехала в дом тёти"),
        Person(nom: "Вера Павловна", gen: "Веры Павловны", dat: "Вере Павловне", ins: "Верой Павловной", female: true, aliases: ["тётя Вера"], role: "хозяйка дома"),
        Person(nom: "Фёдор", gen: "Фёдора", dat: "Фёдору", ins: "Фёдором", female: false, aliases: ["старик в фуражке"], role: "сторож и молочник"),
        Person(nom: "Максим", gen: "Максима", dat: "Максиму", ins: "Максимом", female: false, aliases: ["Макс"], role: "журналист из города"),
        Person(nom: "Ольга", gen: "Ольги", dat: "Ольге", ins: "Ольгой", female: true, aliases: ["Оля"], role: "подруга Анны"),
        Person(nom: "Игнат", gen: "Игната", dat: "Игнату", ins: "Игнатом", female: false, aliases: [], role: "хозяин кемпинга"),
        Person(nom: "Лидия", gen: "Лидии", dat: "Лидии", ins: "Лидией", female: true, aliases: ["Лида"], role: "библиотекарь"),
        Person(nom: "Платон", gen: "Платона", dat: "Платону", ins: "Платоном", female: false, aliases: [], role: "врач"),
        Person(nom: "Нина", gen: "Нины", dat: "Нине", ins: "Ниной", female: true, aliases: [], role: "соседка"),
        Person(nom: "Григорий", gen: "Григория", dat: "Григорию", ins: "Григорием", female: false, aliases: ["Гриша"], role: "брат Максима"),
        Person(nom: "Зоя", gen: "Зои", dat: "Зое", ins: "Зоей", female: true, aliases: [], role: "почтальон"),
        Person(nom: "Борис", gen: "Бориса", dat: "Борису", ins: "Борисом", female: false, aliases: [], role: "бывший муж Ольги"),
    ]

    static let spots: [Spot] = [
        Spot(name: "Сосновая", inside: "в Сосновой", of: "Сосновой", parent: nil, world: 0, type: "place", aliases: ["посёлок"]),
        Spot(name: "Дом на Сосновой", inside: "в доме", of: "дома", parent: 0, world: 0, type: "place", aliases: ["дом"]),
        Spot(name: "Подвал", inside: "в подвале", of: "подвала", parent: 1, world: 0, type: "place", aliases: []),
        Spot(name: "Чердак", inside: "на чердаке", of: "чердака", parent: 1, world: 0, type: "place", aliases: []),
        Spot(name: "Станция", inside: "на станции", of: "станции", parent: 0, world: 0, type: "place", aliases: ["платформа"]),
        Spot(name: "Кемпинг", inside: "в кемпинге", of: "кемпинга", parent: 0, world: 0, type: "place", aliases: ["лагерь"]),
        Spot(name: "Озеро", inside: "у озера", of: "озера", parent: 0, world: 0, type: "place", aliases: []),
        Spot(name: "Библиотека", inside: "в библиотеке", of: "библиотеки", parent: 0, world: 0, type: "place", aliases: []),
        Spot(name: "Город", inside: "в городе", of: "города", parent: nil, world: 1, type: "place", aliases: []),
        Spot(name: "Редакция", inside: "в редакции", of: "редакции", parent: 8, world: 1, type: "place", aliases: []),
        Spot(name: "Квартира Ольги", inside: "в квартире Ольги", of: "квартиры Ольги", parent: 8, world: 1, type: "place", aliases: []),
        Spot(name: "Ключ с биркой", inside: "", of: "ключа", parent: nil, world: 0, type: "thing", aliases: ["ключ"]),
        Spot(name: "Дневник погоды", inside: "", of: "дневника", parent: nil, world: 0, type: "thing", aliases: ["дневник"]),
        Spot(name: "Сосновцы", inside: "", of: "сосновцев", parent: nil, world: 0, type: "people", aliases: []),
    ]

    static let openers = [
        "{P} стояла тишина, и только ветер {where} перебирал страницы чьих-то забытых писем.",
        "{A} долго смотрела {where} и не могла решить, стоит ли возвращаться.",
        "К вечеру {A} почувствовала, что всё это уже было с ней раньше.",
        "Утро началось с того, что {A} услышала шаги {where}.",
        "Никто не сказал {A} правду, но она догадалась сама.",
        "— Ты веришь в совпадения? — спросил {B}, не поднимая глаз.",
        "{B} пришёл без предупреждения и сразу заговорил о деле.",
        "Дождь не прекращался третий день, и {where} стало сыро и тесно.",
    ]
    static let middles = [
        "Она прислушалась. Где-то далеко хлопнула дверь, и всё снова стихло.",
        "В кармане лежало письмо, которое никто не читал так внимательно, как нужно.",
        "Свет в окне погас, потом зажёгся опять, словно кто-то подавал знак.",
        "Слова давались с трудом: каждое приходилось вытаскивать, как гвоздь из старой доски.",
        "На столе остывал чай, и никто не решался заговорить первым.",
        "Часы в коридоре пробили девять, хотя давно должны были остановиться.",
        "Пахло смолой, дымом и чем-то ещё, чему не было названия.",
        "Он улыбнулся, но глаза остались серьёзными.",
        "Она записала это в тетрадь, чтобы не забыть, и тут же пожалела об этом.",
        "Лес за окном шумел ровно и бесконечно, как море.",
        "Всё, что случилось раньше, вдруг сложилось в одну ясную картину.",
        "Казалось, дом слушает их и ждёт, чем закончится разговор.",
    ]
    static let closers = [
        "Больше об этом никто не говорил.",
        "Ночью ей снова приснилась дорога.",
        "Она закрыла дверь и поняла, что назад пути нет.",
        "Утром всё выглядело иначе.",
        "И тогда {A} решилась.",
        "Но это была только половина правды.",
    ]
    static let verse = [
        "Сосны шумят над крышей,\\\nи ветер читает вслух\\\nвсё, что давно не слышно,\\\nвсё, что не сказано вслух.",
        "Дорога уходит в туман,\\\nи следом уходит день,\\\nа память — как старый карман,\\\nгде прячется чья-то тень.",
    ]
    static let notesPool = [
        "Проверить, когда именно {A} узнала о письме.", "Здесь нужна деталь: запах.", "Сократить диалог в середине.", "Связать с эпизодом у озера.",
        "Уточнить погоду по дневнику.", "Переписать конец: слишком быстро.",
    ]
    static let tagsPool = ["letter", "night", "dream", "cellar", "road", "memory", "dialogue", "flashback"]
    static let statuses = ["idea", "draft", "revised", "done"]
    static let words = ["сосновец", "сосновцы", "кемпинговый", "фуражка", "квасцы"]

    /// Writes the book into `folder`: the folder is made (and must not hold a book yet). `scenes` is how many scenes the manuscript gets.
    public static func write(into folder: URL, scenes sceneCount: Int = 120, paragraphs: Int = 12) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var seed: UInt64 = 0x51EED
        func random(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(max(1, n))) }
        func pick<T>(_ a: [T]) -> T { a[random(a.count)] }
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
        func markdown(_ text: String) -> String { MarkdownWriter.write(MarkdownParser.parse(text)) }
        func uuid() -> String { UUID().uuidString.lowercased() }

        let author = "Вадим Сульянов"
        let coverName = uuid() + ".png"
        try putJSON("book.json", ["author": .string(author), "copyright": .string("© 2026 \(author)"), "cover": .string(coverName), "format": .int(1), "id": .string(uuid()),
                                  "language": .string("ru"), "target_characters": .int(sceneCount * 2600), "title": .string(title)])
        try fm.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try SampleBook.coverPNG(title: title, author: author).write(to: folder.appendingPathComponent("assets/\(coverName)"))

        // The manuscript: parts of several chapters of several scenes; the earlier the part, the more finished.
        let partTitles = ["Дорога", "Дом", "Подвал", "Возвращение"]
        let partEpigraph = "> Дорога не спрашивает, куда ты идёшь.\n>\n> — Народная мудрость"
        let perPart = Int((Double(sceneCount) / Double(partTitles.count)).rounded(.up))
        var sceneIDs: [String] = [], sceneTitles: [String] = [], sceneNumber = 0
        for (pi, partTitle) in partTitles.enumerated() {
            let partDir = "manuscript/" + String(format: "%03d-part", pi + 1)
            try putJSON("\(partDir)/_part.json", ["id": .string(uuid()), "title": .string(partTitle)])
            if pi == 0 { try put("\(partDir)/_part.md", markdown(partEpigraph)) }
            var inPart = 0, chapter = 0
            while inPart < perPart && sceneNumber < sceneCount {
                chapter += 1
                let dir = partDir + "/" + String(format: "%03d-chapter", chapter)
                try putJSON("\(dir)/_chapter.json", ["id": .string(uuid()), "title": .string("Глава \(chapter)")])
                if chapter == 2 && pi == 1 { try put("\(dir)/_chapter.md", markdown("# Глава, в которой всё меняется")) }
                for s in 1...(4 + random(3)) where inPart < perPart && sceneNumber < sceneCount {
                    sceneNumber += 1; inPart += 1
                    let id = uuid()
                    let base = "\(dir)/" + String(format: "%03d-scene", s)
                    let status = pi == 0 ? (random(8) == 0 ? "revised" : "done") : pi == 1 ? pick(["revised", "revised", "done", "draft"]) : pi == 2 ? pick(["draft", "draft", "idea", "revised"]) : pick(["idea", "idea", "draft"])
                    let title = "Сцена \(sceneNumber)"
                    var record: JSONObject = ["id": .string(id), "status": .string(status), "title": .string(title)]
                    if random(3) == 0 { record["tags"] = .array([.string(pick(tagsPool)), .string(pick(tagsPool))]) }
                    if status != "idea" || random(2) == 0 { record["synopsis"] = .string("Что происходит в сцене \(sceneNumber): \(pick(middles))") }
                    if random(4) == 0 { record["note"] = .string(pick(notesPool).replacingOccurrences(of: "{A}", with: "Анна")) }
                    if random(3) != 0 { record["target_characters"] = .int(2000 + random(3) * 500) }
                    try putJSON(base + ".json", record)
                    sceneIDs.append(id); sceneTitles.append(title)

                    // The text: an idea is nearly empty; others are written out, with a few features of the markup sprinkled in.
                    let a = people[random(3)], b = people[3 + random(people.count - 3)], place = spots[random(8)]
                    func fill(_ t: String) -> String {
                        t.replacingOccurrences(of: "{A}", with: a.nom).replacingOccurrences(of: "{B}", with: b.nom)
                            .replacingOccurrences(of: "{P}", with: place.inside.isEmpty ? "Здесь" : place.inside.prefix(1).uppercased() + place.inside.dropFirst())
                            .replacingOccurrences(of: "{where}", with: place.inside.isEmpty ? "вокруг" : place.inside)
                    }
                    var paras: [String] = []
                    let count = status == "idea" ? random(2) : max(3, paragraphs - 2 + random(5))
                    for i in 0..<count {
                        var p = fill(pick(openers))
                        for _ in 0..<(2 + random(3)) { p += " " + fill(pick(middles)) }
                        p += " " + fill(pick(closers))
                        if i == 1 && random(2) == 0 { p = p.replacingOccurrences(of: "тишина", with: "**тишина**") }
                        if i == 2 && random(2) == 0 { p += " Это было *странно*." }
                        if i == 3 && random(3) == 0 { p += "^[Сноска к сцене \(sceneNumber): позже выяснится, что это было не случайно.]" }
                        if i == 4 && random(3) == 0 { p = "> " + fill(pick(middles)) + "\n>\n> — " + b.nom }
                        if i == 5 && random(4) == 0 { p = pick(verse) }
                        if i == 6 && random(5) == 0 { p = "## Заметка на полях\n\n" + p }
                        paras.append(p)
                        if i == count / 2 && count > 6 && random(2) == 0 { paras.append("* * *") }
                    }
                    try put(base + ".md", markdown(paras.joined(separator: "\n\n")))
                }
            }
        }
        // A short epilogue outside the parts.
        let epilogueDir = "manuscript/" + String(format: "%03d-chapter", partTitles.count + 1)
        try putJSON("\(epilogueDir)/_chapter.json", ["id": .string(uuid()), "title": .string("Эпилог")])
        let epilogueID = uuid()
        try putJSON("\(epilogueDir)/001-scene.json", ["id": .string(epilogueID), "status": .string("draft"), "title": .string("Утро")])
        try put("\(epilogueDir)/001-scene.md", markdown("Утром пришёл **Фёдор** и принёс молоко. Над крышей шумели сосны."))
        sceneIDs.append(epilogueID); sceneTitles.append("Утро")

        // Characters: names with aliases, a role, the scenes they take part in and the ones told from their side.
        let characters = CharacterStore(book: folder)
        var characterIDs: [String] = []
        for (i, p) in people.enumerated() {
            let id = try characters.add(name: p.nom)
            characterIDs.append(id)
            var linked: [String: String] = [:]
            for k in 0..<min(sceneIDs.count, 6 + random(6)) { linked[sceneIDs[(i * 7 + k * 11) % sceneIDs.count]] = p.role }
            try characters.update(id) {
                $0.aliases = p.aliases
                $0.main = i < 3
                $0.notes = ["Роль: \(p.role)", "Склонение: \(p.gen), \(p.dat), \(p.ins)"]
                $0.links = linked
                if i < 3 { $0.povScenes = Array(sceneIDs.enumerated().filter { $0.offset % (i + 2) == 0 }.map(\.element).prefix(12)) }
            }
            try characters.setProfile(id, "# \(p.nom)\n\n\(p.nom) — \(p.role). \(p.female ? "Она" : "Он") появляется в первой части и остаётся до конца книги.\n\n## Внешность\n\nОписание появится позже.")
        }

        // Relationships: pairs and a group, with the scenes where they meet.
        let relationshipStore = RelationshipStore(book: folder)
        for (i, (members, kind)) in [([0, 1], "племянница и тётя"), ([0, 4], "подруги"), ([3, 9], "братья"), ([4, 11], "бывшие супруги"), ([0, 2, 5], "знакомые по посёлку")].enumerated() {
            let id = try relationshipStore.add(characters: members.map { characterIDs[$0] }, kind: kind)
            try relationshipStore.update(id) {
                $0.notes = ["Заметка об отношениях «\(kind)»."]
                $0.links = Dictionary((0..<3).map { (sceneIDs[(i * 9 + $0 * 17) % sceneIDs.count], "они встречаются") }, uniquingKeysWith: { $1 })
            }
        }

        // Worlds and the places in them.
        let worldStore = WorldStore(book: folder)
        let worldIDs = [try worldStore.addWorld(name: "Сосновая"), try worldStore.addWorld(name: "Город")]
        var spotIDs: [String] = []
        for s in spots {
            let id = try worldStore.addEntry(name: s.name, world: worldIDs[s.world], parent: s.parent.map { spotIDs[$0] }, type: s.type)
            spotIDs.append(id)
            try worldStore.updateEntry(id) {
                $0.aliases = s.aliases
                $0.notes = ["Заметка о месте «\(s.name)»."]
                $0.links = Dictionary((0..<3).map { (sceneIDs[(spotIDs.count * 5 + $0 * 13) % sceneIDs.count], "здесь происходит часть действия") }, uniquingKeysWith: { $1 })
            }
            try worldStore.setText(id, "# \(s.name)\n\nОписание: \(s.name.lowercased()) — важное место книги.")
        }

        // Events in the order of the story, each linked to scenes and a place, then put on the plan.
        let eventStore = EventStore(book: folder)
        let dates = ["весна, год 214", "лето, год 214", "осень, год 214", "зима, год 214", "через несколько лет"]
        var eventIDs: [String] = []
        let eventCount = 30
        for i in 0..<eventCount {
            let id = try eventStore.add(title: "Событие \(i + 1): \(pick(["письмо", "приезд", "находка", "ссора", "разговор", "пожар", "поиски", "признание", "уход", "возвращение"]))")
            eventIDs.append(id)
            let at = i * sceneIDs.count / eventCount
            try eventStore.update(id) {
                $0.date = dates[min(dates.count - 1, i * dates.count / eventCount)]
                $0.notes = ["Что стоит за событием \(i + 1)."]
                $0.places = [spotIDs[random(8)]: "место события"]
                $0.links = Dictionary((0..<(1 + random(3))).map { (sceneIDs[min(sceneIDs.count - 1, at + $0)], "событие \(i + 1) в сцене") }, uniquingKeysWith: { $1 })
            }
            try eventStore.setText(id, "# Событие \(i + 1)\n\nПодробности события.")
        }

        // The plan: four lines of the story; the events and cards stand on them, in the order of the book.
        let plan = try PlanStore(folder: folder)
        let lines = [try plan.addLine(name: "Анна и дом", color: "teal"), try plan.addLine(name: "Тайна подвала", color: "purple"),
                     try plan.addLine(name: "Город и Максим", color: "amber"), try plan.addLine(name: "Ольга", color: "pink")]
        for (id, text) in zip(lines, ["Что Анна находит в доме и узнаёт о тёте.", "Всё, что связано с подвалом и книгой.", "Максим, редакция и расследование.", "Личная линия Ольги."]) {
            try plan.setLineDescription(id, to: text)
        }
        for (i, id) in eventIDs.enumerated() { try plan.placeEvent(id, onLine: lines[i % lines.count], start: (i + 1) * 100) }
        let cardTitles = ["Найти письмо", "Открыть дверь", "Встреча на станции", "Разговор у озера", "Пожар", "Правда о дневнике", "Отъезд", "Книга в подвале"]
        for (i, t) in cardTitles.enumerated() {
            try plan.addCard(title: t, text: "Идея для плана: \(t.lowercased()).", line: lines[i % lines.count], start: (i * 3 + 2) * 100 + 50, color: ["teal", "purple", "amber", "pink"][i % 4])
        }
        try plan.addCard(title: "Идея без места", text: "Эта карточка ещё не на линии.", x: 80, y: 40, color: "green")
        try plan.addCard(title: "Вопрос к себе", text: "Кто на самом деле написал книгу?", x: 320, y: 60, color: "red")

        // The book's own dictionary, and saved export profiles.
        try BookDictionary.save(words, book: folder)
        let publisher: JSONObject = [
            "cover": .bool(true), "footnotes": .string("page"), "format": .string("docx"),
            "headings": .object(["chapter": .object(["new_page": .bool(true), "print": .string("number_and_title"), "template": .string("Глава {number}. {title}")]),
                                 "part": .object(["new_page": .bool(true), "print": .string("number_and_title"), "template": .string("Часть {number}. {title}")]),
                                 "scene": .object(["print": .string("none")])]),
            "name": .string("Рукопись в издательство"), "scene_break": .string("mark"), "title_page": .string("auto"), "toc": .bool(true),
        ]
        let ebook: JSONObject = [
            "cover": .bool(true), "footnotes": .string("book"), "format": .string("epub"),
            "headings": .object(["chapter": .object(["new_page": .bool(false), "print": .string("title")]), "part": .object(["new_page": .bool(false), "print": .string("title")]),
                                 "scene": .object(["print": .string("none")])]),
            "name": .string("Электронная книга"), "scene_break": .string("mark"), "title_page": .string("auto"), "toc": .bool(true), "toc_scenes": .bool(true),
        ]
        let finished: JSONObject = [
            "cover": .bool(false), "footnotes": .string("none"), "format": .string("txt"),
            "filters": .object(["statuses": .array([.string("done"), .string("revised")])]),
            "headings": .object(["chapter": .object(["new_page": .bool(false), "print": .string("title")]), "part": .object(["new_page": .bool(false), "print": .string("title")]),
                                 "scene": .object(["print": .string("none")])]),
            "name": .string("Только готовое"), "scene_break": .string("mark"), "title_page": .string("none"), "toc": .bool(false),
        ]
        try putJSON("export.json", ["format": .int(1), "last_profile": .string("Электронная книга"), "profiles": .array([.object(publisher), .object(ebook), .object(finished)])])

        // Two snapshots, the second after a change, so that there is something to compare.
        let snapshots = SnapshotStore(bookFolder: folder)
        _ = try snapshots.take(.manual, name: "Первый черновик")
        if let first = sceneIDs.first, let url = (try? BookStructure.load(folder: folder))?.scenes.first(where: { $0.id == first }).map({ folder.appendingPathComponent($0.node.base + ".md") }) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try Data((text + "\nДобавлено после первого снимка.\n").utf8).write(to: url)
        }
        _ = try snapshots.take(.manual, name: "После правки")
    }
}
