import Foundation
import Testing
@testable import QuillandCore

@Suite("Keyboard shortcuts")
struct ShortcutTests {
    @Test("a shortcut is written and read back, in a fixed order")
    func roundTrip() {
        let s = Shortcut("opt+cmd+shift+n")!
        #expect(s.command && s.option && s.shift && !s.control && s.key == "n")
        #expect(s.text == "opt+shift+cmd+n" && Shortcut(s.text) == s)
        #expect(s.display == "⌥⇧⌘N")
        #expect(Shortcut("cmd+return")?.display == "⌘↩" && Shortcut("ctrl+f5")?.key == "f5")
        #expect(Shortcut("cmd++")?.key == "+" && Shortcut("cmd+")?.key == nil)
        #expect(Shortcut("hyper+n") == nil && Shortcut("cmd+nonsense") == nil && Shortcut("") == nil)
    }

    @Test("a plain key is not a shortcut; function keys may stand alone; the standard commands are reserved")
    func rules() {
        #expect(!Shortcut("n")!.isUsable && Shortcut("shift+n")!.isUsable == false && Shortcut("cmd+n")!.isUsable && Shortcut("f5")!.isUsable)
        #expect(Shortcut.reserved.contains(Shortcut("cmd+c")!) && Shortcut.reserved.contains(Shortcut("shift+cmd+z")!) && !Shortcut.reserved.contains(Shortcut("cmd+n")!))
    }

    @Test("the author's choice beats the default; none removes it; a damaged one is ignored; conflicts name the other action")
    func effective() {
        let actions: [(id: String, defaults: Shortcut?)] = [("a", Shortcut("cmd+1")), ("b", Shortcut("cmd+2")), ("c", nil)]
        let overrides = ["a": "cmd+9", "b": Shortcuts.none, "c": "garbage"]
        #expect(Shortcuts.effective(id: "a", defaults: actions[0].defaults, overrides: overrides) == Shortcut("cmd+9"))
        #expect(Shortcuts.effective(id: "b", defaults: actions[1].defaults, overrides: overrides) == nil)
        #expect(Shortcuts.effective(id: "c", defaults: nil, overrides: overrides) == nil)
        #expect(Shortcuts.effective(id: "a", defaults: actions[0].defaults, overrides: [:]) == Shortcut("cmd+1"))
        #expect(Shortcuts.users(of: Shortcut("cmd+9")!, besides: "b", actions: actions, overrides: overrides) == ["a"])
        #expect(Shortcuts.users(of: Shortcut("cmd+2")!, besides: "a", actions: actions, overrides: overrides).isEmpty, "b gave it up")
    }

    @Test("the choices are kept in settings.json, and a damaged value is dropped when read")
    func preferences() {
        var p = Preferences()
        p.shortcuts = ["showExport": "opt+cmd+e", "x": Shortcuts.none, "y": "nonsense+key+"]
        let kept = p.clamped()
        #expect(kept.shortcuts == ["showExport": "opt+cmd+e", "x": "none"])
        var o: JSONObject = [:]
        kept.write(into: &o)
        #expect(Preferences(object: o).shortcuts == kept.shortcuts)
        var empty: JSONObject = [:]
        Preferences().write(into: &empty)
        #expect(empty["shortcuts"] == nil)
    }
}
