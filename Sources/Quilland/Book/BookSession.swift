import AppKit
import QuillandCore

/// A book that is open: its structure, and one `SceneDocument` per scene, shared by every view that shows the scene.
final class BookSession {
    private(set) var structure: BookStructure
    private(set) var documents: [String: SceneDocument] = [:]

    init(structure: BookStructure) {
        self.structure = structure
        let language = BookSettings.load(book: structure.folder).language
        let words = BookDictionary.load(book: structure.folder)
        for entry in structure.scenes {
            let doc = SceneDocument(id: entry.id, title: entry.node.title, status: entry.node.status, url: structure.markdownURL(for: entry.node))
            doc.language = language
            doc.dictionaryWords = words
            documents[entry.id] = doc
        }
    }

    /// A section was renamed or got a new status: the structure and the open document are updated, nothing is reloaded.
    func applyInfo(id: String, title: String? = nil, status: String? = nil) {
        structure.update(id: id, title: title, status: status)
        documents[id]?.updateInfo(title: title, status: status)
    }

    /// The book's language or dictionary changed (Book Settings): every scene takes it.
    func applyBookSettings(language: String, words: [String]) {
        for d in documents.values { d.language = language; d.dictionaryWords = words }
    }

    /// A preference changed: every scene is drawn again and its views take the new writing settings.
    func preferencesChanged() { for d in documents.values { d.preferencesChanged() } }

    func document(_ id: String) -> SceneDocument? { documents[id] }

    /// Every unsaved scene is written now.
    func saveAll() { for d in documents.values where d.isDirty { d.saveNow() } }

    var totalWords: Int { documents.values.reduce(0) { $0 + $1.counts.words } }
    var totalCharacters: Int { documents.values.reduce(0) { $0 + $1.counts.characters } }
}
