import AppKit
import QuillandCore

extension MainAreaController {
    /// What the Section menu can do now: the menu items follow it.
    struct SectionState {
        var hasSection = false
        var isScene = false
        var isPart = false
        var canMoveUp = false
        var canMoveDown = false
        var hasNextScene = false
        var hasPreviousScene = false
        var canMergeChosen = false
        var canMoveTo = false
        var canGroup = false
        var canSplit = false
        var status: String?
    }

    /// The siblings of a section and its place among them.
    private func siblings(of id: String) -> (all: [BookStructure.Node], index: Int)? {
        func search(_ nodes: [BookStructure.Node]) -> (all: [BookStructure.Node], index: Int)? {
            if let i = nodes.firstIndex(where: { $0.id == id }) { return (nodes, i) }
            for n in nodes { if let found = search(n.children) { return found } }
            return nil
        }
        return search(session.structure.roots)
    }

    /// The ids of the scenes in the chapter of this scene, in order.
    func siblingScenes(of id: String) -> [String] { siblings(of: id).map { $0.all.filter { $0.kind == .scene }.map(\.id) } ?? [] }

    func sectionState() -> SectionState {
        var state = SectionState()
        let sceneIDs = session.structure.scenes.map(\.id)
        // The tree's own commands (the Outline, the context menu) know their section; the menu uses the chosen one.
        if let id = selectedSectionID, let node = findNode(id), let place = siblings(of: id) {
            state.hasSection = true
            state.isScene = node.kind == .scene
            state.isPart = node.kind == .part
            let editor = BookEditor(structure: session.structure)
            state.canMoveUp = editor.canMove(id, by: -1)
            state.canMoveDown = editor.canMove(id, by: 1)
            if state.isScene {
                // Scenes merge within their chapter: the neighbours are the scenes of the same chapter.
                state.hasNextScene = place.index + 1 < place.all.count
                state.hasPreviousScene = place.index > 0
                state.status = session.structure.scenes.first { $0.id == id }?.node.status
            }
            let loose = Set(session.structure.roots.filter { $0.kind == .chapter }.map(\.id))
            let chosen = (mode == .outline ? tree?.selectedIDs : nil) ?? [id]
            state.canGroup = !chosen.isEmpty && chosen.allSatisfy { loose.contains($0) }
        }
        if mode == .outline {
            let chosen = Set(tree?.selectedIDs ?? [])
            let picked = sceneIDs.filter { chosen.contains($0) }
            let neighbours = picked.first.map { siblingScenes(of: $0) } ?? []
            if picked.count >= 2, let start = neighbours.firstIndex(of: picked[0]), start + picked.count <= neighbours.count { state.canMergeChosen = Array(neighbours[start..<(start + picked.count)]) == picked }
        }
        state.canMoveTo = !moveTargets(for: chosenSections()).isEmpty
        if mode != .outline, mode != .plan, mode != .characters, mode != .world, mode != .events, mode != .research, mode != .reminders,
           let area = controllers.first(where: { $0.currentSceneID != nil }), let id = area.currentSceneID, let doc = session.document(id), let tv = area.currentSheet?.textView {
            state.canSplit = Self.splitCut(in: doc.storage.string as NSString, caret: tv.selectedRange().location) != nil
        }
        return state
    }

    /// The tree's context menu: the clicked section is the chosen one, and a command that cannot be done is greyed.
    func treeCanDo(_ command: StructureTreeController.Command) -> Bool {
        let state = sectionState()
        switch command {
        case .moveUp: return state.canMoveUp
        case .moveDown: return state.canMoveDown
        case .mergeNext: return state.hasNextScene
        case .mergePrevious: return state.hasPreviousScene
        case .mergeChosen: return state.canMergeChosen
        case .moveTo: return state.canMoveTo
        case .group: return state.canGroup
        case .ungroup: return state.isPart
        default: return true
        }
    }
}
