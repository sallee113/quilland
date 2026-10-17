import Foundation

/// One reminder: a line of text the author wants to remember, and whether it is done.
public struct Reminder: Equatable, Sendable {
    public var id: String
    public var text: String
    public var done: Bool
    public var created: String
    public var doneAt: String?

    var json: JSONValue {
        var o: JSONObject = ["id": .string(id), "text": .string(text), "created": .string(created)]
        if done { o["done"] = .bool(true) }
        if let doneAt, done { o["done_at"] = .string(doneAt) }
        return .object(o)
    }

    init?(_ o: JSONObject) {
        guard let id = o.string("id"), let text = o.string("text") else { return nil }
        self.id = id; self.text = text
        done = o.bool("done") ?? false
        created = o.string("created") ?? ""
        doneAt = o.string("done_at")
    }

    init(id: String, text: String, created: String) { self.id = id; self.text = text; done = false; self.created = created; doneAt = nil }
}

/// The reminders of a book: `reminders.json` in the book's folder (a list, in the order they were made). They belong to the book, so they go with it through Git
/// and to another Mac. Unknown fields of the file are kept when it is written again.
public final class RemindersStore {
    public let book: URL
    public private(set) var reminders: [Reminder] = []
    public private(set) var problems: [String] = []
    private var rest: JSONObject = [:]
    /// What the last `delete` took out, for putting it back.
    public private(set) var lastDeleted: (reminder: Reminder, index: Int)?

    public init(book: URL) {
        self.book = book
        reload()
    }

    private var url: URL { book.appendingPathComponent("reminders.json") }

    public func reload() {
        reminders = []
        problems = []
        rest = [:]
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            var o = try JSONParser.parseObject(Data(contentsOf: url))
            for item in o.objects("reminders") ?? [] {
                if let r = Reminder(item) { reminders.append(r) } else { problems.append("reminders.json: an item has no id or text") }
            }
            o.removeValue(forKey: "reminders")
            rest = o
        } catch { problems.append("reminders.json: \(error)") }
    }

    /// The ones not yet done, in the order they were made.
    public var open: [Reminder] { reminders.filter { !$0.done } }
    public var done: [Reminder] { reminders.filter(\.done) }

    private static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    private func save() throws {
        var o = rest
        o["reminders"] = .array(reminders.map(\.json))
        try AtomicFile.write(JSONWriter.data(o), to: url)
    }

    @discardableResult
    public func add(_ text: String) throws -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let r = Reminder(id: UUID().uuidString.lowercased(), text: clean, created: Self.now())
        reminders.append(r)
        do { try save() } catch { reminders.removeLast(); throw error }
        return r.id
    }

    public func setText(_ id: String, _ text: String) throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = reminders.firstIndex(where: { $0.id == id }), reminders[i].text != clean else { return }
        let old = reminders[i]
        reminders[i].text = clean
        do { try save() } catch { reminders[i] = old; throw error }
    }

    public func setDone(_ id: String, _ done: Bool) throws {
        guard let i = reminders.firstIndex(where: { $0.id == id }), reminders[i].done != done else { return }
        let old = reminders[i]
        reminders[i].done = done
        reminders[i].doneAt = done ? Self.now() : nil
        do { try save() } catch { reminders[i] = old; throw error }
    }

    public func delete(_ id: String) throws {
        guard let i = reminders.firstIndex(where: { $0.id == id }) else { return }
        let old = reminders[i]
        reminders.remove(at: i)
        do { try save() } catch { reminders.insert(old, at: i); throw error }
        lastDeleted = (old, i)
    }

    /// Puts back what `delete` took out last, where it was.
    @discardableResult
    public func undoDelete() throws -> Bool {
        guard let (r, i) = lastDeleted else { return false }
        reminders.insert(r, at: min(i, reminders.count))
        do { try save() } catch { reminders.removeAll { $0.id == r.id }; throw error }
        lastDeleted = nil
        return true
    }
}
