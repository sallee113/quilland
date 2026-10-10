import AppKit

/// A table row whose selection is drawn quietly (grey, not the loud blue), so that a field typed in inside the row keeps its own
/// background, its text colour and a cursor that can be seen.
final class QuietRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}
