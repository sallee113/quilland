# Quilland architecture

How the pieces fit together. For what the application does, see the [user guide](user-guide.md); for how to work on it, [Working on Quilland](development.md).

## The shape of it

Quilland is a macOS application written in Swift with AppKit. A book is a **folder of plain files** (prose in Markdown, everything else in JSON) that the application reads and writes directly; there is no database that holds the truth. A local model through LM Studio is optional.

```
┌──────────────────────────────────────────────────────────────┐
│ Quilland (the application target, AppKit)                    │
│   windows, views, menus, dialogs, the editor                 │
├──────────────────────────────────────────────────────────────┤
│ QuillandCore (a library, no UI)                              │
│   formats · stores · operations on records · import/export   │
│   snapshots · names and search · proofreading · AI jobs      │
├──────────────────────────────────────────────────────────────┤
│ Files                          │ LM Studio (HTTP, optional)  │
│   book folder, settings        │   localhost:1234            │
└──────────────────────────────────────────────────────────────┘
```

**The rule:** `QuillandCore` knows nothing about AppKit. Everything that can be decided without a window (what a merge does to the files, how a text is split into scenes, which names are found in a scene, what the model is asked) is in the core and has unit tests. The application target puts windows around it and does no file parsing of its own.

## The package

| Target | What it is |
| --- | --- |
| `QuillandCore` | The library (Swift 6 language mode). |
| `Quilland` | The application, an executable (Swift 5 language mode, because AppKit). `make-app.sh` packages it as `Quilland.app`; a real bundle is needed for Dictation and other system services. |
| `StressWriter` | A small tool that rewrites one file until it is killed, for the tests of atomic writes. |
| `QuillandCoreTests`, `QuillandTests` | The unit tests (Swift Testing). |

There are no third-party dependencies, only Apple's frameworks (AppKit, Foundation, NaturalLanguage, SQLite3, WebKit, CoreText, CryptoKit, Compression).

## The book on disk

```
My Book/
  book.json                  title, author, language, id, format version
  dictionary.json            words the spell checker accepts in this book
  manuscript/
    001-chapter/             a chapter is a folder; a part is a folder holding chapters
      _chapter.json          its id and title
      001-scene.json         a scene: id, title, status, synopsis, note
      001-scene.md           its text (Markdown)
  bible/
    characters/ worlds/ places/ events/ relationships/ kinds/   one JSON file per record,
                                                                named by its id (+ .md for long text)
  reminders.json             the book's checklist (View > Reminders; open ones shown when the book opens)
  research/                  <id>.json, <id>.md (typed text), <id>.file/<name> (a copied file)
  plan/                      canvas.json (the lines) and cards/ (one file per card)
  assets/                    the cover and other images
  .gitignore                 ignores .quilland/
  .quilland/                 never in Git: snapshots/, trash/, cache.sqlite, state.json,
                             proofreading.json, journal.json
```

- **Prose is Markdown, data is JSON.** JSON is written in one canonical form (sorted keys, two-space indent, one array item per line, a final newline), so that Git diffs show exactly what changed, and a record is written again only when it changed.
- **Ids.** Every record has a UUID; links are plain ids. A file is named by its record's id (except scenes and chapters, which are numbered folders and files so that the book order is the file order). Merges and moves keep ids.
- **Writes are atomic** (`AtomicFile`: a temporary file, then a rename). A renumbering of scenes is journalled and finished on the next open if the application stopped half way.
- **Unknown fields are kept** when a file is written again.
- **Looking changes nothing:** opening a book and its views writes no file (a self-test checks it).

`.quilland/` holds local, rebuildable state: snapshots (copy-on-write clones of the whole book, thinned by a rule), the trash (everything removed goes there first), a SQLite cache (counts, a full-text index with word endings, where names are mentioned), the view state, and the journal.

## QuillandCore

| Directory | What is in it |
| --- | --- |
| `JSON/` | A strict parser, the canonical writer, `JSONValue`, typed records (`SceneRecord`, `CharacterRecord`, plan cards), `AtomicFile`. |
| `Markdown/` | The book's Markdown subset: parser, writer, normalizer, text statistics. A round trip is exact. |
| `Editor/` | `AttributedBridge`: Markdown ⇄ styled text for the editor. |
| `Files/` | The stores and operations on the book: `BookStructure` (the tree of parts, chapters and scenes), `BookEditor` (add, move, split, merge, group), `Renumber`, `CharacterStore`, `WorldStore`, `EventStore`, `RemindersStore` (the checklist in `reminders.json`), `ResearchStore` (documents with typed text, an embedded or linked file, and links), `RelationshipStore`, `CharacterMerger` and `WorldMerger` (merge and convert records), `BookRelinker`, `LooseEnds`, `BookCreator`, `AppSettings`, `TrashFolder`. |
| `Graph/` | `GraphViewController` and `GraphCanvasView` (the Graph view, drawn by the view itself); the logic is in the core: `BookGraph`/`GraphBuilder` (nodes and lines from the records), `GraphLayout` (deterministic force-directed layout, each group of joined nodes by itself, then packed), `GraphStore` (`plan/graph.json`, the nodes the author moved). |
| `Plan/` | `PlanStore` (lines and cards, with in-memory undo), positions, the "show from" filter. |
| `Snapshots/` | `SnapshotStore` (take, thin, restore), `SnapshotInspector` (what changed), `SnapshotRecovery` (bring back one item). |
| `Cache/` | `BookCache` over SQLite. |
| `Names/` | Finding characters and places in a text, including Russian word endings, by rules; text search. |
| `Proofreading/` | The typography rules and the grammar prompt and diff. |
| `Collect/` | The AI jobs: collecting characters and places, the consistency check, continuing, the synopsis, the chat context; quotes are verified against the text. |
| `LLM/` | The LM Studio client (chat and streaming), the connection check, the filter for the model's reasoning. |
| `Import/`, `Export/` | Import of Markdown, text and HTML with title analysis; export to DOCX, FB2, EPUB, HTML and TXT (the PDF is drawn by the application, `PDFRenderer`); the demo book generator. |
| `Settings/` | Preferences, shortcuts, typing corrections, interface languages, the AI prompts and saved actions. |

## The application

### Windows and the book

- `AppDelegate` owns the menus (validated through `NSMenuItemValidation`), the book windows, the Welcome window, Settings and the AI connection.
- `BookWindowController` is one open book: the window, the status bar, snapshots on a timer, saving on close.
- `MainAreaController` is the heart of a book window. It shows the book in one of ten **modes** (Panels, Book, Graph, Outline, Plan, Characters, World, Events, Research, Reminders), with the right panel and the bottom panel. Its files:
  - `MainAreaController.swift`: state, modes, `rebuild()` and one builder per mode, saving.
  - `+Structure`, `+Undo`: every change to the structure goes through `restructure(...)` (a snapshot before and after, the stores reloaded, the views rebuilt); Undo and Redo restore those snapshots.
  - `+Records`, `+Outline`, `+SectionState`: merges and conversions of records, the Outline's data, what the Section menu can do now.
  - `+History`: Back and Forward between views (the view and the card or scene chosen in it, kept at each change of the view).
  - `+Search`, `+Proofreading`, `+Chat`, `+Continue`, `+Synopsis`: the bottom panel and the AI commands.
- `BookSession` holds one `SceneDocument` per scene, however many views show it. `SceneDocument` keeps the text styled, saves it shortly after the last key, keeps another program's version of the file in the trash before overwriting it, and reports a failed save.

### Views

`Book/` has the views of the modes and the cards (structure tree, Outline detail, Characters, World, Events, the right panel's tabs, the Chat tab, loose ends, suggestions); `Editor/` the text view (`EditorTextView`, the Format commands, the faint suggestion text for the AI); `Plan/` the canvas; `Export/` the export, import and snapshot windows; `Settings/` the Settings pages; `Lab/` a test harness window for the riskiest early designs.

### State: who owns what

- **The files are the truth.** The stores (`CharacterStore` and the others) are in-memory views of them, reloaded after a change through `restructure`.
- **The text** of a scene lives in its `SceneDocument` while the book is open.
- **Typed text waits for a timer** in several views (cards, notes). Every such view declares `PendingEdits`; `MainAreaController.pendingEditors` is the one list that saving, rebuilding and closing go by.
- **The selection and the cursor** are kept in the tree, the editor and the right panel; `rebuild()` takes the cursor and the tree's choice from a few pending values set before it.

### The AI

`AIService` is the application's one connection to LM Studio (is it on, does it answer, which model, how many tokens it reads). The jobs themselves are in `QuillandCore/Collect` and are tested against a fake server. The rules: the AI is optional and says why it is unavailable; **nothing it proposes is applied until the author accepts it** (suggestions are faint text, or items in the Suggestions tab); every quote it gives is checked against the text; closing a book window stops its jobs.

**Events.** What more than one place cares about is posted as a named event (`App/AppEvents.swift`, for now `.aiStatusChanged`), and each place subscribes where it lives with `subscribe(to:)`, holding the returned `Subscription` (it ends when the view goes). `AIService` posts the event whenever the connection changes (asking, answered, not answering, switched off), so the Outline detail, the right panel, Chat and Proofreading follow it by themselves; coming back to the application asks the server again when the model was not there. A new place that depends on the AI subscribes; nobody needs to be told about it.

### Interface language

English text in the code is its own key (`L("Open Book…")`, `Lp("{n} scene", "{n} scenes", n)`). A language is one JSON file in `Resources/Languages/` (or the user's own folder); `template.json` lists every text and is made by `make-languages.py`. English is the default; Russian and French are bundled. A test fails if a bundled language lacks a text.

## Cross-cutting mechanisms

These touch every window, so they are changed with care (see the rules in `development.md`):

- **`QuillandApplication`** records every exception AppKit catches while handling events; the self-test fails on one.
- **Hover** (`Hover.swift`): lists, buttons and tab strips react to the pointer through tracking areas; a hook on `NSButton` attaches it to every button of the application's windows. A button that is switched off is faded.
- **Menu validation:** Section, View and AI items are enabled and ticked from the state of the book.
- **Confirmations:** every destructive action asks first, with Cancel as the default.

## Tests

- **Unit tests** (about 250): the core library, with real files in temporary folders and a fake LM Studio server.
- **Self-test** (`--selftest-app`, about 480 checks, one file per topic): the real windows and views driven in code, a pretend pointer, and checks that no exception was thrown. **Lab self-test** (`--selftest-lab`): the early design harness.
- **Pictures** (`--snapshot-*`) for looking at layouts.

## Where to add things

- **A new kind of record:** a store and a record type in `Files/`, its files under `bible/`, a view in `Book/`, a mode or a tab in `MainAreaController`; if it has typed text, declare `PendingEdits`; if it can be linked, teach `BookRelinker` and `CharacterMerger`/`WorldMerger` about it; add tests for each.
- **A new AI action:** the job and its prompt in `Collect/` (with a test against the fake server), the command in `AIService`/the AI menu, the result shown as suggestions.
- **A new language:** copy `template.json`, translate, add the file to `Resources/Languages/`.
- **A new change to the structure:** a method on `BookEditor` in the core with a test, then call it through `restructure(...)` so that it has Undo.

## Known limits

- `rebuild()` still takes three loosely coupled values (the cursor, the tree's choice, where the focus goes) set by its callers before it runs; an explicit value passed to it would be safer.
- A scene file that another program changes is kept, not merged.
- Research documents keep their links by id; when a merge or a deletion removes the scene or card a link points to, the link shows as "(missing)" and is not moved over. A linked (not copied) file is remembered by its full path on this Mac; named folders ("roots") and finding a moved file by its hash are not built yet.
- Find and Replace does not look in research documents; the Research view has its own filter.
- Importing a whole folder of Markdown files, and importing into the middle of a book, are not built.
