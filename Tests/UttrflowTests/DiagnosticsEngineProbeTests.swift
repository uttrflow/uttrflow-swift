// The Diagnostics page said "Not checked yet" forever, because nothing ever checked.

import Foundation
import Testing
import UttrflowAI
import UttrflowCore
import UttrflowPipeline
import UttrflowTestSupport

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

/// A downloaded model whose weights are in memory, the state the AI suggestions card calls Loaded.
private struct LoadedLocalModel: CleanupModel {
    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String { text }
}

@MainActor
@Suite("The clean-up engines Diagnostics reports on", .timeLimit(.minutes(1)))
struct DiagnosticsEngineProbeTests {
    /// Starts the probe and waits for it to finish, which it does on a task of its own.
    private func probed(_ app: AppDelegate) async -> [TransformerKind: Bool] {
        await app.probeTransformers().value
        return app.transformerAvailability
    }

    /// Waits for the probe the trigger started to land its answer, however long a loaded host makes it take.
    private func waitFor(_ app: AppDelegate, foundationModels available: Bool) async throws {
        try await eventually { app.transformerAvailability[.foundationModels] == available }
    }

    /// #152: the snapshot's availability was never populated, so every row read `nil`.
    @Test("are asked, so the page has an answer rather than a pending check")
    func areAsked() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, clipboardSource: InMemoryClipboardSource())
        #expect(app.transformerAvailability.isEmpty)

        let answered = await probed(app)
        #expect(!answered.isEmpty, "nothing was asked, so the page would say Not checked yet")
        // The floor can always run, whatever else this Mac has.
        #expect(answered[.rules] == true)
    }

    @Test("and every kind gets an answer, not only the ones that said yes")
    func everyKindIsAnswered() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, clipboardSource: InMemoryClipboardSource())
        let answered = await probed(app)

        for kind in TransformerKind.allCases {
            #expect(answered[kind] != nil, "\(kind.rawValue) was left unanswered")
        }
    }

    @Test("availability changes are read when the app becomes active")
    func availabilityRefreshesOnActivation() async throws {
        let sandbox = Sandbox()
        let readiness = MutableTransformerReadiness([.foundationModels, .rules])
        let app = AppDelegate(
            container: sandbox.root,
            clipboardSource: InMemoryClipboardSource(),
            transformerReadiness: { _ in await readiness.probe() })
        _ = await probed(app)
        #expect(app.transformerAvailability[.foundationModels] == true)

        await readiness.set([.rules])
        app.applicationDidBecomeActive(Notification(name: Notification.Name("app-active")))
        try await waitFor(app, foundationModels: false)

        #expect(app.transformerAvailability[.foundationModels] == false)
        #expect(app.transformerAvailability[.rules] == true)
    }

    @Test("showing Diagnostics asks again after availability changes")
    func availabilityRefreshesWhenDiagnosticsOpens() async throws {
        let sandbox = Sandbox()
        let readiness = MutableTransformerReadiness([.foundationModels, .rules])
        let session = HeldSession(signedIn: true)
        let app = AppDelegate(
            container: sandbox.root,
            clipboardSource: InMemoryClipboardSource(), account: session.layer,
            transformerReadiness: { _ in await readiness.probe() })
        app.drawsWindows = false
        _ = await probed(app)
        await readiness.set([.rules])

        app.showDiagnosticsFromMenu(nil)
        try await waitFor(app, foundationModels: false)

        #expect(app.lastOpened == .settings(.diagnostics))
        #expect(app.transformerAvailability[.foundationModels] == false)
    }

    @Test("a dictation that falls back records its engine and refreshes availability")
    func fallbackDictationRefreshesAvailability() async throws {
        let sandbox = Sandbox()
        let readiness = MutableTransformerReadiness([.foundationModels, .rules])
        let app = AppDelegate(
            container: sandbox.root,
            clipboardSource: InMemoryClipboardSource(),
            transformerReadiness: { _ in await readiness.probe() })
        _ = await probed(app)
        await readiness.set([.rules])

        app.render(
            .inserted(
                DictationOutcome(
                    text: "hello", method: .clipboard, cleanedBy: .rules)))
        try await waitFor(app, foundationModels: false)

        #expect(app.lastCleanedBy == .rules)
        #expect(app.transformerAvailability[.foundationModels] == false)
    }

    /// #1668: the speech model row was never given an answer, so it read Not checked yet forever.
    @Test("the speech model is looked for on disk too")
    func speechModelIsLookedFor() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, clipboardSource: InMemoryClipboardSource())
        #expect(app.speechModelPresence == nil)

        await app.probeSpeechModel().value
        #expect(app.speechModelPresence != nil, "the page would still say Not checked yet")
    }

    /// The probe never asked the loaded model, so Diagnostics warned "Not available" beside a Loaded card.
    @Test("the downloaded model is available when its weights are loaded")
    func loadedLocalModelIsAvailable() async {
        let sandbox = Sandbox()
        let app = AppDelegate(
            container: sandbox.root, clipboardSource: InMemoryClipboardSource(),
            localTidier: LoadedLocalModel())

        let answered = await probed(app)

        #expect(answered[.localModel] == true, "the loaded model was reported as not available")
    }

    @Test("the downloaded model is not available when none is loaded")
    func absentLocalModelIsNotAvailable() async {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, clipboardSource: InMemoryClipboardSource())

        #expect(await probed(app)[.localModel] == false)
    }
}
