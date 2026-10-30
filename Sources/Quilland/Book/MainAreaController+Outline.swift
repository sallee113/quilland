import AppKit
import QuillandCore

/// The Outline's data: the synopsis, the note and the size of every section, and what the Outline changes in them.
extension MainAreaController {
    /// A synopsis or a note was changed from outside the views that show them (Replace): they read them again.
    func didChangeSectionTexts() {
        loadSectionTexts()
        tree?.refreshCounts()
        outlineDetail?.refresh()
        if showsRightPanel { rightPanel.refresh() }
        onChange?()
    }

    func loadSectionTexts() {
        sectionTexts = [:]
        let editor = BookEditor(structure: session.structure)
        func visit(_ node: BookStructure.Node) {
            let record = editor.record(node.id)
            sectionTexts[node.id] = (record?.string("synopsis"), record?.string("note"))
            node.children.forEach(visit)
        }
        session.structure.roots.forEach(visit)
    }

    private func scenes(under id: String) -> [BookStructure.Node] {
        guard let node = findNode(id) else { return [] }
        func collect(_ n: BookStructure.Node) -> [BookStructure.Node] { n.kind == .scene ? [n] : n.children.flatMap(collect) }
        return collect(node)
    }

    /// The size of a scene, a chapter or a part, in characters.
    func sectionCharacters(_ id: String) -> Int { scenes(under: id).reduce(0) { $0 + (session.document($1.id)?.counts.characters ?? 0) } }

    func sectionInfo(_ id: String) -> SectionInfo? {
        if let sub = subsection(id) {
            let place = session.structure.scenes.first { $0.id == sub.scene }?.fullPath ?? ""
            return SectionInfo(id: id, kind: .subsection, title: sub.title, path: place, status: nil, characters: sub.characters, target: nil, synopsis: "", note: "", sceneStatuses: [], sceneCount: 0,
                               characterNames: [], scene: sub.scene, derivedTitle: sub.derivedTitle)
        }
        guard let node = findNode(id) else { return nil }
        let entry = session.structure.scenes.first { $0.id == id }
        let path: String
        switch node.kind {
        case .scene: path = entry?.place ?? ""
        case .chapter: path = session.structure.scenes.first { $0.chapterID == id }?.partTitle ?? ""
        case .part, .subsection: path = ""
        }
        let record = BookEditor(structure: session.structure).record(id)
        let list = scenes(under: id)
        let statuses = SceneRecord.knownStatuses.map { st in (status: st, count: list.filter { (session.document($0.id)?.status ?? "idea") == st }.count) }
        let matcher = ParadigmMatcher(entries: characters.entries)
        var found = Set<String>()
        for scene in list { found.formUnion(matcher.matches(in: session.document(scene.id)?.storage.string ?? "").map(\.entry)) }
        let names = characters.characters.filter { found.contains($0.id ?? "") }.compactMap(\.name)
        return SectionInfo(id: id, kind: node.kind, title: node.title, path: path, status: session.document(id)?.status ?? node.status,
                           characters: sectionCharacters(id), target: record?.int("target_characters"),
                           synopsis: record?.string("synopsis") ?? "", note: record?.string("note") ?? "",
                           sceneStatuses: statuses, sceneCount: list.count, characterNames: names)
    }

    func setSectionText(_ id: String, key: String, _ text: String) {
        do { try BookEditor(structure: session.structure).setText(id, key: key, to: text) } catch { report(error); return }
        var entry = sectionTexts[id] ?? (nil, nil)
        if key == "synopsis" { entry.synopsis = text.isEmpty ? nil : text } else { entry.note = text.isEmpty ? nil : text }
        sectionTexts[id] = entry
        tree?.refreshCounts()
        onChange?()
    }

    func setTarget(_ id: String, _ target: Int?) {
        do { try BookEditor(structure: session.structure).setTarget(id, to: target) } catch { report(error); return }
        outlineDetail?.refresh()
    }
}
