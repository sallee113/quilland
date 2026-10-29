import AppKit
import QuillandCore

/// Two cards with one name: a pop-up built from the book's data keeps both and answers with the one chosen (not the one at that place in a shorter list), and a name in a
/// finding stands for the card that was made first.
extension AppSelfTest {
    func sameNames() -> Int32? {
        let main = self.main!
        // The pop-up: every entry stays, they are told apart, and each answers with its own value.
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addChoices([("Анна", "a1"), ("Лилит", "l1"), ("Лилит", "l2"), ("Сэм", "s1"), ("Лилит", "l3")])
        check(popup.numberOfItems == 5 && popup.itemTitles == ["Анна", "Лилит", "Лилит (2)", "Сэм", "Лилит (3)"], "a pop-up of names keeps every entry and tells the same names apart", "\(popup.itemTitles)")
        var answers: [String] = []
        for i in 0..<popup.numberOfItems { popup.selectItem(at: i); answers.append(popup.chosenValue as? String ?? "?") }
        check(answers == ["a1", "l1", "l2", "s1", "l3"], "and each entry answers with the card it stands for, not the one at that place in a shorter list", "\(answers)")
        check(PopupTitles.distinct(["x", "y"]) == ["x", "y"], "titles that are different stay as they are")

        // A name in a finding goes to the card made first.
        let first = try! main.characters.add(name: "Двойник-Лилит")
        let second = try! main.characters.add(name: "Двойник-Лилит")
        let place1 = try! main.worlds.addEntry(name: "Двойник-Двор", world: main.worlds.worlds[0].id!)
        let place2 = try! main.worlds.addEntry(name: "Двойник-Двор", world: main.worlds.worlds[0].id!)
        main.reloadStores()
        let tables = main.collect.nameTables()
        check(tables.characters[Names.normalize("Двойник-Лилит")] == first && tables.places[Names.normalize("Двойник-Двор")] == place1, "a name two cards have stands for the one made first", "\(String(describing: tables.characters[Names.normalize("Двойник-Лилит")])) \(first) \(second) \(place2)")
        check(CardAges.oldestFirst([second, first], book: main.folder) == [first, second], "the cards are put in the order they were made, whatever the list order")
        try? BookIntegrity.deleteCharacter(first, book: main.folder, snapshot: false)
        try? BookIntegrity.deleteCharacter(second, book: main.folder, snapshot: false)
        for id in [place1, place2] { try? BookIntegrity.deletePlace(id, book: main.folder, snapshot: false) }
        main.reloadStores()
        return nil
    }
}
