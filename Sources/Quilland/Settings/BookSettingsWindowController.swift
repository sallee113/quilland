import AppKit
import QuillandCore

/// Book ▸ Book Settings…: what belongs to the book and travels with it (and with Git): the title, author, copyright, language, target size
/// and cover in `book.json`, and the dictionary of words the spell checker accepts in `dictionary.json`. A change is saved at once.
final class BookSettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    let folder: URL
    var onChanged: () -> Void = {}
    var onClose: (() -> Void)?

    private(set) var settings: BookSettings
    private(set) var words: [String]

    let titleField = NSTextField()
    let authorField = NSTextField()
    let copyrightField = NSTextField()
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let targetField = NSTextField()
    private let coverLabel = NSTextField(labelWithString: "")
    private let wordTable = Hover.rows(NSTableView())
    let addWordField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private static let languages = [("ru", L("Russian")), ("en", L("English")), ("uk", L("Ukrainian")), ("de", L("German")), ("fr", L("French")), ("es", L("Spanish")), ("it", L("Italian")), ("pl", L("Polish"))]

    init(folder: URL) {
        self.folder = folder
        settings = BookSettings.load(book: folder)
        words = BookDictionary.load(book: folder)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Book Settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        build()
        showValues()
        window.center()
    }

    func show() { window.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: Building

    private func label(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.alignment = .right
        l.textColor = .secondaryLabelColor
        l.widthAnchor.constraint(equalToConstant: 110).isActive = true
        return l
    }

    private func build() {
        for f in [titleField, authorField, copyrightField, targetField] { f.delegate = self; f.widthAnchor.constraint(equalToConstant: 320).isActive = true }
        titleField.setAccessibilityLabel(L("Title")); authorField.setAccessibilityLabel(L("Author")); copyrightField.setAccessibilityLabel(L("Copyright"))
        targetField.placeholderString = L("characters (leave empty for none)||text")
        targetField.setAccessibilityLabel(L("Target size"))
        for (code, name) in Self.languages { languagePopup.addItem(withTitle: name); languagePopup.lastItem?.representedObject = code }
        languagePopup.target = self; languagePopup.action = #selector(languageChanged)
        let chooseCover = NSButton(title: L("Choose Image…"), target: self, action: #selector(chooseCover))
        let removeCover = NSButton(title: L("Remove"), target: self, action: #selector(removeCover))
        func row(_ name: String, _ view: NSView) -> NSStackView { let r = NSStackView(views: [label(name), view]); r.spacing = 10; r.alignment = .firstBaseline; return r }
        let note = NSTextField(wrappingLabelWithString: L("The language sets the quote style of the typing corrections, the language of exported files, and the names Quilland gives to new sections."))
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.widthAnchor.constraint(equalToConstant: 440).isActive = true
        let book = NSStackView(views: [row(L("Title"), titleField), row(L("Author"), authorField), row(L("Copyright"), copyrightField), row(L("Language"), languagePopup),
                                       note, row(L("Target size"), targetField), row(L("Cover"), NSStackView(views: [coverLabel, chooseCover, removeCover]))])
        book.orientation = .vertical; book.alignment = .leading; book.spacing = 12
        book.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 20, right: 22)
        book.translatesAutoresizingMaskIntoConstraints = false
        let bookView = NSView()
        bookView.addSubview(book)
        NSLayoutConstraint.activate([book.topAnchor.constraint(equalTo: bookView.topAnchor), book.leadingAnchor.constraint(equalTo: bookView.leadingAnchor)])

        // The dictionary.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("word"))
        wordTable.addTableColumn(column)
        wordTable.headerView = nil
        wordTable.dataSource = self; wordTable.delegate = self
        wordTable.allowsMultipleSelection = true
        wordTable.setAccessibilityLabel(L("Words the spell checker accepts"))
        let scroll = NSScrollView()
        scroll.documentView = wordTable
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 250).isActive = true
        addWordField.placeholderString = L("A word to accept — type it, press Return")
        addWordField.delegate = self
        let removeButton = NSButton(title: L("Remove Selected"), target: self, action: #selector(removeWords))
        countLabel.textColor = .secondaryLabelColor
        let explain = NSTextField(wrappingLabelWithString: L("Words the spell checker should accept in this book: names, places, invented words. They are kept in the book (dictionary.json), so everyone who has the book has them."))
        explain.font = .systemFont(ofSize: 11); explain.textColor = .secondaryLabelColor
        let dict = NSStackView(views: [explain, scroll, NSStackView(views: [addWordField, removeButton]), countLabel])
        dict.orientation = .vertical; dict.alignment = .leading; dict.spacing = 10
        dict.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        scroll.widthAnchor.constraint(equalToConstant: 400).isActive = true
        explain.widthAnchor.constraint(equalToConstant: 440).isActive = true
        addWordField.widthAnchor.constraint(equalToConstant: 270).isActive = true
        dict.translatesAutoresizingMaskIntoConstraints = false
        let dictView = NSView()
        dictView.addSubview(dict)
        NSLayoutConstraint.activate([dict.topAnchor.constraint(equalTo: dictView.topAnchor), dict.leadingAnchor.constraint(equalTo: dictView.leadingAnchor)])

        let tabs = NSTabView()
        let bookItem = NSTabViewItem(identifier: "book"); bookItem.label = "Book"; bookItem.view = bookView
        let dictItem = NSTabViewItem(identifier: "dictionary"); dictItem.label = L("Dictionary"); dictItem.view = dictView
        tabs.addTabViewItem(bookItem); tabs.addTabViewItem(dictItem)
        window.contentView = tabs
    }

    // MARK: Values

    private func showValues() {
        titleField.stringValue = settings.title
        authorField.stringValue = settings.author
        copyrightField.stringValue = settings.copyright
        targetField.stringValue = settings.targetCharacters.map(String.init) ?? ""
        if let i = Self.languages.firstIndex(where: { $0.0 == settings.language }) { languagePopup.selectItem(at: i) }
        else { languagePopup.addItem(withTitle: settings.language); languagePopup.lastItem?.representedObject = settings.language; languagePopup.selectItem(at: languagePopup.numberOfItems - 1) }
        coverLabel.stringValue = settings.cover ?? "none"
        wordTable.reloadData()
        countLabel.stringValue = Lp("{n} word", "{n} words", words.count)
    }

    /// Changes the book's settings and saves them at once.
    func apply(_ change: (inout BookSettings) -> Void) {
        var s = settings
        change(&s)
        s.title = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.title.isEmpty { s.title = settings.title }
        guard s != settings else { showValues(); return }
        do { try s.save(book: folder) } catch { report(error); return }
        settings = s
        showValues()
        onChanged()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === titleField { apply { $0.title = self.titleField.stringValue } }
        else if field === authorField { apply { $0.author = self.authorField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) } }
        else if field === copyrightField { apply { $0.copyright = self.copyrightField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) } }
        else if field === targetField {
            let digits = targetField.stringValue.filter(\.isNumber)
            apply { $0.targetCharacters = Int(digits).flatMap { $0 > 0 ? $0 : nil } }
        } else if field === addWordField { addWords(addWordField.stringValue); addWordField.stringValue = "" }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === addWordField, selector == #selector(NSResponder.insertNewline(_:)) {
            addWords(addWordField.stringValue)
            addWordField.stringValue = ""
            return true
        }
        return false
    }

    @objc private func languageChanged() {
        guard let code = languagePopup.selectedItem?.representedObject as? String else { return }
        apply { $0.language = code }
    }

    func setLanguage(_ code: String) { apply { $0.language = code } }

    @objc private func chooseCover() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setCover(from: url)
    }

    func setCover(from url: URL) {
        do { let name = try BookSettings.addCover(from: url, to: folder); apply { $0.cover = name } } catch { report(error) }
    }

    @objc private func removeCover() { apply { $0.cover = nil } }

    // MARK: The dictionary

    /// Adds one or several words (separated by spaces or commas); they are saved and the spell checker takes them at once.
    func addWords(_ text: String) {
        let new = text.components(separatedBy: CharacterSet(charactersIn: " ,;\n\t")).filter { !$0.isEmpty }
        guard !new.isEmpty else { return }
        saveWords(words + new)
    }

    func removeWord(_ word: String) { saveWords(words.filter { $0 != word }) }

    @objc private func removeWords() {
        let gone = wordTable.selectedRowIndexes.compactMap { words.indices.contains($0) ? words[$0] : nil }
        saveWords(words.filter { !gone.contains($0) })
    }

    private func saveWords(_ list: [String]) {
        let normalized = BookDictionary.normalized(list)
        do { try BookDictionary.save(normalized, book: folder) } catch { report(error); return }
        words = normalized
        showValues()
        onChanged()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { words.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { CenteredCell(NSTextField(labelWithString: words[row])) }

    private func report(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("That could not be saved")
        alert.informativeText = "\(error)"
        alert.runModal()
    }
}
