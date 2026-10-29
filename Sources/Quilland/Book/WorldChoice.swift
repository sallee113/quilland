import AppKit
import QuillandCore

/// The world a new place goes to when nothing says which: the book's only one, one made when there is none, or the author's choice when there are several.
enum WorldChoice {
    static func pick(in store: WorldStore, asking: Bool = true) -> String? {
        let worlds = store.worlds
        if worlds.count == 1 { return worlds[0].id }
        if worlds.isEmpty { return try? store.addWorld(name: L("World")) }
        guard asking else { return nil }
        let alert = NSAlert()
        alert.messageText = L("Which world are the places in?")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        popup.addChoices(worlds.map { (title: $0.name ?? "", value: $0.id) })
        alert.accessoryView = popup
        alert.addButton(withTitle: L("Use This World"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return popup.selectedItem?.representedObject as? String
    }
}
