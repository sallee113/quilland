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

## Rules that came from mistakes

1. **A bug is reproduced by a check that fails before the fix.** Then it is fixed, then the check passes.
2. **Something that touches every window** (the hook on buttons, the pointer tracking, the menu validation, the application object) is a change of its own, with a line in the commit message saying what else it can affect. Three regressions came from such changes: an unanswered `mouseEntered:` that ended every open dialog; a hover that changed a row's background and spoiled its selection; a menu that was never validated because the delegate did not say it could.
3. **An owner of a tracking area answers every message its options ask for** (`mouseEntered:`, `mouseExited:`, `mouseMoved:`, `cursorUpdate:`), with `@objc(name:)` so that the selector is the one the system sends. The self-test checks it for every window.
4. **A view's own drawing and colours are not changed from outside** (a row's background, a button's layer). What is drawn over it is a view of its own that lets the clicks through.
5. **Files are named by their id.** A store writes a record where it read it, and reads two files with one id as one record.
6. **Everything that is typed is saved by `MainAreaController.saveAll()`** before the book is changed in a way that rebuilds the views (a merge, a move, closing the window); a controller that saves after a timer has a `commitEdits()` that `saveAll()` reaches.
7. **A change that touches many files goes through `restructure(...)`:** it takes a snapshot before and after, so that Undo works, and it reloads the stores.
8. Small commits, one subject each; the self-test before each.
