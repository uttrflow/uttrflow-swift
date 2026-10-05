// The Diagnostics page said "Not checked yet" forever, because nothing ever checked.

import Foundation
import Testing
import UttrflowCore
import UttrflowPipeline

@testable import Uttrflow

private actor MutableTransformerReadiness {
    private var ready: Set<TransformerKind>

    init(_ ready: Set<TransformerKind>) {
        self.ready = ready
    }

    func probe() -> Set<TransformerKind> { ready }

    func set(_ ready: Set<TransformerKind>) {
        self.ready = ready
    }
}

@MainActor
@Suite("The clean-up engines Diagnostics reports on", .timeLimit(.minutes(1)))
struct DiagnosticsEngineProbeTests {
    /// Starts the probe and waits for it to finish, which it does on a task of its own.
    private func probed(_ app: AppDelegate) async -> [TransformerKind: Bool] {
        await app.probeTransformers().value
        return app.transformerAvailability
    }

    private func waitFor(_ app: AppDelegate, foundationModels available: Bool) async {
        for _ in 0..<100 {
            if app.transformerAvailability[.foundationModels] == available { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// #152: the snapshot's availability was never populated, so every row read `nil`.
    @Test("are asked, so the page has an answer rather than a pending check")
    func areAsked() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        #expect(app.transformerAvailability.isEmpty)

        let answered = await probed(app)
        #expect(!answered.isEmpty, "nothing was asked, so the page would say Not checked yet")
        // The floor can always run, whatever else this Mac has.
        #expect(answered[.rules] == true)
    }

    @Test("and every kind gets an answer, not only the ones that said yes")
    func everyKindIsAnswered() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let answered = await probed(app)

        for kind in TransformerKind.allCases {
            #expect(answered[kind] != nil, "\(kind.rawValue) was left unanswered")
        }
    }

    @Test("availability changes are read when the app becomes active")
    func availabilityRefreshesOnActivation() async {
        let sandbox = Sandbox()
        let readiness = MutableTransformerReadiness([.foundationModels, .rules])
        let app = AppDelegate(
            container: sandbox.root,
            transformerReadiness: { _ in await readiness.probe() })
        _ = await probed(app)
        #expect(app.transformerAvailability[.foundationModels] == true)

        await readiness.set([.rules])
        app.applicationDidBecomeActive(Notification(name: Notification.Name("app-active")))
        await waitFor(app, foundationModels: false)

        #expect(app.transformerAvailability[.foundationModels] == false)
        #expect(app.transformerAvailability[.rules] == true)
    }

    @Test("showing Diagnostics asks again after availability changes")
    func availabilityRefreshesWhenDiagnosticsOpens() async {
        let sandbox = Sandbox()
        let readiness = MutableTransformerReadiness([.foundationModels, .rules])
        let session = HeldSession(signedIn: true)
        let app = AppDelegate(
            container: sandbox.root, account: session.layer,
            transformerReadiness: { _ in await readiness.probe() })
        app.drawsWindows = false
        _ = await probed(app)
        await readiness.set([.rules])

        app.showDiagnosticsFromMenu(nil)
        await waitFor(app, foundationModels: false)

        #expect(app.lastOpened == .settings(.diagnostics))
        #expect(app.transformerAvailability[.foundationModels] == false)
    }

    @Test("a dictation that falls back records its engine and refreshes availability")
    func fallbackDictationRefreshesAvailability() async {
        let sandbox = Sandbox()
        let readiness = MutableTransformerReadiness([.foundationModels, .rules])
        let app = AppDelegate(
            container: sandbox.root,
            transformerReadiness: { _ in await readiness.probe() })
        _ = await probed(app)
        await readiness.set([.rules])

        app.render(
            .inserted(
                DictationOutcome(
                    text: "hello", method: .clipboard, cleanedBy: .rules)))
        await waitFor(app, foundationModels: false)

        #expect(app.lastCleanedBy == .rules)
        #expect(app.transformerAvailability[.foundationModels] == false)
    }

    @Test("shows the first Apple Intelligence fallback notice once, with System Settings recovery")
    func appleIntelligenceFallbackNoticeIsShownOnce() {
        let app = AppDelegate(container: Sandbox().root)
        let unavailable = CleaningRecord.UnavailableEngine(
            engine: TransformerKind.foundationModels.rawValue,
            reason: .appleIntelligenceDisabled)

        app.render(
            .inserted(
                DictationOutcome(
                    text: "hello", method: .clipboard, cleanedBy: .rules,
                    unavailableEngines: [unavailable])))
        let notice = app.actionNotice
        #expect(notice?.message.contains("switched off") == true)
        #expect(notice?.action?.intent == .recover(.openSystemSettings(.appleIntelligence)))

        app.render(
            .inserted(
                DictationOutcome(
                    text: "again", method: .clipboard, cleanedBy: .rules,
                    unavailableEngines: [
                        .init(engine: TransformerKind.foundationModels.rawValue, reason: .modelNotReady)
                    ])))
        #expect(app.actionNotice == notice)
    }

    /// #1668: the speech model row was never given an answer, so it read Not checked yet forever.
    @Test("the speech model is looked for on disk too")
    func speechModelIsLookedFor() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        #expect(app.speechModelPresence == nil)

        await app.probeSpeechModel().value
        #expect(app.speechModelPresence != nil, "the page would still say Not checked yet")
    }
}
