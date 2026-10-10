import AppKit

/// A cell of a list that holds one view (a label, a check box) centred vertically, so that the selection of the row fits evenly around it.
/// A bare label returned as a cell sits at the top of its row, and the selection then looks shifted down.
final class CenteredCell: NSTableCellView {
    init(_ content: NSView, leading: CGFloat = 4, trailing: CGFloat = 4) {
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        // With the label registered as the cell's text field the text turns light on a selected row, as in any system list.
        if let field = content as? NSTextField { textField = field }
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailing),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
