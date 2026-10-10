import Foundation

// The document model of a scene's text (quilland-format.md, section 4).
//
// A Markdown file and the editor's styled text are two views of this one
// model. The round trip is lossless when
//     parse(write(model)) == model   and   write(parse(file)) == file
// for every file the app itself wrote.

/// Bold and italic. Nothing else is a character style in a scene's text.
public struct Style: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let bold = Style(rawValue: 1)
    public static let italic = Style(rawValue: 2)
}

/// A stretch of text with one style. Never contains a line break.
public struct Run: Equatable, Sendable {
    public var text: String
    public var style: Style
    public init(_ text: String, _ style: Style = []) {
        self.text = text
        self.style = style
    }
}

/// An inline footnote, `^[…]`. Its content is runs only (bold and italic).
/// `style` is the style of the surrounding span the note sits in.
public struct Note: Equatable, Sendable {
    public var content: [Run]
    public var style: Style
    public init(_ content: [Run], style: Style = []) {
        self.content = content
        self.style = style
    }
}

public enum Inline: Equatable, Sendable {
    case run(Run)
    case note(Note)
    /// A line break inside a paragraph (verse), written as a trailing backslash.
    case lineBreak
}

public enum Block: Equatable, Sendable {
    case paragraph([Inline])
    /// Level 1...3.
    case heading(Int, [Inline])
    /// A set-off block: epigraph, letter, poem. One level, paragraphs only.
    case quote([[Inline]])
    case sceneBreak
    /// A hidden fragment marker, `<!-- fragment: <uuid> -->`. The id is a lowercase UUID.
    case fragment(String)
}

public struct Document: Equatable, Sendable {
    public var blocks: [Block]
    public init(_ blocks: [Block] = []) { self.blocks = blocks }
}

// Small conveniences, mostly for tests.
public extension Inline {
    static func text(_ s: String, _ style: Style = []) -> Inline { .run(Run(s, style)) }
}
