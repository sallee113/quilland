import Foundation

/// The few words the program writes into a book's files (not the interface): they follow the book's language.
public enum BookWords {
    public static func contents(_ language: String) -> String { ["ru": "Содержание", "fr": "Table des matières"][language.lowercased()] ?? "Contents" }
    public static func notes(_ language: String) -> String { ["ru": "Примечания", "fr": "Notes"][language.lowercased()] ?? "Notes" }
    public static func beginning(_ language: String) -> String { ["ru": "Начало", "fr": "Début"][language.lowercased()] ?? "Beginning" }
}
