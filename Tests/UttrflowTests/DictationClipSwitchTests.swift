// Tests that dictations enter clipboard history only after an explicit action (#3222).

import Foundation
import UttrflowClipboard
import UttrflowPipeline
import UttrflowSettings
import Testing

@testable import Uttrflow

@MainActor
@Suite("Dictations and the Clipboard switch", .serialized)
struct DictationClipSwitchTests {
    private func app(clipboardOn: Bool, in sandbox: borrowing Sandbox) -> AppDelegate {
        let app = AppDelegate(
            container: sandbox.root,
            clipboardSource: InMemoryClipboardSource(),
            account: HeldSession(signedIn: true).layer)
        app.drawsWindows = false
        app.settingsChanged(to: Settings(clipboardEnabled: clipboardOn))
        return app
    }

    private func keptClips(in sandbox: borrowing Sandbox) async -> [String] {
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        return await store.clips(keeping: ClipRetention(days: 7, now: Date())).map(\.text)
    }

    @Test("dictating never records a clip when the Clipboard switch is off")
    func switchOff() async {
        let sandbox = Sandbox()
        let app = app(clipboardOn: false, in: sandbox)

        #expect(app.recordAsClip("Sample words", of: UUID()) == nil)
        app.render(
            .inserted(DictationOutcome(text: "Sample words", method: .accessibility, cleanedBy: .rules)))

        #expect(await keptClips(in: sandbox).isEmpty)
    }

    @Test("dictating does not record a clip while the Clipboard switch is on")
    func switchOn() async throws {
        let sandbox = Sandbox()
        let app = app(clipboardOn: true, in: sandbox)

        app.render(
            .inserted(DictationOutcome(text: "Sample words", method: .accessibility, cleanedBy: .rules)))
        #expect(await keptClips(in: sandbox).isEmpty)

        let dictation = try #require(app.lastTranscriptID)
        app.carryOut(.keepDictationAsClip(dictation))
        for _ in 0..<50 {
            if await keptClips(in: sandbox) == ["Sample words"] { return }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(await keptClips(in: sandbox) == ["Sample words"])
    }
}
