import AppKit

/// The scenes of a book on sheets, one under another: the content of Book mode.
final class BookStackView: NSView {
    enum Row {
        case band(BandView)
        case header(SceneHeaderView)
        case sheet(SheetView)

        var view: NSView {
            switch self {
            case .band(let v): return v
            case .header(let v): return v
            case .sheet(let v): return v
            }
        }
    }

    private(set) var rows: [Row] = []
    var sheetWidth: CGFloat = 640 { didSet { needsLayout = true } }
    var topInset: CGFloat = 40 { didSet { needsLayout = true } }
    var bottomInset: CGFloat = 40 { didSet { needsLayout = true } }
    private(set) var contentHeight: CGFloat = 0

    override var isFlipped: Bool { true }

    func setRows(_ rows: [Row]) {
        for r in self.rows { r.view.removeFromSuperview() }
        self.rows = rows
        for r in rows { addSubview(r.view) }
        needsLayout = true
    }

    var sheets: [SheetView] { rows.compactMap { if case .sheet(let s) = $0 { return s }; return nil } }

    override func layout() {
        super.layout()
        arrange()
    }

    /// Puts every row in place; the stack's own height follows the content.
    func arrange() {
        let width = bounds.width
        let rowWidth = min(sheetWidth, max(120, width - 40))
        let x = (width - rowWidth) / 2
        var y = topInset
        var previous: Row?
        for row in rows {
            let gap: CGFloat
            switch (previous, row) {
            case (nil, _): gap = 0
            case (.header?, .sheet): gap = 4
            case (.band?, .header): gap = 10
            case (.band?, .band): gap = 10
            case (.sheet?, .band): gap = 26
            case (.sheet?, .header): gap = 22
            default: gap = 12
            }
            y += gap
            switch row {
            case .sheet(let sheet):
                if abs(sheet.frame.width - rowWidth) > 0.5 { sheet.setWidth(rowWidth) }
                sheet.frame.origin = NSPoint(x: x, y: y)
                y += sheet.height
            case .header(let header):
                header.frame = NSRect(x: x, y: y, width: rowWidth, height: 26)
                y += 26
            case .band(let band):
                band.frame = NSRect(x: 0, y: y, width: width, height: band.frame.height)
                y += band.frame.height
            }
            previous = row
        }
        contentHeight = y + bottomInset
        if abs(frame.height - contentHeight) > 0.5 { frame.size.height = contentHeight }
    }
}
