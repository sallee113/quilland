# Changelog

What changed in Quilland, release by release, newest first. The version is in the `VERSION` file; each release is a git tag `vX.Y.Z`.

## 0.1.0 — 2026-10-29

The first tagged release. Quilland is a local-first workspace for writers: a book is a folder of plain files, the editor and the cards work offline, and an AI model (LM Studio) helps only when asked.

### Writing
- Panels, Book (one scroll, splittable into two panes), Focus mode and Outline views over a book of parts, chapters and scenes; move, merge, split and group scenes in one undoable step.
- Find, Replace, Proofread and Loose Ends; the book's own spelling dictionary; import from Word, text and HTML; export to PDF, Word and more.
- Interface in English, Russian and French (more can be added as a JSON file); user guides in English and French.

### The world of the book
- **World Bible** (⌃⌘1 Characters, ⌃⌘2 World): cards for characters and for worlds and places, relationships, merging and converting cards, filters by relation.
- **Events** with the changes they make (profile, names, relationships); the default event "Book starts"; characters and places show what events change.
- **Research** documents with typed text and copied or linked files; **Reminders**.
- The right panel follows the cursor: who and what is in the scene, with one rule for its item tabs (New, description, double-click to open).

### Plan and Graph
- The Plan: plot lines, cards and events, colours, cards realised by events.
- The Graph: the whole book, the social graph, a neighbourhood, a character's arc, a tree of places, the locations along the book, a map of the plan; as of a scene, by plot line, with warnings; the main line can run diagonally, left to right or top to bottom.

### With the AI
- Write with AI (synopsis), continue writing, check grammar and consistency, chat with the book.
- **Collect from the Book**: characters, places, events, changes and relationships found in two passes, with live progress; findings that change nothing are left out; duplicates are caught as they come.
- **Duplicates**: find cards that look like one and merge the new card into the existing one, or delete it.

### Everywhere
- Every view comes back as it was left, with its filters, also after closing the book.
- Snapshots before risky changes, a trash folder, and one Undo for each structural change.

## Earlier

All of the above was built in October 2026: the foundation and the editor (10–15 Oct, 21 commits), research, reminders, the right panel's rules and the Plan (17–21 Oct), the events and their changes, the Graph and its looks (21–23 Oct), and Collect, duplicates and the World Bible (23–29 Oct). There was no release before 0.1.0.
