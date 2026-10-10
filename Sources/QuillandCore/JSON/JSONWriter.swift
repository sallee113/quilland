import Foundation

/// Writes the canonical form of a data file (quilland-format.md, section 2):
/// UTF-8 without a byte order mark, LF, two-space indentation, `"key": value`,
/// keys sorted by their UTF-8 bytes, one key per line and **one array element per
/// line** (so Git shows exactly the element that changed), `[]` and `{}` for empty
/// ones, letters written as themselves, only `"`, `\` and control characters escaped
/// (a slash is not), numbers as they were written, strings in NFC, one final newline.
public enum JSONWriter {
    public static func write(_ object: JSONObject) -> String {
        write(.object(object))
    }

    public static func write(_ value: JSONValue) -> String {
        var out = ""
        emit(value, indent: 0, into: &out)
        out.append("\n")
        return out
    }

    public static func data(_ object: JSONObject) -> Data { Data(write(object).utf8) }

    private static func emit(_ value: JSONValue, indent: Int, into out: inout String) {
        switch value {
        case .null: out.append("null")
        case .bool(let b): out.append(b ? "true" : "false")
        case .number(let n): out.append(n)
        case .string(let s): emitString(s, into: &out)
        case .array(let items):
            if items.isEmpty { out.append("[]"); return }
            out.append("[\n")
            let pad = String(repeating: " ", count: indent + 2)
            for (i, item) in items.enumerated() {
                out.append(pad)
                emit(item, indent: indent + 2, into: &out)
                out.append(i < items.count - 1 ? ",\n" : "\n")
            }
            out.append(String(repeating: " ", count: indent) + "]")
        case .object(let entries):
            if entries.isEmpty { out.append("{}"); return }
            out.append("{\n")
            let pad = String(repeating: " ", count: indent + 2)
            // Keys are made NFC and sorted by UTF-8 bytes (the same as by code point).
            let keys = entries.keys.map { ($0.precomposedStringWithCanonicalMapping, $0) }
                .sorted { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }
            for (i, (normalized, original)) in keys.enumerated() {
                out.append(pad)
                emitString(normalized, into: &out)
                out.append(": ")
                emit(entries[original]!, indent: indent + 2, into: &out)
                out.append(i < keys.count - 1 ? ",\n" : "\n")
            }
            out.append(String(repeating: " ", count: indent) + "}")
        }
    }

    private static func emitString(_ string: String, into out: inout String) {
        out.append("\"")
        var view = String.UnicodeScalarView()
        for scalar in string.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar {
            case "\"": view.append(contentsOf: "\\\"".unicodeScalars)
            case "\\": view.append(contentsOf: "\\\\".unicodeScalars)
            case "\n": view.append(contentsOf: "\\n".unicodeScalars)
            case "\r": view.append(contentsOf: "\\r".unicodeScalars)
            case "\t": view.append(contentsOf: "\\t".unicodeScalars)
            case "\u{08}": view.append(contentsOf: "\\b".unicodeScalars)
            case "\u{0C}": view.append(contentsOf: "\\f".unicodeScalars)
            default:
                if scalar.value < 0x20 {
                    view.append(contentsOf: String(format: "\\u%04x", scalar.value).unicodeScalars)
                } else {
                    view.append(scalar)
                }
            }
        }
        out.append(String(view))
        out.append("\"")
    }
}
