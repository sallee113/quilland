import AppKit
import QuillandCore

/// `Quilland --selftest-lab`: drives the real views in a real window and checks what the design depends on.
final class LabSelfTest {
    private var passed = 0
    private var failed = 0
    private let lab: LabWindowController

    init(lab: LabWindowController) { self.lab = lab }

    private func check(_ ok: Bool, _ what: String, _ detail: @autoclosure () -> String = "") {
        if ok { passed += 1; print("  ok   \(what)") } else { failed += 1; print("  FAIL \(what) \(detail())") }
    }

    private func spin(_ seconds: TimeInterval = 0.1) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func tempBook(big: Bool) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("quilland-labtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if big { try LabBookGenerator.generate(into: folder) } else { try SampleBook.write(into: folder) }
        return folder
    }

    func run() -> Int32 {
        do {
            try bookMode()
            try compareMode()
            try typewriterMode()
            try planCanvas()
        } catch {
            print("  FAIL exception: \(error)")
            failed += 1
        }
        print("\n\(passed) passed, \(failed) failed")
        return failed == 0 ? 0 : 1
    }

    // MARK: 1. Book mode: a stack of scene editors

    private func bookMode() throws {
        print("Book mode")
        let folder = try tempBook(big: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        lab.setMode(compare: false)
        lab.load(folder: folder)
        spin(0.3)
        guard let c = lab.firstController, let session = lab.currentSession else { check(false, "the book opens"); return }
        let sheets = c.stack.sheets
        check(sheets.count == 8, "one sheet per scene", "\(sheets.count)")
        check(c.stack.rows.count == 8 * 2 + 2 + 5, "a header and a sheet for every scene, a band for each of 2 parts and 5 chapters", "\(c.stack.rows.count)")
        check(zip(sheets, sheets.dropFirst()).allSatisfy { $0.frame.maxY < $1.frame.minY }, "sheets do not overlap, in book order")

        // Typing in the first scene.
        c.focus(sceneID: sheets[0].document.id, atEnd: true)
        spin(0.05)
        let first = sheets[0]
        let y1 = sheets[1].frame.minY
        let h1 = first.height
        first.textView.insertText("\n\nНовый абзац, который добавили при проверке.", replacementRange: first.textView.selectedRange())
        spin(0.2)
        check(c.currentSceneID == first.document.id, "the scene with the cursor is the current one")
        check(first.document.isDirty || first.document.saveCount > 0, "typing marks the scene unsaved")
        check(sheets[0].height > h1 && abs((sheets[1].frame.minY - y1) - (sheets[0].height - h1)) < 1, "the sheets below move down when a sheet grows", "\(sheets[0].height - h1) vs \(sheets[1].frame.minY - y1)")
        first.document.saveNow()
        let saved = try String(contentsOf: first.document.url, encoding: .utf8)
        check(saved.contains("Новый абзац, который добавили при проверке."), "the scene is saved to its own file")
        check(!saved.contains("Часть") , "and only that scene's text is in the file")

        // Walking across the boundary.
        let doc0 = sheets[0].textView
        doc0.setSelectedRange(NSRange(location: doc0.textStorage!.length, length: 0))
        doc0.moveDown(nil)
        spin(0.05)
        check(c.currentSceneID == sheets[1].document.id, "arrow down at the end of a scene goes into the next one", "\(String(describing: c.currentSceneID))")
        check(sheets[1].textView.window?.firstResponder === sheets[1].textView, "the next scene's editor has the focus")
        sheets[1].textView.setSelectedRange(NSRange(location: 0, length: 0))
        sheets[1].textView.moveUp(nil)
        spin(0.05)
        check(c.currentSceneID == sheets[0].document.id, "arrow up at the start of a scene goes back")
        // From the start of the last line, Down goes straight into the next scene (it does not first run to the end of the line).
        let tv0 = sheets[0].textView
        let length = tv0.textStorage!.length
        let startOfLastLine = tv0.startOfLastLine()
        tv0.window?.makeFirstResponder(tv0)
        tv0.setSelectedRange(NSRange(location: startOfLastLine, length: 0))
        spin(0.05)
        check(startOfLastLine < length - 3 && startOfLastLine > 0, "the last line is long enough to test with", "\(length - startOfLastLine)")
        tv0.moveDown(nil)
        spin(0.05)
        check(c.currentSceneID == sheets[1].document.id, "Down from the start of the last line goes into the next scene", "\(String(describing: c.currentSceneID))")
        sheets[1].textView.moveUp(nil)   // the first line of the next scene: straight back
        spin(0.05)
        check(c.currentSceneID == sheets[0].document.id, "Up from the first line goes back into the previous scene")
        // A selection never runs across two scenes.
        sheets[0].textView.setSelectedRange(NSRange(location: max(0, sheets[0].textView.textStorage!.length - 3), length: 0))
        sheets[0].textView.moveDownAndModifySelection(nil)
        check(c.currentSceneID == sheets[0].document.id && sheets[0].textView.selectedRange().length <= 3, "a selection stops at the end of the scene")
        session.saveAll()
        everyBoundary(c, label: "typewriter off")
        c.setTypewriter(true)
        spin(0.3)
        everyBoundary(c, label: "typewriter on")
        walkDown(c, label: "typewriter on")
        c.setTypewriter(false)
        spin(0.2)
        walkDown(c, label: "typewriter off")
    }

    /// From the start of the last line of every scene, Down goes into the next scene, with typewriter scrolling on and off.
    private func everyBoundary(_ c: BookViewController, label: String) {
        let sheets = c.stack.sheets
        var failures: [String] = []
        for i in 0..<(sheets.count - 1) {
            let tv = sheets[i].textView
            let length = tv.textStorage!.length
            let start = tv.startOfLastLine()
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: start, length: 0))
            spin(0.2)
            tv.moveDown(nil)
            spin(0.2)
            if c.currentSceneID != sheets[i + 1].document.id { failures.append("scene \(i + 1) (\(sheets[i].document.title)): start of last line \(start) of \(length), ended in \(String(describing: c.currentSceneID)), selection \(tv.selectedRange())") }
        }
        check(failures.isEmpty, "\(label): Down from the start of the last line goes on into the next scene, in every scene", failures.joined(separator: "; "))
    }

    /// Walking down with the arrow key from the top of a scene: whenever the cursor is on the last line, the next press crosses into the next scene
    /// (it must never run along the last line first).
    private func walkDown(_ c: BookViewController, label: String, scenes: Int = 6) {
        let sheets = c.stack.sheets
        var failures: [String] = []
        for i in 0..<min(sheets.count - 1, scenes) {
            let tv = sheets[i].textView
            let length = tv.textStorage!.length
            guard let end = tv.caretRect(at: length) else { continue }
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            spin(0.15)
            var presses = 0
            while presses < 400 {
                let onLast = (tv.caretRect().map { abs($0.minY - end.minY) < 1 }) ?? false
                let before = tv.selectedRange()
                tv.moveDown(nil)
                presses += 1
                spin(0.12)
                let crossed = c.currentSceneID == sheets[i + 1].document.id
                if crossed { if !onLast { failures.append("scene \(i + 1) crossed while not on its last line") }; break }
                if onLast { failures.append("scene \(i + 1): the press on the last line (position \(before.location) of \(length)) did not cross; now at \(tv.selectedRange().location)"); break }
            }
        }
        check(failures.isEmpty, "\(label): from the last line the next press crosses into the next scene", failures.joined(separator: "; "))
    }

    // MARK: 2. Compare: two views on one text

    private func compareMode() throws {
        print("Compare: two views on the same text")
        let folder = try tempBook(big: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        lab.setMode(compare: true)
        lab.load(folder: folder)
        spin(0.4)
        let controllers = lab.allControllers
        check(controllers.count == 2, "two areas")
        lab.window.contentView?.layoutSubtreeIfNeeded()
        spin(0.2)
        check(controllers.count == 2 && abs(controllers[0].view.frame.width - controllers[1].view.frame.width) < 2 && controllers[1].view.frame.width > 400, "the two areas are equal in width", "\(controllers.map { $0.view.frame.width })")
        guard controllers.count == 2, let session = lab.currentSession else { return }
        let left = controllers[0].stack.sheets[2], right = controllers[1].stack.sheets[2]
        check(left.document === right.document && left.textView !== right.textView, "the same scene is open in both, in two views of one text")
        let before = left.textView.string
        controllers[0].focus(sceneID: left.document.id, atEnd: true)
        spin(0.05)
        left.textView.insertText(" ВТОРОЕ-ОКНО", replacementRange: left.textView.selectedRange())
        spin(0.3)
        check(right.textView.string == left.textView.string && right.textView.string.contains("ВТОРОЕ-ОКНО"), "typing in one area shows live in the other")
        print("       debug: left sheet \(left.frame), right sheet \(right.frame), left stack \(controllers[0].stack.frame.width), right stack \(controllers[1].stack.frame.width), clip widths \(controllers[0].scrollView.contentView.bounds.width) \(controllers[1].scrollView.contentView.bounds.width), containers \(left.textView.textContainer!.size.width) \(right.textView.textContainer!.size.width)")
        check(abs(right.height - left.height) < 1, "both views have the same height", "\(left.height) vs \(right.height)")
        // Typing in the other area.
        controllers[1].focus(sceneID: right.document.id, atEnd: true)
        spin(0.05)
        right.textView.insertText(" И-ЕЩЁ", replacementRange: right.textView.selectedRange())
        spin(0.3)
        check(left.textView.string.contains("И-ЕЩЁ"), "both areas are editable: typing in the right one shows in the left one")
        check(left.document.saveCount == 0 && left.document.isDirty, "one text, one autosave: unsaved once, not twice")
        // One undo history.
        let undo = right.textView.undoManager
        check(undo != nil && undo === left.textView.undoManager, "one undo manager for both")
        undo?.undo()
        spin(0.1)
        check(!left.textView.string.contains("И-ЕЩЁ") && !right.textView.string.contains("И-ЕЩЁ"), "undo removes the last typing from both views")
        _ = before
        session.saveAll()
        let saved = try String(contentsOf: left.document.url, encoding: .utf8)
        print("       after undo the views show: …\(left.textView.string.suffix(30))")
        check(saved.contains(left.textView.string.suffix(12).replacingOccurrences(of: AttributedBridge.object, with: "")), "the file has what both areas show", "file ends: \(saved.suffix(40))")
    }

    // MARK: 3. Typewriter scrolling, at the size of a novel

    private func typewriterMode() throws {
        print("Typewriter scrolling and the size of a novel")
        let folder = try tempBook(big: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        lab.setMode(compare: false)
        let started = CACurrentMediaTime()
        lab.load(folder: folder)
        let opened = CACurrentMediaTime()
        spin(0.4)
        print("       opening 100 scenes: \(Int((opened - started) * 1000)) ms")
        check(opened - started < 4, "100 scenes open in under 4 seconds")
        guard let c = lab.firstController else { return }
        c.setTypewriter(true)
        spin(0.2)
        walkDown(c, label: "a novel, typewriter on", scenes: 3)
        let sheet = c.stack.sheets[50]
        c.focus(sceneID: sheet.document.id)
        spin(0.1)
        let tv = sheet.textView
        tv.setSelectedRange(NSRange(location: (tv.textStorage?.length ?? 0) / 2, length: 0))
        spin(0.3)
        let clip = c.scrollView.contentView
        func caretOffset() -> CGFloat {
            let inStack = c.stack.convert(tv.caretRect() ?? .zero, from: tv)
            return inStack.midY - clip.bounds.origin.y - clip.bounds.height / 2
        }
        print("       debug: clip origin \(clip.bounds.origin.y) height \(clip.bounds.height), stack height \(c.stack.frame.height), sheet y \(sheet.frame.minY), caret offset \(caretOffset()), responder \(String(describing: tv.window?.firstResponder === tv))")
        check(abs(caretOffset()) < 12, "the cursor's line is in the middle of the screen", "off by \(caretOffset())")
        // Typing 400 characters: the line stays in the middle while the text grows.
        var worst: CGFloat = 0
        for i in 0..<40 {
            tv.insertText("слово\(i) и ещё слова, чтобы строка росла и росла. ", replacementRange: tv.selectedRange())
            spin(0.16)   // the scroll is animated for 0.12 s
            worst = max(worst, abs(caretOffset()))
        }
        print("       worst distance from the middle while typing: \(Int(worst)) points")
        check(worst < 24, "while typing, the line stays in the middle (within 24 points)", "\(worst)")
        // Arrow keys recentre.
        for _ in 0..<12 { tv.moveUp(nil); spin(0.16) }
        check(abs(caretOffset()) < 24, "moving with the arrow keys keeps the line in the middle", "\(caretOffset())")
        // Walking from the first scene's start: the first line can be brought to the middle too.
        let firstSheet = c.stack.sheets[0]
        c.focus(sceneID: firstSheet.document.id)
        firstSheet.textView.setSelectedRange(NSRange(location: 0, length: 0))
        spin(0.4)
        let y = c.stack.convert(firstSheet.textView.caretRect() ?? .zero, from: firstSheet.textView).midY - clip.bounds.origin.y - clip.bounds.height / 2
        check(abs(y) < 24, "even the first line of the book can be in the middle", "\(y)")
        c.setTypewriter(false)
        spin(0.2)
        // Without typewriter scrolling the view follows the cursor: it never leaves the screen when moving down or up.
        c.focus(sceneID: c.stack.sheets[10].document.id)
        let walker = c.stack.sheets[10].textView
        walker.setSelectedRange(NSRange(location: 0, length: 0))
        spin(0.2)
        var outside = 0
        var presses = 0
        for _ in 0..<60 {
            walker.moveDown(nil)
            presses += 1
            spin(0.02)
            if let r = walker.caretRect() {
                let inStack = c.stack.convert(r, from: walker)
                if !c.scrollView.contentView.bounds.contains(inStack) { outside += 1 }
            }
        }
        check(outside == 0, "without typewriter scrolling the cursor stays on the screen while moving down line by line", "\(outside) of \(presses) presses left the cursor outside")
        var outsideUp = 0
        walker.window?.makeFirstResponder(walker)
        walker.setSelectedRange(NSRange(location: walker.textStorage!.length, length: 0))
        spin(0.2)
        for _ in 0..<20 {
            walker.moveUp(nil)
            spin(0.02)
            if let r = walker.caretRect(), !c.scrollView.contentView.bounds.contains(c.stack.convert(r, from: walker)) { outsideUp += 1 }
        }
        check(outsideUp == 0, "and while moving up", "\(outsideUp) presses")
        // Typing at the bottom of the screen scrolls too.
        walker.setSelectedRange(NSRange(location: walker.textStorage!.length, length: 0))
        spin(0.1)
        var outsideTyping = 0
        for i in 0..<60 {
            walker.insertText("строка \(i)\n", replacementRange: walker.selectedRange())
            spin(0.02)
            if let r = walker.caretRect(), !c.scrollView.contentView.bounds.contains(c.stack.convert(r, from: walker)) { outsideTyping += 1 }
        }
        check(outsideTyping == 0, "and while typing new lines", "\(outsideTyping) of 60")
        lab.saveAll()
    }

    // MARK: 4. The Plan canvas

    private func mouse(_ type: NSEvent.EventType, in canvas: NSView, at point: NSPoint) -> NSEvent {
        let window = canvas.window!
        return NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// A real drag: the mouse goes down on the view, moves, and goes up.
    private func drag(_ view: PlanItemView, to target: NSPoint, in canvas: NSView) {
        let from = NSPoint(x: view.frame.midX, y: view.frame.midY)
        view.mouseDown(with: mouse(.leftMouseDown, in: canvas, at: from))
        view.mouseDragged(with: mouse(.leftMouseDragged, in: canvas, at: NSPoint(x: (from.x + target.x) / 2, y: (from.y + target.y) / 2)))
        view.mouseDragged(with: mouse(.leftMouseDragged, in: canvas, at: target))
        view.mouseUp(with: mouse(.leftMouseUp, in: canvas, at: target))
    }

    private func planCanvas() throws {
        print("The Plan canvas")
        let folder = try tempBook(big: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        lab.setMode(compare: false)
        lab.load(folder: folder)
        try LabPlanGenerator.generate(into: folder)
        lab.setPlanMode()
        spin(0.4)
        guard let plan = lab.planController else { check(false, "the plan opens"); return }
        let canvas = plan.canvas
        func cards() -> [PlanItemView] { canvas.itemViews.filter { $0.item.kind == .card } }
        func events() -> [PlanItemView] { canvas.itemViews.filter { $0.item.kind == .event } }
        func card(_ title: String) -> PlanItemView { cards().first { $0.item.title == title }! }
        func disk() -> PlanStore { try! PlanStore(folder: folder) }

        check(canvas.headers.count == 3 && cards().count == 13 && events().count == 5, "3 lines, 13 cards (3 floating) and 5 real events are drawn", "\(canvas.headers.count) \(cards().count) \(events().count)")
        // Rows: what has the same position is level, in every line.
        let at100 = cards().filter { $0.item.start == 100 }
        check(at100.count == 2 && Set(at100.map { $0.frame.minY }).count == 1, "cards with the same position are level across the lines", "\(at100.count)")
        let ys = [100, 200, 300, 400, 500].map { s in cards().first { $0.item.start == s }!.frame.minY }
        check(ys == ys.sorted() && Set(ys).count == 5, "the story goes down: later positions are lower")
        // Layers.
        let order = canvas.subviews
        let lastEvent = order.lastIndex { ($0 as? PlanItemView)?.item.kind == .event } ?? -1
        let firstCard = order.firstIndex { ($0 as? PlanItemView)?.item.kind == .card } ?? Int.max
        check(lastEvent < firstCard, "in Plan mode the cards are above the events")
        check(events().allSatisfy { !$0.isTopLayer } && cards().allSatisfy(\.isTopLayer), "the events below are grayed, the cards are not")
        let pairedEvent = events().first { $0.item.title == "Анна находит ключ" }!
        let pairedCard = card("Captain wakes on the yacht")
        check(abs(pairedCard.frame.minX - pairedEvent.frame.minX + PlanLayout.layerOffset.x) < 0.5 && abs(pairedCard.frame.minY - pairedEvent.frame.minY + PlanLayout.layerOffset.y) < 0.5, "an event peeks out from under its card, a little to the left and up")

        // Nothing moves when the mode changes; only the layers swap.
        let planFrames = Dictionary(uniqueKeysWithValues: canvas.itemViews.map { ("\($0.item.kind)-\($0.item.id)", $0.frame) })
        plan.setMode(.events)
        let eventFrames = Dictionary(uniqueKeysWithValues: canvas.itemViews.map { ("\($0.item.kind)-\($0.item.id)", $0.frame) })
        check(planFrames == eventFrames, "no card or event changes its place when the mode changes (the events stay a little to the left)")
        plan.setMode(.plan)

        // The mode follows the click.
        plan.itemClicked(events()[0])
        check(plan.mode == .events, "clicking an event card switches to Events mode")
        let order2 = canvas.subviews
        let lastCard = order2.lastIndex { ($0 as? PlanItemView)?.item.kind == .card && ($0 as? PlanItemView)?.item.lineIndex != nil } ?? -1
        let firstEvent = order2.firstIndex { ($0 as? PlanItemView)?.item.kind == .event } ?? Int.max
        check(lastCard < firstEvent && events().allSatisfy(\.isTopLayer), "in Events mode the events are above the cards")
        plan.itemClicked(card("He leaves the bay"))
        check(plan.mode == .plan, "clicking a plan card switches back to Plan mode")

        // Colours: several cards and events at once, from the right-click menu's Color submenu.
        let colorCards = [card("He leaves the bay"), card("Captain wakes on the yacht")]
        plan.click(colorCards[0], extending: false)
        plan.click(colorCards[1], extending: true)
        check(plan.selection == Set(colorCards.map { $0.item.id }), "⌘-click adds a card to the chosen ones")
        check(canvas.itemViews.filter(\.isSelected).count == 2, "and both are drawn as chosen")
        plan.click(colorCards[1], extending: true)
        check(plan.selection == [colorCards[0].item.id], "and ⌘-click on a chosen one takes it out")
        plan.click(colorCards[1], extending: true)
        let colorMenu = plan.colorMenuItem(for: plan.selection)
        let entries = colorMenu.submenu?.items.filter { !$0.isSeparatorItem } ?? []
        check(entries.map(\.title) == PlanColors.palette.map(\.title) && entries.allSatisfy { $0.image != nil }, "the Color submenu lists the colours, each with its swatch", entries.map(\.title).joined(separator: ","))
        check(!(colorMenu.submenu?.items.contains { $0.title == "No Color" } ?? false), "there is no No Color for cards alone")
        plan.setColor("red", for: plan.selection)
        check(disk().cards[colorCards[0].item.id]?.color == "red" && disk().cards[colorCards[1].item.id]?.color == "red", "choosing a colour gives it to every chosen card, in the card files")
        check(card("He leaves the bay").item.colorName == "red", "and the canvas draws it")
        check(plan.colorMenuItem(for: plan.selection).submenu?.items.first { $0.state == .on }?.title == "Red", "the colour they share is ticked")
        plan.undo()
        check(disk().cards[colorCards[0].item.id]?.color != "red" && disk().cards[colorCards[1].item.id]?.color != "red", "one Undo takes the colours back from all of them")
        plan.redo()
        check(disk().cards[colorCards[0].item.id]?.color == "red", "and Redo gives them again")

        // The choice is plain to see, and the keys come from the click itself.
        func pixels(_ v: PlanItemView) -> [UInt8] {
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return [] }
            v.cacheDisplay(in: v.bounds, to: rep)
            return Array(UnsafeBufferPointer(start: rep.bitmapData, count: rep.bytesPerRow * rep.pixelsHigh))
        }
        let probe = PlanItemView(item: PlanItem(kind: .card, id: "probe", title: "Проба", text: "", colorName: "teal", lineIndex: nil, start: nil, floatingAt: nil), frame: NSRect(x: 0, y: 0, width: PlanLayout.columnWidth, height: PlanLayout.cardHeight))
        let plainPixels = pixels(probe)
        probe.isSelected = true
        let chosenPixels = pixels(probe)
        let differing = zip(plainPixels, chosenPixels).filter { $0 != $1 }.count
        check(!plainPixels.isEmpty && differing > 400, "a chosen card is drawn clearly differently from a plain one (tint, heavy outline, check mark)", "\(differing) bytes differ")
        let eventProbe = PlanItemView(item: PlanItem(kind: .event, id: "probe-e", title: "Событие", text: "", colorName: nil, lineIndex: 0, start: 1, floatingAt: nil), frame: NSRect(x: 0, y: 0, width: PlanLayout.columnWidth, height: PlanLayout.eventHeight))
        let eventPlain = pixels(eventProbe)
        eventProbe.isSelected = true
        check(zip(eventPlain, pixels(eventProbe)).filter { $0 != $1 }.count > 300, "and so is a chosen event, even with no colour")
        func mouse(_ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: flags, timestamp: 0, windowNumber: plan.view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        plan.clearSelection()
        let first = card("He leaves the bay"), second = card("Captain wakes on the yacht")
        first.mouseDown(with: mouse([])); first.mouseUp(with: mouse([]))
        second.mouseDown(with: mouse(.command)); second.mouseUp(with: mouse(.command))
        check(plan.selection == [first.item.id, second.item.id], "a click with ⌘ held, as the system delivers it, adds the card")
        check(plan.selectionNote == "2 chosen", "the toolbar says how many are chosen", "\(String(describing: plan.selectionNote))")
        let third = card("Old harbour master")
        third.mouseDown(with: mouse(.shift)); third.mouseUp(with: mouse(.shift))
        check(plan.selection.count == 3 && plan.selectionNote == "3 chosen", "a click with Shift adds one more")
        plan.canvas.mouseDown(with: mouse(.command))
        check(plan.selection.count == 3, "a click with ⌘ on empty canvas keeps the choice")
        plan.canvas.mouseDown(with: mouse([]))
        check(plan.selection.isEmpty && plan.selectionNote == nil && canvas.itemViews.allSatisfy { !$0.isSelected }, "a plain click on empty canvas clears it, and the note goes")
        plan.click(first, extending: false)
        check(plan.selectionNote == nil && plan.selection == [first.item.id], "one chosen shows no count")

        // The right-click menu itself: a right click on a chosen card is about all the chosen ones.
        func fire(_ menu: NSMenu?, color: String) {
            guard let sub = menu?.items.first(where: { $0.title == "Color" })?.submenu, let entry = sub.items.first(where: { $0.title == color }), let action = entry.action else { check(false, "the menu has a Color submenu with \(color)"); return }
            _ = NSApp.sendAction(action, to: entry.target, from: entry)
        }
        plan.clearSelection()
        let rc = [card("He leaves the bay"), card("Captain wakes on the yacht"), card("Old harbour master")]
        plan.click(rc[0], extending: false); plan.click(rc[1], extending: true); plan.click(rc[2], extending: true)
        let menuOnChosen = plan.menu(at: .zero, over: rc[1])
        check(plan.selection == Set(rc.map { $0.item.id }), "a right click on one of three chosen cards leaves all three chosen")
        fire(menuOnChosen, color: "Amber")
        check(rc.allSatisfy { disk().cards[$0.item.id]?.color == "amber" }, "and the colour goes to all three, not only to the card under the pointer", rc.map { disk().cards[$0.item.id]?.color ?? "-" }.joined(separator: ","))
        // A right click on a card that is not chosen chooses just that one.
        let unchosen = card("A dog on board?")
        _ = plan.menu(at: .zero, over: unchosen)
        check(plan.selection == [unchosen.item.id], "a right click on a card that is not chosen chooses only it")
        // Cards and events together.
        plan.click(card("He leaves the bay"), extending: false)
        plan.click(events()[0], extending: true)
        let mixedEvent = events()[0]
        let mixedMenu = plan.menu(at: .zero, over: mixedEvent)
        check(plan.selection.count == 2 && mixedMenu?.items.first?.title == "Color", "a right click on a chosen event keeps a chosen card with it")
        fire(mixedMenu, color: "Green")
        check(disk().cards[card("He leaves the bay").item.id]?.color == "green" && disk().eventColors[mixedEvent.item.id] == "green", "and the colour goes to both the card and the event")
        plan.undo()
        plan.click(card("He leaves the bay"), extending: false)

        // Events have a colour too, kept in the event's own file.
        let colorEvents = [events()[0], events()[1]]
        var changed = 0
        plan.onEventsChanged = { changed += 1 }
        plan.click(colorEvents[0], extending: false)
        plan.click(colorEvents[1], extending: true)
        let withEvents = plan.colorMenuItem(for: plan.selection)
        check(withEvents.submenu?.items.contains { $0.title == "No Color" } == true, "with events among them the menu has No Color")
        plan.setColor("teal", for: plan.selection)
        check(disk().eventColors[colorEvents[0].item.id] == "teal" && disk().eventColors[colorEvents[1].item.id] == "teal" && changed == 1, "events get the colour in their own files, and whoever holds the events is told")
        check(events().first { $0.item.id == colorEvents[0].item.id }?.item.colorName == "teal", "and the canvas draws the event in it")
        plan.setColor(nil, for: plan.selection)
        check(disk().eventColors[colorEvents[0].item.id] == nil, "No Color takes it away")
        plan.undo()
        check(disk().eventColors[colorEvents[0].item.id] == "teal" && disk().eventColors[colorEvents[1].item.id] == "teal", "Undo puts the colour back")
        plan.undo()
        check(disk().eventColors.isEmpty, "and again, the events are plain as they were")
        plan.click(card("He leaves the bay"), extending: false)
        check(plan.mode == .plan, "the next plain click chooses one again")

        // A real drag: onto another line, level with a row.
        let colGirl = plan.canvas.layout.columnX(1) + PlanLayout.columnWidth / 2
        let row300 = plan.canvas.layout.row(forStart: 300)!
        let id = card("He leaves the bay").item.id
        drag(card("He leaves the bay"), to: NSPoint(x: colGirl, y: row300.y + row300.height / 2), in: canvas)
        spin(0.05)
        let girl = plan.store.lines[1].id
        check(plan.store.cards[id]?.line == girl && plan.store.cards[id]?.start == 300, "dragged level with a row on another line: it takes that line and that position", "\(String(describing: plan.store.cards[id]?.line)) \(String(describing: plan.store.cards[id]?.start))")
        check(disk().cards[id]?.line == girl && disk().cards[id]?.start == 300, "and it is on disk at once")
        check(Set(cards().filter { $0.item.start == 300 }.map { $0.frame.minY }).count == 1, "now level with the other card at 300")

        // Between two rows: a new position between their numbers.
        let layout = plan.canvas.layout
        let r1 = layout.row(forStart: 100)!, r2 = layout.row(forStart: 200)!
        let movingID = card("He finds the letter").item.id
        let captainLine = plan.store.lines[0].id!
        plan.apply(drop: NSRect(x: layout.columnX(0), y: (r1.y + r1.height + r2.y) / 2 - 46, width: PlanLayout.columnWidth, height: PlanLayout.cardHeight), of: card("He finds the letter").item)
        let placed = plan.store.cards[movingID]?.start ?? 0
        check(placed > 100 && placed < 200 && plan.store.cards[movingID]?.line == captainLine, "dropped between two rows: a new position between theirs", "\(placed)")
        check(plan.canvas.layout.rows.count == layout.rows.count + 1 || layout.rows.contains { $0.start == 400 } == false || plan.canvas.layout.rows.count >= layout.rows.count, "a row is made for it")

        // No room: everything is renumbered and keeps its order.
        let tight = plan.store.cards[movingID]!.start!
        try plan.store.updateCard(movingID) { $0.start = 101 }
        plan.reload(); spin(0.05)
        let l2 = plan.canvas.layout
        let a = l2.row(forStart: 100)!, b = l2.row(forStart: 101)!
        let other = card("He turns back").item
        plan.apply(drop: NSRect(x: l2.columnX(0), y: (a.y + a.height + b.y) / 2 - 46, width: PlanLayout.columnWidth, height: PlanLayout.cardHeight), of: other)
        let order3 = plan.store.rowStarts
        check(order3 == order3.sorted() && Set(order3).count == order3.count, "with no room between two positions everything is renumbered, in the same order", "\(order3)")
        check(plan.store.cards[other.id]!.start! > plan.store.cards.values.first { $0.title == "Captain wakes on the yacht" }!.start!, "the dropped card is after the first card, before the next")
        _ = tight

        // Floating: a real drag out of the columns.
        let dragged = card("The storm hits")
        drag(dragged, to: NSPoint(x: plan.canvas.layout.columnsRight + 120, y: 300), in: canvas)
        spin(0.05)
        let stormID = plan.store.cards.values.first { $0.title == "The storm hits" }!.id!
        check(plan.store.cards[stormID]?.isFloating == true && (plan.store.cards[stormID]?.x ?? 0) > Int(plan.canvas.layout.columnsRight), "dragged out of the lines: it floats where it was dropped")
        check(disk().cards[stormID]?.line == nil && disk().cards[stormID]?.x != nil, "a floating card has no line on disk, only a place")
        // Back onto a line.
        plan.apply(drop: NSRect(x: plan.canvas.layout.columnX(2), y: plan.canvas.layout.rows[0].y, width: 190, height: 92), of: card("The storm hits").item)
        check(plan.store.cards[stormID]?.line == plan.store.lines[2].id && plan.store.cards[stormID]?.x == nil, "a floating card dropped on a line is linked to it and forgets its place")

        // An event dragged in Events mode; a card in the lower layer is not dragged.
        plan.itemClicked(events().first { $0.item.title == "Шторм у берега" }!)
        let eventView = events().first { $0.item.title == "Шторм у берега" }!
        let eventID = eventView.item.id
        let before = plan.store.entry(forEvent: eventID)!
        drag(eventView, to: NSPoint(x: plan.canvas.layout.columnX(2) + 95, y: plan.canvas.layout.rows[1].y + 40), in: canvas)
        spin(0.05)
        let after = plan.store.entry(forEvent: eventID)!
        check(after.lane == plan.store.lines[2].id && after.lane != before.lane, "in Events mode an event can be dragged to another line")
        check(plan.store.cards.count == 13, "dragging an event adds and removes no cards")

        // Zoom.
        plan.zoomToFit(); spin(0.1)
        let fitZoom = plan.zoom
        check(canvas.frame.width * fitZoom <= plan.scrollView.contentSize.width + 2 && canvas.frame.height * fitZoom <= plan.scrollView.contentSize.height + 2, "Fit shows the whole canvas", "zoom \(fitZoom)")
        plan.zoomIn(); spin(0.05)
        check(plan.zoom > fitZoom, "zoom in")
        plan.zoomOut(); plan.zoomOut(); spin(0.05)
        check(plan.zoom < fitZoom, "zoom out")

        // Zoom keeps the selected card in view.
        plan.zoomToFit(); spin(0.1)
        plan.itemClicked(card("He turns back"))
        for _ in 0..<5 { plan.zoomIn() }
        spin(0.1)
        let sel = card("He turns back")
        check(plan.zoom > 1.5 && plan.scrollView.documentVisibleRect.contains(sel.frame), "zooming in keeps the selected card visible", "zoom \(plan.zoom) card \(sel.frame) visible \(plan.scrollView.documentVisibleRect)")
        plan.zoomToFit(); spin(0.1)

        // Adding and deleting.
        let lineCount = plan.store.lines.count
        _ = plan.addLine()
        check(plan.store.lines.count == lineCount + 1 && disk().lines.count == lineCount + 1 && plan.canvas.headers.count == lineCount + 1, "a line is added and written")
        let newCard = plan.addCard()!
        check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("plan/cards/\(newCard).json").path) && plan.mode == .plan, "a card is added and written")
        plan.deleteSelected()
        check(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("plan/cards/\(newCard).json").path), "deleting the selected card removes its file")
        let girlLine = plan.store.lines[1].id!
        let onGirl = plan.store.cards.values.filter { $0.line == girlLine }.count
        let eventsOnGirl = plan.store.entries.filter { $0.lane == girlLine }.count
        let firstLine = plan.store.lines[0].id!
        let firstEntries = plan.store.entries.filter { $0.lane == firstLine }.count
        plan.deleteLine(girlLine)
        check(plan.store.lines.count == lineCount && plan.store.cards.values.filter { $0.line == girlLine }.isEmpty, "a deleted line is gone", "\(onGirl)")
        check(plan.store.cards.values.filter(\.isFloating).count >= onGirl, "its cards float (none is lost)")
        check(plan.store.entries.filter { $0.lane == firstLine }.count == firstEntries + eventsOnGirl, "its real events move to the first line")
        check(plan.store.cards.count == disk().cards.count && disk().problems.isEmpty, "memory and disk agree, and the files have no problems", "\(disk().problems)")

        // Undo: nothing is lost for good.
        let victim = plan.store.cards.values.first { $0.title == "She follows the coast" }!.id!
        plan.itemClicked(card("She follows the coast"))
        plan.deleteSelected()
        check(plan.store.cards[victim] == nil && plan.bannerText?.contains("She follows the coast") == true, "deleting a card shows a banner that names it")
        plan.undo()
        check(plan.store.cards[victim]?.title == "She follows the coast" && disk().cards[victim] != nil, "Undo brings the deleted card back, on disk too")
        plan.redo()
        check(plan.store.cards[victim] == nil && disk().cards[victim] == nil, "Redo deletes it again")
        plan.undo()
        let movedID = card("The letter from his mother").item.id
        let startBefore = plan.store.cards[movedID]!.start!
        plan.apply(drop: NSRect(x: plan.canvas.layout.columnsRight + 100, y: 400, width: 190, height: 92), of: card("The letter from his mother").item)
        check(plan.store.cards[movedID]?.isFloating == true, "(a card is moved)")
        plan.undo()
        check(plan.store.cards[movedID]?.start == startBefore && plan.store.cards[movedID]?.isFloating == false, "Undo puts a moved card back where it was")
        let linesNow = plan.store.lines.count
        let cardsNow = plan.store.cards.count
        plan.deleteLine(plan.store.lines[0].id!)
        check(plan.store.lines.count == linesNow - 1, "(a line is deleted)")
        plan.undo()
        check(plan.store.lines.count == linesNow && plan.store.cards.count == cardsNow && disk().lines.count == linesNow, "Undo brings back a deleted line with its cards and its events")
        check(plan.canvas.lineColors.count == plan.store.lines.count, "the lines are drawn in their colours")

        // The size of a plan.
        let big = try tempBook(big: false)
        defer { try? FileManager.default.removeItem(at: big) }
        let bigStore = try PlanStore(folder: big)
        let lines = try (0..<5).map { try bigStore.addLine(name: "Line \($0)") }
        for i in 0..<300 { _ = try bigStore.addCard(title: "Card \(i)", text: "text", line: lines[i % 5], start: (i / 5 + 1) * 100) }
        let t0 = CACurrentMediaTime()
        let bigController = PlanCanvasController(store: try PlanStore(folder: big))
        _ = bigController.view
        let t1 = CACurrentMediaTime()
        let target = bigController.store.cards.values.first!.id!
        bigController.apply(drop: NSRect(x: 40, y: 500, width: 190, height: 92), of: PlanItem(kind: .card, id: target, title: "", text: "", colorName: nil, lineIndex: 0, start: 100, floatingAt: nil))
        let t2 = CACurrentMediaTime()
        print("       300 cards on 5 lines: read and draw \(Int((t1 - t0) * 1000)) ms, one drop \(Int((t2 - t1) * 1000)) ms")
        check(t1 - t0 < 1.5 && t2 - t1 < 0.5, "a plan of 300 cards opens in under 1.5 s and a drop takes under half a second")
        lab.setMode(compare: false)
    }
}
