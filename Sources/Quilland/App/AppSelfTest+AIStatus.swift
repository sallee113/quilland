import AppKit
import QuillandCore

/// What depends on the model follows the connection by itself: it listens to `.aiStatusChanged` where it lives.
extension AppSelfTest {
    func aiStatusEvents() -> Int32? {
        let main = self.main!
        let prefs = AppPreferences.shared
        let before = (prefs.values, AIService.shared.status)
        defer { prefs.update { $0 = before.0 }; AIService.shared.apply(before.1) }
        prefs.update { $0.aiEnabled = true; $0.aiAddress = "http://127.0.0.1:9" }
        let down = AIStatus(reachable: false, models: [], model: nil, info: nil, context: 4096, loaded: false, message: "down")
        let up = AIStatus(reachable: true, models: [], model: "m", info: nil, context: 4096, loaded: true, message: "ok")

        // The Outline view: the button follows the connection with no view change and no choice of another section.
        main.setMode(.outline); spin(0.5)
        guard let detail = main.outlineDetail else { check(false, "the Outline view shows"); return 1 }
        AIService.shared.apply(down); spin(0.1)
        check(!detail.writeEnabled, "with the model not answering, Write with AI is off")
        AIService.shared.apply(up); spin(0.1)
        check(detail.writeEnabled, "the moment the connection is up it is on, though the view stayed as it was")
        AIService.shared.apply(down); spin(0.1)
        check(!detail.writeEnabled, "and off again when the connection is lost")

        // The right panel.
        main.setMode(.book); spin(0.4)
        main.setRightPanel(true); spin(0.3)
        main.rightPanel.showTab(.section); spin(0.2)
        AIService.shared.apply(up); spin(0.1)
        check(main.rightPanel.writeEnabled, "the right panel's button follows it too")
        AIService.shared.apply(down); spin(0.1)
        check(!main.rightPanel.writeEnabled, "in both directions")
        main.setRightPanel(false)

        // A subscription lasts as long as it is held.
        var hits = 0
        var held: Subscription? = subscribe(to: .aiStatusChanged) { hits += 1 }
        AIService.shared.apply(up); spin(0.1)
        check(hits == 1 && held != nil, "a subscriber hears the event")
        held = nil
        AIService.shared.apply(down); spin(0.1)
        check(hits == 1, "and stops hearing it when the subscription is let go")

        // Coming back to the application, the model is asked again when it was not there.
        AIService.shared.apply(down)
        app.recheckAIIfNeeded()
        check(AIService.shared.checking, "back in the application with no model, it asks the server again")
        for _ in 0..<40 where AIService.shared.checking { spin(0.25) }
        check(!AIService.shared.checking, "and the answer arrives")
        AIService.shared.apply(up)
        app.recheckAIIfNeeded()
        check(!AIService.shared.checking, "with the model there it does not ask again")

        main.setMode(main.writingMode); spin(0.3)
        return nil
    }
}
