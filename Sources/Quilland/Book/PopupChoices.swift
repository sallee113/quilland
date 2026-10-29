import AppKit

/// Pop-up menus made from the book's own data (characters, places, events, sections…), where two entries can have the same name.
/// `NSPopUpButton.addItem(withTitle:)` takes out an earlier entry of the same title, so the entries are no longer the list they were made from: choosing by position then
/// gives another card than the one shown, and an earlier card of that name cannot be chosen at all. Here every entry is kept, carries what it stands for, and is read by it.
enum PopupTitles {
    /// The titles, with a number after the second and later of the same name: «Лилит», «Лилит (2)».
    static func distinct(_ titles: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return titles.map { title in
            let n = (seen[title] ?? 0) + 1
            seen[title] = n
            return n == 1 ? title : title + " (\(n))"
        }
    }
}

extension NSPopUpButton {
    /// Adds an entry that carries a value (an id, an index). An earlier entry of the same title stays.
    @discardableResult
    func addChoice(_ title: String, value: Any?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.representedObject = value
        menu?.addItem(item)
        return item
    }

    /// Adds entries made from the book's data; those of one name are told apart by a number.
    func addChoices(_ entries: [(title: String, value: Any?)]) {
        for (title, entry) in zip(PopupTitles.distinct(entries.map(\.title)), entries) { addChoice(title, value: entry.value) }
    }

    /// What the chosen entry stands for.
    var chosenValue: Any? { selectedItem?.representedObject }
}
