import Foundation

/// A prompt the author saved from the Chat to use again: a name, the words, and what to attach to it each time (the scene, the characters found in it, the plan…).
/// Kept in `actions.json` in the settings folder; it appears in the AI menu.
public struct AIAction: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    /// What is attached when it runs, by the names `ChatMentions.attachment(for:)` knows: `scene`, `chapter`, `characters`, `places`, `events`, `plan`, `cards`, `synopses`.
    public var attach: [String]
    public init(id: String = UUID().uuidString.lowercased(), name: String, prompt: String, attach: [String] = []) { self.id = id; self.name = name; self.prompt = prompt; self.attach = attach }
}

public enum AIActions {
    static func url(_ directory: URL) -> URL { directory.appendingPathComponent("actions.json") }

    public static func load(directory: URL) -> [AIAction] {
        guard let data = try? Data(contentsOf: url(directory)), let o = try? JSONParser.parseObject(data) else { return [] }
        return (o.objects("actions") ?? []).compactMap { a in
            guard let id = a.string("id"), let name = a.string("name"), let prompt = a.string("prompt"), !name.isEmpty, !prompt.isEmpty else { return nil }
            return AIAction(id: id, name: name, prompt: prompt, attach: a.strings("attach") ?? [])
        }
    }

    public static func save(_ actions: [AIAction], directory: URL) throws {
        var o: JSONObject = (try? JSONParser.parseObject(Data(contentsOf: url(directory)))) ?? [:]
        o["format"] = .int(1)
        o["actions"] = .array(actions.map { a in
            var d: JSONObject = ["id": .string(a.id), "name": .string(a.name), "prompt": .string(a.prompt)]
            if !a.attach.isEmpty { d.setStrings("attach", a.attach) }
            return .object(d)
        })
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFile.write(JSONWriter.data(o), to: url(directory))
    }
}
