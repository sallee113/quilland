import AppKit

/// A view that holds what the author typed and saves it after a timer of its own: it can be told to save at once. A view that is torn down, or a book that is
/// changed from files, must first reach every one of them (`MainAreaController.commitPendingEdits()`); a timer does not outlive its view.
@objc protocol PendingEdits: AnyObject {
    @objc func commitEdits()
}

extension RightPanelController: PendingEdits {}
extension OutlineDetailController: PendingEdits {}
extension CharactersViewController: PendingEdits {}
extension WorldViewController: PendingEdits {}
extension EventsViewController: PendingEdits {}
extension ResearchViewController: PendingEdits {}
extension RemindersViewController: PendingEdits {}
extension RelationshipCardController: PendingEdits {}
extension PanelListTab: PendingEdits {}
