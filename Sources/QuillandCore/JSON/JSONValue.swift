import Foundation

/// A JSON value, kept exactly: a number stays as it was written (`1.50` is not `1.5`),
/// so reading and writing a file never changes what the app does not understand.
///
/// Every data file of a book is an object (quilland-format.md, section 2). The app
/// reads it into this tree, changes only the fields it knows, and writes the tree back:
/// a field it does not know, at any depth, is carried along untouched.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// The number as written; always a valid JSON number.
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public static func int(_ value: Int) -> JSONValue { .number(String(value)) }

    /// A decimal with at most `digits` digits after the point, without trailing zeros (0.2, not 0.20).
    public static func decimal(_ value: Double, digits: Int = 2) -> JSONValue {
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return .number(text == "-0" ? "0" : text)
    }
}

public typealias JSONObject = [String: JSONValue]

// MARK: Typed access to the fields of an object. Reading a field of the wrong type
// gives nil but never removes it; writing a field replaces only that field.

public extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        if case .string(let s)? = self[key] { return s }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case .number(let n)? = self[key] { return Int(n) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if case .bool(let b)? = self[key] { return b }
        return nil
    }

    /// The strings of an array; nil if the field is missing or not an array of strings.
    func strings(_ key: String) -> [String]? {
        guard case .array(let items)? = self[key] else { return nil }
        var out: [String] = []
        for item in items {
            guard case .string(let s) = item else { return nil }
            out.append(s)
        }
        return out
    }

    /// A map from strings to strings; nil if the field is missing or not such a map.
    func stringMap(_ key: String) -> [String: String]? {
        guard case .object(let entries)? = self[key] else { return nil }
        var out: [String: String] = [:]
        for (k, v) in entries {
            guard case .string(let s) = v else { return nil }
            out[k] = s
        }
        return out
    }

    func object(_ key: String) -> JSONObject? {
        if case .object(let o)? = self[key] { return o }
        return nil
    }

    func objects(_ key: String) -> [JSONObject]? {
        guard case .array(let items)? = self[key] else { return nil }
        var out: [JSONObject] = []
        for item in items {
            guard case .object(let o) = item else { return nil }
            out.append(o)
        }
        return out
    }

    // Setting nil, or an empty optional collection, removes the key: absent means "not set".

    mutating func setString(_ key: String, _ value: String?) {
        if let value { self[key] = .string(value) } else { removeValue(forKey: key) }
    }

    mutating func setInt(_ key: String, _ value: Int?) {
        if let value { self[key] = .int(value) } else { removeValue(forKey: key) }
    }

    mutating func setBool(_ key: String, _ value: Bool?) {
        if let value { self[key] = .bool(value) } else { removeValue(forKey: key) }
    }

    // An empty collection that is already in the file stays as it is (setting a field to
    // the value it has must not change the file); otherwise an empty one removes the key.

    mutating func setStrings(_ key: String, _ values: [String]) {
        if values.isEmpty {
            if case .array(let a)? = self[key], a.isEmpty { return }
            removeValue(forKey: key)
        } else {
            self[key] = .array(values.map { .string($0) })
        }
    }

    mutating func setStringMap(_ key: String, _ values: [String: String]) {
        if values.isEmpty {
            if case .object(let o)? = self[key], o.isEmpty { return }
            removeValue(forKey: key)
        } else {
            self[key] = .object(values.mapValues { .string($0) })
        }
    }

    mutating func setObjects(_ key: String, _ values: [JSONObject]) {
        if values.isEmpty {
            if case .array(let a)? = self[key], a.isEmpty { return }
            removeValue(forKey: key)
        } else {
            self[key] = .array(values.map { .object($0) })
        }
    }
}
