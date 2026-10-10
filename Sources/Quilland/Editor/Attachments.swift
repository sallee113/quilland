import AppKit
import QuillandCore

/// Footnote markers and fragment boundaries are one placeholder character (U+FFFC) carrying the
/// semantic attribute; here they get something to look at.
enum Attachments {
    /// A picture with real pixels (two per point). Pictures drawn by a closure are drawn again whenever
    /// the system wants them as an image, and failed to encode (the log was full of "CGImageDestinationFinalize failed").
    static func bitmapImage(size: NSSize, draw: (NSRect) -> Void) -> NSImage {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    static func noteImage(_ number: Int) -> NSImage {
        bitmapImage(size: NSSize(width: 15, height: 15)) { rect in
            NSColor.systemOrange.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            let text = NSAttributedString(string: String(number), attributes: [
                .font: NSFont.systemFont(ofSize: number > 9 ? 8 : 10, weight: .bold), .foregroundColor: NSColor.white,
            ])
            let box = text.size()
            text.draw(at: NSPoint(x: rect.midX - box.width / 2, y: rect.midY - box.height / 2))
        }
    }

    static func fragmentImage() -> NSImage {
        bitmapImage(size: NSSize(width: 380, height: 8)) { rect in
            NSColor.tertiaryLabelColor.setFill()
            NSRect(x: 0, y: rect.midY - 0.5, width: rect.width, height: 1).fill()
        }
    }

    /// Gives every placeholder character its picture, and numbers the footnotes in order.
    static func refresh(_ storage: NSTextStorage) {
        var number = 0
        let whole = NSRange(location: 0, length: storage.length)
        var edits: [(NSRange, [NSAttributedString.Key: Any])] = []
        storage.enumerateAttributes(in: whole, options: []) { attrs, range, _ in
            if let box = attrs[.quillandNote] as? NoteBox, range.length == 1 {
                number += 1
                let attachment = attrs[.attachment] as? NSTextAttachment
                let shown = attachment?.image?.accessibilityDescription
                if shown != String(number) {
                    let new = NSTextAttachment()
                    let image = noteImage(number)
                    image.accessibilityDescription = String(number)
                    new.image = image
                    new.bounds = CGRect(x: 0, y: -2, width: 15, height: 15)
                    edits.append((range, [.attachment: new, .toolTip: box.runs.map(\.text).joined()]))
                }
            } else if attrs[.quillandFragment] != nil, range.length == 1, attrs[.attachment] == nil {
                let new = NSTextAttachment()
                new.image = fragmentImage()
                new.bounds = CGRect(x: 0, y: 0, width: 380, height: 8)
                edits.append((range, [.attachment: new, .toolTip: L("Fragment boundary")]))
            }
        }
        for (range, attrs) in edits { storage.addAttributes(attrs, range: range) }
    }

    static func notes(in storage: NSAttributedString) -> Int {
        var count = 0
        storage.enumerateAttribute(.quillandNote, in: NSRange(location: 0, length: storage.length)) { v, _, _ in if v != nil { count += 1 } }
        return count
    }
}
