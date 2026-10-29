import AppKit
import QuillandCore

/// "Narrator ▾" in the settings of a scene: a menu of the characters, ticked for those whose point of view the scene is. It is the same data as the point of view on the
/// character's card, seen from the scene.
final class NarratorButton: NSPopUpButton {
    var characters: () -> [(id: String, name: String)] = { [] }
    var narrators: (String) -> Set<String> = { _ in [] }
    /// The scene, the character and whether the character is now a narrator of it.
    var onToggle: ((String, String, Bool) -> Void)?
    private(set) var scene: String?

    init() {
        super.init(frame: .zero, pullsDown: true)
        controlSize = .small
        bezelStyle = .rounded
        setAccessibilityLabel(L("Narrator"))
        toolTip = L("Who tells this scene (its point of view). In the first person, the “I” of the text is this character; Collect uses it.")
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Reads the characters and their points of view from the store, and writes a tick back to it; `changed` tells the owner (the cards show it too).
    func connect(to store: CharacterStore, changed: @escaping () -> Void) {
        characters = { [weak store] in (store?.characters ?? []).compactMap { c in c.id.map { ($0, c.name ?? "") } } }
        narrators = { [weak store] scene in Set((store?.narrators(of: scene) ?? []).compactMap(\.id)) }
        onToggle = { [weak store] scene, id, on in
            try? store?.setNarrator(on, of: scene, character: id)
            changed()
        }
    }

    func show(scene: String?) { self.scene = scene; rebuild() }

    func rebuild() {
        removeAllItems()
        let people = characters()
        let chosen = scene.map(narrators) ?? []
        let names = people.filter { chosen.contains($0.id) }.map(\.name)
        addItem(withTitle: names.isEmpty ? L("None") : names.joined(separator: ", "))
        for (title, person) in zip(PopupTitles.distinct(people.map(\.name)), people) {
            let on = chosen.contains(person.id)
            let item = ClosureMenuItem(title: title) { [weak self] in
                guard let self, let scene = self.scene else { return }
                self.onToggle?(scene, person.id, !on)
                self.rebuild()
            }
            item.state = on ? .on : .off
            menu?.addItem(item)
        }
        isEnabled = scene != nil && !people.isEmpty
    }

    /// For the checks: the names ticked, and the title shown.
    var tickedTitles: [String] { (menu?.items.dropFirst() ?? []).filter { $0.state == .on }.map(\.title) }
}
