import Foundation
import Testing
@testable import QuillandCore

private final class BundleToken {}

/// Experiment 2: a crash during a write never leaves half a file.
@Suite("Atomic writes", .serialized)
struct AtomicFileTests {
    static func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a write replaces the file")
    func plainWrite() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.json")
        try AtomicFile.write(Data("old".utf8), to: file)
        try AtomicFile.write(Data("new content".utf8), to: file)
        #expect(try Data(contentsOf: file) == Data("new content".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a.json"], "no temporary file is left")
    }

    @Test("a crash at any stage leaves the old whole file or the new whole file")
    func crashAtEveryStage() throws {
        let stages: [AtomicFile.Stage] = [.tempCreated, .tempHalfWritten, .tempWritten, .tempFlushed, .renamed]
        let old = Data(String(repeating: "OLD", count: 5000).utf8)
        let new = Data(String(repeating: "NEW", count: 7000).utf8)
        for stage in stages {
            let folder = try Self.makeFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appendingPathComponent("a.json")
            try old.write(to: file)
            #expect(throws: AtomicFile.SimulatedCrash.self) {
                try AtomicFile.write(new, to: file) { reached in if reached == stage { throw AtomicFile.SimulatedCrash() } }
            }
            let now = try Data(contentsOf: file)
            if stage == .renamed {
                #expect(now == new, "after the rename the new file is whole")
            } else {
                #expect(now == old, "before the rename the old file is untouched (stage \(stage))")
            }
            // The leftovers of the crash are only temporary files, and they can be removed.
            let leftovers = AtomicFile.removeLeftovers(in: folder)
            #expect(leftovers.count == (stage == .renamed ? 0 : 1), "\(stage): \(leftovers)")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a.json"])
        }
    }

    @Test("a crash while creating a file leaves no file, not half of one")
    func crashOnNewFile() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("new.json")
        #expect(throws: AtomicFile.SimulatedCrash.self) {
            try AtomicFile.write(Data("content".utf8), to: file) { if $0 == .tempHalfWritten { throw AtomicFile.SimulatedCrash() } }
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("an ordinary error cleans up after itself and keeps the old file")
    func ordinaryError() throws {
        struct Boom: Error {}
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.json")
        try Data("old".utf8).write(to: file)
        #expect(throws: Boom.self) {
            try AtomicFile.write(Data("new".utf8), to: file) { if $0 == .tempWritten { throw Boom() } }
        }
        #expect(try Data(contentsOf: file) == Data("old".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["a.json"])
    }

    // MARK: A real process, killed for real

    static func stressWriterURL() -> URL {
        Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent().appendingPathComponent("StressWriter")
    }

    /// The file is a whole version: valid JSON whose payload matches its counter.
    static func isWholeVersion(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let object = try? JSONParser.parseObject(data),
              let n = object.int("n"), let payload = object.string("payload") else { return false }
        return payload == String(repeating: "x\(n)-", count: 40_000)
    }

    @Test("a process killed with kill -9 at random moments never leaves a damaged file")
    func killedWriter() throws {
        let executable = Self.stressWriterURL()
        #expect(FileManager.default.isExecutableFile(atPath: executable.path), "StressWriter was not built: \(executable.path)")
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("stress.json")

        var rng = SplitMix64(seed: 7)
        var damaged = 0
        var killedMidWrite = 0
        let rounds = 150
        for round in 0..<rounds {
            let process = Process()
            process.executableURL = executable
            process.arguments = [file.path]
            let out = Pipe()
            process.standardOutput = out
            try process.run()
            // Wait until the first version is in place (its first line is "ready").
            var seen = Data()
            while !String(decoding: seen, as: UTF8.self).contains("ready") {
                let chunk = out.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                seen.append(chunk)
            }
            usleep(UInt32.random(in: 0...40_000, using: &rng))
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            if !Self.isWholeVersion(file) {
                damaged += 1
                Issue.record("round \(round): the file is damaged after the kill")
            }
            let leftovers = AtomicFile.removeLeftovers(in: folder)
            if !leftovers.isEmpty { killedMidWrite += 1 }
        }
        print("KILL TEST: \(rounds) kills, \(killedMidWrite) of them in the middle of a write (a temporary file was left), \(damaged) damaged files")
        #expect(damaged == 0)
        #expect(killedMidWrite > 10, "the test must really hit the middle of writes")
    }

    @Test("a reader never sees half a file while another process keeps rewriting it")
    func concurrentReader() throws {
        let executable = Self.stressWriterURL()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("stress.json")
        let process = Process()
        process.executableURL = executable
        process.arguments = [file.path]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        defer {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        var seen = Data()
        while !String(decoding: seen, as: UTF8.self).contains("ready") {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            seen.append(chunk)
        }
        var reads = 0
        var bad = 0
        var versions = Set<Int>()
        let until = Date().addingTimeInterval(3)
        while Date() < until {
            reads += 1
            if let data = try? Data(contentsOf: file), let object = try? JSONParser.parseObject(data), let n = object.int("n"),
               object.string("payload") == String(repeating: "x\(n)-", count: 40_000) {
                versions.insert(n)
            } else {
                bad += 1
            }
        }
        print("READER TEST: \(reads) reads of a file being rewritten, \(versions.count) different versions seen, \(bad) damaged")
        #expect(bad == 0)
        #expect(versions.count > 5, "the writer must really have rewritten the file meanwhile")
    }
}
