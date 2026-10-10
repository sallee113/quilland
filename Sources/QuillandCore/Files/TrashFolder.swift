import Foundation

/// The trash folder of a book: `.quilland/trash/<name>/`. Every removal gets a folder of its own, so two removals in the same second
/// (merging three scenes in a row, say) never meet in one folder and never collide on a file name.
public enum TrashFolder {
    /// A new, unique name: the time to the millisecond, then a short random tail.
    public static func newName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH-mm-ss-SSS'Z'"
        return f.string(from: Date()) + "-" + String(UUID().uuidString.lowercased().prefix(4))
    }
}
