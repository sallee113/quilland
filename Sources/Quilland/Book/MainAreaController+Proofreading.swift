import AppKit
import QuillandCore

extension MainAreaController {
    /// The scenes a proofreading scope covers, with their text and a title for the list.
    func proofreadingTargets(_ scope: SearchScope) -> [(id: String, title: String, text: String)] {
        searchTargets(scope).scenes.compactMap { id in
            guard let doc = session.document(id) else { return nil }
            let title = session.structure.scenes.first { $0.id == id }?.fullPath ?? ""
            return (id, title, doc.storage.string)
        }
    }

    var bookLanguage: String { BookSettings.load(book: folder).language }

    private static var spellTag: Int = NSSpellChecker.uniqueSpellDocumentTag()

    /// Is there a dictionary of the book's language in the system's spell checker?
    func spellingAvailable(language: String) -> Bool {
        let code = language.lowercased()
        return NSSpellChecker.shared.availableLanguages.contains { $0.lowercased().hasPrefix(code) }
    }

    /// The words the spell checker must not flag: the book's dictionary and the words of the names of characters and places (and their beginnings, for the endings
    /// a name gets in a sentence).
    func spellingIgnored() -> (words: Set<String>, stems: [String]) {
        var words = Set(BookDictionary.load(book: folder).map { $0.lowercased() })
        var stems: [String] = []
        let names = characters.entries + worlds.nameEntries
        for entry in names {
            for full in [entry.name] + entry.aliases {
                for part in full.split(whereSeparator: { !$0.isLetter && $0 != "-" }) {
                    let w = part.lowercased()
                    words.insert(w)
                    if w.count >= 5 { stems.append(String(w.dropLast())) }
                }
            }
        }
        return (words, stems)
    }

    /// Misspelled words in a text, each with the checker's first suggestion (empty when it has none).
    func spellingFindings(in text: String, language: String, ignored: (words: Set<String>, stems: [String])) -> [TypographyFinding] {
        guard spellingAvailable(language: language) else { return [] }
        let checker = NSSpellChecker.shared
        let tag = Self.spellTag
        checker.setIgnoredWords(Array(ignored.words), inSpellDocumentWithTag: tag)
        let ns = text as NSString
        var out: [TypographyFinding] = []
        var position = 0
        while position < ns.length {
            let found = checker.checkSpelling(of: text, startingAt: position, language: language, wrap: false, inSpellDocumentWithTag: tag, wordCount: nil)
            guard found.location != NSNotFound, found.length > 0 else { break }
            position = NSMaxRange(found)
            let r = (range: found, 0)
            let word = ns.substring(with: r.range)
            let lower = word.lowercased()
            if word.count < 2 || word.contains(where: { $0.isNumber }) || ignored.words.contains(lower) || ignored.stems.contains(where: { lower.hasPrefix($0) }) { continue }
            let suggestion = checker.guesses(forWordRange: r.range, in: text, language: language, inSpellDocumentWithTag: tag)?.first ?? ""
            let from = max(0, r.range.location - 24), to = min(ns.length, NSMaxRange(r.range) + 24)
            var cb = ns.substring(with: NSRange(location: from, length: r.range.location - from))
            var ca = ns.substring(with: NSRange(location: NSMaxRange(r.range), length: to - NSMaxRange(r.range)))
            if let i = cb.lastIndex(of: "\n") { cb = String(cb[cb.index(after: i)...]) }
            if let i = ca.firstIndex(of: "\n") { ca = String(ca[..<i]) }
            out.append(TypographyFinding(rule: .spelling, range: r.range, before: word, after: suggestion, contextBefore: cb, contextAfter: ca))
        }
        return out
    }

    /// Teaches the book a word: it is saved in the dictionary and every scene's spell checker takes it.
    func addToDictionary(_ word: String) {
        let words = BookDictionary.normalized(BookDictionary.load(book: folder) + [word])
        do { try BookDictionary.save(words, book: folder) } catch { reportError(error); return }
        session.applyBookSettings(language: bookLanguage, words: words)
    }

    /// Applies findings as ordinary edits in the scene's editor, so that ⌘Z takes them back (all of one call as one step). A piece whose text is no longer
    /// what the finding saw is skipped. Returns how many were applied.
    @discardableResult
    func applyProofreading(scene: String, edits: [(range: NSRange, expected: String, replacement: String)]) -> Int {
        guard let first = edits.first else { return 0 }
        _ = first
        // A scene that is already open stays as it is (the cursor and the view do not jump); another one is opened first. No range for reveal: its highlight
        // animation runs a moment later and would meet a text that has changed.
        if !controllers.contains(where: { $0.currentSceneID == scene }) { reveal(scene: scene, range: nil) }
        guard let area = controllers.first(where: { $0.currentSceneID == scene }) ?? controllers.first, let tv = area.currentSheet?.textView else { return 0 }
        var applied = 0
        tv.undoManager?.beginUndoGrouping()
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            let ns = tv.string as NSString
            guard NSMaxRange(edit.range) <= ns.length, ns.substring(with: edit.range) == edit.expected else { continue }
            if tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
                tv.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
                tv.didChangeText()
                applied += 1
            }
        }
        tv.undoManager?.endUndoGrouping()
        if applied > 0, let last = edits.min(by: { $0.range.location < $1.range.location }) {
            let end = min((tv.string as NSString).length, last.range.location + last.replacement.utf16.count)
            tv.setSelectedRange(NSRange(location: end, length: 0))
            // The corrected place is brought into view, so that the author sees what was done.
            area.scrollToCursor()
        }
        return applied
    }
}
