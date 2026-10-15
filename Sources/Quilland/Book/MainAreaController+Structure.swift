import AppKit
import QuillandCore

/// Changing the structure: add, move, rename, delete, split, merge, group, import. Every change that touches files goes through `restructure`, which takes a snapshot before and
/// after (so that Undo works), reloads the stores and rebuilds the views.
extension MainAreaController {
    func treeCommand(_ command: StructureTreeController.Command, _ id: String) {
        switch command {
        case .newSceneAfter: add(.scene, place: .after, anchor: id, fromTree: true)
        case .newSceneBefore: add(.scene, place: .before, anchor: id, fromTree: true)
        case .newChapter: add(.chapter, place: .after, anchor: id, fromTree: true)
        case .newPart: add(.part, place: .after, anchor: id, fromTree: true)
        case .moveUp: move(id, by: -1)
        case .moveDown: move(id, by: 1)
        case .delete: delete(id)
        case .status(let s): setStatus(id, to: s)
        case .mergeNext: merge(id, direction: 1)
        case .mergePrevious: merge(id, direction: -1)
        case .group: groupIntoPart()
        case .ungroup: ungroupPart(id)
        }
    }

    func add(_ kind: BookStructure.Kind, place: BookEditor.Place = .after, anchor: String? = nil, fromTree: Bool = false) {
        let inTree = fromTree || treeHasFocus
        restructure(focusText: !inTree, beginRename: inTree, undoName: L("New {kind}", ["kind": L(kind.rawValue.capitalized)])) { editor in
            try editor.add(kind, relativeTo: anchor ?? self.selectedSectionID, place: place)
        }
    }

    func move(_ id: String? = nil, by step: Int) {
        guard let id = id ?? selectedSectionID else { return }
        restructure(focusText: !treeHasFocus, undoName: L("Move")) { editor in
            try editor.moveAcrossChapters(id, by: step)
            return id
        }
    }

    func setStatus(_ id: String? = nil, to status: String) {
        guard let id = id ?? selectedSectionID, session.structure.scenes.contains(where: { $0.id == id }) else { return }
        do { try BookEditor(structure: session.structure).setStatus(id, to: status) } catch { report(error); return }
        session.applyInfo(id: id, status: status)
        afterInfoChange()
    }

    func rename(_ id: String, to title: String) {
        do { try BookEditor(structure: session.structure).rename(id, to: title) } catch { report(error); return }
        session.applyInfo(id: id, title: title)
        afterInfoChange()
    }

    private func afterInfoChange() {
        tree?.reload(structure: session.structure, characters: { [weak self] in self?.sectionCharacters($0) ?? 0 })
        outlineDetail?.refresh()
        controllers.forEach { $0.updateJumpBar() }
        onChange?()
    }

    /// Opens the section's first scene in the writing mode.
    func openInEditor(_ id: String) {
        guard let scene = firstScene(of: id, in: session.structure) else { return }
        pendingCursor = (scene, 0)
        if mode == .outline { setMode(writingMode) }
    }

    /// Rows were dropped in the Outline: they go before the sibling that was at the drop place (or to the end), in book order.
    func moveSections(_ ids: [String], parent: String?, index: Int?) {
        let siblings = parent.flatMap { findNode($0)?.children } ?? (parent == nil ? session.structure.roots : [])
        let anchor = index.flatMap { i in siblings.dropFirst(i).first { !ids.contains($0.id) }?.id }
        restructure(focusText: false, undoName: "Move") { [folder] _ in
            for id in ids {
                let fresh = try BookStructure.load(folder: folder)
                func find(_ target: String, in nodes: [BookStructure.Node]) -> BookStructure.Node? {
                    for n in nodes { if n.id == target { return n }; if let f = find(target, in: n.children) { return f } }
                    return nil
                }
                let list = parent.flatMap { find($0, in: fresh.roots)?.children } ?? fresh.roots
                let at = anchor.flatMap { a in list.firstIndex { $0.id == a } } ?? list.count
                try BookEditor(structure: fresh).move(id, toParent: parent, at: at)
            }
            return ids.first
        }
    }

    /// Rename from the menu: the tree edits in place; elsewhere a small window asks.
    func renameSelected() {
        guard let id = selectedSectionID else { return }
        if mode == .panels || mode == .outline, let tree { tree.focus(); tree.beginRename(); return }
        guard let node = findNode(id) else { return }
        let field = NSTextField(string: node.title)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = L("Rename")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Rename"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { rename(id, to: title) }
    }

    func findNode(_ id: String) -> BookStructure.Node? {
        func search(_ nodes: [BookStructure.Node]) -> BookStructure.Node? {
            for n in nodes { if n.id == id { return n }; if let f = search(n.children) { return f } }
            return nil
        }
        return search(session.structure.roots)
    }

    /// Asks, then takes the section out of the book (into `.quilland/trash`). Cancel is the default.
    func delete(_ id: String? = nil, confirm: Bool = true) {
        guard let id = id ?? selectedSectionID, let node = findNode(id) else { return }
        let editor = BookEditor(structure: session.structure)
        let weight = editor.weight(of: id) { [session] in session.document($0)?.counts.characters ?? 0 }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            switch node.kind {
            case .scene: alert.messageText = L("Delete the scene “{title}”?", ["title": node.title])
            case .chapter: alert.messageText = L("Delete the chapter “{title}”?", ["title": node.title])
            case .part: alert.messageText = L("Delete the part “{title}”?", ["title": node.title])
            }
            let number = { (n: Int) in NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal) }
            alert.informativeText = node.kind == .scene
                ? L("The scene has {size}. Its files go to the book's trash folder (.quilland/trash).", ["size": Lp("{n} character||text", "{n} characters||text", weight.characters)])
                : L("It holds {scenes} with {size} in all. Their files go to the book's trash folder (.quilland/trash).", ["scenes": Lp("{n} scene", "{n} scenes", weight.scenes), "size": Lp("{n} character||text", "{n} characters||text", weight.characters)])
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let remove = alert.addButton(withTitle: L("Delete"))
            remove.keyEquivalent = ""
            remove.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        // The cursor goes to the scene before the deleted one's place, or the next.
        let scenes = session.structure.scenes.map(\.id)
        var inside = Set<String>()
        func collect(_ n: BookStructure.Node) { if n.kind == .scene { inside.insert(n.id) }; n.children.forEach(collect) }
        collect(node)
        let first = scenes.firstIndex { inside.contains($0) } ?? 0
        let after = scenes.first { !inside.contains($0) && (scenes.firstIndex(of: $0) ?? 0) > first }
        let before = first > 0 ? scenes[first - 1] : nil
        let keep = inside.contains(currentSceneID ?? "") ? (before ?? after) : currentSceneID
        restructure(focusText: !treeHasFocus, cursorScene: keep, undoName: L("Delete “{title}”", ["title": node.title])) { editor in
            try editor.delete(id)
            return nil
        }
    }

    /// Does a structural change, then reads the book again: the files were renumbered, so every scene is loaded anew.
    func restructure(focusText: Bool, beginRename: Bool = false, cursorScene: String? = nil, undoName: String = L("Change"), _ change: (BookEditor) throws -> String?) {
        saveAll()
        remember()
        // A change that touches files takes a snapshot first, and another after it, so that Undo can tell whether the book moved on since.
        let snapshots = SnapshotStore(bookFolder: folder)
        let pre = try? snapshots.take(.beforeOperation, reason: L("Before {action}", ["action": undoName]))
        let editor = BookEditor(structure: session.structure)
        let selectedID: String?
        do { selectedID = try change(editor) } catch { report(error); return }
        if let pre {
            let post = try? snapshots.take(.automatic, reason: L("After {action}", ["action": undoName]))
            undoStack.append(StructureUndo(name: undoName, pre: pre, post: post))
            redoStack.removeAll()
            if undoStack.count > 20 { undoStack.removeFirst() }
            banner.show(L("{action}.", ["action": undoName]), undoable: true)
        }
        // Merging moves links in the data files: the stores read them again.
        reloadStores()
        guard let structure = try? BookStructure.load(folder: folder) else { return }
        session = BookSession(structure: structure)
        // Where the cursor goes: the scene of the new or moved section (a chapter's or a part's first scene), otherwise where it was.
        if let cursorScene { pendingCursor = (cursorScene, 0) }
        else if mode != .outline, let id = selectedID, let scene = firstScene(of: id, in: structure) {
            pendingCursor = scene == pendingCursor?.scene ? pendingCursor : (scene, 0)
        }
        pendingTreeSelection = selectedID
        focusTextAfterRebuild = focusText
        rebuild()
        if beginRename { tree?.beginRename() }
    }

    /// Adds an imported text at the end of the book: a snapshot first, a banner offering Undo after.
    @discardableResult
    func performImport(_ plan: ImportPlan) -> Bool {
        var done = false
        restructure(focusText: true, undoName: "Import") { [folder] _ in
            let written = try TextImporter.write(plan, into: folder)
            done = true
            return written.firstSceneID
        }
        if done { banner.show(Lp("Imported {n} scene at the end of the book.", "Imported {n} scenes at the end of the book.", plan.sceneCount), undoable: true) }
        return done
    }

    /// Where a scene would be cut with the cursor at `caret`: at the start of a paragraph, that paragraph begins the new scene; anywhere else in it, the new
    /// scene begins after it. Nil when there is no text on one side of the cut.
    static func splitCut(in text: NSString, caret: Int) -> Int? {
        let place = min(max(0, caret), text.length)
        let paragraph = text.paragraphRange(for: NSRange(location: place, length: 0))
        let cut = place == paragraph.location ? paragraph.location : NSMaxRange(paragraph)
        let rest = cut < text.length ? text.substring(from: cut).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard cut > 0, !rest.isEmpty, !text.substring(to: cut).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return cut
    }

    /// ⌥⌘↩: the scene is cut between two paragraphs; everything after the cut becomes a new scene next to it.
    func splitSceneHere() {
        guard let area = controllers.first(where: { $0.currentSceneID != nil }), let id = area.currentSceneID, let doc = session.document(id), let tv = area.currentSheet?.textView,
              let entry = session.structure.scenes.first(where: { $0.id == id }) else { return }
        let text = doc.storage.string as NSString
        guard let cut = Self.splitCut(in: text, caret: tv.selectedRange().location) else {
            let alert = NSAlert()
            alert.messageText = L("Put the cursor between two paragraphs")
            alert.informativeText = L("A scene is split where there is text on both sides of the cut.")
            alert.runModal()
            return
        }
        let moved = NSMutableAttributedString(attributedString: doc.storage.attributedSubstring(from: NSRange(location: cut, length: text.length - cut)))
        // A fragment that goes on across the cut is divided: the second half gets a new id.
        var divided = false
        var lastBefore = false
        doc.storage.enumerateAttribute(.quillandFragment, in: NSRange(location: 0, length: cut)) { v, _, _ in if v != nil { lastBefore = true } }
        let startsWithMarker = moved.length > 0 && moved.attribute(.quillandFragment, at: 0, effectiveRange: nil) != nil
        if lastBefore && !startsWithMarker {
            var attrs = Styler.attributes(kind: BlockKind.fragment)
            attrs[.quillandFragment] = UUID().uuidString.lowercased()
            let marker = NSMutableAttributedString(string: AttributedBridge.object, attributes: attrs)
            marker.append(NSAttributedString(string: "\n", attributes: Styler.attributes(kind: BlockKind.fragment)))
            moved.insert(marker, at: 0)
            divided = true
        }
        let movedMarkdown = MarkdownWriter.write(AttributedBridge.document(from: moved))
        let title = entry.node.title + " 2"
        let status = doc.status ?? "idea"
        restructure(focusText: true, undoName: L("Split scene")) { [folder] editor in
            // The old scene is cut and saved before any renumbering, while its file still has its name.
            doc.storage.deleteCharacters(in: NSRange(location: cut, length: text.length - cut))
            doc.textDidChange()
            doc.updateCounts()
            _ = doc.saveNow()
            let newID = try editor.add(.scene, relativeTo: id, place: .after, title: title)
            let fresh = try BookStructure.load(folder: folder)
            try BookEditor(structure: fresh).setStatus(newID, to: status)
            guard let made = fresh.scenes.first(where: { $0.id == newID }) else { throw BookEditor.Failure(description: L("The new scene was not found.")) }
            try AtomicFile.write(Data(movedMarkdown.utf8), to: fresh.markdownURL(for: made.node))
            return newID
        }
        if divided { banner.show(L("Scene split. A fragment was divided: its links stay with the first half."), undoable: true) }
    }

    /// Merges a scene with the one after it (`direction` 1) or before it (-1). The first of the two survives.
    func merge(_ id: String? = nil, direction: Int, confirm: Bool = true) {
        guard let id = id ?? selectedSectionID else { return }
        // The scenes of its own chapter only: the neighbours in the same list.
        let ids = siblingScenes(of: id)
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + direction) else {
            banner.show(direction > 0 ? L("There is no scene after this one in the chapter.") : L("There is no scene before this one in the chapter."), undoable: false)
            return
        }
        let first = direction > 0 ? id : ids[i + direction]
        let second = direction > 0 ? ids[i + direction] : id
        mergeScenes(first: first, others: [second], confirm: confirm)
    }

    /// Outline: the chosen scenes (which must follow one another) are merged into the first.
    func mergeSelected(confirm: Bool = true) {
        let chosen = Set(tree?.selectedIDs ?? [])
        let picked = session.structure.scenes.map(\.id).filter { chosen.contains($0) }
        let ids = picked.first.map { siblingScenes(of: $0) } ?? []
        guard picked.count >= 2, let start = ids.firstIndex(of: picked[0]), start + picked.count <= ids.count, Array(ids[start..<(start + picked.count)]) == picked else {
            banner.show(L("Choose two or more scenes that follow one another in one chapter."), undoable: false)
            return
        }
        mergeScenes(first: picked[0], others: Array(picked.dropFirst()), confirm: confirm)
    }

    private func mergeScenes(first: String, others: [String], confirm: Bool) {
        if confirm {
            let name = { (id: String) in self.findNode(id)?.title ?? "" }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = others.count == 1 ? L("Merge “{second}” into “{first}”?", ["second": name(others[0]), "first": name(first)]) : L("Merge the chosen scenes into “{first}”?", ["first": name(first)])
            alert.informativeText = L("The text, synopsis, note and tags of the other scene are added after those of the first, the links to it point at the first, and the other scene goes to the book's trash folder (.quilland/trash). You can undo this.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Merge"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        restructure(focusText: !treeHasFocus, cursorScene: first, undoName: L("Merge scenes")) { [folder] _ in
            for other in others {
                let fresh = try BookStructure.load(folder: folder)
                try BookEditor(structure: fresh).merge(first, with: other)
            }
            return first
        }
    }

    /// Group into a New Part…: the chosen chapters (not yet in a part) move into a new part.
    func groupIntoPart() {
        let chosen = (mode == .outline ? tree?.selectedIDs : nil) ?? [selectedSectionID].compactMap { $0 }
        let loose = Set(session.structure.roots.filter { $0.kind == .chapter }.map(\.id))
        guard !chosen.isEmpty, chosen.allSatisfy({ loose.contains($0) }) else {
            banner.show(L("Choose one or more chapters that are not in a part."), undoable: false)
            return
        }
        let field = NSTextField(string: BookEditor(structure: session.structure).language == "ru" ? "Новая часть" : "New Part")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        let alert = NSAlert()
        alert.messageText = L("Group into a new part")
        alert.informativeText = L("The title of the part:")
        alert.accessoryView = field
        alert.addButton(withTitle: L("Group"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        groupChapters(chosen, titled: title)
    }

    func groupChapters(_ ids: [String], titled title: String) {
        restructure(focusText: !treeHasFocus, undoName: L("Group into a part")) { editor in try editor.group(ids, intoNewPart: title) }
    }

    /// Ungroup Part…: its chapters move up to where it was; the part's own title and text go to the trash folder. Asks first.
    func ungroupPart(_ id: String? = nil, confirm: Bool = true) {
        guard let id = id ?? selectedSectionID, let part = findNode(id), part.kind == .part else {
            banner.show(L("Choose a part."), undoable: false)
            return
        }
        if confirm {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Ungroup the part “{title}”?", ["title": part.title])
            alert.informativeText = L("{chapters} move up to where the part was. The part's own title, text, synopsis and note go to the book's trash folder (.quilland/trash).", ["chapters": Lp("Its {n} chapter", "Its {n} chapters", part.children.count)])
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Ungroup"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        restructure(focusText: !treeHasFocus, cursorScene: currentSceneID, undoName: L("Ungroup “{title}”", ["title": part.title])) { editor in
            try editor.ungroup(id)
            return nil
        }
    }

    func firstScene(of id: String, in structure: BookStructure) -> String? {
        if structure.scenes.contains(where: { $0.id == id }) { return id }
        return structure.scenes.first { $0.chapterID == id || $0.partID == id }?.id
    }

    func report(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("That could not be done")
        alert.informativeText = "\(error)"
        alert.runModal()
    }
}
