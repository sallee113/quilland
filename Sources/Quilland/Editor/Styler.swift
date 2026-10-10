import AppKit
import QuillandCore

/// How the semantic text (blocks, bold, italic) is drawn. The semantic attributes (`quillandBlock`,
/// `quillandBold`, `quillandItalic`) are the truth; fonts and paragraph styles are derived from them.
enum Fonts {
    /// Set from the Settings window (Appearance).
    static var name = "Georgia"
    static var baseSize: CGFloat = 17
    static var lineSpacing: CGFloat = 1.3

    static func base(size: CGFloat) -> NSFont {
        NSFont(name: name, size: size) ?? NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    static func font(kind: String, bold: Bool, italic: Bool) -> NSFont {
        var size = baseSize
        var isBold = bold
        switch kind {
        case BlockKind.heading1: size = baseSize * 1.7; isBold = true
        case BlockKind.heading2: size = baseSize * 1.4; isBold = true
        case BlockKind.heading3: size = baseSize * 1.2; isBold = true
        default: break
        }
        var font = base(size: size)
        let manager = NSFontManager.shared
        if isBold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }
}

enum Styler {
    static func paragraphStyle(kind: String) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Fonts.lineSpacing
        style.paragraphSpacing = 9
        switch kind {
        case BlockKind.heading1: style.paragraphSpacingBefore = 22; style.paragraphSpacing = 12
        case BlockKind.heading2: style.paragraphSpacingBefore = 16; style.paragraphSpacing = 10
        case BlockKind.heading3: style.paragraphSpacingBefore = 12; style.paragraphSpacing = 8
        case BlockKind.quote:
            style.firstLineHeadIndent = 36
            style.headIndent = 36
            style.tailIndent = -36
        case BlockKind.sceneBreak:
            style.alignment = .center
            style.paragraphSpacingBefore = 10
            style.paragraphSpacing = 10
        case BlockKind.fragment:
            style.paragraphSpacing = 4
            style.lineHeightMultiple = 0.6
        default: break
        }
        return style
    }

    /// Attributes for text of a given kind: the semantic ones and the ones derived from them.
    static func attributes(kind: String, bold: Bool = false, italic: Bool = false) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .quillandBlock: kind,
            .font: Fonts.font(kind: kind, bold: bold, italic: italic),
            .paragraphStyle: paragraphStyle(kind: kind),
            .foregroundColor: kind == BlockKind.sceneBreak ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        if bold { attrs[.quillandBold] = true }
        if italic { attrs[.quillandItalic] = true }
        return attrs
    }

    /// Draws every paragraph that touches `range` from its semantic attributes.
    static func style(_ storage: NSTextStorage, range: NSRange) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }
        let from = min(range.location, text.length - 1)
        var location = text.paragraphRange(for: NSRange(location: from, length: 0)).location
        let end = min(NSMaxRange(range), text.length)
        var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            let kind = storage.attribute(.quillandBlock, at: paragraph.location, effectiveRange: nil) as? String ?? BlockKind.body
            changes.append((paragraph, [.paragraphStyle: paragraphStyle(kind: kind),
                                        .foregroundColor: kind == BlockKind.sceneBreak ? NSColor.secondaryLabelColor : NSColor.labelColor]))
            storage.enumerateAttributes(in: paragraph, options: []) { attrs, run, _ in
                // A paragraph has one kind: text typed or pasted in it takes it.
                let bold = attrs[.quillandBold] as? Bool == true
                let italic = attrs[.quillandItalic] as? Bool == true
                changes.append((run, [.font: Fonts.font(kind: kind, bold: bold, italic: italic), .quillandBlock: kind]))
            }
            location = NSMaxRange(paragraph)
            if paragraph.length == 0 { break }
        } while location < end
        for (r, attrs) in changes { storage.addAttributes(attrs, range: r) }
        // A suggestion that is not text yet stays faint.
        storage.enumerateAttribute(.ghost, in: NSRange(location: 0, length: storage.length)) { value, r, _ in
            if value != nil { storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: r) }
        }
    }
}
