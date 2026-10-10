import Foundation

/// Adding a language: checking a file and copying it into the user's folder, and writing the template a translator starts from.
public enum LanguageFiles {
    public struct Failure: Error, CustomStringConvertible {
        public var description: String
        public init(description: String) { self.description = description }
    }

    /// The folder for the user's own language files.
    public static func userDirectory(settings: URL) -> URL { settings.appendingPathComponent("Languages") }

    /// Checks a language file and copies it to `<code>.json` in the user's folder (replacing a file of that language that is there).
    @discardableResult
    public static func install(_ source: URL, into directory: URL) throws -> Language {
        let loaded = Language.load(source)
        guard let language = loaded.language else { throw Failure(description: loaded.problem ?? L("The file could not be read.")) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("\(language.code.lowercased()).json")
        try AtomicFile.write(try Data(contentsOf: source), to: target)
        return language
    }

    /// Writes the template for a new language: the texts to translate (empty values), with the fields that name the language.
    public static func writeTemplate(from template: URL, to destination: URL, code: String = "xx", name: String = "My language", rule: PluralRule = .en) throws {
        var o = try JSONParser.parseObject(Data(contentsOf: template))
        o["code"] = .string(code)
        o["name"] = .string(name)
        o["plural_rule"] = .string(rule.rawValue)
        let forms = rule.categories.joined(separator: ", ")
        let help = "Fill in the empty strings; leave out (or empty) what you do not translate and English is shown. Keep {names} in braces as they are. "
            + "In plurals give one text for each of: " + forms + ". A key ending with ||context says what the word means there; translate the part before ||."
        o["_help"] = .string(help)
        try AtomicFile.write(JSONWriter.data(o), to: destination)
    }
}
