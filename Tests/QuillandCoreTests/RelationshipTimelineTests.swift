import Foundation
import Testing
@testable import QuillandCore

@Suite("What events change, and when the relationships are active")
struct RelationshipTimelineTests {
    struct Fixture {
        let parent: URL, book: URL
        let start: String, e1: String, e2: String, e3: String, noScene: String
        let rel: String
        let timeline: RelationshipTimeline
    }

    /// Events in the order of the book: Book starts, e1 (scene 1), e2 (scene 2), e3 (scene 3), and one with no scene.
    static func fixture(setup: (EventStore, String, String, String, String, String) throws -> Void = { _, _, _, _, _, _ in }) throws -> Fixture {
        let parent = try NewBookTests.folder()
        let book = try BookCreator.create(NewBookRequest(title: "Дом", language: "ru", parentFolder: parent))
        let events = EventStore(book: book)
        let start = try #require(events.startEvent?.id)
        let e1 = try events.add(title: "Один"), e2 = try events.add(title: "Два"), e3 = try events.add(title: "Три"), no = try events.add(title: "Без сцены")
        try events.update(e1) { $0.links = ["s1": ""] }
        try events.update(e2) { $0.links = ["s2": ""] }
        try events.update(e3) { $0.links = ["s3": ""] }
        let people = CharacterStore(book: book)
        let a = try people.add(name: "А"), b = try people.add(name: "Б")
        let rel = try RelationshipStore(book: book).add(characters: [a, b], kind: "друзья")
        try setup(events, start, e1, e2, e3, rel)
        let fresh = EventStore(book: book)
        return Fixture(parent: parent, book: book, start: start, e1: e1, e2: e2, e3: e3, noScene: no, rel: rel, timeline: RelationshipTimeline(events: fresh, sceneOrder: ["s1", "s2", "s3"]))
    }

    @Test("an event's effects are kept by field, empty means no change, and the name and the notes are not fields")
    func effects() throws {
        let f = try Self.fixture(); defer { try? FileManager.default.removeItem(at: f.parent) }
        let events = EventStore(book: f.book)
        try events.update(f.e1) { r in
            r.setEffect(.profile, of: "анна", text: "  Теперь капитан.  ")
            r.setEffect(.aliases, of: "анна", list: ["Вильгельм", " ", "Билл"])
            r.setEffectFlag(of: "анна", true)
            r.setEffect(.description, of: "дом", text: "Сгорел.")
        }
        let e = try #require(EventStore(book: f.book).event(f.e1))
        #expect(e.effectText(.profile, of: "анна") == "Теперь капитан." && e.effectList(.aliases, of: "анна") == ["Вильгельм", "Билл"] && e.effectFlag(of: "анна") == true)
        #expect(e.effectCount(of: "анна") == 3 && e.effectCount(of: "дом") == 1 && e.changesSomething)
        #expect(EffectTarget.character.fields == [.aliases, .main, .profile, .worlds] && EffectTarget.place.fields == [.description] && EffectTarget.relationship.fields == [.kind])
        try events.update(f.e1) { r in
            r.setEffect(.profile, of: "анна", text: "   ")
            r.setEffect(.aliases, of: "анна", list: [])
            r.setEffectFlag(of: "анна", nil)
            r.setEffect(.description, of: "дом", text: "")
        }
        let cleared = try #require(EventStore(book: f.book).event(f.e1))
        #expect(cleared.effects.isEmpty && !cleared.changesSomething && cleared.object["effects"] == nil, "emptied fields leave nothing behind")
    }

    @Test("a relationship starts at an event, is active from it until the event that ends it, and the default event is first")
    func active() throws {
        let f = try Self.fixture { events, start, e1, e2, e3, rel in
            try events.update(e1) { $0.relationships = [rel: "starts"] }
            try events.update(e3) { $0.relationships = [rel: "ends"] }
            _ = start; _ = e2
        }
        defer { try? FileManager.default.removeItem(at: f.parent) }
        let t = f.timeline
        #expect(t.order(of: f.start) == -1 && t.order(of: f.e1) == 0 && t.order(of: f.noScene) == nil)
        #expect(!t.isActive(f.rel, at: f.start), "not before it starts")
        #expect(t.isActive(f.rel, at: f.e1) && t.isActive(f.rel, at: f.e2) && t.isActive(f.rel, at: f.e3), "active from its start through the event that ends it")
        #expect(t.active(at: f.e2, among: [f.rel]) == [f.rel] && !t.isActive(f.rel, at: f.noScene), "an event with no scene has no place")
        let m = t.marks(of: f.rel)
        #expect(m.start == f.e1 && m.end == f.e3 && m.changes.isEmpty)
    }

    @Test("a relationship that is only stated starts at Book starts and is active everywhere")
    func startsAtBookStarts() throws {
        let f = try Self.fixture { events, start, _, _, _, rel in try events.update(start) { $0.relationships = [rel: "starts"] } }
        defer { try? FileManager.default.removeItem(at: f.parent) }
        #expect(f.timeline.isActive(f.rel, at: f.start) && f.timeline.isActive(f.rel, at: f.e1) && f.timeline.isActive(f.rel, at: f.e3))
    }

    @Test("an order that would break is refused, and the event in the way is named")
    func refused() throws {
        // Starts at e1, changes at e2, ends at e3.
        let f = try Self.fixture { events, _, e1, e2, e3, rel in
            try events.update(e1) { $0.relationships = [rel: "starts"] }
            try events.update(e2) { $0.effects = [rel: .object(["kind": .string("враги")])] }
            try events.update(e3) { $0.relationships = [rel: "ends"] }
        }
        defer { try? FileManager.default.removeItem(at: f.parent) }
        let t = f.timeline
        #expect(t.problem(starting: f.rel, at: f.start) == nil, "it may start earlier, at Book starts")
        #expect(t.problem(starting: f.rel, at: f.e3) == .startsAfterEnd(eventTitle: "Три"), "not at the event that ends it")
        #expect(t.problem(starting: f.rel, at: f.e2) == nil, "at the event of its change is fine")
        #expect(t.problem(starting: f.rel, at: f.noScene) == .noScene)
        #expect(t.problem(ending: f.rel, at: f.e1) == .endsWhereItStarts, "not where it starts")
        #expect(t.problem(ending: f.rel, at: f.start) == .endsBeforeStart(eventTitle: "Один"), "not before it starts")
        #expect(t.problem(ending: f.rel, at: f.e2) == nil && t.problem(ending: f.rel, at: f.noScene) == .noScene)
        #expect(t.problem(changing: f.rel, at: f.start) == .endsBeforeStart(eventTitle: "Один"), "nor change before its start")
        #expect(t.problem(changing: f.rel, at: f.e1) == nil && t.problem(changing: f.rel, at: f.e3) == nil)
        #expect(t.broken(f.rel).isEmpty)
    }

    @Test("an order that was broken later (scenes moved) is reported, and the calculation does not fail")
    func broken() throws {
        // Ends at e1, starts at e3, changes at e2 and at an event with no scene.
        let f = try Self.fixture { events, _, e1, e2, e3, rel in
            try events.update(e1) { $0.relationships = [rel: "ends"] }
            try events.update(e3) { $0.relationships = [rel: "starts"] }
            try events.update(e2) { $0.effects = [rel: .object(["kind": .string("враги")])] }
        }
        defer { try? FileManager.default.removeItem(at: f.parent) }
        let problems = f.timeline.broken(f.rel)
        #expect(problems.contains(.endsBeforeStart(eventTitle: "Один")) && problems.contains(.startsAfterChange(eventTitle: "Два")), "\(problems)")
        #expect(!f.timeline.isActive(f.rel, at: f.e1), "(the start is after, so it is not active)")
        let noScene = try Self.fixture { events, _, _, _, e3, rel in
            try events.update(e3) { $0.relationships = [rel: "starts"] }
        }
        defer { try? FileManager.default.removeItem(at: noScene.parent) }
        let events = EventStore(book: noScene.book)
        try events.update(noScene.noScene) { $0.effects = [noScene.rel: .object(["kind": .string("x")])] }
        let t2 = RelationshipTimeline(events: EventStore(book: noScene.book), sceneOrder: ["s1", "s2", "s3"])
        #expect(t2.broken(noScene.rel).contains(.noScene), "a change in an event with no scene is flagged")
    }
}
