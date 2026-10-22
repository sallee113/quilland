import AppKit
import QuillandCore

/// The Outline: dragging what was not chosen, a right click that keeps the choice, and Move To… with several sections.
extension AppSelfTest {
    func outlineMoves() -> Int32? {
        let main = self.main!
        func fresh() -> BookEditor { BookEditor(structure: try! BookStructure.load(folder: main.folder)) }
        var ids: [String] = []
        let lastRoot = main.session.structure.roots.last!.id
        main.restructure(focusText: false, undoName: "T") { _ in
            var anchor = lastRoot
            for title in ["ТМП-К1", "ТМП-К2", "ТМП-К3"] { anchor = try fresh().add(.chapter, relativeTo: anchor, title: title); ids.append(anchor) }
            ids.append(try fresh().add(.part, relativeTo: anchor, title: "ТМП-Часть"))
            return nil
        }
        let (k1, k2, k3, part) = (ids[0], ids[1], ids[2], ids[3])
        main.setMode(.outline); spin(0.6)
        guard let tree = main.tree else { check(false, "the Outline shows"); return 1 }
        let scenes = main.session.structure.scenes.map(\.id)

        // Dragging a section that was not chosen: the drag is about the section picked up, in book order.
        tree.choose([k1])
        check(tree.orderedDraggedIDs([k2]) == [k2], "a section picked up with another one chosen is what is dragged")
        check(tree.orderedDraggedIDs([k3, k1, "nothing"]) == [k1, k3], "several are dragged in book order, and what is not a section is left out")

        // Where a drop lands: before or after the row it is over, or into a part.
        let rootIDs = main.session.structure.roots.map(\.id)
        let at1 = rootIDs.firstIndex(of: k1)!
        let before = tree.dropPlanForTests(ids: [k3], on: k1, lowerHalf: false), after = tree.dropPlanForTests(ids: [k3], on: k1, lowerHalf: true)
        check(before?.parent == nil && before?.at == at1, "dropped on the upper half of a chapter, it goes before it", "\(String(describing: before))")
        check(after?.parent == nil && after?.at == at1 + 1, "and on the lower half, after it", "\(String(describing: after))")
        let into = tree.dropPlanForTests(ids: [k3], on: part)
        check(into?.parent == part && into?.at == -1, "dropped on a part, it goes into it (the box round the part)", "\(String(describing: into))")
        check(tree.dropPlanForTests(ids: [k1], on: k1) == nil, "not onto itself")
        check(tree.dropPlanForTests(ids: [scenes[0]], on: part) == nil && tree.dropPlanForTests(ids: [k1], on: scenes[0]) == nil, "a scene cannot go into a part, a chapter not into a scene")
        check(tree.dropPlanForTests(ids: [part], on: k1)?.parent == nil && tree.dropPlanForTests(ids: [part], on: part) == nil, "a part goes among the parts and chapters of the book, and not into itself")
        check(tree.dropFeedbackStyle == .regular, "the drop is shown with a line, and a box round what it goes into")

        // A right click keeps a choice it falls on, and takes another row alone.
        tree.choose([k1, k2])
        tree.prepareContextSelection(clickedRow: tree.row(of: k2))
        check(Set(tree.selectedIDs) == [k1, k2], "a right click on a chosen row keeps all the chosen rows")
        tree.prepareContextSelection(clickedRow: tree.row(of: k3))
        check(tree.selectedIDs == [k3], "and on another row chooses that row alone")

        // The menu follows what is chosen.
        func state(_ title: String, _ menu: [(title: String, enabled: Bool)]) -> Bool? { menu.first { $0.title == title }?.enabled }
        tree.choose([k1, k2])
        var m = tree.contextMenuState
        check(state("Move To…", m) == true && state("Group into a New Part…", m) == true && state("Delete…", m) == true, "several chapters can be moved, grouped and deleted")
        check(state("Rename", m) == false && state("New Chapter", m) == false && state("Move Up", m) == false && state("Merge with Next Scene", m) == nil, "and not renamed, added to or moved a step")
        tree.choose([k3]); m = tree.contextMenuState
        check(state("Rename", m) == true && state("Move To…", m) == true && state("Move Up", m) == true, "one chapter has all of them")
        tree.choose([k1, scenes[0]]); m = tree.contextMenuState
        check(state("Move To…", m) == false && state("Group into a New Part…", m) == nil, "a chapter and a scene together cannot be moved or grouped")
        tree.choose([part]); m = tree.contextMenuState
        check(state("Move To…", m) == false, "a part cannot be moved into anything")
        tree.choose([scenes[0], scenes[1]]); m = tree.contextMenuState
        check(state("Move To…", m) == true && state("Merge the Chosen Scenes", m) != nil && state("Rename", m) == false, "several scenes: Move To…, merging, and no renaming")

        // Where chapters and scenes can go.
        let chapterTargets = main.moveTargets(for: [k1, k2]).map(\.title)
        check(chapterTargets.first == "The top level of the book" && chapterTargets.contains("ТМП-Часть"), "chapters can go to the top level or into a part", "\(chapterTargets)")
        let sceneTargets = main.moveTargets(for: [scenes[0]])
        check(!sceneTargets.isEmpty && sceneTargets.allSatisfy { $0.id != nil } && sceneTargets.contains { $0.title.contains("ТМП-К1") }, "scenes can go into any chapter, shown with their part", "\(sceneTargets.map(\.title))")
        check(main.moveTargets(for: [k1, scenes[0]]).isEmpty && main.moveTargets(for: [part]).isEmpty, "nothing for a mixed choice or a part")

        // Moving the chapters one after another, as dragging them one at a time would.
        main.moveSections([k1], parent: part, index: nil); spin(0.6)
        main.moveSections([k2], parent: part, index: nil); spin(0.6)
        main.moveSections([k3], parent: part, index: nil); spin(0.6)
        let inPart = main.session.structure.roots.first { $0.id == part }?.children.map(\.id) ?? []
        check(inPart == [k1, k2, k3], "the chapters one after another go into the part, in order", "\(inPart)")
        main.moveSections([k1, k2], parent: nil, index: nil); spin(0.6)
        check(main.session.structure.roots.map(\.id).suffix(3) == [part, k1, k2] && main.session.structure.roots.first { $0.id == part }?.children.map(\.id) == [k3], "two chapters together go back to the top level in their order")

        // Several scenes get a status at once.
        main.setStatus(ids: [scenes[0], scenes[1]], to: "draft")
        check([scenes[0], scenes[1]].allSatisfy { id in main.session.structure.scenes.first { $0.id == id }?.node.status == "draft" }, "several scenes get a status at once")

        // Several sections are deleted with one question, and one undo brings them back.
        main.tree?.choose([k1, k2]); spin(0.2)
        main.deleteChosen(confirm: false); spin(0.8)
        check(!main.session.structure.roots.contains { $0.id == k1 || $0.id == k2 }, "several chosen sections are deleted together")
        main.undoStructure(); spin(0.8)
        check(main.session.structure.roots.contains { $0.id == k1 } && main.session.structure.roots.contains { $0.id == k2 }, "and one undo brings them all back")

        for id in [k1, k2, part] { main.delete(id, confirm: false); spin(0.5) }
        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
