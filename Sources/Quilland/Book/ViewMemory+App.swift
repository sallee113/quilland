import AppKit
import QuillandCore

extension NSView {
    /// How far the scroll view this view is in is scrolled (from the top).
    var scrolledBy: CGFloat { enclosingScrollView?.contentView.bounds.origin.y ?? 0 }

    /// Scrolls the scroll view this view is in to this place (as far as the content allows).
    func scroll(toPlace y: CGFloat) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        scroll.layoutSubtreeIfNeeded()
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: y), size: clip.bounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// Puts the scroll back now, and once more when the view has its size (a view that was just made has none yet).
    func restoreScroll(_ y: Double) {
        scroll(toPlace: CGFloat(y))
        DispatchQueue.main.async { [weak self] in self?.scroll(toPlace: CGFloat(y)) }
    }
}

extension RelationFilter {
    /// The chips as `kind:id`.
    var memory: [String] {
        anchors.map { a -> String in
            switch a {
            case .section(let id): return "section:" + id
            case .event(let id): return "event:" + id
            case .character(let id): return "character:" + id
            case .place(let id): return "place:" + id
            }
        }
    }
}
