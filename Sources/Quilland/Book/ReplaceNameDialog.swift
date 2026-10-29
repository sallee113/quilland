import AppKit
import QuillandCore

/// "Replace a Name…" in the Suggestions tab: a name the model made up («Герой» for the narrator) is replaced by the card it really is, in this finding or in all of them.
/// The names are those of the finding; the cards offered are of the kind the name can be (characters, places, or both for a change or a fact).
final class ReplaceNameDialog: NSObject {
    struct Result { var slot: NameSlot; var card: String; var inAll: Bool }

    private let slots: [NameSlot]
    private let characters: [String]
    private let places: [String]
    private let namePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cardPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let allBox = NSButton(checkboxWithTitle: L("In all suggestions"), target: nil, action: nil)

    init(slots: [NameSlot], characters: [String], places: [String]) {
        self.slots = slots; self.characters = characters; self.places = places
        super.init()
    }

    /// How a name is shown in the first pop-up: with what it stands for.
    static func label(_ slot: NameSlot) -> String {
        switch slot.role {
        case .character: return L("character “{name}”", ["name": slot.name])
        case .place: return L("place “{name}”", ["name": slot.name])
        case .either: return "“" + slot.name + "”"
        }
    }

    /// The cards a name of this kind can be replaced with: names, in groups with a heading when there are two kinds.
    static func cardEntries(for role: NameRole, characters: [String], places: [String]) -> [(title: String, value: Any?, heading: Bool)] {
        func entries(_ names: [String], _ heading: String?) -> [(title: String, value: Any?, heading: Bool)] {
            let titles = PopupTitles.distinct(names)
            return (heading.map { [($0, nil, true)] } ?? []) + zip(titles, names).map { ($0, $1, false) }
        }
        switch role {
        case .character: return entries(characters, nil)
        case .place: return entries(places, nil)
        case .either: return entries(characters, L("Characters")) + entries(places, L("Places"))
        }
    }

    @objc private func nameChosen() { fillCards() }

    private func fillCards() {
        cardPopup.removeAllItems()
        let role = slots[max(0, namePopup.indexOfSelectedItem)].role
        for entry in Self.cardEntries(for: role, characters: characters, places: places) {
            if entry.heading {
                let header = NSMenuItem(title: entry.title, action: nil, keyEquivalent: ""); header.isEnabled = false
                cardPopup.menu?.addItem(header)
            } else {
                cardPopup.addChoice(entry.title, value: entry.value)
            }
        }
        if let first = cardPopup.itemArray.firstIndex(where: { $0.isEnabled }) { cardPopup.selectItem(at: first) }
    }

    /// Asks. Nil when the author cancels, or there is nothing to choose.
    func run() -> Result? {
        guard !slots.isEmpty else { return nil }
        let alert = NSAlert()
        alert.messageText = L("Replace a Name")
        alert.informativeText = L("Choose the name that is wrong and the card it really is. The suggestions change; the cards do not.")
        for s in slots { namePopup.addChoice(Self.label(s), value: nil) }
        namePopup.target = self; namePopup.action = #selector(nameChosen)
        fillCards()
        allBox.state = .on
        let captionName = NSTextField(labelWithString: L("Replace")), captionCard = NSTextField(labelWithString: L("with"))
        for c in [captionName, captionCard] { c.font = .systemFont(ofSize: 11); c.textColor = .secondaryLabelColor }
        let stack = NSStackView(views: [captionName, namePopup, captionCard, cardPopup, allBox])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        namePopup.setFrameSize(NSSize(width: 340, height: 26)); cardPopup.setFrameSize(NSSize(width: 340, height: 26))
        stack.frame = NSRect(x: 0, y: 0, width: 340, height: 130)
        stack.setFrameSize(stack.fittingSize)
        alert.accessoryView = stack
        alert.addButton(withTitle: L("Replace"))
        alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, let card = cardPopup.chosenValue as? String, slots.indices.contains(namePopup.indexOfSelectedItem) else { return nil }
        return Result(slot: slots[namePopup.indexOfSelectedItem], card: card, inAll: allBox.state == .on)
    }
}
