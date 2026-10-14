import AppKit
import QuillandCore

if CommandLine.arguments.contains("--snapshot-ui") {
    setenv("QUILLAND_SETTINGS_DIR", NSTemporaryDirectory() + "quilland-snapshot-settings-\(UUID().uuidString)", 1)
}
// `Quilland --make-demo <folder>` writes the big demo book there and leaves.
if let i = CommandLine.arguments.firstIndex(of: "--make-demo"), i + 1 < CommandLine.arguments.count {
    do { try DemoBook.write(into: URL(fileURLWithPath: CommandLine.arguments[i + 1])); print("written") } catch { print("failed: \(error)"); exit(1) }
    exit(0)
}
if CommandLine.arguments.contains("--selftest-app") || CommandLine.arguments.contains("--selftest-lab") {
    // The checks read the English texts, whatever the language of the system is.
    setenv("QUILLAND_LANGUAGE", "en", 1)
}
if CommandLine.arguments.contains("--selftest-app") {
    // The settings of the test are its own, never the author's.
    setenv("QUILLAND_SETTINGS_DIR", NSTemporaryDirectory() + "quilland-selftest-settings-\(UUID().uuidString)", 1)
}
let app = QuillandApplication.shared
app.setActivationPolicy(.regular)
// Before the first window is made: a button reacts to the pointer from the start.
Hover.installForAllButtons()
let delegate = AppDelegate()
app.delegate = delegate
if CommandLine.arguments.contains("--selftest-lab") {
    setvbuf(stdout, nil, _IONBF, 0)
    // Run the checks once the window exists, then leave with the result as the exit code.
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        delegate.labController.show()
        let code = LabSelfTest(lab: delegate.labController).run()
        exit(code)
    }
}
// `Quilland --export-pdf <book> <file.pdf>` writes the book as a PDF with the default profile and leaves (a check for the PDF export).
if let i = CommandLine.arguments.firstIndex(of: "--export-pdf"), i + 2 < CommandLine.arguments.count {
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let book = URL(fileURLWithPath: CommandLine.arguments[i + 1]), out = URL(fileURLWithPath: CommandLine.arguments[i + 2])
        guard let model = try? BookLoader.load(folder: book) else { print("could not read the book"); exit(1) }
        let options = ExportOptions(profile: ExportStore(book: book).profiles.first ?? ExportStore.defaultProfile(name: "x", format: .pdf))
        let html = String(decoding: BookExporter.export(model, format: .pdf, options: options), as: UTF8.self)
        switch PDFRenderer.renderAndWait(html: html, to: out, layout: options.layout, timeout: 120) {
        case .success(let pages): print("pages: \(pages)"); exit(0)
        case .failure(let error): print("failed: \(error)"); exit(1)
        }
    }
}
// `Quilland --collect-book <book> [characters places events relationships observations]` runs Collect from the Book on a book with the local model and
// prints what it finds (a check of the prompts against the real model).
if let i = CommandLine.arguments.firstIndex(of: "--collect-book"), i + 1 < CommandLine.arguments.count {
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        let named = CommandLine.arguments[(i + 2)...].compactMap(CollectKind.init(rawValue:))
        let kinds = Set(named.isEmpty ? CollectKind.allCases : named)
        guard let structure = try? BookStructure.load(folder: folder) else { print("cannot read the book"); exit(1) }
        let scenes = structure.scenes.map { CollectScene(id: $0.id, title: $0.node.title, text: (try? String(contentsOf: structure.markdownURL(for: $0.node), encoding: .utf8)) ?? "") }
        var done = false
        Task {
            let status = await AIConnection.check(address: AIConnection.defaultAddress, model: "", contextSetting: 0)
            guard let model = status.model, let config = AIConnection.config(address: AIConnection.defaultAddress, model: model) else { print("no model: \(status.message)"); exit(1) }
            print(status.message)
            var request = CollectRequest(kinds: kinds, scenes: scenes)
            request.context = status.context
            request.language = BookSettings.load(book: folder).language
            let started = Date()
            let box = CollectBox()
            let summary = await CollectJob.run(request, client: LMStudioClient(config: config), progress: { print("scene \($0.scene)/\($0.of) \($0.title)") }, found: { box.set.merge($0) })
            for item in box.set.items {
                print("\(item.kind.rawValue): \(item.title) | aliases \(item.aliases) | \(item.detail) | \(item.type) \(item.parent) \(item.date) \(item.places)")
                for e in item.evidence { print("    «\(e.quote)» — \(e.note)") }
            }
            print("summary: \(summary), \(Int(Date().timeIntervalSince(started))) s")
            done = true
            exit(0)
        }
        _ = done
    }
}
final class CollectBox: @unchecked Sendable { var set = CollectedSet() }
// `Quilland --check-consistency <book> <scene title>` checks one scene of a book against its cards with the local model and prints the findings.
if let i = CommandLine.arguments.firstIndex(of: "--check-consistency"), i + 2 < CommandLine.arguments.count {
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1]), title = CommandLine.arguments[i + 2]
        guard let structure = try? BookStructure.load(folder: folder), let entry = structure.scenes.first(where: { $0.node.title == title }) else { print("no such scene"); exit(1) }
        let text = (try? String(contentsOf: structure.markdownURL(for: entry.node), encoding: .utf8)) ?? ""
        Task {
            let status = await AIConnection.check(address: AIConnection.defaultAddress, model: "", contextSetting: 0)
            guard let model = status.model, let config = AIConnection.config(address: AIConnection.defaultAddress, model: model) else { print("no model"); exit(1) }
            let sources = ConsistencySources.gather(sceneID: entry.id, passage: text, characters: CharacterStore(book: folder), worlds: WorldStore(book: folder), events: EventStore(book: folder), relationships: RelationshipStore(book: folder), structure: structure, budget: 12000)
            for s in sources { print("[\(s.label)] \(s.title): \(s.text.prefix(120))") }
            let box = ConsistencyBox()
            let summary = await ConsistencyJob.run(scenes: [ConsistencyScene(id: entry.id, title: title, text: text, sources: sources)], language: BookSettings.load(book: folder).language, context: status.context, client: LMStudioClient(config: config), progress: { _ in }, found: { box.list += $0 })
            for f in box.list { print("FOUND: \(f.problem)\n   passage «\(f.quote)»\n   \(f.source.label) «\(f.sourceQuote)»") }
            print("summary: \(summary)")
            exit(0)
        }
    }
}
final class ConsistencyBox: @unchecked Sendable { var list: [ConsistencyFinding] = [] }
// `Quilland --snapshot-suggestions <file.png>` opens a demo book with findings in the Suggestions tab and takes a picture of the window (to see the layout).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-suggestions"), i + 1 < CommandLine.arguments.count {
    setenv("QUILLAND_SETTINGS_DIR", NSTemporaryDirectory() + "quilland-snapshot-settings-\(UUID().uuidString)", 1)
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
        let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-suggest-\(UUID().uuidString)")
        try? DemoBook.write(into: folder, scenes: 12, paragraphs: 4)
        guard delegate.openBook(at: folder), let win = delegate.bookWindows.first else { print("no window"); exit(1) }
        win.window.setContentSize(NSSize(width: 1100, height: 760))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let main = win.main
        let scene = main.session.structure.scenes[3].id
        let source = ConsistencySource(label: "C1", kind: .character, ref: "x", title: "Анна", text: "Серые глаза, двадцать восемь лет.")
        main.collect.injectFindings([
            ConsistencyFinding(scene: scene, problem: "В тексте Анне тридцать пять лет, а в карточке двадцать восемь.", quote: "Анне было тридцать пять лет, и она хорошо это помнила", range: NSRange(location: 0, length: 5), source: source, sourceQuote: "Анна — высокая женщина двадцати восьми лет"),
            ConsistencyFinding(scene: scene, problem: "Голубые глаза вместо серых.", quote: "Анна подняла голубые глаза", range: NSRange(location: 0, length: 5), source: source, sourceQuote: "Глаза серые"),
        ])
        var c = CollectedItem(kind: .characters, name: "Вера Павловна"); c.aliases = ["Тётя Вера"]; c.detail = "Хозяйка дома, тётя Анны."
        c.evidence = [CollectedEvidence(scene: scene, quote: "Вы к Вере Павловне", range: NSRange(location: 0, length: 5), note: "её ждёт Анна")]
        var p = CollectedItem(kind: .places, name: "Дом на Сосновой"); p.detail = "Дом в конце улицы."; p.parent = "Сосновая"
        p.evidence = [CollectedEvidence(scene: scene, quote: "Дом стоял в конце улицы", range: NSRange(location: 0, length: 5), note: "освещён изнутри")]
        main.collect.inject([c, p])
        main.showSearch(.suggestions)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        guard let view = win.window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("no picture"); exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out)
        print("written")
        exit(0)
    }
}
// `Quilland --continue-test <book> <scene title> [direction]` asks the local model to continue a scene after its last word and prints the streamed text.
if let i = CommandLine.arguments.firstIndex(of: "--continue-test"), i + 2 < CommandLine.arguments.count {
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1]), title = CommandLine.arguments[i + 2]
        let direction = i + 3 < CommandLine.arguments.count ? CommandLine.arguments[i + 3] : nil
        guard let structure = try? BookStructure.load(folder: folder), let entry = structure.scenes.first(where: { $0.node.title == title }) else { print("no such scene"); exit(1) }
        let text = (try? String(contentsOf: structure.markdownURL(for: entry.node), encoding: .utf8)) ?? ""
        Task {
            let status = await AIConnection.check(address: AIConnection.defaultAddress, model: "", contextSetting: 0)
            guard let model = status.model, let config = AIConnection.config(address: AIConnection.defaultAddress, model: model) else { print("no model"); exit(1) }
            let sources = ConsistencySources.gather(sceneID: entry.id, passage: String(text.suffix(6000)), characters: CharacterStore(book: folder), worlds: WorldStore(book: folder), events: EventStore(book: folder), relationships: RelationshipStore(book: folder), structure: structure, budget: 6000)
            let (messages, summary) = ContinuePrompt.messages(before: text, after: "", language: BookSettings.load(book: folder).language, synopsis: "", note: "", sources: sources, planCards: [], direction: direction, context: status.context)
            print("summary: \(summary)")
            var filter = ContinuationFilter(before: text)
            print("---")
            do {
                for try await event in LMStudioClient(config: config).chatStream(messages, think: false, temperature: 0.8, maxTokens: 700) {
                    if case .text(let piece) = event { print(filter.feed(piece), terminator: "") }
                }
            } catch { print("error: \(error)") }
            print("\n---")
            exit(0)
        }
    }
}
// `Quilland --synopsis-test <book> <section title>` writes a synopsis for a scene, chapter or part with the local model and prints it.
if let i = CommandLine.arguments.firstIndex(of: "--synopsis-test"), i + 2 < CommandLine.arguments.count {
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1]), title = CommandLine.arguments[i + 2]
        guard let structure = try? BookStructure.load(folder: folder) else { print("cannot read the book"); exit(1) }
        func find(_ nodes: [BookStructure.Node]) -> BookStructure.Node? { for n in nodes { if n.title == title { return n }; if let f = find(n.children) { return f } }; return nil }
        guard let node = find(structure.roots) else { print("no such section"); exit(1) }
        let editor = BookEditor(structure: structure)
        Task {
            let status = await AIConnection.check(address: AIConnection.defaultAddress, model: "", contextSetting: 0)
            guard let model = status.model, let config = AIConnection.config(address: AIConnection.defaultAddress, model: model) else { print("no model"); exit(1) }
            let language = BookSettings.load(book: folder).language
            var user = ""
            if node.kind == .scene {
                user = SynopsisPrompt.userForScene(title: node.title, text: (try? String(contentsOf: structure.markdownURL(for: node), encoding: .utf8)) ?? "")
            } else {
                user = SynopsisPrompt.userForSection(kind: node.kind, title: node.title, children: node.children.map { ($0.title, editor.record($0.id)?.string("synopsis") ?? "") })
            }
            var filter = ContinuationFilter(before: "")
            do {
                for try await event in LMStudioClient(config: config).chatStream([ChatMessage("system", SynopsisPrompt.system(kind: node.kind, language: language)), ChatMessage("user", user)], think: false, temperature: 0.4, maxTokens: 500) {
                    if case .text(let piece) = event { print(filter.feed(piece), terminator: "") }
                }
            } catch { print("error: \(error)") }
            print("")
            exit(0)
        }
    }
}
// `Quilland --snapshot-chat <file.png>` opens a demo book with the Chat tab open and a short conversation, and takes a picture of the window (to see the layout).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-chat"), i + 1 < CommandLine.arguments.count {
    setenv("QUILLAND_SETTINGS_DIR", NSTemporaryDirectory() + "quilland-snapshot-settings-\(UUID().uuidString)", 1)
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
        let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-chatshot-\(UUID().uuidString)")
        try? DemoBook.write(into: folder, scenes: 12, paragraphs: 4)
        guard delegate.openBook(at: folder), let win = delegate.bookWindows.first else { print("no window"); exit(1) }
        win.window.setContentSize(NSSize(width: 1180, height: 780))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let main = win.main
        main.setRightPanel(true)
        main.rightPanel.setVisibleTabs([.section, .characters, .world, .events, .chat])
        main.rightPanel.showTab(.chat)
        let scene = main.session.structure.scenes[3].id
        main.rightPanel.show(scene)
        let book = ChatMentions.Book(structure: main.session.structure, characters: main.characters, worlds: main.worlds, events: main.eventStore, relationships: main.relationships, plan: nil, sceneText: { main.session.document($0)?.storage.string ?? "" })
        if let a = ChatMentions.scene(scene, in: book) { main.chatSession.attach(a) }
        if let a = ChatMentions.characters(of: scene, in: book) { main.chatSession.attach(a) }
        main.chatSession.inject([ChatTurn("user", "Кто такая Вера Павловна и что она делает в этой сцене?"), ChatTurn("assistant", "Вера Павловна — хозяйка дома, тётя Анны. В этой сцене она слышит шаги на чердаке и не может решить, стоит ли возвращаться.")])
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        guard let view = win.window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("no picture"); exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out)
        print("written")
        exit(0)
    }
}
// `Quilland --chat-test <book> <scene title> <question>` asks the local model a question about a scene (with the scene and its cards attached) and prints the answer.
if let i = CommandLine.arguments.firstIndex(of: "--chat-test"), i + 3 < CommandLine.arguments.count {
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1]), title = CommandLine.arguments[i + 2], question = CommandLine.arguments[i + 3]
        guard let structure = try? BookStructure.load(folder: folder), let entry = structure.scenes.first(where: { $0.node.title == title }) else { print("no such scene"); exit(1) }
        Task {
            let status = await AIConnection.check(address: AIConnection.defaultAddress, model: "", contextSetting: 0)
            guard let model = status.model, let config = AIConnection.config(address: AIConnection.defaultAddress, model: model) else { print("no model"); exit(1) }
            let book = ChatMentions.Book(structure: structure, characters: CharacterStore(book: folder), worlds: WorldStore(book: folder), events: EventStore(book: folder), relationships: RelationshipStore(book: folder), plan: try? PlanStore(folder: folder),
                                         sceneText: { id in structure.scenes.first { $0.id == id }.flatMap { try? String(contentsOf: structure.markdownURL(for: $0.node), encoding: .utf8) } ?? "" })
            let attachments = [ChatMentions.scene(entry.id, in: book), ChatMentions.characters(of: entry.id, in: book)].compactMap { $0 }
            let (messages, usage) = ChatPrompt.build(history: [], question: question, attachments: attachments, language: BookSettings.load(book: folder).language, context: status.context)
            print("usage: \(usage.tokens)/\(usage.context)")
            do { for try await event in LMStudioClient(config: config).chatStream(messages, think: false, temperature: 0.7, maxTokens: 800) { if case .text(let t) = event { print(t, terminator: "") } } } catch { print("error: \(error)") }
            print("")
            exit(0)
        }
    }
}
// `Quilland --grammar-test "<text>"` asks the local model to correct the text and prints what it would suggest (a check of the prompt against the real model).
if let i = CommandLine.arguments.firstIndex(of: "--grammar-test"), i + 1 < CommandLine.arguments.count {
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let text = CommandLine.arguments[i + 1]
        Task {
            let status = await AIConnection.check(address: AIConnection.defaultAddress, model: "", contextSetting: 0)
            guard let model = status.model, let config = AIConnection.config(address: AIConnection.defaultAddress, model: model) else { print("no model"); exit(1) }
            let box = FindingsBoxApp()
            let summary = await GrammarJob.run(scenes: [GrammarScene(id: "t", title: "t", text: text)], language: "ru", client: LMStudioClient(config: config), progress: { _ in }, found: { _, list in box.list += list })
            for f in box.list { print("«\(f.before)» → «\(f.after)»") }
            print("summary: \(summary)")
            exit(0)
        }
    }
}
final class FindingsBoxApp: @unchecked Sendable { var list: [TypographyFinding] = [] }
// `Quilland --snapshot-settings <file.png> <section number>` takes a picture of the Settings window on a section (to see the layout).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-settings"), i + 2 < CommandLine.arguments.count {
    setenv("QUILLAND_SETTINGS_DIR", NSTemporaryDirectory() + "quilland-snapshot-settings-\(UUID().uuidString)", 1)
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
        let out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
        delegate.showSettings()
        guard let st = delegate.settingsWindow, let section = SettingsWindowController.Section(rawValue: Int(CommandLine.arguments[i + 2]) ?? 0) else { print("no window"); exit(1) }
        st.select(section)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        guard let view = st.window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("no picture"); exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: out)
        print("written")
        exit(0)
    }
}
if CommandLine.arguments.contains("--selftest-app") {
    setvbuf(stdout, nil, _IONBF, 0)
    // From a timer, not from a block on the main queue: while a block of the (serial) main queue runs, no other block of it can, even if the run loop is spun,
    // and the application's own delayed work (focusing the first scene, say) is just such a block.
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-apptest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let code = AppSelfTest(app: delegate, temp: temp).run()
        try? FileManager.default.removeItem(at: temp)
        exit(code)
    }
}
if let i = CommandLine.arguments.firstIndex(of: "--snapshot-ui"), i + 1 < CommandLine.arguments.count {
    // `--snapshot-ui dir`: pictures of the Welcome window, the New Book dialog and a new book's window.
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    setvbuf(stdout, nil, _IONBF, 0)
    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
        print("snapshot-ui: start")
        func shot(_ window: NSWindow, _ name: String) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-uishot-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        // A recent book, so that the list is not empty.
        _ = try? BookCreator.create(NewBookRequest(title: "Дом на Сосновой", author: "Вадим Сульянов", language: "ru", parentFolder: temp))
        delegate.settings.noteOpened(folder: temp.appendingPathComponent("Дом на Сосновой"), name: "Дом на Сосновой")
        delegate.showWelcome()
        shot(delegate.welcome.window, "welcome.png")
        let dialog = NewBookWindowController(parentFolder: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
        dialog.titleField.stringValue = "Моя книга"
        dialog.authorField.stringValue = "Вадим Сульянов"
        dialog.window.makeKeyAndOrderFront(nil)
        shot(dialog.window, "newbook.png")
        dialog.window.orderOut(nil)
        _ = delegate.openBook(at: temp.appendingPathComponent("Дом на Сосновой"))
        if let book = delegate.bookWindows.first {
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            if let tv = book.main.controllers.first?.currentSheet?.textView { tv.insertText("Ночь. Улица. Фонарь. Аптека.\n\nБессмысленный и тусклый свет.", replacementRange: tv.selectedRange()) }
            shot(book.window, "book.png")
        }
        exit(0)
    }
}
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    // `--snapshot out.png [--compare] [--typewriter]`: opens the sample book, scrolls to the third scene, writes a picture of the window, leaves.
    let path = CommandLine.arguments[i + 1]
    DispatchQueue.main.async {
        delegate.labController.show()
        delegate.labController.snapshot(to: path, compare: CommandLine.arguments.contains("--compare"), typewriter: CommandLine.arguments.contains("--typewriter"), plan: CommandLine.arguments.contains("--plan"))
        exit(0)
    }
}
app.run()
