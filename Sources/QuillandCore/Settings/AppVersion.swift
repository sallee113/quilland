import Foundation

/// The version of the application and the changelog that goes with it. In the packaged application they are in its Info.plist and its Resources (`make-app.sh` puts them
/// there); run from the build folder, they are found in the repository (`VERSION`, `CHANGELOG.md`) above the executable.
public enum AppVersion {
    /// A file shipped with the application: in the bundle's Resources, or the one of the repository above the executable.
    public static func file(_ name: String) -> URL? {
        let fm = FileManager.default
        if let url = Bundle.main.resourceURL?.appendingPathComponent(name), fm.fileExists(atPath: url.path) { return url }
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let d = dir else { break }
            let url = d.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path), fm.fileExists(atPath: d.appendingPathComponent("Package.swift").path) { return url }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    /// `0.1.0`: from the Info.plist, else from the VERSION file, else "dev".
    public static var short: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !v.isEmpty { return v }
        if let url = file("VERSION"), let text = try? String(contentsOf: url, encoding: .utf8) {
            let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        return "dev"
    }

    /// The build number (the number of commits), when the application is packaged.
    public static var build: String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "" }

    /// `Quilland 0.1.0 (build 94)`.
    public static var text: String { "Quilland " + short + (build.isEmpty ? "" : " (build \(build))") }

    /// The changelog, or nil when this build has none.
    public static var changelog: String? { file("CHANGELOG.md").flatMap { try? String(contentsOf: $0, encoding: .utf8) } }

    /// The version a changelog text is at the top of: the first `## X.Y.Z` heading.
    public static func newestVersion(inChangelog text: String) -> String? {
        for line in text.split(separator: "\n") where line.hasPrefix("## ") {
            let rest = line.dropFirst(3)
            if let first = rest.split(separator: " ").first, first.split(separator: ".").count == 3, first.allSatisfy({ $0.isNumber || $0 == "." }) { return String(first) }
        }
        return nil
    }
}
