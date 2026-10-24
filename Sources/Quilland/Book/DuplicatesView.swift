import AppKit
import QuillandCore

/// The Duplicates tab of the bottom panel: cards of the book that look like one thing written more than once (found by the app's own finder: no model), each group with
/// the choice to merge the new card into the one that is already there, to delete the new card, or to say that they are not the same. Nothing is asked: Undo takes it back.
final class DuplicatesView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var main: MainAreaController?
    private(set) var groups: [DuplicateGroup] = []
    private let summary = NSTextField(labelWithString: "")
    private let table = Hover.rows(NSTableView())
    private let explanation = NSTextField(wrappingLabelWithString: "")
    private let mergeButton = NSButton(title: L("Merge"), target: nil, action: nil)
    private let deleteButton = NSButton(title: L("Delete"), target: nil, action: nil)
    private let openButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let notSameButton = NSButton(title: L("Not the Same"), target: nil, action: nil)
    private let againButton = NSButton(title: L("Check Again"), target: nil, action: nil)
    private let showDismissedButton = NSButton(title: L("Show Dismissed Again"), target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor
        explanation.maximumNumberOfLines = 3
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("group"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.rowSizeStyle = .small
        table.setAccessibilityLabel(L("Duplicates"))
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        for b in [mergeButton, deleteButton, notSameButton, againButton, showDismissedButton] { b.bezelStyle = .rounded; b.controlSize = .small; b.keyEquivalent = "" }
        notSameButton.target = self; notSameButton.action = #selector(notSamePressed)
        againButton.target = self; againButton.action = #selector(refreshAction)
        showDismissedButton.target = self; showDismissedButton.action = #selector(showDismissedPressed)
        mergeButton.target = self; mergeButton.action = #selector(mergePressed)
        deleteButton.target = self; deleteButton.action = #selector(deletePressed)
        openButton.controlSize = .small; openButton.bezelStyle = .rounded
        let top = NSStackView(views: [againButton, summary])
        top.spacing = 10
        let bottom = NSStackView(views: [mergeButton, deleteButton, openButton, notSameButton, showDismissedButton])
        bottom.spacing = 8
        let stack = NSStackView(views: [top, scroll, explanation, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 70),
            explanation.leadingAnchor.constraint(equalTo: stack.leadingAnchor), explanation.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func refreshAction() { refresh() }

    /// Looks through the book again.
    func refresh() {
        guard let main else { return }
        let keep = selectedGroup?.key
        groups = BookDuplicates.find(characters: main.characters, worlds: main.worlds, events: main.eventStore, relationships: main.relationships, dismissed: BookDuplicates.dismissed(book: main.folder), ages: CardAges.ages(book: main.folder))
        table.reloadData()
        if let keep, let i = groups.firstIndex(where: { $0.key == keep }) { table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false) }
        else if !groups.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        summary.stringValue = groups.isEmpty ? L("No cards look like duplicates") : Lp("{n} group of cards that look like one", "{n} groups of cards that look like one", groups.count)
        updateButtons()
    }

    var selectedGroup: DuplicateGroup? { table.selectedRow >= 0 && table.selectedRow < groups.count ? groups[table.selectedRow] : nil }

    func select(where match: (DuplicateGroup) -> Bool) {
        guard let i = groups.firstIndex(where: match) else { return }
        table.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        updateButtons()
    }

    private func updateButtons() {
        let group = selectedGroup
        let open = NSMenu()
        open.addItem(NSMenuItem(title: L("Open"), action: nil, keyEquivalent: ""))
        if let group {
            for m in group.members { open.addItem(ClosureMenuItem(title: Self.title(of: m, in: group)) { [weak self] in self?.open(m.id, of: group) }) }
        }
        openButton.menu = open
        for b in [mergeButton, deleteButton, notSameButton] { b.isEnabled = group != nil }
        openButton.isEnabled = group != nil
        showDismissedButton.isEnabled = !BookDuplicates.dismissed(book: main?.folder ?? URL(fileURLWithPath: "/")).isEmpty
        explanation.stringValue = group.map { Self.explanation(for: $0) } ?? L("Choose a group. The card that is already there stays. Merge adds what the new card holds to it and removes the new card; Delete removes the new card. Nothing is asked: one Undo takes either back. Not the Same stops listing the group.")
    }

    static func title(of m: DuplicateGroup.Member, in group: DuplicateGroup) -> String { m.title.isEmpty ? L("(no name)") : m.title }

    static func kindName(_ kind: CollectKind) -> String {
        switch kind {
        case .characters: return L("Characters")
        case .places: return L("Places")
        case .events: return L("Events")
        case .relationships: return L("Relationships")
        default: return ""
        }
    }

    static func explanation(for group: DuplicateGroup) -> String {
        (group.reasons.isEmpty ? "" : group.reasons.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "; ") + ". ")
            + (group.level == .same ? L("They are most likely the same.") : L("They may be the same: check before merging."))
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { groups.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let g = groups[row]
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        let s = NSMutableAttributedString(string: g.level == .same ? "● " : "○ ", attributes: [.foregroundColor: g.level == .same ? NSColor.systemOrange : NSColor.systemYellow, .font: NSFont.systemFont(ofSize: 12)])
        s.append(NSAttributedString(string: Self.kindName(g.kind) + "  ", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        s.append(NSAttributedString(string: "«" + Self.title(of: g.existing, in: g) + "»", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]))
        s.append(NSAttributedString(string: "  ⟵  " + L("new") + ": " + g.newer.map { "«" + Self.title(of: $0, in: g) + "»" }.joined(separator: ", "), attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        label.attributedStringValue = s
        label.toolTip = g.reasons.joined(separator: "\n")
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    // MARK: Doing something about it

    @objc private func mergePressed() { if let group = selectedGroup { merge(group) } }
    @objc private func deletePressed() { if let group = selectedGroup { delete(group) } }

    /// Merges the new card (two new ones: both) into the card that is already there: one click, one step that Undo takes back (so there is nothing to confirm), and the next
    /// group is chosen.
    @discardableResult
    func merge(_ group: DuplicateGroup) -> Bool {
        guard let main else { return false }
        let row = max(0, table.selectedRow)
        main.mergeDuplicates(group)
        afterAction(row)
        return true
    }

    /// Deletes the new card (two new ones: both), with everything that refers to it, as one step Undo takes back; nothing is asked. A relationship that starts in a deleted
    /// event starts in the event that stays instead, since the two are the same event.
    @discardableResult
    func delete(_ group: DuplicateGroup) -> Bool {
        guard let main else { return false }
        let row = max(0, table.selectedRow)
        main.deleteDuplicates(group)
        afterAction(row)
        return true
    }

    private func afterAction(_ row: Int) {
        refresh()
        if !groups.isEmpty { table.selectRowIndexes(IndexSet(integer: min(row, groups.count - 1)), byExtendingSelection: false); updateButtons() }
    }

    private func open(_ id: String, of group: DuplicateGroup) {
        guard let main else { return }
        switch group.kind {
        case .characters: main.setMode(.characters); main.charactersView?.select(id)
        case .places: main.setMode(.world); main.worldView?.select(id)
        case .events: main.setMode(.events); main.eventsView?.select(id)
        case .relationships: if let event = main.eventHolding(relationship: id) { main.setMode(.events); main.eventsView?.select(event) }
        default: break
        }
    }

    @objc private func notSamePressed() { notSame() }

    func notSame() {
        guard let group = selectedGroup, let main else { return }
        BookDuplicates.dismiss([group.key], book: main.folder)
        refresh()
    }

    @objc private func showDismissedPressed() {
        guard let main else { return }
        BookDuplicates.forgetDismissed(book: main.folder)
        refresh()
    }
}

extension MainAreaController {
    /// Merges the new cards of a group into the card that is already there: one undoable step, after a snapshot (as for the other merges).
    func mergeDuplicates(_ group: DuplicateGroup) {
        let existing = group.existing
        restructure(focusText: false, undoName: L("Merge into “{name}”", ["name": existing.title])) { editor in
            for new in group.newer {
                switch group.kind {
                case .characters: try CharacterMerger.merge(new.id, into: existing.id, book: editor.folder)
                case .places: try WorldMerger.mergePlaces(new.id, into: existing.id, book: editor.folder)
                case .events: try EventMerger.merge(new.id, into: existing.id, book: editor.folder)
                case .relationships: try RelationshipMerger.merge(new.id, into: existing.id, book: editor.folder)
                default: break
                }
            }
            return nil
        }
    }

    /// Deletes the new cards of a group (the card that is already there stays): one undoable step.
    func deleteDuplicates(_ group: DuplicateGroup) {
        let existing = group.existing
        let name = group.newer.map(\.title).joined(separator: ", ")
        restructure(focusText: false, undoName: L("Delete “{name}”", ["name": name])) { editor in
            for new in group.newer {
                switch group.kind {
                case .characters: try BookIntegrity.deleteCharacter(new.id, book: editor.folder, snapshot: false)
                case .places: try BookIntegrity.deletePlace(new.id, book: editor.folder, snapshot: false)
                case .events: try BookIntegrity.deleteEvent(new.id, book: editor.folder, started: .moveStart(to: existing.id), snapshot: false)
                case .relationships: try BookIntegrity.deleteRelationship(new.id, book: editor.folder, snapshot: false)
                default: break
                }
            }
            return nil
        }
    }
}
