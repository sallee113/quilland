import Foundation

/// The settings of the person that the Settings window changes (quilland-ui.md, "Settings"): kept in `settings.json` under `preferences`.
public struct Preferences: Equatable, Sendable {
    // General
    /// `en` (the default), `system` (the language of the system when it is installed, else English), or the code of an installed language.
    public var interfaceLanguage = "en"
    /// `panels`, `book` or `compare`: where a book with no remembered view starts.
    public var defaultMode = "panels"
    public var recentLimit = 10
    public var reopenLastBook = true
    public var autoSnapshots = true
    public var snapshotMinutes = 15
    /// Where New Book proposes to keep books (nil: the Documents folder).
    public var newBookFolder: String?
    // Appearance
    public var fontName = "Georgia"
    public var fontSize = 17.0
    public var lineSpacing = 1.3
    /// The width of a sheet, in points (about 70 characters).
    public var readingWidth = 640.0
    /// How big the application's own texts are, as a factor (1 is the usual size): labels, buttons, lists and panels. The book's text has its own size above.
    /// `system`, `light` or `dark`.
    public var appearance = "system"
    // Writing
    public var checkSpelling = true
    /// The system's text replacements (the ones in System Settings ▸ Keyboard).
    public var systemTextReplacement = true
    // Panels
    public var panelTabs = ["section", "characters"]
    public var followDelay = 1.5
    // Shortcuts: an action's id to its shortcut (`cmd+opt+n`), or `none`; actions not here have their own.
    public var shortcuts: [String: String] = [:]
    // AI (local only: LM Studio on this computer)
    public var aiEnabled = true
    public var aiAddress = AIConnection.defaultAddress
    /// The model the actions use; empty: the one that is loaded.
    public var aiModel = ""
    /// Tokens the model reads at once; 0: what the server says.
    public var aiContext = 0

    public init() {}

    public static let limits = (recent: 1...30, snapshotMinutes: 1...240, fontSize: 10.0...36.0, lineSpacing: 1.0...2.2, readingWidth: 420.0...1100.0, followDelay: 0.3...6.0)

    /// The values brought into their allowed ranges (a hand-edited file can hold anything).
    public func clamped() -> Preferences {
        var p = self
        p.recentLimit = min(max(recentLimit, Self.limits.recent.lowerBound), Self.limits.recent.upperBound)
        p.snapshotMinutes = min(max(snapshotMinutes, Self.limits.snapshotMinutes.lowerBound), Self.limits.snapshotMinutes.upperBound)
        p.fontSize = min(max(fontSize, Self.limits.fontSize.lowerBound), Self.limits.fontSize.upperBound)
        p.lineSpacing = min(max(lineSpacing, Self.limits.lineSpacing.lowerBound), Self.limits.lineSpacing.upperBound)
        p.readingWidth = min(max(readingWidth, Self.limits.readingWidth.lowerBound), Self.limits.readingWidth.upperBound)
        p.followDelay = min(max(followDelay, Self.limits.followDelay.lowerBound), Self.limits.followDelay.upperBound)
        if interfaceLanguage.isEmpty { p.interfaceLanguage = "en" }
        if !["panels", "book", "compare"].contains(defaultMode) { p.defaultMode = "panels" }
        if !["system", "light", "dark"].contains(appearance) { p.appearance = "system" }
        if p.panelTabs.isEmpty { p.panelTabs = ["section"] }
        if p.aiAddress.trimmingCharacters(in: .whitespaces).isEmpty { p.aiAddress = AIConnection.defaultAddress }
        if p.aiContext != 0 { p.aiContext = min(max(p.aiContext, 1024), 1_048_576) }
        p.shortcuts = p.shortcuts.filter { $0.value == Shortcuts.none || Shortcut($0.value) != nil }
        return p
    }

    init(object o: JSONObject) {
        var p = Preferences()
        p.interfaceLanguage = o.string("interface_language") ?? p.interfaceLanguage
        p.defaultMode = o.string("default_mode") ?? p.defaultMode
        p.recentLimit = o.int("recent_limit") ?? p.recentLimit
        p.reopenLastBook = o.bool("reopen_last_book") ?? p.reopenLastBook
        p.autoSnapshots = o.bool("auto_snapshots") ?? p.autoSnapshots
        p.snapshotMinutes = o.int("snapshot_minutes") ?? p.snapshotMinutes
        p.newBookFolder = o.string("new_book_folder")
        p.fontName = o.string("font_name") ?? p.fontName
        p.fontSize = o.string("font_size").flatMap(Double.init) ?? p.fontSize
        p.lineSpacing = o.string("line_spacing").flatMap(Double.init) ?? p.lineSpacing
        p.readingWidth = o.string("reading_width").flatMap(Double.init) ?? p.readingWidth
        p.appearance = o.string("appearance") ?? p.appearance
        p.checkSpelling = o.bool("check_spelling") ?? p.checkSpelling
        p.systemTextReplacement = o.bool("system_text_replacement") ?? p.systemTextReplacement
        p.panelTabs = o.strings("panel_tabs") ?? p.panelTabs
        p.followDelay = o.string("follow_delay").flatMap(Double.init) ?? p.followDelay
        p.shortcuts = o.stringMap("shortcuts") ?? [:]
        p.aiEnabled = o.bool("ai_enabled") ?? p.aiEnabled
        p.aiAddress = o.string("ai_address") ?? p.aiAddress
        p.aiModel = o.string("ai_model") ?? p.aiModel
        p.aiContext = o.int("ai_context") ?? p.aiContext
        self = p.clamped()
    }

    /// Writes into the object, leaving the keys this version does not know.
    func write(into o: inout JSONObject) {
        o.setString("interface_language", interfaceLanguage)
        o.setString("default_mode", defaultMode)
        o.setInt("recent_limit", recentLimit)
        o.setBool("reopen_last_book", reopenLastBook)
        o.setBool("auto_snapshots", autoSnapshots)
        o.setInt("snapshot_minutes", snapshotMinutes)
        o.setString("new_book_folder", newBookFolder)
        o.setString("font_name", fontName)
        // Real numbers are kept as text in the file, so that a value is written exactly as it was typed (the format's rule for numbers).
        o.setString("font_size", Self.text(fontSize))
        o.setString("line_spacing", Self.text(lineSpacing))
        o.setString("reading_width", Self.text(readingWidth))
        o.setString("appearance", appearance)
        o.setBool("check_spelling", checkSpelling)
        o.setBool("system_text_replacement", systemTextReplacement)
        o.setStrings("panel_tabs", panelTabs)
        o.setString("follow_delay", Self.text(followDelay))
        if shortcuts.isEmpty { o.removeValue(forKey: "shortcuts") } else { o.setStringMap("shortcuts", shortcuts) }
        o.setBool("ai_enabled", aiEnabled)
        o.setString("ai_address", aiAddress)
        o.setString("ai_model", aiModel.isEmpty ? nil : aiModel)
        o.setInt("ai_context", aiContext)
    }

    private static func text(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
}

extension AppSettings {
    /// The Settings window's values, kept under `preferences` in `settings.json`.
    public var preferences: Preferences {
        get { Preferences(object: objectValue.object("preferences") ?? [:]) }
        set {
            var all = objectValue
            var o = all.object("preferences") ?? [:]
            newValue.clamped().write(into: &o)
            all["preferences"] = .object(o)
            replaceObject(all)
        }
    }
}
