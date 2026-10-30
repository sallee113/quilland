import AppKit
import QuillandCore

extension MainAreaController {
    /// The subsections of a scene, in order, as its text is now (the scenes that have markers are known from the structure; their text is read as it is open, so a title
    /// that begins a subsection and its size are current).
    func subsections(of scene: String) -> [Subsection] {
        guard session.structure.subsections[scene] != nil else { return [] }
        guard let doc = session.document(scene) else { return session.structure.subsections[scene] ?? [] }
        let markdown = MarkdownWriter.write(AttributedBridge.document(from: doc.storage))
        let titles = BookEditor(structure: session.structure).record(scene).map { SceneRecord(object: $0).fragmentTitles } ?? [:]
        return Subsections.parse(scene: scene, markdown: markdown, titles: titles)
    }

    /// A subsection by its id, with the scene it is in.
    func subsection(_ id: String) -> Subsection? {
        guard SceneLinks.isSubsection(id) || session.structure.subsections.values.contains(where: { $0.contains { $0.id == id } }) else { return nil }
        let scene = SceneLinks.scene(of: id)
        return subsections(of: scene).first { $0.id == id }
    }

    /// "Part › Chapter › Scene › Subsection": where a subsection is, for lists and menus.
    func subsectionTitle(_ s: Subsection) -> String {
        let place = session.structure.scenes.first { $0.id == s.scene }?.fullPath ?? ""
        return place.isEmpty ? s.shownTitle : place + " › " + s.shownTitle
    }

    /// The subsection the cursor is in, in the scene of this id at this place of its text; nil when the scene is not divided.
    func subsection(inScene scene: String, at position: Int) -> Subsection? {
        guard let doc = session.document(scene), session.structure.subsections[scene] != nil else { return nil }
        let subs = subsections(of: scene)
        guard !subs.isEmpty else { return nil }
        // The markers' places in the open text, in order: the subsection whose marker is the last one at or before the cursor.
        var starts: [Int] = []
        doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: doc.storage.length)) { value, range, _ in if value != nil { starts.append(range.location) } }
        let leading = subs.first.map { !$0.isMarked } ?? false
        var index = leading ? 0 : -1
        for (i, start) in starts.enumerated() where start <= position { index = i + (leading ? 1 : 0) }
        return subs.indices.contains(max(0, index)) ? subs[max(0, index)] : subs.first
    }

    /// Where the marker of a subsection is in the open text of its scene (0 for the part before the first marker).
    func markerLocation(of id: String, in scene: String) -> Int? {
        guard let doc = session.document(scene) else { return nil }
        var found: Int?
        doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: doc.storage.length)) { value, range, stop in
            if let v = value as? String, v == id { found = range.location; stop.pointee = true }
        }
        return found ?? (id == scene ? 0 : nil)
    }

    /// The tree shows the subsections under their scenes and tells the owner what happens to them.
    func wireSubsections(_ list: StructureTreeController) {
        list.subsectionsOf = { [weak self] in self?.subsections(of: $0) ?? [] }
        list.onRenameSubsection = { [weak self] scene, id, title in self?.renameSubsection(scene: scene, id: id, to: title) }
        list.onJoinSubsection = { [weak self] scene, id in self?.joinSubsection(scene: scene, id: id) }
    }

    /// Gives a subsection a title (empty: the first words stand for it again): written in its scene's data file, one undoable change like the other titles.
    func renameSubsection(scene: String, id: String, to title: String) {
        saveAll()
        do { try BookEditor(structure: session.structure).setSubsectionTitle(id, of: scene, to: title) } catch { report(error); return }
        reloadStructureQuietly()
    }

    /// Reads the structure again and shows it, with nothing else changed (the cursor, the views stay).
    func reloadStructureQuietly() {
        guard let structure = try? BookStructure.load(folder: folder) else { return }
        session.replaceStructure(structure)
        tree?.reload(structure: session.structure, characters: { [weak self] in self?.sectionCharacters($0) ?? 0 })
        outlineDetail?.refresh()
        NotificationCenter.default.post(name: .bookDataChanged, object: nil)
        onChange?()
    }

    // MARK: Dividing a scene into subsections, and joining them

    /// Where a scene would be divided with the cursor here: the start of the paragraph the cursor is in. Nil when it cannot be (on a marker, at the top of a scene that has none,
    /// or in a paragraph that begins a subsection already).
    func subsectionCut(in scene: String, caret: Int) -> Int? {
        guard let doc = session.document(scene) else { return nil }
        let text = doc.storage.string as NSString
        guard text.length > 0 else { return nil }
        let cut = text.paragraphRange(for: NSRange(location: min(max(0, caret), text.length), length: 0)).location
        var starts: [Int] = []
        doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: doc.storage.length)) { value, range, _ in if value != nil { starts.append(range.location) } }
        if starts.contains(cut) { return nil }                       // the cursor is on a marker
        if starts.contains(where: { $0 + 2 == cut }) { return nil }  // this paragraph begins a subsection already
        if cut == 0 && starts.isEmpty { return nil }                 // the first part would be empty
        return cut
    }

    /// ⌥⌘⇧↩: the scene is divided into subsections, the next one beginning at the paragraph the cursor is in. The first time, the scene becomes two subsections; after that
    /// each one adds a subsection. One undoable step.
    func divideIntoSubsections() {
        guard let area = controllers.first(where: { $0.currentSceneID != nil }), let id = area.currentSceneID, let doc = session.document(id), let tv = area.currentSheet?.textView else { return }
        guard let cut = subsectionCut(in: id, caret: tv.selectedRange().location) else {
            let alert = NSAlert()
            alert.messageText = L("Put the cursor in a paragraph where a new subsection begins")
            alert.informativeText = L("A subsection begins at the paragraph the cursor is in. The first part of a scene cannot be empty, and a paragraph that begins a subsection already cannot begin another.")
            alert.runModal()
            return
        }
        func marker() -> NSAttributedString {
            var attrs = Styler.attributes(kind: BlockKind.fragment)
            attrs[.quillandFragment] = UUID().uuidString.lowercased()
            let m = NSMutableAttributedString(string: AttributedBridge.object, attributes: attrs)
            m.append(NSAttributedString(string: "\n", attributes: Styler.attributes(kind: BlockKind.fragment)))
            return m
        }
        var hasMarkers = false
        doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: doc.storage.length)) { value, _, _ in if value != nil { hasMarkers = true } }
        restructure(focusText: true, undoName: L("Divide into subsections")) { _ in
            doc.storage.insert(marker(), at: cut)
            // (The first time, the first part gets its marker too, at the top: every part of a divided scene has one.)
            if !hasMarkers { doc.storage.insert(marker(), at: 0) }
            doc.textDidChange()
            doc.updateCounts()
            _ = doc.saveNow()
            self.pendingCursor = (id, cut + 2 + (hasMarkers ? 0 : 2))
            return id
        }
    }

    /// The cursor is in a subsection that is not the first: it is joined with the one before.
    func joinWithPreviousSubsection() {
        guard let area = controllers.first(where: { $0.currentSceneID != nil }), let id = area.currentSceneID, let tv = area.currentSheet?.textView,
              let sub = subsection(inScene: id, at: tv.selectedRange().location), sub.index > 0 else { return }
        joinSubsection(scene: id, id: sub.id)
    }

    /// Takes the boundary before a subsection away: its text joins the one before it, and what was linked to it is linked to that one. When one subsection is left, the scene
    /// has no markers again. One undoable step.
    func joinSubsection(scene: String, id: String) {
        guard let doc = session.document(scene) else { return }
        let subs = subsections(of: scene)
        guard let at = subs.firstIndex(where: { $0.id == id }), at > 0, subs[at].isMarked else { return }
        let before = subs[at - 1]
        let removing = [id]
        restructure(focusText: true, undoName: L("Join subsections")) { [folder] editor in
            var markers: [(range: NSRange, id: String)] = []
            doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: doc.storage.length)) { value, range, _ in if let v = value as? String { markers.append((range, v)) } }
            func delete(_ marker: (range: NSRange, id: String)) {
                // (The marker's line: its object character and the line break after it.)
                let length = min(2, doc.storage.length - marker.range.location)
                doc.storage.deleteCharacters(in: NSRange(location: marker.range.location, length: length))
            }
            var gone = removing
            var survivor = before.id
            var topGone = false
            if let m = markers.first(where: { $0.id == id }) {
                let place = m.range.location
                delete(m)
                markers.removeAll { $0.id == id }
                // One subsection left: it is the whole scene, and it needs no marker.
                if markers.count == 1, markers[0].range.location == 0, let only = markers.first {
                    delete((only.range, only.id))
                    gone.append(only.id)
                    topGone = true
                    if before.id == only.id { survivor = scene }
                }
                self.pendingCursor = (scene, max(0, place - (topGone ? 2 : 0)))
            }
            doc.textDidChange()
            doc.updateCounts()
            _ = doc.saveNow()
            // What was linked to the subsection that went is linked to the one it joined (or the scene).
            _ = try BookRelinker.retarget(book: folder, from: id, to: survivor)
            if gone.count > 1 { _ = try BookRelinker.retarget(book: folder, from: gone[1], to: scene) }
            for old in gone { try editor.setSubsectionTitle(old, of: scene, to: "") }
            return scene
        }
    }

    // MARK: Telling the model who "I" is

    /// The narrators of a scene (by name), and when it is divided the parts with their own: a subsection that has narrators of its own is read with them, else with the scene's.
    func narration(of scene: String) -> (narrators: [String], parts: [CollectPart]) {
        func names(of key: String) -> [String] { characters.narrators(of: key).compactMap(\.name).filter { !$0.isEmpty } }
        let sceneNarrators = names(of: scene)
        guard let doc = session.document(scene), session.structure.subsections[scene] != nil else { return (sceneNarrators, []) }
        let subs = subsections(of: scene)
        guard !subs.isEmpty else { return (sceneNarrators, []) }
        // Where each subsection begins in the open text (after its marker's line), and where the text ends.
        var starts: [String: Int] = [:]
        doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: doc.storage.length)) { value, range, _ in if let v = value as? String { starts[v] = range.location } }
        var parts: [CollectPart] = []
        for (i, sub) in subs.enumerated() {
            let begin = sub.isMarked ? (starts[sub.id] ?? 0) : 0
            let end = subs.indices.contains(i + 1) ? (starts[subs[i + 1].id] ?? doc.storage.length) : doc.storage.length
            let own = sub.isMarked ? names(of: sub.id) : []
            parts.append(CollectPart(start: begin, end: end, narrators: own.isEmpty ? sceneNarrators : own))
        }
        return (sceneNarrators, parts)
    }

    /// The subsection the text cursor is in now (nil when its scene is not divided, or there is no cursor).
    func subsectionAtCursor() -> Subsection? {
        guard let area = controllers.first(where: { $0.currentSceneID != nil }), let id = area.currentSceneID, let tv = area.currentSheet?.textView else { return nil }
        return subsection(inScene: id, at: tv.selectedRange().location)
    }
}
