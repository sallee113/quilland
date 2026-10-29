import AppKit
import QuillandCore

/// Help ▸ What's New in Quilland: the changelog, release by release, newest first.
final class WhatsNewWindowController: NSWindowController {
    private let textView = NSTextView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L("What's New in Quilland") + " — " + AppVersion.short
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("QuillandWhatsNew")
        super.init(window: window)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 22, height: 18)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel(L("What's New in Quilland"))
        scroll.documentView = textView
        window.contentView = scroll
        show(markdown: AppVersion.changelog)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// What the window shows, as text (for the checks).
    var shownText: String { textView.string }

    func show(markdown: String?) {
        textView.textStorage?.setAttributedString(Self.attributed(markdown: markdown ?? L("The changelog is not part of this build.")))
        textView.scrollToBeginningOfDocument(nil)
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The headings, the bullets and the bold or code inside a line of the changelog's markdown, drawn as text.
    static func attributed(markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 13)
        func inline(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
            let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            var a = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
            a.font = font
            a.foregroundColor = color
            let ns = NSMutableAttributedString(a)
            // (Bold and code spans carry their own traits in the parsed text.)
            ns.enumerateAttribute(.inlinePresentationIntent, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
                guard let raw = value as? Int else { return }
                let intent = InlinePresentationIntent(rawValue: UInt(raw))
                if intent.contains(.stronglyEmphasized) { ns.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: font.pointSize), range: range) }
                if intent.contains(.emphasized) { ns.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: range) }
                if intent.contains(.code) { ns.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular), range: range) }
            }
            return ns
        }
        func paragraph(_ spacingAfter: CGFloat, indent: CGFloat = 0, hanging: CGFloat = 0) -> NSParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacing = spacingAfter; p.firstLineHeadIndent = indent; p.headIndent = indent + hanging
            return p
        }
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { continue }
            let piece: NSMutableAttributedString
            if line.hasPrefix("# ") {
                piece = NSMutableAttributedString(attributedString: inline(String(line.dropFirst(2)), font: .systemFont(ofSize: 24, weight: .semibold)))
                piece.addAttribute(.paragraphStyle, value: paragraph(10), range: NSRange(location: 0, length: piece.length))
            } else if line.hasPrefix("## ") {
                piece = NSMutableAttributedString(attributedString: inline(String(line.dropFirst(3)), font: .systemFont(ofSize: 18, weight: .semibold)))
                piece.addAttribute(.paragraphStyle, value: { let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = 14; p.paragraphSpacing = 6; return p }(), range: NSRange(location: 0, length: piece.length))
            } else if line.hasPrefix("### ") {
                piece = NSMutableAttributedString(attributedString: inline(String(line.dropFirst(4)), font: .systemFont(ofSize: 14, weight: .semibold), color: .secondaryLabelColor))
                piece.addAttribute(.paragraphStyle, value: { let p = NSMutableParagraphStyle(); p.paragraphSpacingBefore = 8; p.paragraphSpacing = 3; return p }(), range: NSRange(location: 0, length: piece.length))
            } else if line.hasPrefix("- ") {
                piece = NSMutableAttributedString(string: "•  ", attributes: [.font: body])
                piece.append(inline(String(line.dropFirst(2)), font: body))
                piece.addAttribute(.paragraphStyle, value: paragraph(4, indent: 4, hanging: 14), range: NSRange(location: 0, length: piece.length))
            } else {
                piece = NSMutableAttributedString(attributedString: inline(line, font: body))
                piece.addAttribute(.paragraphStyle, value: paragraph(6), range: NSRange(location: 0, length: piece.length))
            }
            out.append(piece)
            out.append(NSAttributedString(string: "\n"))
        }
        return out
    }
}
