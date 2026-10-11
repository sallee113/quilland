import AppKit
import QuillandCore

extension Notification.Name {
    /// The Settings window (or a reset) changed a preference: everything that shows text, panels or timers reads the new values.
    static let quillandPreferencesChanged = Notification.Name("QuillandPreferencesChanged")
}

/// The person's settings as the running app uses them: one copy, read from `settings.json` and `autocorrect.json`, changed by the Settings
/// window, and announced to the rest of the app when they change.
final class AppPreferences {
    static let shared = AppPreferences()

    private(set) var values = Preferences()
    private(set) var autocorrect = AutocorrectSettings()
    private var settings: AppSettings?
    private var directory: URL?

    // MARK: The language of the interface

    /// The folder with the languages that come with the app: in the bundle, or (when run from the build folder) the project's `Resources/Languages`.
    static var bundledLanguagesDirectory: URL? {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["QUILLAND_LANGUAGES_DIR"] { return URL(fileURLWithPath: env) }
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Languages"), fm.fileExists(atPath: url.appendingPathComponent("template.json").path) { return url }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/Languages")
            if fm.fileExists(atPath: candidate.appendingPathComponent("template.json").path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    var userLanguagesDirectory: URL? { directory.map { LanguageFiles.userDirectory(settings: $0) } }

    /// Chooses the language of the interface from the preference (`system` is the language of the system if installed; the environment
    /// variable QUILLAND_LANGUAGE stands in for the system's, which the automatic checks use to stay in English).
    func applyLanguage() {
        var dirs: [URL] = []
        if let bundled = Self.bundledLanguagesDirectory { dirs.append(bundled) }
        if let user = userLanguagesDirectory { dirs.append(user) }
        Localizer.shared.directories = dirs
        let wanted = values.interfaceLanguage
        // QUILLAND_FORCE_LANGUAGE: the pictures of the interface in a language (a development aid).
        let code: String? = ProcessInfo.processInfo.environment["QUILLAND_FORCE_LANGUAGE"] ?? (wanted == "system" ? (ProcessInfo.processInfo.environment["QUILLAND_LANGUAGE"] ?? Localizer.shared.systemCode()) : wanted)
        Localizer.shared.use(code: code)
        // The system's own menu items (Dictation, Emoji, Window ▸ Zoom…) take the language from the next start on. The checks leave the author's alone.
        if ProcessInfo.processInfo.environment["QUILLAND_SETTINGS_DIR"] == nil {
            if wanted == "system" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
            else if let code { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
        }
    }

    /// Reads the files (called once at the start, with the settings the app opened).
    func load(settings: AppSettings) {
        self.settings = settings
        directory = settings.directory
        values = settings.preferences
        autocorrect = AutocorrectSettings.load(directory: settings.directory).settings
        promptSettings = AIPromptSettings.load(directory: settings.directory)
        actions = AIActions.load(directory: settings.directory)
        AIPrompts.use(promptSettings)
        settings.recentCap = values.recentLimit
        Self.applyToFonts(values)
        applyLanguage()
    }

    func update(_ edit: (inout Preferences) -> Void) {
        var p = values
        edit(&p)
        p = p.clamped()
        guard p != values else { return }
        let languageChanged = p.interfaceLanguage != values.interfaceLanguage
        values = p
        settings?.preferences = p
        settings?.recentCap = p.recentLimit
        Self.applyToFonts(p)
        if languageChanged { applyLanguage() }
        NotificationCenter.default.post(name: .quillandPreferencesChanged, object: nil)
    }

    /// The author's own wording of the AI prompts and their temperatures (`prompts.json`): changed from Settings, used by the actions at once.
    private(set) var promptSettings = AIPromptSettings()

    func updatePrompts(_ edit: (inout AIPromptSettings) -> Void) {
        var s = promptSettings
        edit(&s)
        guard s != promptSettings else { return }
        promptSettings = s
        AIPrompts.use(s)
        if let directory { try? s.save(directory: directory) }
    }

    /// The prompts the author saved from the Chat (`actions.json`), shown in the AI menu.
    private(set) var actions: [AIAction] = []

    func updateActions(_ edit: (inout [AIAction]) -> Void) {
        var list = actions
        edit(&list)
        guard list != actions else { return }
        actions = list
        if let directory { try? AIActions.save(list, directory: directory) }
    }

    func updateAutocorrect(_ edit: (inout AutocorrectSettings) -> Void) {
        var a = autocorrect
        edit(&a)
        guard a != autocorrect else { return }
        autocorrect = a
        if let directory { a.save(directory: directory) }
        NotificationCenter.default.post(name: .quillandPreferencesChanged, object: nil)
    }

    func resetPreferences(_ keep: (inout Preferences, Preferences) -> Void) {
        update { keep(&$0, Preferences()) }
    }

    /// The text's font, size and spacing live in `Fonts`, where the styler reads them.
    static func applyToFonts(_ p: Preferences) {
        Fonts.name = p.fontName
        Fonts.baseSize = CGFloat(p.fontSize)
        Fonts.lineSpacing = CGFloat(p.lineSpacing)
    }
}
