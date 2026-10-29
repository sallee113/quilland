import AppKit
import QuillandCore

/// Help ▸ What's New in Quilland shows the changelog; the version is the one in the VERSION file.
extension AppSelfTest {
    func whatsNew() -> Int32? {
        let help = NSApp.mainMenu?.items.first { $0.submenu?.title == "Help" }?.submenu
        check(help?.items.map(\.title) == ["What's New in Quilland"] && NSApp.helpMenu === help, "the Help menu has What's New in Quilland")
        let version = AppVersion.file("VERSION").flatMap { try? String(contentsOf: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        check(version != nil && AppVersion.short == version, "the version is the one in the VERSION file", "\(AppVersion.short) \(String(describing: version))")
        app.showWhatsNew(); spin(0.3)
        let window = app.whatsNew
        check(window?.window?.isVisible == true && window?.window?.title.contains(AppVersion.short) == true, "the window opens with the version in its title", "\(String(describing: window?.window?.title))")
        let text = window?.shownText ?? ""
        check(text.contains("Changelog") && text.contains("## ") == false && text.contains("•") && text.contains(AppVersion.short), "it shows the changelog, with headings and bullets drawn as text, and the version", "\(text.prefix(80))")
        window?.show(markdown: nil)
        check(window?.shownText.contains("not part of this build") == true, "a build with no changelog says so")
        window?.show(markdown: AppVersion.changelog)
        window?.window?.close(); spin(0.2)
        return nil
    }
}
