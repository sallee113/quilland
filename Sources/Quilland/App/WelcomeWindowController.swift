import AppKit
import QuillandCore

/// What is shown when no book is open: New Book, Open Book, and the recent books.
final class WelcomeWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let table = NSTableView()
    private var books: [AppSettings.KnownBook] = []
    var onNewBook: (() -> Void)?
    var onOpenBook: (() -> Void)?
    var onOpenRecent: ((URL) -> Void)?
    var onImport: (() -> Void)?

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Quilland")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let title = NSTextField(labelWithString: L("Quilland"))
        title.font = NSFont(name: "Georgia", size: 34) ?? .systemFont(ofSize: 34, weight: .semibold)
        let subtitle = NSTextField(labelWithString: L("A local-first workspace for writers"))
        subtitle.textColor = .secondaryLabelColor
        func button(_ title: String, _ action: Selector) -> NSButton { let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded; b.controlSize = .large; return b }
        let newButton = button("New Book…", #selector(newBook))
        newButton.keyEquivalent = "\r"
        let importButton = button(L("Import a Text…"), #selector(importText))
        let buttons = NSStackView(views: [newButton, button("Open Book…", #selector(openBook)), importButton])
        buttons.spacing = 10

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("book"))
        column.width = 480
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 38
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        let recents = NSTextField(labelWithString: L("Recent books"))
        recents.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle, buttons, recents, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: subtitle)
        stack.setCustomSpacing(24, after: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 30), stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.contentView = content
    }

    func show(books: [AppSettings.KnownBook]) {
        self.books = books.filter { FileManager.default.fileExists(atPath: $0.path + "/book.json") }
        table.reloadData()
        window.makeKeyAndOrderFront(nil)
    }

    var visibleBooks: [AppSettings.KnownBook] { books }

    @objc private func newBook() { onNewBook?() }
    @objc private func openBook() { onOpenBook?() }
    @objc private func importText() { onImport?() }
    @objc private func openSelected() { if table.clickedRow >= 0 { onOpenRecent?(URL(fileURLWithPath: books[table.clickedRow].path)) } }

    func numberOfRows(in tableView: NSTableView) -> Int { books.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let book = books[row]
        let name = NSTextField(labelWithString: book.name)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        let path = NSTextField(labelWithString: (book.path as NSString).abbreviatingWithTildeInPath)
        path.font = .systemFont(ofSize: 11)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        let cell = NSStackView(views: [name, path])
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 1
        return cell
    }
}
