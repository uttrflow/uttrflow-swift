// Tests that the app watches the clipboard it is given, not the one on this Mac.

import Testing
import UttrflowSettings
import UttrflowTestSupport

@testable import Uttrflow

@MainActor
@Suite("The clipboard the app watches", .serialized, .timeLimit(.minutes(1)))
struct InjectedClipboardTests {
    private func watching(_ source: InMemoryClipboardSource, in sandbox: borrowing Sandbox) -> AppDelegate {
        let app = AppDelegate(
            container: sandbox.root, clipboardSource: source,
            settingsStore: UserDefaultsSettingsStore(store: ModelDownloadSettingsStore()),
            account: HeldSession(signedIn: true).layer)
        app.drawsWindows = false
        app.settingsChanged(to: Settings(clipboardEnabled: true))
        app.followSession()
        return app
    }

    @Test("each app notices only its own in-memory clipboard's copies")
    func copiesRemainPrivateToEachSource() async throws {
        let firstSandbox = Sandbox()
        let secondSandbox = Sandbox()
        let firstSource = InMemoryClipboardSource()
        let secondSource = InMemoryClipboardSource()
        let foreignSource = InMemoryClipboardSource()
        let firstApp = watching(firstSource, in: firstSandbox)
        let secondApp = watching(secondSource, in: secondSandbox)
        try #require(firstApp.isWatchingTheClipboard)
        try #require(secondApp.isWatchingTheClipboard)
        defer {
            firstApp.settingsChanged(to: Settings(clipboardEnabled: false))
            secondApp.settingsChanged(to: Settings(clipboardEnabled: false))
        }

        foreignSource.copy("Foreign clipboard text")
        firstSource.copy("First source text")
        try await eventually { firstApp.clipboardArrivals == 1 }
        try #require(secondApp.clipboardArrivals == 0)

        foreignSource.copy("Another foreign clipboard text")
        firstSource.copy("First source again")
        try await eventually { firstApp.clipboardArrivals == 2 }
        try #require(secondApp.clipboardArrivals == 0)
        secondSource.copy("Second source text")
        try await eventually { secondApp.clipboardArrivals == 1 }
        #expect(firstSource.text() == "First source again")
        try #require(secondSource.text() == "Second source text")
        #expect(foreignSource.text() == "Another foreign clipboard text")
        #expect(firstApp.clipboardArrivals == 2)
        #expect(secondApp.clipboardArrivals == 1)
    }

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
