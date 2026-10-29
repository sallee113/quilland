import AppKit
import QuillandCore

/// Merging two places or two worlds, and turning a place into a world or a world into a place: the dialogs that ask which, and the hand-over to the owner of the book.
extension WorldViewController {
    @objc func mergePressed() { mergeSelected() }
    @objc func convertPressed() { convertSelected() }

    /// A dialog with a list to choose from (Cancel is the default); the id of the chosen one, or nil.
    private func choose(message: String, info: String, button: String, options: [(title: String, id: String)]) -> String? {
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 26), pullsDown: false)
        popup.addChoices(options.map { (title: $0.title, value: $0.id) })
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = info
        alert.accessoryView = popup
        let cancel = alert.addButton(withTitle: L("Cancel"))
        cancel.keyEquivalent = "\r"
        let go = alert.addButton(withTitle: button)
        go.keyEquivalent = ""
        go.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return nil }
        return popup.selectedItem?.representedObject as? String
    }

    func mergeSelected() {
        guard let id = selected else { return }
        commitEdits()
        if let world = store.world(id) {
            let others = store.worlds.filter { $0.id != id }.map { (title: $0.name ?? "", id: $0.id ?? "") }
            guard !others.isEmpty else { return }
            let name = world.name ?? ""
            if let target = choose(message: L("Merge “{name}” into…", ["name": name]),
                                   info: L("Choose the world to keep. “{name}” is taken out of the book: its name and aliases become aliases of the kept world, and all its places move to the top of the kept world. The card goes to the book's trash folder (.quilland/trash). You can undo this.", ["name": name]),
                                   button: L("Merge"), options: others) { onMergeWorld?(id, target) }
        } else if let entry = store.entry(id) {
            let inside = Set(store.descendants(of: id).compactMap(\.id))
            let others = store.entries.filter { $0.id != id && !inside.contains($0.id ?? "") }
                .map { (title: store.path(of: $0.id ?? "").joined(separator: " › "), id: $0.id ?? "") }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            guard !others.isEmpty else { return }
            let name = entry.name ?? ""
            if let target = choose(message: L("Merge “{name}” into…", ["name": name]),
                                   info: L("Choose the place to keep. “{name}” is taken out of the book: its name and aliases become aliases of the kept place, its description, notes and scenes are added to theirs, and what is inside it moves into the kept place. The card goes to the book's trash folder (.quilland/trash). You can undo this.", ["name": name]),
                                   button: L("Merge"), options: others) { onMergePlace?(id, target) }
        }
    }

    func convertSelected() {
        guard let id = selected else { return }
        commitEdits()
        if let world = store.world(id) {
            // Where it goes: another world (at the top) or a place in one.
            var options: [(title: String, id: String)] = []
            for other in store.worlds where other.id != id {
                guard let wid = other.id else { continue }
                options.append((other.name ?? "", "w:" + wid))
                for e in store.entries.filter({ $0.world == wid }).sorted(by: { store.path(of: $0.id ?? "").joined().localizedCaseInsensitiveCompare(store.path(of: $1.id ?? "").joined()) == .orderedAscending }) {
                    options.append((store.path(of: e.id ?? "").joined(separator: " › "), "e:" + (e.id ?? "")))
                }
            }
            guard !options.isEmpty else { return }
            let name = world.name ?? ""
            guard let pick = choose(message: L("Turn “{name}” into a place?", ["name": name]),
                                    info: L("Choose where the place goes. The world becomes a place there, and its places are inside it. You can undo this."),
                                    button: L("Turn Into a Place"), options: options) else { return }
            if pick.hasPrefix("w:") { onWorldToPlace?(id, String(pick.dropFirst(2)), nil) }
            else if let entry = store.entry(String(pick.dropFirst(2))), let target = entry.world { onWorldToPlace?(id, target, entry.id) }
        } else if let entry = store.entry(id) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Turn “{name}” into a world?", ["name": entry.name ?? ""])
            alert.informativeText = L("The place becomes a world of its own, and the places inside it are at the top of that world. Its description, notes, scenes and the links to it go with it. You can undo this.")
            let cancel = alert.addButton(withTitle: L("Cancel"))
            cancel.keyEquivalent = "\r"
            let go = alert.addButton(withTitle: L("Turn Into a World"))
            go.keyEquivalent = ""
            go.hasDestructiveAction = true
            guard alert.runModal() == .alertSecondButtonReturn else { return }
            onPlaceToWorld?(id)
        }
    }
}
