import AppKit
import QuillandCore

/// What accepting suggestions did, in words.
struct AcceptReport {
    var created: [CollectKind: Int] = [:]
    var updated = 0
    var skipped: [String] = []

    var text: String {
        var parts: [String] = []
        for kind in [CollectKind.characters, .places, .events, .relationships, .changes] {
            if let n = created[kind], n > 0 { parts.append(CollectSession.createdText(kind, n)) }
        }
        if updated > 0 { parts.append(Lp("{n} existing card updated", "{n} existing cards updated", updated)) }
        if !skipped.isEmpty { parts.append(Lp("{n} skipped", "{n} skipped", skipped.count) + ": " + skipped.joined(separator: ", ")) }
        return parts.isEmpty ? L("Nothing was changed.") : parts.joined(separator: " · ")
    }
}

/// One run of Collect from the Book and what it found, for the Suggestions tab: the findings wait here, unchecked, until the author accepts them.
final class CollectSession {
    weak var main: MainAreaController?
    private(set) var collected = CollectedSet()
    /// Contradictions found by Consistency Check; they only point at places and cards, nothing in them can be accepted.
    private(set) var findings: [ConsistencyFinding] = []
    var checked: Set<UUID> = []
    /// Why a finding that was asked to be accepted could not be (it stays in the list, unchecked, with this under it).
    private(set) var skipReasons: [UUID: String] = [:]
    func skipReason(for id: UUID) -> String? { skipReasons[id] }
    private(set) var running = false
    /// What the finder says of the findings as they come in: those that look like a card or another row (not the same for sure), and how many were joined to a row they repeat.
    var lookAlikes: [UUID: LookAlike] = [:]
    private(set) var mergedOnTheFly = 0
    /// What each finding that repeats a card of the book would add to it (`refreshAdditions`); one that would add nothing is not listed.
    var additions: [UUID: CardAddition] = [:]
    var cardFacetCache: [CollectKind: [(facet: DupeFacet, title: String)]]?
    var cardFacetSignature = ""
    private(set) var progress: CollectProgress?
    private(set) var summary: CollectSummary?
    private(set) var message = ""
    var onChange: (() -> Void)?
    private var task: Task<Void, Never>?

    static func createdText(_ kind: CollectKind, _ n: Int) -> String {
        switch kind {
        case .characters: return Lp("{n} character created", "{n} characters created", n)
        case .places: return Lp("{n} place created", "{n} places created", n)
        case .events: return Lp("{n} event created", "{n} events created", n)
        case .relationships: return Lp("{n} relationship created", "{n} relationships created", n)
        case .observations: return ""
        case .changes: return Lp("{n} change recorded in an event", "{n} changes recorded in events", n)
        }
    }

    /// All the findings, also those that need no change; the ones to show are `visibleItems`.
    var items: [CollectedItem] { collected.items }

    // MARK: Running

    /// A new run starts from an empty list: what an earlier run found (and what was left waiting) goes, so the list shows what the scope asked for now.
    func beginNewRun() {
        collected = CollectedSet()
        findings = []
        checked = []
        skipReasons = [:]
        lookAlikes = [:]
        additions = [:]
        mergedOnTheFly = 0
        cardFacetCache = nil
        summary = nil
        progress = nil
        message = ""
        onChange?()
    }

    /// Reads every scene of the scope with the model (a run is a fresh look: nothing is skipped because an earlier run read it). The findings come in
    /// as they are made; Stop keeps them.
    func start(kinds: Set<CollectKind>, scope: SearchScope) {
        guard let main, !running else { return }
        guard let client = AIService.shared.client() else {
            let alert = NSAlert()
            alert.messageText = L("The AI is not available")
            alert.informativeText = AIService.shared.unavailableReason ?? ""
            alert.runModal()
            return
        }
        beginNewRun()
        main.saveAll()
        let scenes = main.proofreadingTargets(scope).map { CollectScene(id: $0.id, title: $0.title.isEmpty ? $0.id : $0.title, text: $0.text) }
        var request = CollectRequest(kinds: kinds, scenes: scenes)
        request.language = main.bookLanguage
        request.knownCharacters = main.characters.characters.compactMap(\.name)
        request.knownPlaces = main.worlds.entries.compactMap(\.name)
        request.cards = main.collectCards()
        // The events the book has, by scene: the model is told them, so that it uses a title again and does not name the same event twice.
        for e in main.eventStore.events { if let title = e.title { for s in e.links.keys { request.knownEvents[s, default: []].append(title) } } }
        request.context = AIService.shared.context
        request.reanalyse = true
        running = true
        progress = nil; summary = nil
        message = L("Reading…")
        onChange?()
        let me = self
        task = Task {
            let result = await CollectJob.run(request, client: client, progress: { p in
                DispatchQueue.main.async { me.progress = p; me.onChange?() }
            }, found: { items in
                DispatchQueue.main.async {
                    // (A finding that repeats one already in the list joins it; one that only looks like another is marked, as the list grows.)
                    let before = me.collected.items.count
                    me.collected.merge(me.withFieldsOfCards(items))
                    me.mergedOnTheFly += items.count - (me.collected.items.count - before)
                    me.refreshLookAlikes()
                    me.onChange?()
                }
            })
            await MainActor.run {
                me.running = false
                me.summary = result
                me.progress = nil
                me.message = CollectSession.summaryText(result, found: me.collected.items.count) + (me.duplicatesText.isEmpty ? "" : " · " + me.duplicatesText)
                me.task = nil
                me.onChange?()
            }
        }
    }

    static func summaryText(_ s: CollectSummary, found: Int) -> String {
        if let error = s.error { return error }
        var parts = [s.stopped ? L("Stopped") : L("Done"), Lp("{n} scene read", "{n} scenes read", s.scenesDone)]
        if s.scenesTooShort > 0 { parts.append(Lp("{n} too short", "{n} too short", s.scenesTooShort)) }
        if s.failedPieces > 0 { parts.append(Lp("{n} part could not be read", "{n} parts could not be read", s.failedPieces)) }
        if s.droppedUnverified > 0 { parts.append(Lp("{n} finding left out: its quote is not in the text", "{n} findings left out: their quotes are not in the text", s.droppedUnverified)) }
        return parts.joined(separator: " · ")
    }

    func stop() { task?.cancel() }

    /// For the checks: shows a run in progress (or none), as a run would.
    func injectProgress(_ p: CollectProgress?) { running = p != nil; progress = p; onChange?() }

    /// For the checks: puts findings in the list as a run would.
    func inject(_ items: [CollectedItem]) {
        let before = collected.items.count
        collected.merge(withFieldsOfCards(items))
        mergedOnTheFly += items.count - (collected.items.count - before)
        refreshLookAlikes()
        onChange?()
    }

    /// A change to a card of the book that is already there says "profile" for a character and "description" for a place, whichever word the model used.
    func withFieldsOfCards(_ items: [CollectedItem]) -> [CollectedItem] {
        guard let main else { return items }
        return items.map { item in
            guard item.kind == .changes else { return item }
            let key = Names.normalize(item.name)
            var i = item
            if main.characters.characters.contains(where: { c in ([c.name ?? ""] + c.aliases).contains { Names.normalize($0) == key } }) { if i.field == "description" { i.field = "profile" } }
            else if main.worlds.entries.contains(where: { e in ([e.name ?? ""] + e.aliases).contains { Names.normalize($0) == key } }) { if i.field == "profile" { i.field = "description" } }
            return i
        }
    }

    func dismiss(_ ids: Set<UUID>) {
        dismissFindings(ids.intersection(Set(findings.map(\.id))))
        collected.remove(ids)
        checked.subtract(ids)
        onChange?()
    }

    func clear() { collected = CollectedSet(); findings = []; checked = []; skipReasons = [:]; lookAlikes = [:]; additions = [:]; mergedOnTheFly = 0; cardFacetCache = nil; summary = nil; message = ""; onChange?() }

    // MARK: Consistency Check

    /// Checks the passages of the scope against the book's cards and what earlier scenes say. A selection checks only the selected words.
    func startConsistency(scope: SearchScope) {
        guard let main, !running else { return }
        guard let client = AIService.shared.client() else {
            let alert = NSAlert()
            alert.messageText = L("The AI is not available")
            alert.informativeText = AIService.shared.unavailableReason ?? ""
            alert.runModal()
            return
        }
        beginNewRun()
        main.saveAll()
        let targets = main.searchTargets(scope)
        let context = AIService.shared.context
        let budget = min(12000, max(2000, context - 5000))
        let structure = main.session.structure
        var scenes: [ConsistencyScene] = []
        for id in targets.scenes {
            guard let doc = main.session.document(id) else { continue }
            let text = doc.storage.string
            let within = targets.selection?.scene == id ? targets.selection?.range : nil
            let passage = within.map { (text as NSString).substring(with: $0) } ?? text
            let sources = ConsistencySources.gather(sceneID: id, passage: passage, characters: main.characters, worlds: main.worlds, events: main.eventStore, relationships: main.relationships, structure: structure, budget: budget)
            scenes.append(ConsistencyScene(id: id, title: structure.scenes.first { $0.id == id }?.node.title ?? id, text: text, within: within, sources: sources))
        }
        let language = main.bookLanguage
        let dismissed = AIDismissals.load(book: main.folder)
        running = true
        progress = nil; summary = nil
        message = L("Checking…")
        onChange?()
        let me = self
        task = Task {
            let result = await ConsistencyJob.run(scenes: scenes, language: language, context: context, client: client, progress: { p in
                DispatchQueue.main.async { me.progress = p; me.onChange?() }
            }, found: { new in
                DispatchQueue.main.async {
                    me.findings += new.filter { f in !dismissed.contains(f.key) && !me.findings.contains { $0.key == f.key && $0.scene == f.scene } }
                    me.onChange?()
                }
            })
            await MainActor.run {
                me.running = false
                me.progress = nil
                me.message = CollectSession.consistencyText(result, shown: me.findings.count)
                me.task = nil
                me.onChange?()
            }
        }
    }

    static func consistencyText(_ s: ConsistencySummary, shown: Int) -> String {
        if let error = s.error { return error }
        var parts = [s.stopped ? L("Stopped") : L("Done"), Lp("{n} scene checked", "{n} scenes checked", s.scenesDone)]
        parts.append(shown == 0 ? L("no contradictions found") : Lp("{n} contradiction found", "{n} contradictions found", shown))
        if s.scenesTooShort > 0 { parts.append(Lp("{n} too short", "{n} too short", s.scenesTooShort)) }
        if s.failedPieces > 0 { parts.append(Lp("{n} part could not be read", "{n} parts could not be read", s.failedPieces)) }
        if s.droppedUnverified > 0 { parts.append(Lp("{n} finding left out: its quote is not in the text", "{n} findings left out: their quotes are not in the text", s.droppedUnverified)) }
        if s.droppedByJudge > 0 { parts.append(Lp("{n} doubtful finding left out", "{n} doubtful findings left out", s.droppedByJudge)) }
        return parts.joined(separator: " · ")
    }

    /// Dismisses findings for good (remembered by their words, on this machine).
    func dismissFindings(_ ids: Set<UUID>) {
        let chosen = findings.filter { ids.contains($0.id) }
        AIDismissals.add(chosen.map(\.key), book: main?.folder ?? URL(fileURLWithPath: "/"))
        findings.removeAll { ids.contains($0.id) }
        checked.subtract(ids)
        onChange?()
    }

    /// For the checks: puts findings in the list as a run would.
    func injectFindings(_ list: [ConsistencyFinding]) { findings += list; onChange?() }

    /// For the checks: waits until the run is over.
    func waitUntilDone(timeout: TimeInterval = 60) {
        let end = Date().addingTimeInterval(timeout)
        while running, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    }

    // MARK: Accepting

    /// Whether the finding is for something that already has a card (it then only adds the scenes it was found in).
    func existingMatch(_ item: CollectedItem) -> String? {
        guard let main else { return nil }
        let wanted = Set(([item.name] + item.aliases).map(Names.normalize))
        switch item.kind {
        case .characters:
            if let name = main.characters.characters.first(where: { c in !wanted.isDisjoint(with: Set(([c.name ?? ""] + c.aliases).map(Names.normalize))) })?.name { return name }
        case .places:
            if let name = main.worlds.entries.first(where: { e in !wanted.isDisjoint(with: Set(([e.name ?? ""] + e.aliases).map(Names.normalize))) })?.name { return name }
        case .events:
            if let title = main.eventStore.events.first(where: { Names.normalize($0.title ?? "") == Names.normalize(item.name) })?.title { return title }
        case .relationships: break
        default: return nil
        }
        // Or the finder says it is the same card under another wording (an event with the same scene and people and a title that says the same).
        return sameCard(item)?.title
    }

    /// Makes the cards. A snapshot is taken first. An existing card is never overwritten: it only gets the scenes where the thing was found, the other names
    /// and the notes it did not have.
    @discardableResult
    func accept(_ ids: Set<UUID>) -> AcceptReport {
        var report = AcceptReport()
        guard let main else { return report }
        let chosen = collected.items.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return report }
        main.saveAll()
        _ = try? SnapshotStore(bookFolder: main.folder).take(.beforeOperation, reason: L("Collect from the Book"))

        func linkText(_ item: CollectedItem) -> [String: String] {
            var out: [String: String] = [:]
            for e in item.evidence where out[e.scene] == nil { out[e.scene] = e.note.isEmpty ? String(e.quote.prefix(80)) : e.note }
            return out
        }
        func merged(_ old: [String: String], _ new: [String: String]) -> [String: String] { old.merging(new) { existing, _ in existing } }
        for item in chosen { skipReasons.removeValue(forKey: item.id) }
        /// A finding that could not be accepted: it stays, and says why.
        func skip(_ item: CollectedItem, _ reason: String) {
            report.skipped.append(item.title)
            skipReasons[item.id] = reason
        }

        // Who is who, by name and other name: the cards there are now and the ones made here.
        var characterIDs: [String: String] = [:]
        for c in main.characters.characters { for n in [c.name ?? ""] + c.aliases { if let id = c.id { characterIDs[Names.normalize(n)] = id } } }
        var entryIDs: [String: String] = [:]
        for e in main.worlds.entries { for n in [e.name ?? ""] + e.aliases { if let id = e.id { entryIDs[Names.normalize(n)] = id } } }

        let story = StoryAccept(main: main, characterIDs: characterIDs, entryIDs: entryIDs, story: chosen)
        for item in chosen where item.kind == .characters {
            let names = ([item.name] + item.aliases).map(Names.normalize)
            if let id = names.compactMap({ characterIDs[$0] }).first ?? sameCard(item)?.id {
                try? main.characters.update(id) { r in
                    r.links = merged(r.links, linkText(item))
                    for a in [item.name] + item.aliases where !([r.name ?? ""] + r.aliases).contains(where: { Names.normalize($0) == Names.normalize(a) }) { r.aliases.append(a) }
                }
                report.updated += 1
            } else if let id = try? main.characters.add(name: item.name) {
                try? main.characters.update(id) { r in r.aliases = item.aliases; r.links = linkText(item) }
                if !item.detail.isEmpty { try? main.characters.setProfile(id, item.detail) }
                for n in names { characterIDs[n] = id }
                report.created[.characters, default: 0] += 1
            }
        }

        // Places: a world to put them in (the book's only one; asked when there are several), the larger places before the ones inside them.
        let places = chosen.filter { $0.kind == .places }.sorted { ($0.parent.isEmpty ? 0 : 1) < ($1.parent.isEmpty ? 0 : 1) }
        var worldID: String?
        var worldAsked = false
        for item in places {
            let names = ([item.name] + item.aliases).map(Names.normalize)
            if let id = names.compactMap({ entryIDs[$0] }).first ?? sameCard(item)?.id {
                try? main.worlds.updateEntry(id) { r in r.links = merged(r.links, linkText(item)) }
                report.updated += 1
                continue
            }
            if worldID == nil, !worldAsked { worldAsked = true; worldID = chooseWorld(main) }
            guard let world = worldID else { skip(item, L("no world was chosen for it")); continue }
            let parent = entryIDs[Names.normalize(item.parent)]
            if let id = try? main.worlds.addEntry(name: item.name, world: world, parent: parent, type: "place") {
                try? main.worlds.updateEntry(id) { r in r.aliases = item.aliases; r.links = linkText(item) }
                if !item.detail.isEmpty { try? main.worlds.setText(id, item.detail) }
                for n in names { entryIDs[n] = id }
                report.created[.places, default: 0] += 1
            }
        }

        story.characterIDs = characterIDs; story.entryIDs = entryIDs
        for item in chosen where item.kind == .events {
            // (An event is the same as one the book has when the title is, or when the finder says it is the same event worded otherwise.)
            let found = main.eventStore.events.first { Names.normalize($0.title ?? "") == Names.normalize(item.name) } ?? sameCard(item).flatMap { main.eventStore.event($0.id) }
            // Who takes part: the event keeps the link. A name with no card (here or made in this run) is left out.
            func linkParticipants(_ event: String) {
                let who = Set(item.members.compactMap { characterIDs[Names.normalize($0)] })
                guard !who.isEmpty else { return }
                try? main.eventStore.update(event) { r in
                    var l = r.characters
                    for cid in who where l[cid] == nil { l[cid] = "" }
                    r.characters = l
                }
            }
            if let id = found?.id {
                try? main.eventStore.update(id) { r in r.links = merged(r.links, linkText(item)) }
                linkParticipants(id)
                story.noteEvent(id, title: item.name, scenes: item.evidence.map(\.scene))
                report.updated += 1
            } else if let id = try? main.eventStore.add(title: item.name) {
                story.noteEvent(id, title: item.name, scenes: item.evidence.map(\.scene))
                let placeIDs = item.places.compactMap { entryIDs[Names.normalize($0)] }
                try? main.eventStore.update(id) { r in
                    r.date = item.date
                    r.links = linkText(item)
                    r.places = Dictionary(placeIDs.map { ($0, "") }, uniquingKeysWith: { a, _ in a })
                }
                if !item.detail.isEmpty { try? main.eventStore.setText(id, item.detail) }
                linkParticipants(id)
                report.created[.events, default: 0] += 1
            }
        }

        // Relationships and changes: in the events (a change with no event of the story gets one made for its scene).
        func record(_ item: CollectedItem, _ outcome: StoryAccept.Outcome) {
            switch outcome {
            case .created(let kind): report.created[kind, default: 0] += 1
            case .updated: report.updated += 1
            case .skipped(let reason): skip(item, reason)
            }
        }
        for item in chosen where item.kind == .relationships { record(item, story.apply(relationship: item, linkText: linkText(item))) }
        for item in chosen where item.kind == .changes { record(item, story.apply(change: item)) }
        if story.eventsMade > 0 { report.created[.events, default: 0] += story.eventsMade }

        // A fact that was always so goes into the card's own text as a new paragraph (the notes are the author's: nothing is written there).
        for item in chosen where item.kind == .observations {
            let key = Names.normalize(item.about)
            func appended(_ base: String) -> String? { DuplicateFinder.says(base, item.detail) ? nil : (base.isEmpty ? item.detail : base + "\n\n" + item.detail) }
            if let id = characterIDs[key] {
                if let text = appended(main.characters.profile(id)) { try? main.characters.setProfile(id, text); report.updated += 1 } else { skip(item, L("the card already says this")) }
            } else if let id = entryIDs[key] {
                if let text = appended(main.worlds.text(id)) { try? main.worlds.setText(id, text); report.updated += 1 } else { skip(item, L("the card already says this")) }
            } else { skip(item, L("no card named “{name}” to attach it to", ["name": item.about])) }
        }

        // What was accepted leaves the list. What was skipped stays, with its reason, and is no longer ticked (so that it is not tried again by itself).
        let done = Set(chosen.filter { skipReasons[$0.id] == nil }.map(\.id))
        collected.remove(done)
        checked.subtract(chosen.map(\.id))
        cardFacetCache = nil   // (the book has new cards to be compared with)
        refreshLookAlikes()
        main.collectedCardsChanged()
        message = report.text
        // Cards that look like one are in the book (from this run or earlier ones): the writer is told where to look.
        let doubles = BookDuplicates.find(characters: main.characters, worlds: main.worlds, events: main.eventStore, relationships: main.relationships, dismissed: BookDuplicates.dismissed(book: main.folder)).count
        if doubles > 0 { message += " · " + Lp("{n} group of cards that look like one: Edit ▸ Find Duplicate Cards…", "{n} groups of cards that look like one: Edit ▸ Find Duplicate Cards…", doubles) }
        onChange?()
        return report
    }

    /// The world the places go to: the book's only one, one made when there is none, or the author's choice.
    private func chooseWorld(_ main: MainAreaController) -> String? {
        let worlds = main.worlds.worlds
        if worlds.count == 1 { return worlds[0].id }
        if worlds.isEmpty { return try? main.worlds.addWorld(name: L("World")) }
        let alert = NSAlert()
        alert.messageText = L("Which world are the places in?")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for w in worlds { popup.addItem(withTitle: w.name ?? ""); popup.lastItem?.representedObject = w.id }
        alert.accessoryView = popup
        alert.addButton(withTitle: L("Use This World"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return popup.selectedItem?.representedObject as? String
    }
}

extension MainAreaController {
    /// The cards changed under the views (after accepting suggestions): they read again.
    func collectedCardsChanged() {
        charactersView?.reload()
        worldView?.reload()
        eventsView?.reload()
        rightPanel.refresh()
        onChange?()
    }
}
