import Foundation
import QuillandCore

// Usage: StressWriter <file>
// Rewrites <file> again and again (about 400 KB each time) until it is killed.
// Each version is a JSON object { "n": counter, "payload": <text made from n> }, so
// a reader can tell a whole version from a damaged one. Prints "ready" after the first write.
let path = CommandLine.arguments.dropFirst().first ?? "stress.json"
let url = URL(fileURLWithPath: path)
var n = 0
while true {
    n += 1
    let payload = String(repeating: "x\(n)-", count: 40_000)
    let object: JSONObject = ["n": .int(n), "payload": .string(payload)]
    do {
        try AtomicFile.write(JSONWriter.data(object), to: url)
    } catch {
        FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        exit(1)
    }
    if n == 1 {
        print("ready")
        fflush(stdout)
    }
}
