# Quilland user guide

English · [Français](user-guide.fr.md)

Quilland is a writing workspace for macOS. A book is a folder of plain files on your disk: the text in Markdown, everything else in JSON. Nothing is sent anywhere. The optional AI helpers use a model that runs on your own computer, through [LM Studio](https://lmstudio.ai).

Contents

1. [Getting started](#1-getting-started)
2. [The window](#2-the-window)
3. [Writing](#3-writing)
4. [Structure: parts, chapters, scenes](#4-structure-parts-chapters-scenes)
5. [Characters, World, Events and relationships](#5-characters-world-events-research-and-relationships)
6. [The Plan](#6-the-plan)
7. [Search, Replace, Proofreading, Loose Ends](#7-search-replace-proofreading-loose-ends)
8. [AI helpers](#8-ai-helpers)
9. [Snapshots](#9-snapshots)
10. [Import and export](#10-import-and-export)
11. [Settings](#11-settings)
12. [Keyboard shortcuts](#12-keyboard-shortcuts)
13. [Your files](#13-your-files)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Getting started

**Build and open the app.** See the [README](../README.md): `./make-app.sh` makes `Quilland.app`, which you open like any Mac app.

**A new book.** *File ▸ New Book…* asks for a title, an author, the language of the book (English by default, also Russian and French) and a folder. You can start with the text or with the plan. The book appears as a folder; you can put it under Git, copy it, or open it again later with *File ▸ Open Book…* (⌘O) or *Open Recent*.

**An existing manuscript.** *File ▸ Import…* (⇧⌘I) reads a Markdown, plain text or HTML file and offers to split it into chapters and scenes. See [Import and export](#10-import-and-export). Keep your original file: the import makes a copy.

**Back up first.** Quilland is under construction. Besides the automatic [snapshots](#9-snapshots), keep your own copy of anything you care about.

## 2. The window

The View menu (⌘1–⌘9 and ⌘0) chooses what the main area shows.

**Writing views**

| View | Key | What it is |
| --- | --- | --- |
| Panels | ⌘1 | The classic layout: the structure tree on the left, one scene in the middle, a tabbed panel on the right. |
| Book | ⌘2 | The scenes one after another in a single scroll, like the manuscript. A thin header between scenes shows the title, the status and the count. Each scene is still its own file. **View ▸ Split Book View** (⌘\\) splits it into two panes side by side, both editable; the split is remembered for the book, and a second choice closes it (the left pane stays, and the cursor goes to it). You can open the same scene in both: it is one text with one undo history. Search follows the side where your cursor is: a result scrolls only that side, and "This scene", "Chapter" and "Part" start from its scene. |

**Full-window views**

| View | Key | What it is |
| --- | --- | --- |
| Graph | ⌘3 | The characters, places, events and (if you switch them on) scenes as nodes, with the links between them as lines; a relationship carries its kind ("sisters"). **Whole book**, **Social graph** (characters and their relationships, thicker lines for more shared events) or **Neighbourhood** (one thing and what is around it, 1 to 3 steps out: choose it in *Look at*, or right-click a node and choose *Focus on This*). The kind switches, *Show unlinked* (a place no event uses, a character in no event: the gaps) and the section list narrow what is shown. Click a node to light it and what is joined to it, double-click to open its card, drag it to put it where you want: it stays there (kept in the book, in `plan/graph.json`), and the others are arranged around it. *Release Position* (right-click) frees one node and *Reset Layout* all of them. The view opens as you left it: its look, switches, section, focus, zoom and the place it was looking at are remembered for the book on this machine (not in Git), also after a restart; changing a setting fits the new picture to the window. It only shows: links are made on the cards. |
| Outline | ⌘4 | The structure on the left, the details of the chosen section (synopsis, note, status) on the right. |
| Plan | ⌘5 | A canvas of cards on plot lines. |
| Characters | ⌘6 | Cards of characters and the relationships between them. |
| World | ⌘7 | Worlds and places as a tree. |
| Events | ⌘8 | Events of the story. |
| Research | ⌘9 | Your reference material: notes, sources and files. |
| Reminders | ⌘0 | A checklist for the book. |

**Around the text**

- **The right panel** has the tabs *Section*, *Characters*, *World*, *Events*, *Research* and *Chat*. It follows the cursor after a short delay; tick *Pin* to hold it on one thing. Show or hide it with ⌥⌘R. A character or a place is "in" the scene when its name is in the text, or the scene is one of the scenes on its card (a line you typed for it, or, for a character, its point of view); the panel and the cards use the same rule, so a narrator who is never named still shows in the scenes you linked him to. For a character or a place that is not in the scene, the button *Add to This Scene* (under the list; switch on *All* to see everyone) links it by hand, and *Remove from This Scene* takes such a link away. **From the text:** select a name (a few words) and right-click: *Make a Character from…* and *Make a Place from…* make the card with that name and link the scene, and *Add … as a Name of* gives an existing card one more name (a nickname, another form), which the matching knows from then on.
- **The bottom panel** has *Search*, *Replace*, *Proofreading*, *Loose Ends* and *Suggestions*. It opens from the commands that use it.
- **The status bar** shows the count of the scene where the cursor is, the count of the book and today's change, the input language, and "Saved".
- **Focus Mode** (⌃⌘↩, in Book view) hides everything but the text and keeps the line you are typing in the middle of the screen.
- **Typewriter Scrolling** (⌥⌘T) does the same in the ordinary views.
- **Moving sections.** In the Outline, drag any section (it does not have to be chosen first) onto a part or a chapter, or use **Section ▸ Move To…** (also in the right-click menu): it takes the chosen scenes, or the chosen chapters, and asks where to put them (a chapter for scenes; a part, or the top level of the book, for chapters). They go to the end of the target, in their order. A right click on a chosen row keeps the whole choice, so the menu's commands act on all of them: Move To…, Group into a New Part…, Merge the Chosen Scenes, Status (for scenes) and Delete…. What needs one section (Rename, New …, Move Up and Down) is grey, with a hint.
- **Jump to Scene…** (⌘J) finds a scene by name: a list opens, type to filter, arrows and Return choose, Esc closes. It works in every view; in the Book view the list opens under the path bar, and in the split view the side where your cursor is changes while the other stays. From the other views it opens at the top of the window and takes you to the scene in the text. A link to a scene from a card view lands on the side of the split Book view you were last in.
- **Back** (⌘[) and **Forward** (⌘]) in the View menu go back and forward between the views you have been in, as in a browser. Every change of the view counts, whether you followed a link (for example from a place to a scene), pressed ⌘1–⌘0 or Esc. Back returns to the same card (the character, place, event, document or section you had chosen) and, in the writing views, to the same scene and cursor. A new change of the view drops the way forward. The status bar shows the trail at its right end, as `Characters ‹ ● › Events`: the view Back would go to, a dot for the view you are in, and the view Forward would go to.

Dragging the borders between panels changes their sizes; Quilland remembers them.

## 3. Writing

The editor shows your text as it will look. The file is Markdown, but you do not type Markdown symbols: headings, bold, italic and set-off blocks are shown as formatted text.

There is no formatting toolbar. Use the keyboard or the **Format** menu:

| What | Key |
| --- | --- |
| Bold | ⌘B |
| Italic | ⌘I |
| Heading 1, 2, 3 | ⌥⌘1, ⌥⌘2, ⌥⌘3 |
| Body text | ⌥⌘0 |
| Set-off block (a quotation, a letter) | ⌘' |
| Scene break | ⇧⌘↩ |
| Footnote… | ⌃⌘N |

**Typing corrections.** For Russian, English and French (French books get « » quotes), Quilland can replace typed characters as you write: quotes, dashes in dialogue, and so on. The ellipsis is left as three dots. You can switch each correction in *Settings ▸ Writing*.

**A pause.** An empty line you type between two paragraphs (a pause after an epigraph, say) is kept: it is saved in the file as a paragraph of `&nbsp;` and is there again when you open the book. An empty line at the very start or end of a scene is not kept. Empty lines are not counted as text and show as a gap when you export.

**Spelling.** The system spell checker underlines mistakes. Right-click a word to see the corrections. *Add to Dictionary* in the proofreading panel teaches a word to the book only, and so does *Learn Spelling* in the right-click menu of a word. The words are listed (and can be removed) in *Book Settings ▸ Dictionary* and kept in `dictionary.json`. Words that an earlier version of Quilland taught to the system itself (through *Learn Spelling*) are in the system's own dictionary, which macOS does not let an application read: add them here again if you want them to travel with the book.

**The right-click menu** is short: Cut, Copy, Paste, Paste and Match Style, Spelling and Grammar, and the AI submenu. The rest of the system's text menu (fonts, substitutions, speech and so on) is left out on purpose.

**Book text size.** *View ▸ Larger Book Text / Smaller Book Text / Usual Book Text Size* (⌥⌘+, ⌥⌘−, ⌥⌘0) change the text size of the book. The font, line spacing and reading width are in *Settings ▸ Appearance*. These settings change only the book's text, not the labels of the application.

**Undo and redo** (⌘Z, ⇧⌘Z) work in the text. Structure changes (moving or deleting sections) have their own undo, shown in a banner above the tree.

## 4. Structure: parts, chapters, scenes

A book is made of **parts** (optional), **chapters** and **scenes**. A scene is the unit you write in: each scene is its own file. The tree on the left (Panels view) or in the Outline shows the structure. The arrow beside the "+" under the tree closes every part and chapter, or opens them all again.

The **Section** menu does the work. It offers only what can be done now: for example, *Move Up* is greyed for the first scene of the book, or the first chapter, *Merge with Next Scene* for the last scene, and *Status* when a chapter is chosen.



- *New Scene* (⌘N), *New Scene Before*, *New Chapter* (⇧⌘N), *New Part* (⌥⇧⌘N)
- *Rename*, and *Status* (for example draft, done); the coloured dot in the tree shows the status
- *Move Up / Move Down* (⌥⌘↑, ⌥⌘↓), or drag in the tree; a scene at the edge of its chapter moves into the neighbouring chapter (to the end of the previous one, or the start of the next)
- *Split Scene Here* (⌥⌘↩) splits at the cursor; *Merge with Next / Previous Scene*; *Merge Chosen Scenes* joins the scenes you selected (merging always asks first, and works within one chapter: move a scene into the other chapter first if you need to)
- *Group into a New Part…* and *Ungroup Part…*
- *Delete…* always asks first

Each section also has a **synopsis** and a **note**, edited in the *Section* tab of the right panel or in the Outline. The synopsis can be written by the AI (see below).

## 5. Characters, World, Events, Research and relationships

These views keep cards: a name, aliases, a description, notes and fields of the kind. Quilland knows the names and aliases, so the right panel shows which characters and places appear in the scene you are writing.

- **Characters** (⌘6): the list on the left, the card on the right. A character has a list of scenes where they appear and a list of relationships. The list holds the scenes that name the character, the ones where they are the point of view, and the ones you add by hand with *Add a Scene…* (for a scene where the name is not written); type what the character does there, and *Remove Link* takes the line and the point of view away again. The same list holds the **events** the character takes part in (marked ◆): *Add a Scene or Event…* offers them under the scenes, a double-click opens the event, and the link is kept in the character's file, as in the Events view.
- **Relationships** link two characters (for example "sister", "enemy") and can be opened as their own card.
- **World** (⌘7): worlds and places as a tree, with a card for each. A place lists the scenes that name it; *Add a Scene…* links one where the name is not written, you type what happens there, and *Remove Link* takes the line away. The same list holds the **events** held at the place (marked ◆): *Add a Scene or Event…* offers them under the scenes (the place is written into the event's file, as in the Events view), a double-click opens the event, and *Remove Link* takes the place away from it.
- **Events** (⌘8): things that happen in the story, with the scenes and characters they belong to. The list is grouped under a heading for each scene (the first scene an event is linked to), in the order of the book, with the events linked to no scene last. Two events of one scene are put in order **by hand**: drag one up or down inside its group, or use *Move Up* and *Move Down* in the right-click menu, or ⌥⌘↑ and ⌥⌘↓. An event cannot leave its scene by being moved: its scene is decided by its links. The order is kept in the events' files (an `order` number, given only to the events of the scene you reorder), and ordering is off while the list is filtered. In the *Add…* menu (and in Research's *Link to…*) the places are listed under the name of their world, in alphabetical order, so a place of another world is easy to find; to link an event to a whole world, make a top-level place in it.
- **Research** (⌘9): the material you gathered for the book, for example the history of music education in the USA. A *document* has a title, a *source* (a book, an article, an address), your own typed text, and, if you like, a file. Each can be there or not: a document may be only text, only a file, or both. A file is either *copied into the book* (it travels with the book and its Git history; Quilland asks first above 20 MB) or only *linked* (it stays where it is, outside the book; the link is for this Mac, and if the file moves Quilland shows it as missing and does not forget it). *Open* and *Show in Finder* work on the file. A document can be linked to the whole book, a scene, a character, a place or an event, with a remark for each; double-click a link to go there. The *Research* tab of the right panel lists the documents linked to the scene you are in and lets you read and change their text. To add a note without leaving the text, type a title in the field at the top of the tab and press Return: the document is linked to the scene you are in, and the cursor goes to its text. *From a File…* makes a document from a file (copied into the book, or only linked if it is over 20 MB). Filtering the list looks in titles, sources, remarks and text. Deleting a document sends it to the trash folder.

**The same person on two cards.** If the AI (or you) made two cards for one person, right-click the one to remove, or press *Merge Into…* on its card, and choose the character to keep. The removed card's name and aliases become aliases of the kept one, so the AI and the text matching recognise the name from now on; its profile, notes, scenes and relationships are added to the kept character's, and the card goes to the book's trash folder. A snapshot is taken first, and the banner's Undo (or ⌘Z) takes the merge back.

**Places and worlds.** In the World view, right-click a place or a world (or use the buttons on its card) for the same kind of tools: *Merge Into…* joins two places, or two worlds, into one (the removed one's name becomes an alias, its places and links move over). If the AI took a whole world for a place, choose *Turn Into a World…*: the place becomes a world of its own and the places inside it are at the top of that world. The opposite, *Turn Into a Place…*, puts a world inside another world, or inside one of its places. Each is one change with a snapshot before and after, and Undo takes it back.

**Filters by relation.** Under the word filter of the Characters, World and Events views, *Filter by…* lets you show only what is related to a **section** (a part, a chapter or a scene), an **event**, a **character** or a **place**, whichever of these the view does not list itself. For example: the characters in Chapter 3; the events a character takes part in; the places where an event happens; the events in a scene. Each filter shows as a chip you can click to take it off, with "3 of 12" beside it, and filters combine (everything must match), together with the word filter. A link is stored on one side only, and the filter reads it from either side: a character's link to an event is kept in the character's file, an event's places in the event's, and the filter answers both "who is in this event" and "what is this character in". A character is "in" a scene when the name is in its text, the scene has a line for the character, or it is the character's point of view; a place the same, without the point of view. A character has been **at a place** only when they take part in an event held there (the character's link to the event and the event's place): sharing a scene with the place does not count, so filtering the characters by a place shows nobody until you have linked participants to the events held there, and filtering the places by a character shows the places of the events that character takes part in. Hover over a chip to see what its filter means. A filter on something you then delete goes away by itself.

Names are matched by rules that handle Russian endings (an "Анне" is found as "Анна"), so an alias list is usually enough.

**Reminders (⌘0).** A checklist for the book: things to check, fix or do. Type one at the bottom and press Return (a reminder may have several lines: Shift-Return starts a new line; long lines wrap); tick the box when it is done (done ones move under a "Done" heading, and can be brought back); click the text to change it; ✕ deletes it, and the banner that follows offers Undo. The list is saved in `reminders.json` in the book's folder, so it goes with the book through Git. When you open a book that has reminders not yet done, a window lists them; tick the ones you have done there, and close it. *Settings ▸ General* can turn that window off.

## 6. The Plan

The Plan (⌘5) is a canvas. A **card** is an idea for something that will happen. Cards stand on **plot lines**, the horizontal lanes with a name and a colour. Drag a card along or between lines. Events that are already written appear on the same canvas in grey, so you can see what is done and what is still planned.

- **No stacking.** Two cards, or two events, never stand in the same place on a line: one dropped (or put on the plan) where another of its kind already stands goes to a new row just after it, and nothing else moves. Items on different lines may stand level, which means the same moment, and a card may stand over an event (they are two layers). A floating card dropped on another floating card is moved down to a free spot.
- **Colours of cards and events.** Click a card or an event, and ⌘-click (or Shift-click) more of them to choose several. A chosen one is tinted, has a heavy outline and a check mark, and the toolbar says how many are chosen; a click on empty canvas clears the choice. Right-click one of the chosen ones and pick *Color ▸* a colour, shown with a small swatch beside its name: all the chosen cards and events get it at once, and one Undo takes it back. *No Color* (offered when an event is among them) gives an event its plain look again. A card's colour can also be set in its window (double-click). An event's colour is kept in the event's own file.
- Double-click a line's title to edit it, or right-click it for *Edit…*, colour, move and delete.
- *Show from* limits the plan to part of the book.
- ⌘+ and ⌘− zoom the canvas, ⇧⌘0 fits it to the window.

## 7. Search, Replace, Proofreading, Loose Ends

All four live in the bottom panel.

**Search** (⌘F) finds text as you type, in the scenes and, if you choose, in notes and synopses. ⌘G and ⇧⌘G go to the next and previous match.

**Replace** (⌥⌘F) is deliberately careful. You choose each time what to search in. The results are unticked until you tick them. Return never replaces. Every replace shows a warning with *Cancel* as the default, takes a snapshot first, and can be undone. An empty replacement deletes the matches, and the button says so.

**Proofreading** (⌥⌘P) lists problems in a scene, a chapter or the book:

- *Rules*: typography, such as dashes, spaces and quotes
- *Spelling*, using the system dictionary and your book's own dictionary (character names are not flagged)
- *Check Grammar* uses the AI to propose corrections as a before/after pair

Choose a finding to see what the rule does. *Accept* changes the text (⌘Z takes it back), *Dismiss* hides the finding for good, *Add to Dictionary* teaches a word, and *Accept All in this Scene* applies the whole list of that scene. *Show Dismissed Again* brings hidden findings back. Return never accepts a finding.

**Loose Ends** (⌥⌘L) lists problems in the book itself: damaged or missing files and records that point at nothing, so you can see them and decide what to do.

## 8. AI helpers

The AI is optional. Everything else works without it. It uses a model that runs on your computer; nothing leaves it.

**Set up**

1. Install [LM Studio](https://lmstudio.ai) and load a model. Quilland was tuned with `qwen3-14b`; others may work worse.
2. Start LM Studio's local server (the default address is `http://localhost:1234`).
3. In Quilland, open *Settings ▸ AI* and press the connection check. It names the model and how many tokens it reads at once.

The AI menu shows the connection status at the top. Anything the model proposes is a **suggestion**. Nothing is stored until you accept it.

**What it can do**

| Action | Where | What it does |
| --- | --- | --- |
| Continue Writing | AI menu, ⌃⌘G; right-click ▸ AI | Writes the next paragraph as faint text. **Tab** accepts it, **Esc** drops it. *…with a Direction* (⇧⌃⌘G) lets you say where it should go. |
| Write Synopsis | AI menu, ⌃⌘Y; the *Write with AI* button in the Section tab | Writes a short summary of the scene into an empty synopsis. |
| Collect from the Book… | AI menu, ⌥⌘K | Reads the scenes and proposes characters, places, events and relationships with the quotes they come from. The window opens on the current scene (the whole book when none is current); choose the chapter, the part or the whole book to read more. Every run reads all the scenes of the scope you choose and starts from an empty Suggestions list: what an earlier run found, and what was left waiting, is removed. Accepting an event also links the characters who take part in it (those that have a card, or get one in the same run); the link is kept in the character's file. A finding that cannot be accepted (a note about something that has no card, a relationship whose characters have no cards) stays in the list, unticked, with the reason under it, and the result line names it. |
| Check Consistency… | AI menu, ⌥⌘Y; right-click ▸ AI | Looks for contradictions between scenes (eye colour, age, who knows what). Each finding quotes both places. |
| Check Grammar | AI menu, ⌥⇧⌘G; the Proofreading panel | Proposes corrections of grammar. |
| Chat | the *Chat* tab of the right panel | Ask questions about your book. Attach the scene, characters, places or the plan with **@**. The model only answers; it changes nothing. |
| Actions | AI menu ▸ Actions | Your own saved prompts. |

All proposals go to the **Suggestions** tab of the bottom panel (⌥⇧⌘J). Tick what you want and accept it. Quotes are checked against the text, so a quote the model invented is dropped.

**Your own prompts.** In the Chat tab, a prompt can be saved with *Save Prompt as Action…*. Saved actions appear in the AI menu and in *Settings ▸ AI Prompts* next to the built-in ones. The built-in prompts are marked "System"; yours are unmarked and can be renamed, edited and deleted. You can also change the wording of the built-in prompts there. The placeholder `{language}` is replaced by the book's language.

A long job (collecting from the whole book, a consistency check) shows a progress bar and can be stopped.

## 9. Snapshots

A snapshot is a copy of the whole book at a moment. Quilland takes one automatically every 15 minutes while you write (change the interval in *Settings ▸ General*) and before risky operations such as Replace.

- *File ▸ Save Snapshot* (⌘S) and *Save Named Snapshot…* (⌥⌘S) make your own.
- *File ▸ Snapshots…* (⇧⌘S) lists them and restores one.
- Snapshots are cheap: they share unchanged files on disk, and old ones are thinned out.

## 10. Import and export

**Import** (*File ▸ Import…*, ⇧⌘I) reads one Markdown, plain text or HTML file. Choose the encoding if the text looks wrong. The window lists the kinds of title-like lines it found (headings of levels 1 to 6, "Chapter N", "Prologue", numbers, short capital lines…); for each one, *Becomes* says what it makes: a part, a chapter, a scene, or not a title. Check the preview of the tree before you confirm. You can import into a new book or at the end of the open one. The import can be undone.

Not built yet: importing a whole folder of Markdown files, and importing into the middle of a book.

**Export** (*File ▸ Export…*, ⌘E) writes DOCX, PDF, FB2, EPUB, HTML or plain text (always UTF-8). The window has profiles, a list of the sections to include and a preview where Quilland draws the file itself. The DOCX files have been checked in Pages, not in Microsoft Word.

## 11. Settings

*Quilland ▸ Settings…* (⌘,) has these sections: General, Appearance, Writing, Panels, AI, AI Prompts and Shortcuts. The search field at the top finds a setting by its name.

- **General:** interface language (English, Russian and French; English is the default), the folder for books, the recent list, what opens at start, the snapshot interval.
- **Appearance:** font, text size, line spacing, reading width of a sheet, light or dark.
- **Writing:** typing corrections and spelling.
- **Panels:** the right panel's tabs and how fast it follows the cursor.
- **AI:** the address of LM Studio, the model, and the connection check.
- **AI Prompts:** the prompts of each helper and your saved actions.
- **Shortcuts:** change the key of any command. Select a row and press the new key.

*File ▸ Book Settings…* (⇧⌘,) holds what belongs to one book: its language, its title and cover, its target size, and its own dictionary.

**Size of the book.** Choose a *Type of book* (flash fiction, short story, novelette, novella, short novel, novel, epic) and Quilland fills in a typical *Target size* for the book's language, in characters with spaces; you can type any other number, and the type then reads "Custom". Under the target you see it in words, and for Russian and Ukrainian books in author's sheets (1 sheet = 40,000 characters with spaces). *Size now* shows how big the book is at this moment (characters, words, sheets) and how far it has come, with a bar; the status bar shows the same as "book 123,456 of 540,000 (23%)". Changing the language of a book that has a type gives the type's target in the new language.

## 12. Keyboard shortcuts

These are the defaults. Every one can be changed in *Settings ▸ Shortcuts*.

**Files**

| Key | Command |
| --- | --- |
| ⌘N | New Book (only while no book is open; with a book open, ⌘N is New Scene) |
| ⌘O | Open Book |
| ⌘S | Save Snapshot |
| ⌥⌘S | Save Named Snapshot |
| ⇧⌘S | Snapshots |
| ⇧⌘I | Import |
| ⌘E | Export |

**Views**

| Key | Command |
| --- | --- |
| ⌘1 ⌘2 ⌘3 | Panels, Book, Graph |
| ⌘\\ | Split the Book view in two |
| ⌘4 ⌘5 ⌘6 ⌘7 ⌘8 ⌘9 ⌘0 | Outline, Plan, Characters, World, Events, Research, Reminders |
| ⌘J | Jump to Scene |
| ⌘[ ⌘] | Back, Forward between views |
| ⌥⌘R | Show or hide the right panel |
| ⌃⌘↩ | Focus Mode |
| ⌥⌘T | Typewriter Scrolling |
| ⌘+ ⌘− ⇧⌘0 | Zoom the Plan or the Graph, fit it to the window |
| ⌥⌘+ ⌥⌘− ⌥⌘0 | Larger, smaller, usual book text size |

**Finding and checking**

| Key | Command |
| --- | --- |
| ⌘F, ⌥⌘F | Find, Replace |
| ⌘G, ⇧⌘G | Find Next, Previous |
| ⌥⌘P | Proofread |
| ⌥⌘L | Loose Ends |

**Writing**

| Key | Command |
| --- | --- |
| ⌘B, ⌘I | Bold, italic |
| ⌥⌘1 ⌥⌘2 ⌥⌘3 ⌥⌘0 | Headings 1–3, body text |
| ⌘' | Set-off block |
| ⇧⌘↩ | Scene break |
| ⌃⌘N | Footnote |
| ⌘N, ⇧⌘N, ⌥⇧⌘N | New scene (with a book open), chapter, part |
| ⌥⌘↩ | Split scene here |
| ⌥⌘↑, ⌥⌘↓ | Move section up, down |

**AI**

| Key | Command |
| --- | --- |
| ⌃⌘G | Continue Writing (Tab accepts, Esc drops) |
| ⇧⌃⌘G | Continue Writing with a Direction |
| ⌃⌘Y | Write Synopsis |
| ⌥⌘K | Collect from the Book |
| ⌥⇧⌘G | Check Grammar |
| ⌥⌘Y | Check Consistency |
| ⌥⇧⌘J | Show Suggestions |

## 13. Your files

A book is a folder. You can open it in Finder, put it under Git, and copy it. In outline:

- `book.json`: the book's title, language and settings. `reminders.json`: the reminders.
- `manuscript/`: the structure. Each scene is a `.md` file (the text) with a `.json` file beside it (status, synopsis, note); chapters and parts are folders.
- Folders for characters, world, events, relationships and the plan hold one JSON file per card. `research/` holds the research documents: a `.json` file, a `.md` file with the text, and a folder `<id>.file/` with a copied file.
- Snapshots and the search cache are kept beside the book and are safe to delete; Quilland rebuilds the cache.

Quilland's own settings live in your user folder: preferences, `prompts.json` (changed prompts) and `actions.json` (saved actions). You can back them up or copy them to another Mac.

Edit the files outside Quilland only when the app is closed, and keep a copy. If another program changes a scene while Quilland has it open (a Git checkout, a synchronised folder), Quilland keeps that version in the trash folder and says so before it saves its own, so that neither is lost; a save that fails is shown in the status bar as "Not saved". If a file is damaged, *Loose Ends* names it.

## 14. Troubleshooting

**The AI menu is greyed out.** The status line at the top of the AI menu says why: usually LM Studio is not running, its server is off, or no model is loaded. Fix that, then use the connection check in *Settings ▸ AI*.

**A long AI job seems stuck.** Look for the progress bar and the orange status line. A local model can take minutes on a long book. The *Stop* button ends the job and keeps what was found.

**The model's answers are poor or in the wrong language.** Try a larger model. Check the book's language in *Book Settings*, and read the prompt in *Settings ▸ AI Prompts*.

**A name is not found in a scene.** Add the form as an alias on the card.

**Something changed that should not have.** Open *File ▸ Snapshots…* and restore the book from before the change.

**The app behaves strangely after an update.** Quit it fully (⌘Q), then open it again.

If you find a problem, please report it with the steps that cause it.
