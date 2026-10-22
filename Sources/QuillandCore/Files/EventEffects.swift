import Foundation

/// What an event changes in a character, a place or a relationship (quilland-change-events.md): the fields that were filled in, by the id of what is changed, in the
/// event's own file (`effects`). Empty means no change; a field that is emptied is taken away. The name and the notes are never changed by events.
public enum EffectTarget: Sendable {
    case character, place, relationship

    /// The fields of a target that an event can change.
    public var fields: [EffectField] {
        switch self {
        case .character: return [.aliases, .main, .profile, .worlds]
        case .place: return [.description]
        case .relationship: return [.kind]
        }
    }
}

public enum EffectField: String, Sendable {
    /// New names (added to the card's, never taking one away).
    case aliases
    /// Becomes main (`true`) or stops being main (`false`).
    case main
    case profile
    /// Worlds the character now belongs to as well (ids).
    case worlds
    case description
    /// A relationship's kind.
    case kind

    /// Is the value a list (`aliases`, `worlds`), a flag (`main`) or a text?
    public var isList: Bool { self == .aliases || self == .worlds }
}

public extension EventRecord {
    /// The fields filled in for a target.
    func effect(of target: String) -> JSONObject { effects[target].flatMap { if case .object(let o) = $0 { return o } else { return nil } } ?? [:] }

    func effectText(_ field: EffectField, of target: String) -> String? { effect(of: target).string(field.rawValue) }
    func effectList(_ field: EffectField, of target: String) -> [String] { effect(of: target).strings(field.rawValue) ?? [] }
    func effectFlag(of target: String) -> Bool? { effect(of: target).bool(EffectField.main.rawValue) }

    /// How many fields an event fills in for a target.
    func effectCount(of target: String) -> Int { effect(of: target).count }

    /// Does the event change anything: an effect, or a relationship that starts, changes or ends in it?
    var changesSomething: Bool { !effects.isEmpty || !relationships.isEmpty }

    /// Sets a text field; an empty text takes the field away (and the target, when nothing is left).
    mutating func setEffect(_ field: EffectField, of target: String, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        update(target) { if clean.isEmpty { $0.removeValue(forKey: field.rawValue) } else { $0[field.rawValue] = .string(clean) } }
    }

    mutating func setEffect(_ field: EffectField, of target: String, list: [String]) {
        let clean = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        update(target) { if clean.isEmpty { $0.removeValue(forKey: field.rawValue) } else { $0[field.rawValue] = .array(clean.map { .string($0) }) } }
    }

    /// `nil` means no change.
    mutating func setEffectFlag(of target: String, _ value: Bool?) {
        update(target) { if let value { $0[EffectField.main.rawValue] = .bool(value) } else { $0.removeValue(forKey: EffectField.main.rawValue) } }
    }

    private mutating func update(_ target: String, _ change: (inout JSONObject) -> Void) {
        var all = effects
        var one = effect(of: target)
        change(&one)
        if one.isEmpty { all.removeValue(forKey: target) } else { all[target] = .object(one) }
        effects = all
    }
}
