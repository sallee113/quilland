import Foundation
import Testing
@testable import QuillandCore

/// Experiment 2: the typed records change the fields they know, and carry along
/// every field they do not know, at any depth.
@Suite("Records keep what they do not know")
struct RecordTests {
    static func load(_ name: String) throws -> (text: String, object: JSONObject) {
        let url = Corpus.files("json/canonical", suffix: "\(name).json")[0]
        let text = Corpus.read(url)
        return (text, try JSONParser.parseObject(Data(text.utf8)))
    }

    /// Lines removed and added between two texts: what a line-based diff (Git) would show.
    static func lineDiff(_ a: String, _ b: String) -> (removed: Int, added: Int) {
        let x = a.components(separatedBy: "\n")
        let y = b.components(separatedBy: "\n")
        // Longest common subsequence of lines.
        var table = [[Int]](repeating: [Int](repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                table[i][j] = x[i] == y[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return (x.count - table[0][0], y.count - table[0][0])
    }

    @Test("assigning a field the value it already has changes nothing, in every corpus file")
    func noOpEdits() throws {
        var failures: [String] = []
        for url in Corpus.files("json/canonical", suffix: ".json") {
            let text = Corpus.read(url)
            var object = try JSONParser.parseObject(Data(text.utf8))
            switch url.lastPathComponent.prefix(2) {
            case "01", "02", "03", "14":
                var r = SceneRecord(object: object)
                r.id = r.id; r.title = r.title; r.status = r.status; r.synopsis = r.synopsis; r.note = r.note
                r.tags = r.tags; r.targetCharacters = r.targetCharacters
                object = r.object
            case "04", "05", "06", "07", "08":
                var r = CharacterRecord(object: object)
                r.id = r.id; r.name = r.name; r.aliases = r.aliases; r.notes = r.notes; r.povScenes = r.povScenes
                r.worlds = r.worlds; r.links = r.links; r.images = r.images
                object = r.object
            case "09":
                var t = TimelineFile(object: object)
                t.entries = t.entries
                t.lanes = t.lanes
                object = t.object
            case "12":
                var e = ExportFile(object: object)
                e.profiles = e.profiles
                object = e.object
            default:
                break
            }
            let out = JSONWriter.write(object)
            if out != text { failures.append("\(url.lastPathComponent): \(describeDifference(text, out))") }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test("a scene: changing the title changes one line; unknown fields stay")
    func sceneEdits() throws {
        let (text, object) = try Self.load("01-scene")
        var scene = SceneRecord(object: object)
        scene.title = "In the cellar"
        let after = JSONWriter.write(scene.object)
        #expect(Self.lineDiff(text, after) == (1, 1))
        #expect(scene.object["x_future"] == object["x_future"])
        #expect(scene.object["x_future_color"] == object["x_future_color"])

        scene.status = "revised"
        scene.targetCharacters = 9000
        #expect(Self.lineDiff(after, JSONWriter.write(scene.object)) == (2, 2))

        scene.tags.append("rain")
        #expect(scene.tags == ["flashback", "night", "rain"])
        scene.tags = []
        #expect(scene.object["tags"] == nil, "an emptied optional list leaves no trace")
        scene.note = nil
        #expect(scene.object["note"] == nil)
        #expect(scene.object["x_future"] == object["x_future"])
        #expect(scene.problems.isEmpty)
    }

    @Test("an unknown status, wrong kinds of value and missing fields are reported and never changed")
    func damagedButKept() throws {
        let weird = #"{"id": 5, "status": "waiting", "tags": ["a", 2], "target_characters": "many", "title": ["x"], "x_keep": {"k": [true]}}"#
        let object = try JSONParser.parseObject(Data(weird.utf8))
        var scene = SceneRecord(object: object)
        #expect(scene.id == nil && scene.title == nil && scene.targetCharacters == nil)
        #expect(scene.tags == [], "a list with a non-string reads as empty")
        #expect(scene.status == "waiting")
        let problems = scene.problems
        #expect(problems.contains("\"id\" has the wrong kind of value"))
        #expect(problems.contains("\"title\" has the wrong kind of value"))
        #expect(problems.contains("unknown status \"waiting\" (kept)"))
        #expect(problems.count == 5, "\(problems)")
        // Touching one field leaves the others, wrong or not, as they were.
        scene.synopsis = "New text"
        var expected = object
        expected["synopsis"] = .string("New text")
        #expect(scene.object == expected)

        let missing = SceneRecord(object: ["x": .int(1)])
        #expect(missing.problems == ["\"id\" is missing", "\"title\" is missing"])
    }

    @Test("a character: adding and removing a link changes only its own lines")
    func characterEdits() throws {
        let (text, object) = try Self.load("04-character")
        var character = CharacterRecord(object: object)
        #expect(character.problems.isEmpty)
        #expect(character.main)
        #expect(character.links.count == 3)
        let newTarget = "ffffffff-0000-4000-8000-000000000001"
        character.links[newTarget] = "Wears her mother's ring."
        let added = JSONWriter.write(character.object)
        #expect(Self.lineDiff(text, added).removed <= 1)
        #expect(Self.lineDiff(text, added).added <= 2)
        #expect(added.contains(newTarget))
        character.links.removeValue(forKey: newTarget)
        #expect(JSONWriter.write(character.object) == text, "adding and removing again leaves no trace")
        #expect(character.object["x_future"] == object["x_future"])
    }

    @Test("the timeline: dragging one event changes its entry only; unknown fields in other entries stay")
    func timelineEdits() throws {
        let (text, object) = try Self.load("09-timeline")
        var timeline = TimelineFile(object: object)
        #expect(timeline.problems.isEmpty)
        let event = timeline.entries[0].event!
        timeline.move(event: event, toStart: 120, end: 570)
        let after = JSONWriter.write(timeline.object)
        #expect(Self.lineDiff(text, after) == (2, 2), "the start and the end of one entry")
        #expect(timeline.entries[0].object["x_pinned"] == .bool(true))
        #expect(timeline.entries[2].object["x_future"] == .object(["a": .null]))
        #expect(Array(timeline.entries.dropFirst()) == Array(TimelineFile(object: object).entries.dropFirst()), "the other entries are untouched")
        timeline.move(event: event, toStart: 100, end: 550)
        #expect(JSONWriter.write(timeline.object) == text)
    }

    @Test("an end before the start is reported")
    func timelineProblems() {
        let object: JSONObject = ["entries": .array([.object(["end": .int(5), "event": .string("e"), "lane": .string("l"), "start": .int(9)])])]
        #expect(TimelineFile(object: object).problems == ["entry 0: the end is before the start"])
    }

    @Test("export profiles: changing a heading rule keeps the unknown keys around it")
    func exportEdits() throws {
        let (text, object) = try Self.load("12-export")
        var file = ExportFile(object: object)
        var profile = file.profiles[0]
        #expect(profile.headingRule("chapter") == ExportFile.HeadingRule(print: "number_and_title", template: "Chapter {number}. {title}", newPage: true))
        profile.setHeadingRule("chapter", ExportFile.HeadingRule(print: "title", template: nil, newPage: true))
        var profiles = file.profiles
        profiles[0] = profile
        file.profiles = profiles
        let after = JSONWriter.write(file.object)
        #expect(after.contains("\"x_font\": \"serif\""), "a key inside the rule that the app does not know")
        #expect(after.contains("\"x_layout\""), "a key of the profile that the app does not know")
        #expect(!after.contains("Chapter {number}"))
        #expect(Self.lineDiff(text, after) == (2, 1))
        // And back.
        profile.setHeadingRule("chapter", ExportFile.HeadingRule(print: "number_and_title", template: "Chapter {number}. {title}", newPage: true))
        profiles[0] = profile
        file.profiles = profiles
        #expect(JSONWriter.write(file.object) == text)
    }

    @Test("every record type in the corpus reads without problems")
    func corpusIsValid() throws {
        for name in ["01-scene", "02-scene-minimal", "03-scene-text-escapes", "14-title-page"] {
            #expect(SceneRecord(object: try Self.load(name).object).problems.isEmpty, "\(name)")
        }
        for name in ["04-character", "05-world", "06-place"] {
            #expect(CharacterRecord(object: try Self.load(name).object).problems.isEmpty, "\(name)")
        }
        #expect(TimelineFile(object: try Self.load("09-timeline").object).problems.isEmpty)
    }
}
