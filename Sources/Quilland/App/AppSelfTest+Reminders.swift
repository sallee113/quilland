import AppKit
import QuillandCore

/// The Reminders view and the window shown when a book opens.
extension AppSelfTest {
    func reminders() -> Int32? {
        let main = self.main!
        let folder = self.folder!
        app.modeReminders(); spin(0.5)
        guard let rv = main.remindersView else { check(false, "View ▸ Reminders shows the view"); return 1 }
        check(main.mode == .reminders && rv.shownTexts.open.isEmpty && main.localState().mode == "reminders", "View ▸ Reminders opens an empty list and is remembered as the view")
        check(rv.add("   ") == nil, "a blank reminder makes nothing")
        let a = rv.add("Проверить год основания школы")!
        let b = rv.add("Позвонить редактору")!
        let c = rv.add("Купить блокнот")!
        check(rv.shownTexts.open == ["Проверить год основания школы", "Позвонить редактору", "Купить блокнот"] && RemindersStore(book: folder).open.count == 3, "reminders are listed in the order they were made and saved to the book")
        check(FileManager.default.fileExists(atPath: folder.appendingPathComponent("reminders.json").path), "they live in reminders.json in the book")
        rv.mark(b, true)
        check(rv.shownTexts.open.count == 2 && rv.shownTexts.done == ["Позвонить редактору"], "a marked reminder moves to the done ones")
        rv.mark(b, false)
        check(rv.shownTexts.open.count == 3, "and can be brought back")
        rv.rename(a, "Проверить год основания школы в архиве")
        check(RemindersStore(book: folder).reminders.first?.text == "Проверить год основания школы в архиве", "the text of a reminder can be changed")
        rv.rename(a, "   ")
        check(RemindersStore(book: folder).reminders.first?.text == "Проверить год основания школы в архиве", "but not emptied")
        rv.delete(c)
        check(rv.shownTexts.open.count == 2 && rv.bannerText != nil, "deleting removes the reminder and offers Undo")
        rv.undoDelete()
        check(rv.shownTexts.open.count == 3 && RemindersStore(book: folder).reminders.last?.text == "Купить блокнот", "Undo puts it back where it was")
        rv.delete(c); rv.undoDelete()

        // Several lines, and a long text that wraps.
        let tall = rv.add("Проверить:\n— год основания школы\n— имя первого директора")!
        let heights = rv.rowHeights
        check(heights.count == 4 && heights[3] > heights[0] * 2, "a reminder of several lines gets a taller row", "\(heights)")
        check(RemindersStore(book: folder).reminders.last?.text == "Проверить:\n— год основания школы\n— имя первого директора", "and keeps its lines")
        let long = rv.add(String(repeating: "очень длинная строка без остановки ", count: 12))!
        check(rv.rowHeights[4] > heights[0] * 2, "a long text wraps in its row instead of running on", "\(rv.rowHeights)")
        rv.delete(tall); rv.delete(long)
        check(rv.shownTexts.open.count == 3, "they are deleted like the others")

        // Text being changed in a row is saved when the view is left.
        app.modeBook(); spin(0.3)
        check(main.remindersView == nil, "leaving the view tears it down")

        // The window shown when a book opens.
        main.remindersStore.reload()
        main.remindersStore.reload()
        try? main.remindersStore.setDone(b, true)
        let bookWindow = app.bookWindows.first { $0.main === main }!
        let prefs = AppPreferences.shared
        let had = prefs.values.showReminders
        prefs.update { $0.showReminders = false }
        check(!bookWindow.showRemindersIfAny(), "with the setting off the window is not shown")
        prefs.update { $0.showReminders = true }
        check(bookWindow.showRemindersIfAny() && bookWindow.remindersSheet != nil, "with open reminders and the setting on the window is shown")
        let ids = bookWindow.remindersPopup!.boxes.map(\.id)
        check(ids == [a, c], "it lists only the reminders not yet done", "\(ids)")
        let box = bookWindow.remindersPopup!.boxes[0].box
        box.performClick(nil)
        check(RemindersStore(book: folder).done.contains { $0.id == a } && main.remindersStore.open.map(\.id) == [c], "a reminder can be marked there")
        check(bookWindow.remindersSheet!.frame.width <= RemindersPopup.width + 1, "the window is the width it was made")
        bookWindow.closeReminders(); spin(0.2)
        let wide = try! main.remindersStore.add(String(repeating: "длинное-слово-без-пробелов-", count: 20) + "\n" + String(repeating: "много слов в строке ", count: 30))!
        check(bookWindow.showRemindersIfAny(), "the window is shown again with a long text")
        spin(0.3)
        let widths = bookWindow.remindersSheet!.frame.width
        check(widths <= RemindersPopup.width + 1 && bookWindow.remindersPopup!.labels.allSatisfy { $0.frame.width <= RemindersPopup.width }, "a long text wraps in the window; it does not make it wider", "\(widths)")
        try? main.remindersStore.delete(wide)
        check(!bookWindow.showRemindersIfAny(), "a second window is not stacked on the first")
        bookWindow.closeReminders(); spin(0.3)
        check(bookWindow.remindersSheet == nil, "Close closes it")
        for id in [a, c] { try? main.remindersStore.setDone(id, true) }
        check(!bookWindow.showRemindersIfAny(), "with nothing left to do the window is not shown")

        app.modeReminders(); spin(0.3)
        check(main.remindersView?.shownTexts.open.isEmpty == true && main.remindersView?.shownTexts.done.count == 3, "the view shows what was marked in the window")
        // Opening the view writes nothing by itself.
        let bytes = try? Data(contentsOf: folder.appendingPathComponent("reminders.json"))
        app.modeBook(); spin(0.2); app.modeReminders(); spin(0.3); app.modeBook(); spin(0.2)
        check((try? Data(contentsOf: folder.appendingPathComponent("reminders.json"))) == bytes, "looking at the view changes no file")
        prefs.update { $0.showReminders = had }
        for id in [a, b, c] { try? main.remindersStore.delete(id) }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("reminders.json"))
        main.remindersStore.reload()
        if main.mode != main.writingMode { main.setMode(main.writingMode) }
        spin(0.2)
        return nil
    }
}
