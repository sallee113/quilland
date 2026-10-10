import Foundation

public struct JSONError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var line: Int
    public var column: Int
    public var description: String { "\(message) (line \(line), column \(column))" }
}

/// A strict JSON reader (RFC 8259). It refuses what a careless reader would accept
/// or silently repair: trailing commas, comments, single quotes, leading zeros,
/// control characters in strings, lone surrogates, duplicate keys. A refused file
/// is never overwritten; the app reports it instead.
///
/// Strings and keys are made NFC when read. A leading byte order mark is skipped.
public enum JSONParser {
    public static let maxDepth = 100

    /// The file's top-level value, which must be an object.
    public static func parseObject(_ data: Data) throws -> JSONObject {
        var parser = Parser(bytes: [UInt8](data))
        let value = try parser.parseDocument()
        guard case .object(let object) = value else {
            throw parser.error("the top level must be an object", at: 0)
        }
        return object
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        var parser = Parser(bytes: [UInt8](data))
        return try parser.parseDocument()
    }

    public static func parse(_ text: String) throws -> JSONValue { try parse(Data(text.utf8)) }

    private struct Parser {
        let bytes: [UInt8]
        var pos = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { pos = 3 }
        }

        func error(_ message: String, at offset: Int) -> JSONError {
            var line = 1
            var column = 1
            for byte in bytes[..<min(offset, bytes.count)] {
                if byte == 0x0A { line += 1; column = 1 } else if byte & 0xC0 != 0x80 { column += 1 }
            }
            return JSONError(message: message, line: line, column: column)
        }

        mutating func parseDocument() throws -> JSONValue {
            skipWhitespace()
            let value = try parseValue(depth: 0)
            skipWhitespace()
            if pos < bytes.count { throw error("unexpected content after the value", at: pos) }
            return value
        }

        mutating func skipWhitespace() {
            while pos < bytes.count, bytes[pos] == 0x20 || bytes[pos] == 0x09 || bytes[pos] == 0x0A || bytes[pos] == 0x0D { pos += 1 }
        }

        mutating func parseValue(depth: Int) throws -> JSONValue {
            guard depth <= JSONParser.maxDepth else { throw error("nested too deeply", at: pos) }
            guard pos < bytes.count else { throw error("the text ends too early", at: pos) }
            switch bytes[pos] {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
            default: throw error("unexpected character", at: pos)
            }
        }

        mutating func expect(_ word: String) throws {
            let letters = Array(word.utf8)
            guard bytes.count - pos >= letters.count, Array(bytes[pos..<(pos + letters.count)]) == letters else {
                throw error("unexpected character", at: pos)
            }
            pos += letters.count
        }

        mutating func parseObject(depth: Int) throws -> JSONValue {
            pos += 1
            var object: [String: JSONValue] = [:]
            skipWhitespace()
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "}") {
                pos += 1
                return .object(object)
            }
            while true {
                skipWhitespace()
                guard pos < bytes.count, bytes[pos] == UInt8(ascii: "\"") else { throw error("a key in quotes was expected", at: pos) }
                let keyStart = pos
                let key = try parseString()
                skipWhitespace()
                guard pos < bytes.count, bytes[pos] == UInt8(ascii: ":") else { throw error("a colon was expected", at: pos) }
                pos += 1
                skipWhitespace()
                let value = try parseValue(depth: depth + 1)
                if object[key] != nil { throw error("the key \"\(key)\" appears twice", at: keyStart) }
                object[key] = value
                skipWhitespace()
                guard pos < bytes.count else { throw error("the text ends too early", at: pos) }
                if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
                if bytes[pos] == UInt8(ascii: "}") { pos += 1; return .object(object) }
                throw error("a comma or a closing brace was expected", at: pos)
            }
        }

        mutating func parseArray(depth: Int) throws -> JSONValue {
            pos += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "]") {
                pos += 1
                return .array(items)
            }
            while true {
                skipWhitespace()
                items.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                guard pos < bytes.count else { throw error("the text ends too early", at: pos) }
                if bytes[pos] == UInt8(ascii: ",") { pos += 1; continue }
                if bytes[pos] == UInt8(ascii: "]") { pos += 1; return .array(items) }
                throw error("a comma or a closing bracket was expected", at: pos)
            }
        }

        mutating func parseNumber() throws -> JSONValue {
            let start = pos
            if bytes[pos] == UInt8(ascii: "-") { pos += 1 }
            guard pos < bytes.count, isDigit(bytes[pos]) else { throw error("a digit was expected", at: pos) }
            if bytes[pos] == UInt8(ascii: "0") {
                pos += 1
                if pos < bytes.count, isDigit(bytes[pos]) { throw error("a number may not start with a zero", at: pos) }
            } else {
                while pos < bytes.count, isDigit(bytes[pos]) { pos += 1 }
            }
            if pos < bytes.count, bytes[pos] == UInt8(ascii: ".") {
                pos += 1
                guard pos < bytes.count, isDigit(bytes[pos]) else { throw error("a digit was expected after the point", at: pos) }
                while pos < bytes.count, isDigit(bytes[pos]) { pos += 1 }
            }
            if pos < bytes.count, bytes[pos] == UInt8(ascii: "e") || bytes[pos] == UInt8(ascii: "E") {
                pos += 1
                if pos < bytes.count, bytes[pos] == UInt8(ascii: "+") || bytes[pos] == UInt8(ascii: "-") { pos += 1 }
                guard pos < bytes.count, isDigit(bytes[pos]) else { throw error("a digit was expected in the exponent", at: pos) }
                while pos < bytes.count, isDigit(bytes[pos]) { pos += 1 }
            }
            return .number(String(decoding: bytes[start..<pos], as: UTF8.self))
        }

        func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }

        mutating func parseString() throws -> String {
            let start = pos
            pos += 1
            var out: [UInt8] = []
            while true {
                guard pos < bytes.count else { throw error("the string is not closed", at: start) }
                let b = bytes[pos]
                switch b {
                case UInt8(ascii: "\""):
                    pos += 1
                    guard let text = String(bytes: out, encoding: .utf8) else { throw error("the string is not valid UTF-8", at: start) }
                    return text.precomposedStringWithCanonicalMapping
                case UInt8(ascii: "\\"):
                    pos += 1
                    guard pos < bytes.count else { throw error("the string is not closed", at: start) }
                    switch bytes[pos] {
                    case UInt8(ascii: "\""): out.append(0x22)
                    case UInt8(ascii: "\\"): out.append(0x5C)
                    case UInt8(ascii: "/"): out.append(0x2F)
                    case UInt8(ascii: "b"): out.append(0x08)
                    case UInt8(ascii: "f"): out.append(0x0C)
                    case UInt8(ascii: "n"): out.append(0x0A)
                    case UInt8(ascii: "r"): out.append(0x0D)
                    case UInt8(ascii: "t"): out.append(0x09)
                    case UInt8(ascii: "u"):
                        pos += 1
                        var unit = try hex4()
                        if (0xD800...0xDBFF).contains(unit) {
                            guard pos + 1 < bytes.count, bytes[pos] == UInt8(ascii: "\\"), bytes[pos + 1] == UInt8(ascii: "u") else {
                                throw error("a lone surrogate", at: pos)
                            }
                            pos += 2
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw error("a lone surrogate", at: pos) }
                            unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        } else if (0xDC00...0xDFFF).contains(unit) {
                            throw error("a lone surrogate", at: pos)
                        }
                        guard let scalar = Unicode.Scalar(unit) else { throw error("not a character", at: pos) }
                        out.append(contentsOf: Array(String(Character(scalar)).utf8))
                        continue // hex4 already moved past the digits
                    default:
                        throw error("an unknown escape", at: pos)
                    }
                    pos += 1
                case 0x00..<0x20:
                    throw error("a control character in a string must be escaped", at: pos)
                default:
                    out.append(b)
                    pos += 1
                }
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard pos + 4 <= bytes.count else { throw error("a \\u escape needs four hex digits", at: pos) }
            var value: UInt32 = 0
            for _ in 0..<4 {
                let b = bytes[pos]
                let digit: UInt32
                switch b {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(b - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(b - UInt8(ascii: "a")) + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(b - UInt8(ascii: "A")) + 10
                default: throw error("a \\u escape needs four hex digits", at: pos)
                }
                value = value * 16 + digit
                pos += 1
            }
            return value
        }
    }
}
