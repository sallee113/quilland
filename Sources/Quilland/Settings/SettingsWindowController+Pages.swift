import AppKit
import QuillandCore

/// What each page of the Settings window holds (the rows of controls); the window puts the heading, the rows and Reset to Defaults together (`page(for:)`).
extension SettingsWindowController {
    /// General: the interface language, the folder for new books, recent books, what opens, snapshots.
    func generalRows() -> [NSView] {
        let folderLabel = NSTextField(labelWithString: "")
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        controls["newBookFolder"] = folderLabel
        return [
            row([NSTextField(labelWithString: L("Interface language")), popup("language", [(L("Like the system"), "system")], #selector(popupChanged(_:)))]),
            row([NSButton(title: L("Add Language…"), target: self, action: #selector(addLanguage)), NSButton(title: L("Export Template…"), target: self, action: #selector(exportTemplate)),
                 NSButton(title: L("Show Languages Folder"), target: self, action: #selector(showLanguagesFolder))]),
            caption(L("Menus change at once; windows that are already open take the language when they are opened again. A language is one text file: Export Template… writes the list of texts to translate.")),
            caption(L("Where New Book proposes to keep books")),
            row([folderLabel, NSButton(title: L("Choose…"), target: self, action: #selector(chooseNewBookFolder)), NSButton(title: L("Documents"), target: self, action: #selector(useDocumentsFolder))]),
            row([NSTextField(labelWithString: L("Recent books to remember")), stepperField("recent", range: 1...30, step: 1, #selector(stepperChanged(_:)))]),
            check("reopen", L("Reopen the last book when Quilland starts"), #selector(boxChanged(_:))),
            row([NSTextField(labelWithString: L("A book with no remembered view opens in")), popup("mode", [("Panels", "panels"), ("Book", "book"), ("Compare", "compare")], #selector(popupChanged(_:)))]),
            caption(L("Snapshots")),
            check("autoSnapshots", L("Take snapshots by themselves while something changes"), #selector(boxChanged(_:))),
            row([NSTextField(labelWithString: L("Every")), stepperField("snapshotMinutes", range: 1...240, step: 5, #selector(stepperChanged(_:))), NSTextField(labelWithString: L("minutes"))]),
        ]
    }

    /// Appearance: the font, the text size, the line spacing, the reading width, light or dark.
    func appearanceRows() -> [NSView] {
        let fontPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let families = (["Georgia", "Palatino", "Times New Roman", "Baskerville", "Charter", "Iowan Old Style", "Hoefler Text", "New York", "Helvetica Neue", "Avenir Next", "Menlo"]).filter { NSFontManager.shared.availableFontFamilies.contains($0) }
        for f in families { fontPopup.addItem(withTitle: f); fontPopup.lastItem?.representedObject = f }
        fontPopup.target = self; fontPopup.action = #selector(popupChanged(_:))
        controls["font"] = fontPopup
        let sample = NSTextField(wrappingLabelWithString: "Анна вышла на платформу станции. The morning was cold and the lights were low.")
        controls["sample"] = sample
        return [
            row([NSTextField(labelWithString: L("Font")), fontPopup]),
            row([NSTextField(labelWithString: L("Text size")), stepperField("fontSize", range: 10...36, step: 1, #selector(stepperChanged(_:)))]),
            row([NSTextField(labelWithString: L("Line spacing")), stepperField("lineSpacing", range: 1.0...2.2, step: 0.05, #selector(stepperChanged(_:)))]),
            row([NSTextField(labelWithString: L("Reading width of a sheet")), stepperField("readingWidth", range: 420...1100, step: 20, width: 70, #selector(stepperChanged(_:))), NSTextField(labelWithString: L("points"))]),
            row([NSTextField(labelWithString: L("Appearance")), popup("appearance", [(L("Like the system"), "system"), (L("Light"), "light"), (L("Dark"), "dark")], #selector(popupChanged(_:)))]),
            caption(L("How the text looks")), sample,
        ]
    }

    /// Writing: the typing corrections and the spelling.
    func writingRows() -> [NSView] {
        return [
            check("corrections", L("Correct my typing as I write"), #selector(boxChanged(_:))),
            row([NSTextField(labelWithString: "      "), check("smartQuotes", L("Quotes by the book's language: «…» for Russian, “…” for English"), #selector(boxChanged(_:)))]),
            row([NSTextField(labelWithString: "      "), check("dashes", L("A dash for “ - ” (with a non-breaking space before it) and for “--”"), #selector(boxChanged(_:)))]),
            row([NSTextField(labelWithString: "      "), check("dialogueDash", L("A dialogue dash for “- ” at the start of a paragraph"), #selector(boxChanged(_:)))]),
            row([NSTextField(labelWithString: "      "), check("ellipsis", L("An ellipsis for “...” (off: three dots stay three dots)"), #selector(boxChanged(_:)))]),
            row([NSTextField(labelWithString: L("Quotes")), popup("quoteStyle", [(L("Follow the book's language"), "auto"), (L("« » (Russian)"), "ru"), (L("“ ” (English)"), "en")], #selector(popupChanged(_:)))]),
            caption(L("Spelling")),
            check("spelling", L("Check spelling while typing"), #selector(boxChanged(_:))),
            check("textReplacement", L("Use the system's text replacements (System Settings ▸ Keyboard)"), #selector(boxChanged(_:))),
            caption(L("One ⌘Z takes back a correction just made.")),
        ]
    }

    /// Panels: the tabs of the right panel and how fast it follows the cursor.
    func panelsRows() -> [NSView] {
        return [
            caption(L("Tabs of the right panel")),
            check("tab.section", L("Section"), #selector(boxChanged(_:))),
            check("tab.characters", L("Characters"), #selector(boxChanged(_:))),
            check("tab.world", L("World"), #selector(boxChanged(_:))),
            check("tab.events", L("Events"), #selector(boxChanged(_:))),
            check("tab.research", L("Research"), #selector(boxChanged(_:))),
            check("tab.chat", L("Chat"), #selector(boxChanged(_:))),
            row([NSTextField(labelWithString: L("The panel follows the cursor after")), stepperField("followDelay", range: 0.3...6, step: 0.1, #selector(stepperChanged(_:))), NSTextField(labelWithString: L("seconds"))]),
        ]
    }

    /// AI: the address of LM Studio, the model, the context size and the connection check.
    func aiRows() -> [NSView] {
        let address = NSTextField()
        address.placeholderString = AIConnection.defaultAddress
        address.widthAnchor.constraint(equalToConstant: 260).isActive = true
        address.delegate = self
        controls["aiAddress"] = address
        let status = NSTextField(wrappingLabelWithString: "")
        status.font = .systemFont(ofSize: 12)
        status.preferredMaxLayoutWidth = 480
        controls["aiStatus"] = status
        let test = NSButton(title: L("Test Connection"), target: self, action: #selector(testAI))
        test.bezelStyle = .rounded
        controls["aiTest"] = test
        return [
            check("aiEnabled", L("Use the AI actions"), #selector(boxChanged(_:))),
            caption(L("The AI runs on this computer, in LM Studio. Nothing is sent anywhere else, and nothing it suggests is applied until you accept it.")),
            row([NSTextField(labelWithString: L("LM Studio address")), address]),
            row([NSTextField(labelWithString: L("Model")), popup("aiModel", [(L("The loaded one"), "")], #selector(popupChanged(_:))), test]),
            row([NSTextField(labelWithString: L("Tokens read at once")), stepperField("aiContext", range: 0...262144, step: 1024, width: 80, #selector(stepperChanged(_:)))]),
            caption(L("0 means what the server says. A smaller number makes the actions read less at a time.")),
            status,
        ]
    }

    /// AI Prompts: the wording and the temperature of each action, and the saved actions.
    func aiPromptsRows() -> [NSView] {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.target = self; popup.action = #selector(promptChosen)
        popup.widthAnchor.constraint(equalToConstant: 330).isActive = true
        controls["promptChoice"] = popup
        let note = NSTextField(wrappingLabelWithString: "")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor; note.preferredMaxLayoutWidth = 520
        controls["promptNote"] = note
        promptView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        promptView.isRichText = false; promptView.allowsUndo = true
        promptView.isVerticallyResizable = true; promptView.autoresizingMask = [.width]
        promptView.textContainerInset = NSSize(width: 6, height: 6)
        promptView.delegate = self
        promptView.setAccessibilityLabel(L("The prompt"))
        let promptScroll = NSScrollView()
        promptScroll.documentView = promptView
        promptScroll.hasVerticalScroller = true; promptScroll.borderType = .bezelBorder
        promptScroll.translatesAutoresizingMaskIntoConstraints = false
        promptScroll.widthAnchor.constraint(equalToConstant: 540).isActive = true
        promptScroll.heightAnchor.constraint(equalToConstant: 230).isActive = true
        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        controls["promptStatus"] = status
        let resetOne = NSButton(title: L("Back to the Built-in Text"), target: self, action: #selector(resetPrompt))
        resetOne.bezelStyle = .rounded; resetOne.controlSize = .small
        controls["promptResetOne"] = resetOne
        let rename = NSButton(title: L("Rename…"), target: self, action: #selector(renameActionPressed))
        let delete = NSButton(title: L("Delete"), target: self, action: #selector(deleteActionPressed))
        for b in [rename, delete] { b.bezelStyle = .rounded; b.controlSize = .small }
        controls["promptRename"] = rename; controls["promptDelete"] = delete
        let temperatureRow = row([NSTextField(labelWithString: L("Temperature")), stepperField("promptTemperature", range: 0...2, step: 0.05, #selector(promptTemperatureChanged(_:))),
                                  NSTextField(labelWithString: L("0 is exact and repeatable, 1 and more is freer"))])
        promptTemperatureRow = temperatureRow
        return [
            caption(L("The instructions the AI actions send to the model, in your words. A change counts at once. {language} stands for the language of the book. Prompts you saved from the Chat are here too, without the mark “System”: they are in the AI menu, under Actions.")),
            row([NSTextField(labelWithString: L("Prompt")), popup, rename, delete]),
            note, promptScroll, row([status, resetOne]), temperatureRow,
        ]
    }
}
