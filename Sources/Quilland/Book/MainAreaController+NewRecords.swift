import AppKit
import QuillandCore

/// Making a character or a place from a name found in the text, and teaching a card one more name.
extension MainAreaController {
    /// What a selection must be to be taken for a name: a few words on one line, with a letter in them.
    static func nameFromSelection(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !name.isEmpty, name.count <= 60, !name.contains("\n"), name.split(separator: " ").count <= 4,
              name.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        return name
    }

    /// A character with this name, linked to the scene (with an empty line), and shown in the Right panel. Returns its id.
    @discardableResult
    func makeCharacter(named raw: String, linkedTo scene: String?) -> String? {
        guard let name = Self.nameFromSelection(raw), let id = try? characters.add(name: name) else { return nil }
        if let scene { try? characters.update(id) { var l = $0.links; l[scene] = ""; $0.links = l } }
        showInRightPanel { $0.selectCharacter(id) }
        return id
    }

    /// A place with this name, in the book's first world, linked to the scene, and shown in the Right panel. Returns its id.
    @discardableResult
    func makePlace(named raw: String, linkedTo scene: String?) -> String? {
        guard let name = Self.nameFromSelection(raw), let world = worlds.worlds.first?.id, let id = try? worlds.addEntry(name: name, world: world) else { return nil }
        if let scene { try? worlds.updateEntry(id) { var l = $0.links; l[scene] = ""; $0.links = l } }
        showInRightPanel { $0.selectPlace(id) }
        return id
    }

    /// One more name for a character (a nickname, another form of the name): the text matching knows it from now on.
    func addName(_ raw: String, toCharacter id: String) {
        guard let name = Self.nameFromSelection(raw), let c = characters.character(id), !c.aliases.contains(name), c.name != name else { return }
        try? characters.update(id) { $0.aliases = $0.aliases + [name] }
        showInRightPanel { $0.selectCharacter(id) }
    }

    func addName(_ raw: String, toPlace id: String) {
        guard let name = Self.nameFromSelection(raw), let p = worlds.entry(id), !p.aliases.contains(name), p.name != name else { return }
        try? worlds.updateEntry(id) { $0.aliases = $0.aliases + [name] }
        showInRightPanel { $0.selectPlace(id) }
    }

    private func showInRightPanel(_ select: (RightPanelController) -> Void) {
        if !showsRightPanel { setRightPanel(true) }
        rightPanel.refresh()
        select(rightPanel)
        onChange?()
    }
}
