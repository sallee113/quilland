import Foundation

public struct CollectScene: Sendable {
    public var id: String
    public var title: String
    public var text: String
    public init(id: String, title: String, text: String) { self.id = id; self.title = title; self.text = text }
}

public struct CollectRequest: Sendable {
    public var kinds: Set<CollectKind>
    public var scenes: [CollectScene]
    /// The book's language code: the descriptions are written in it.
    public var language = ""
    public var knownCharacters: [String] = []
    public var knownPlaces: [String] = []
    /// Tokens the model reads at once: the pieces sent are cut to fit.
    public var context = LMStudioClient.defaultContext
    /// Fingerprints of the scenes already analysed (scene id to fingerprint); those that have not changed are skipped unless `reanalyse`.
    public var analysed: [String: String] = [:]
    public var reanalyse = false
    public init(kinds: Set<CollectKind>, scenes: [CollectScene]) { self.kinds = kinds; self.scenes = scenes }
}

public struct CollectProgress: Equatable, Sendable {
    public var scene: Int
    public var of: Int
    public var title: String
    public var found: Int
    /// Where the run is among all the pieces it will read (0 of 0 when it does not say).
    public var piece = 0
    public var pieces = 0
    public init(scene: Int, of: Int, title: String, found: Int, piece: Int = 0, pieces: Int = 0) { self.scene = scene; self.of = of; self.title = title; self.found = found; self.piece = piece; self.pieces = pieces }
}

public struct CollectSummary: Equatable, Sendable {
    public var scenesDone = 0
    public var scenesSkipped = 0
    /// Scenes too short to read (the model would invent a cast).
    public var scenesTooShort = 0
    public var droppedUnverified = 0
    public var failedPieces = 0
    public var stopped = false
    /// The fingerprints of the scenes that were read to the end, to be remembered.
    public var analysed: [String: String] = [:]
    /// The model could not be reached (the first piece failed that way): nothing was read.
    public var error: String?
}

public enum CollectJob {
    public static let minimumCharacters = 300

    /// A fingerprint of a scene's text and what was asked of it: the same scene, unchanged, asked the same, is not read again.
    public static func fingerprint(_ text: String, kinds: Set<CollectKind>) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in (text + "|" + kinds.map(\.rawValue).sorted().joined(separator: ",")).utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return String(hash, radix: 16)
    }

    /// How many characters of the passage may go in one request: the context less the instructions and the answer, at about two characters a token.
    public static func pieceSize(context: Int) -> Int { min(8000, max(1500, (context - 3500) * 2)) }

    /// Reads the scenes one after another. `found` gets each piece's findings as they come; stopping (cancelling the task) keeps what was found.
    public static func run(_ request: CollectRequest, client: LMStudioClient, progress: @Sendable (CollectProgress) -> Void, found: @Sendable ([CollectedItem]) -> Void) async -> CollectSummary {
        var summary = CollectSummary()
        var total = 0
        let size = pieceSize(context: request.context)
        let system = CollectPrompt.system(kinds: request.kinds, language: request.language)
        for (index, scene) in request.scenes.enumerated() {
            if Task.isCancelled { summary.stopped = true; break }
            let print = fingerprint(scene.text, kinds: request.kinds)
            if !request.reanalyse, request.analysed[scene.id] == print { summary.scenesSkipped += 1; continue }
            let prose = scene.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if prose.count < minimumCharacters { summary.scenesTooShort += 1; continue }
            progress(CollectProgress(scene: index + 1, of: request.scenes.count, title: scene.title, found: total))
            var sceneFailed = false
            for piece in CollectChunker.chunks(scene.text, maxCharacters: size) {
                if Task.isCancelled { summary.stopped = true; break }
                if piece.text.trimmingCharacters(in: .whitespacesAndNewlines).count < minimumCharacters / 2 { continue }
                let messages = [ChatMessage("system", system), ChatMessage("user", CollectPrompt.user(chunk: piece.text, sceneTitle: scene.title, knownCharacters: request.knownCharacters, knownPlaces: request.knownPlaces))]
                do {
                    let reply = try await client.chat(messages, think: false, temperature: AIPrompts.temperature("collect", default: 0.2), maxTokens: 2000)
                    let result = CollectParser.parse(reply, kinds: request.kinds, scene: scene.id, chunk: piece.text, chunkOffset: piece.offset)
                    summary.droppedUnverified += result.dropped
                    if result.malformed { summary.failedPieces += 1; sceneFailed = true }
                    if !result.items.isEmpty { total += result.items.count; found(result.items) }
                } catch {
                    if Task.isCancelled || error is CancellationError { summary.stopped = true; break }
                    if let e = error as? LLMError, e == .unreachable || e.description.contains("not found") { summary.error = e.description; return summary }
                    summary.failedPieces += 1; sceneFailed = true
                }
            }
            if summary.stopped { break }
            summary.scenesDone += 1
            if !sceneFailed { summary.analysed[scene.id] = print }
        }
        return summary
    }
}
