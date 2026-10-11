// Tests that the app watches the clipboard it is given, not the one on this Mac.

import Testing
import UttrflowSettings
import UttrflowTestSupport

@testable import Uttrflow

@MainActor
@Suite("The clipboard the app watches", .serialized, .timeLimit(.minutes(1)))
struct InjectedClipboardTests {
    @Test("notices a copy made to the injected clipboard")
    func noticesAnInjectedCopy() async throws {
        let sandbox = Sandbox()
        let source = InMemoryClipboardSource()
        let app = AppDelegate(
            container: sandbox.root, clipboardSource: source,
            account: HeldSession(signedIn: true).layer)
        app.drawsWindows = false
        app.settingsChanged(to: Settings(clipboardEnabled: true))
        app.followSession()
        #expect(app.isWatchingTheClipboard)

        source.copy("Sample copy")

        try await eventually { app.clipboardArrivals == 1 }
        app.settingsChanged(to: Settings(clipboardEnabled: false))
    }
}
