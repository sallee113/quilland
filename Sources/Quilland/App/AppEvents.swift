import Foundation

/// Things that happen in the application and that more than one place may care about. A place that cares subscribes where it lives (`subscribe`), so that the
/// one that reports the change does not have to know who listens.
extension Notification.Name {
    /// The state of the connection to the local model changed (checking, answered, not answering, switched off): what depends on the AI is drawn again.
    static let aiStatusChanged = Notification.Name("QuillandAIStatusChanged")
}

/// A subscription to an event. It lasts as long as it is kept: the view that subscribes holds it, and when the view goes, so does the subscription.
final class Subscription {
    private let token: NSObjectProtocol
    fileprivate init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Calls `handler` (on the main thread) each time the event is posted. Keep the result: `private var subscriptions: [Subscription] = []`.
/// The handler should not keep what subscribes: `subscribe(to: .aiStatusChanged) { [weak self] in self?.refresh() }`.
func subscribe(to name: Notification.Name, _ handler: @escaping () -> Void) -> Subscription {
    Subscription(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in handler() })
}
