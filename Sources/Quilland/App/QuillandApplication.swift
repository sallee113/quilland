import AppKit

/// The application object. AppKit catches an exception thrown while it handles an event (a message nobody answers, say), prints a line and goes on, and inside a modal dialog it
/// ends the dialog: nothing shows the author what went wrong. Here every such exception is also kept, so that the automatic checks fail on it.
final class QuillandApplication: NSApplication {
    nonisolated(unsafe) static var caught: [String] = []

    override func reportException(_ exception: NSException) {
        Self.caught.append("\(exception.name.rawValue): \(exception.reason ?? "")")
        super.reportException(exception)
    }
}
