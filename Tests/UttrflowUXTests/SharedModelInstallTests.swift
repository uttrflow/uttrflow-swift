// Tests for the speech model's one download: shared between windows, outliving them, and reported to the app.
import Testing

@testable import UttrflowCore
@testable import UttrflowUX

/// The download failure the tests script.
private let downloadFailure = SpeechEngineError.modelDownloadFailed(description: "offline")

/// What the app is told about the one download.
@MainActor
private final class AppSide {
    private(set) var fractions: [Double] = []
    private(set) var endings: [SpeechEngineError?] = []

    init(watching install: SharedModelInstall) {
        install.onProgress = { [weak self] in self?.fractions.append($0) }
        install.onEnd = { [weak self] in self?.endings.append($0) }
    }
}

@MainActor
@Suite("The speech model's shared download")
struct SharedModelInstallTests {

    @Test("a second window joins the download in flight rather than starting another")
    func secondWindowJoins() async {
        let gated = GatedInstaller()
        let install = SharedModelInstall(wrapping: gated)
        let first = Harness(microphone: .granted, accessibility: .granted, installer: install)
        let second = Harness(microphone: .granted, accessibility: .granted, installer: install)
        await first.flow.start()
        await second.flow.start()

        let firstRunning = Task { await first.flow.perform(.advance) }
        await settle(until: { gated.startedDownloads == 1 && install.isRunning })
        let secondRunning = Task { await second.flow.perform(.advance) }
        await settle(until: { install.waiting == 2 })

        gated.send(.report(0.4))
        await settle(until: { first.detail == .installing(0.4) && second.detail == .installing(0.4) })
        gated.send(.succeed)
        await firstRunning.value
        await secondRunning.value

        #expect(gated.startedDownloads == 1)
        #expect(first.detail == .finishing(.ready))
        #expect(second.detail == .finishing(.ready))
        #expect(!install.isRunning)
    }

    @Test("a download whose window has gone keeps reporting to the app, and says when it lands")
    func outlivesItsWindow() async {
        let gated = GatedInstaller()
        let install = SharedModelInstall(wrapping: gated)
        let app = AppSide(watching: install)
        let window = Harness(microphone: .granted, accessibility: .granted, installer: install)
        await window.flow.start()
        let running = Task { await window.flow.perform(.advance) }
        await settle(until: { gated.startedDownloads == 1 })

        // The red button cancels nothing, so what the app hears is all that is left to draw.
        gated.send(.report(0.25))
        await settle(until: { app.fractions == [0.25] })
        #expect(app.endings.isEmpty)

        gated.send(.succeed)
        await running.value
        await settle(until: { app.endings.count == 1 })
        #expect(app.endings == [nil])
        #expect(install.isInstalled)
    }

    @Test("a failed download ends with its failure, and the next ask starts a fresh one")
    func failureEndsAndRestarts() async {
        let gated = GatedInstaller()
        let install = SharedModelInstall(wrapping: gated)
        let app = AppSide(watching: install)

        let failing = Task { () -> SpeechEngineError? in
            do throws(SpeechEngineError) {
                try await install.install { _ in }
                return nil
            } catch {
                return error
            }
        }
        await settle(until: { gated.startedDownloads == 1 })
        gated.send(.fail(downloadFailure))
        #expect(await failing.value == downloadFailure)
        #expect(app.endings == [downloadFailure])

        let again = Task { try? await install.install { _ in } }
        await settle(until: { gated.startedDownloads == 2 })
        gated.send(.succeed)
        await again.value
        #expect(app.endings == [downloadFailure, nil])
    }

    @Test("cancelling the one asking stops the download, and the next ask starts again")
    func cancellingStopsTheDownload() async {
        let gated = GatedInstaller()
        let install = SharedModelInstall(wrapping: gated)
        let app = AppSide(watching: install)
        let window = Harness(microphone: .granted, accessibility: .granted, installer: install)
        await window.flow.start()

        let running = Task { await window.flow.perform(.advance) }
        await settle(until: { gated.startedDownloads == 1 })
        #expect(await window.press("Cancel"))
        await running.value
        await settle(until: { app.endings.count == 1 })
        #expect(!install.isRunning)
        #expect(!install.isInstalled)

        let again = Task { _ = await window.press("Download Now") }
        await settle(until: { gated.startedDownloads == 2 })
        gated.send(.succeed)
        await again.value
        #expect(window.detail == .finishing(.ready))
    }
}
