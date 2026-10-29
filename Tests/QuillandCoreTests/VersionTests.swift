import Foundation
import Testing
@testable import QuillandCore

@Suite("Version and changelog")
struct VersionTests {
    static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    @Test("the VERSION file is X.Y.Z, and the changelog's newest section is that version")
    func files() throws {
        let version = try String(contentsOf: Self.root.appendingPathComponent("VERSION"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(version.split(separator: ".").count == 3 && version.split(separator: ".").allSatisfy { Int($0) != nil }, "VERSION is \(version)")
        let changelog = try String(contentsOf: Self.root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        #expect(AppVersion.newestVersion(inChangelog: changelog) == version, "the top of CHANGELOG.md is not \(version)")
        #expect(changelog.contains("## \(version) — "), "the section has a date")
    }

    @Test("the newest version is read from the first version heading")
    func newest() {
        #expect(AppVersion.newestVersion(inChangelog: "# Changelog\n\nText\n\n## 0.2.1 — 2026-11-02\n- a\n\n## 0.2.0 — 2026-10-30\n") == "0.2.1")
        #expect(AppVersion.newestVersion(inChangelog: "## Earlier\n## 1.0.0 — x") == "1.0.0", "a heading that is no version is passed over")
        #expect(AppVersion.newestVersion(inChangelog: "no headings") == nil)
    }

    @Test("the text of the version")
    func text() {
        #expect(AppVersion.text.hasPrefix("Quilland ") && !AppVersion.short.isEmpty)
    }
}
