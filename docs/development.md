# Working on Quilland

## Before every commit

```bash
swift build -c release
swift test                                   # the unit tests (the core library)
.build/release/Quilland --selftest-app       # the application's own checks (about 465), takes a minute or two
.build/release/Quilland --selftest-lab       # the Lab window's checks
```

All of them must pass. The self-test ends with a check that no exception was thrown while the application handled events: AppKit catches such an exception, prints one line and goes on (inside a modal dialog it ends the dialog), so it is easy to miss without this check.

## What the checks cover

- **Unit tests** (`Tests/`): files, formats, import, export, names, snapshots, the AI jobs against a fake LM Studio server, merging and converting records.
- **Self-test** (`Sources/Quilland/App/AppSelfTest.swift`): the windows and views of the real application, driven in code. It also moves a pretend pointer over the windows (`PointerSimulator`) and tells every tracking area what the system would, so that a list, a button or a tab that does not answer is found.
- **Pictures** (`--snapshot-ui`, `--snapshot-chat`, `--snapshot-settings`): to look at a layout; `QUILLAND_FORCE_LANGUAGE=fr` shows a language.

## Where things are: the main area

`MainAreaController` (`Sources/Quilland/Book/`) shows the open book's views. Its files:

- `MainAreaController.swift`: the state, the modes, `rebuild()` and one builder per mode, the right and bottom panels, saving (`saveAll()`, `pendingEditors`).
- `+Structure`: add, move, rename, delete, split, merge, group, import; every change that touches files goes through `restructure(...)` (a snapshot before and after, the stores reloaded, the views rebuilt).
- `+Undo`: Undo and Redo of those changes (the snapshots), `reloadStores()`, `reloadFromDisk()`.
- `+Records`: mentions of characters and places in the scenes; merging and converting characters, places and worlds.
- `+Outline`: the Outline's data (synopsis, note, size of each section).
- `+SectionState`: what the Section menu can do now.
- `+Search`, `+Proofreading`, `+Chat`, `+Continue`, `+Synopsis`: the bottom panel and the AI commands. (The Proofreading tab itself is `ProofreadingView.swift`.)

## Rules that came from mistakes

1. **A bug is reproduced by a check that fails before the fix.** Then it is fixed, then the check passes.
2. **Something that touches every window** (the hook on buttons, the pointer tracking, the menu validation, the application object) is a change of its own, with a line in the commit message saying what else it can affect. Three regressions came from such changes: an unanswered `mouseEntered:` that ended every open dialog; a hover that changed a row's background and spoiled its selection; a menu that was never validated because the delegate did not say it could.
3. **An owner of a tracking area answers every message its options ask for** (`mouseEntered:`, `mouseExited:`, `mouseMoved:`, `cursorUpdate:`), with `@objc(name:)` so that the selector is the one the system sends. The self-test checks it for every window.
4. **A view's own drawing and colours are not changed from outside** (a row's background, a button's layer). What is drawn over it is a view of its own that lets the clicks through.
5. **Files are named by their id.** A store writes a record where it read it, and reads two files with one id as one record.
6. **Everything that is typed is saved by `MainAreaController.saveAll()`** before the book is changed in a way that rebuilds the views (a merge, a move, closing the window). An editor that saves after a timer declares `PendingEdits` (`commitEdits()`) and is added to `pendingEditors` in `MainAreaController`: the one list that saving, rebuilding and closing go by. The self-test fails for a class with a `commitEdits()` that does not declare it.
7. **A change that touches many files goes through `restructure(...)`:** it takes a snapshot before and after, so that Undo works, and it reloads the stores.
8. **A view that holds typed text with a save timer is saved before it is torn down** (`rebuild()` commits the cards of the full-area views; the timers do not outlive their views).
9. **A file's change is read with `FileManager.attributesOfItem`, never `URL.resourceValues` on a URL kept around:** a URL remembers the values it read first and would not see another program's change.
10. **A save that fails is shown** (status bar: "Not saved"), and a scene changed by another program since it was read is kept in the trash folder before ours is written.
11. **Looking changes nothing:** opening every view and every scene writes no file of the book (the self-test checks it), so that Git shows only what the author changed. Data files are written in their canonical form (`JSONWriter`), a record is written again only when it changed.
12. **Closing a book window stops the model's jobs for it** (`MainAreaController.stopAI()`).
13. **A change to the files that fails is told** (a banner or an alert), never dropped with `try?`.
14. Small commits, one subject each; the self-test before each.
