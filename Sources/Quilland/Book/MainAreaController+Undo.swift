import AppKit
import QuillandCore

/// Undo and Redo of the structure: the book is put back as it was from the snapshots `restructure` took.
extension MainAreaController {
    /// Puts the book back as it was before the last structural change (⌘Z in the tree or the Outline, or the banner's button).
    /// Anything written since is taken back too, so that is asked first; a safety snapshot is taken either way.
    func undoStructure(confirm: Bool = true) {
        // "Change removed. Undo": for a moment the banner's Undo puts the removed change back (it is not a structural change).
        if let pending = effectUndo, pending.until > Date() { effectUndo = nil; pending.run(); banner.close(); return }
        effectUndo = nil
        guard let entry = undoStack.last else { return }
        saveAll()
        let snapshots = SnapshotStore(bookFolder: folder)
        if confirm, let post = entry.post, snapshots.changed(since: post) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Undo “{name}”?", ["name": entry.name])
            alert.informativeText = L("The book has changed since then (text written, or other changes). Undo takes the whole book back to how it was before “{name}”. A snapshot of the book as it is now is taken first, so nothing is lost.", ["name": entry.name])
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Undo"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let before: SnapshotStore.Info
        do { before = try snapshots.restoreAll(from: entry.pre) } catch { report(error); return }
        undoStack.removeLast()
        redoStack.append(StructureUndo(name: entry.name, pre: entry.pre, post: before))
        reloadFromDisk()
        banner.show(L("Undone: {name}.", ["name": entry.name]), undoable: false, redo: true)
    }

    /// Does again what Undo took back (⇧⌘Z in the tree or the Outline, or the banner's button): the book as it was just before the undo is put back.
    /// What was written since the undo is taken too, so that is asked first; a safety snapshot is taken either way.
    func redoStructure(confirm: Bool = true) {
        guard let entry = redoStack.last, let target = entry.post else { return }
        saveAll()
        let snapshots = SnapshotStore(bookFolder: folder)
        if confirm, snapshots.changed(since: entry.pre) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Redo “{name}”?", ["name": entry.name])
            alert.informativeText = L("The book has changed since the undo. Redo takes the whole book back to how it was before the undo. A snapshot of the book as it is now is taken first, so nothing is lost.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Redo"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        do { _ = try snapshots.restoreAll(from: target) } catch { report(error); return }
        redoStack.removeLast()
        undoStack.append(StructureUndo(name: entry.name, pre: entry.pre, post: target))
        reloadFromDisk()
        banner.show(L("Redone: {name}.", ["name": entry.name]), undoable: true)
    }

    /// Reads everything again from the files (after something was put back from a snapshot).
    /// The data files were changed under the stores (a merge, an undo, a restore): each store reads its files again.
    func reloadStores() {
        characters.reload()
        relationships.reload()
        worlds.reload()
        eventStore.reload()
        researchStore.reload()
        remindersStore.reload()
        NotificationCenter.default.post(name: .bookDataChanged, object: nil)
    }

    func reloadFromDisk() {
        reloadStores()
        guard let structure = try? BookStructure.load(folder: folder) else { return }
        session = BookSession(structure: structure)
        pendingTreeSelection = nil
        focusTextAfterRebuild = !(tree?.isFirstResponder ?? false)
        rebuild()
    }
}
