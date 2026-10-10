import Foundation

/// A keyboard shortcut as the settings file keeps it: `cmd+opt+shift+n`, `ctrl+return`. Modifiers in a fixed order, then the key: one character, or a name
/// (`return`, `tab`, `space`, `delete`, `escape`, `up`, `down`, `left`, `right`, `f1`…`f12`).
public struct Shortcut: Hashable, Sendable {
    public var key: String
    public var command = false, option = false, shift = false, control = false

    public init(key: String, command: Bool = false, option: Bool = false, shift: Bool = false, control: Bool = false) {
        self.key = key.lowercased()
        self.command = command; self.option = option; self.shift = shift; self.control = control
    }

    public static let keyNames: Set<String> = Set(["return", "tab", "space", "delete", "escape", "up", "down", "left", "right"] + (1...12).map { "f\($0)" })

    public init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, !last.isEmpty || parts.count >= 2 else { return nil }
        // "cmd++" is the plus key.
        var key = last
        var mods = parts.dropLast()
        if last.isEmpty, mods.last == "" { key = "+"; mods = mods.dropLast() }
        guard key.count == 1 || Self.keyNames.contains(key) else { return nil }
        self.init(key: key)
        for m in mods {
            switch m {
            case "cmd", "command": command = true
            case "opt", "option", "alt": option = true
            case "shift": shift = true
            case "ctrl", "control": control = true
            default: return nil
            }
        }
    }

    /// The text kept in the file.
    public var text: String {
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if shift { parts.append("shift") }
        if command { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// Like ⌃⌥⇧⌘N, as the menus show it.
    public var display: String {
        let names = ["return": "↩", "tab": "⇥", "space": "␣", "delete": "⌫", "escape": "⎋", "up": "↑", "down": "↓", "left": "←", "right": "→"]
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + (names[key] ?? key.uppercased())
    }

    /// A shortcut with no modifier would take a key away from typing; only the function keys may stand alone.
    public var isUsable: Bool { (command || control || option) || key.hasPrefix("f") && key.count > 1 }

    /// The combinations of the standard commands, which no action of the app may take.
    public static let reserved: Set<Shortcut> = Set([
        Shortcut(key: "c", command: true), Shortcut(key: "x", command: true), Shortcut(key: "v", command: true), Shortcut(key: "a", command: true),
        Shortcut(key: "z", command: true), Shortcut(key: "z", command: true, shift: true), Shortcut(key: "w", command: true), Shortcut(key: "q", command: true),
        Shortcut(key: "h", command: true), Shortcut(key: "m", command: true), Shortcut(key: ",", command: true), Shortcut(key: "h", command: true, option: true),
    ])
}

/// The shortcuts the author changed: an action's id to a shortcut, or `none` for no shortcut at all. Kept under `preferences.shortcuts`.
public enum Shortcuts {
    public static let none = "none"

    /// What an action has: the author's choice, else its default (which may be nothing).
    public static func effective(id: String, defaults: Shortcut?, overrides: [String: String]) -> Shortcut? {
        guard let text = overrides[id] else { return defaults }
        return text == none ? nil : (Shortcut(text) ?? defaults)
    }

    /// The other actions that already use `shortcut`.
    public static func users(of shortcut: Shortcut, besides id: String, actions: [(id: String, defaults: Shortcut?)], overrides: [String: String]) -> [String] {
        actions.filter { $0.id != id && effective(id: $0.id, defaults: $0.defaults, overrides: overrides) == shortcut }.map(\.id)
    }
}
