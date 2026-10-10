import Foundation

/// Writing a file so that a crash, a power cut or a kill at any moment leaves
/// either the old whole file or the new whole file, never half of one.
///
/// The new content goes into a temporary file in the same folder, is flushed to
/// the disk, and then replaces the old file in one step (`rename`, which the file
/// system does atomically). A temporary file left behind by a crash is harmless
/// and is removed by `removeLeftovers`.
public enum AtomicFile {
    /// Where in a write a test may stop it (to simulate a crash).
    public enum Stage: Sendable {
        case tempCreated, tempHalfWritten, tempWritten, tempFlushed, renamed
    }

    public struct SimulatedCrash: Error {}

    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    static let suffix = ".quilland-tmp"

    public static func write(_ data: Data, to url: URL, hook: ((Stage) throws -> Void)? = nil) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString.lowercased())\(suffix)")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard fd >= 0 else { throw Failure(description: "cannot create \(temp.path): \(String(cString: strerror(errno)))") }
        var closed = false
        func closeOnce() { if !closed { close(fd); closed = true } }
        do {
            try hook?(.tempCreated)
            let half = data.count / 2
            try writeAll(fd, data.prefix(half))
            try hook?(.tempHalfWritten)
            try writeAll(fd, data.dropFirst(half))
            try hook?(.tempWritten)
            // On macOS fsync does not reach the platters; F_FULLFSYNC does.
            if fcntl(fd, F_FULLFSYNC) != 0 && fsync(fd) != 0 {
                throw Failure(description: "cannot flush \(temp.path): \(String(cString: strerror(errno)))")
            }
            try hook?(.tempFlushed)
            closeOnce()
            guard rename(temp.path, url.path) == 0 else {
                throw Failure(description: "cannot replace \(url.path): \(String(cString: strerror(errno)))")
            }
            try hook?(.renamed)
        } catch let crash as SimulatedCrash {
            closeOnce() // a real crash would leave the temp file; so does this
            throw crash
        } catch {
            closeOnce()
            unlink(temp.path)
            throw error
        }
        syncDirectory(directory)
    }

    private static func writeAll(_ fd: Int32, _ data: some DataProtocol) throws {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                throw Failure(description: "write failed: \(String(cString: strerror(errno)))")
            }
            offset += written
        }
    }

    private static func syncDirectory(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        if fd >= 0 {
            _ = fsync(fd)
            close(fd)
        }
    }

    /// Removes temporary files that a crash left in `directory`; returns what it removed.
    @discardableResult
    public static func removeLeftovers(in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var removed: [String] = []
        for name in names where name.hasPrefix(".") && name.hasSuffix(suffix) {
            if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))) != nil { removed.append(name) }
        }
        return removed.sorted()
    }
}
