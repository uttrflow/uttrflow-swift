import Foundation
import Synchronization
import Testing
import UttrflowPipeline
import UttrflowPredict

@testable import Uttrflow

private final class ClipboardPanelSessionStub: @unchecked Sendable {
    struct State: Sendable {
        var isOpen = true
        var revealed: Set<UUID> = [UUID()]
    }

    private let state = Mutex(State())

    func close() {
        state.withLock {
            $0.isOpen = false
            $0.revealed.removeAll()
        }
    }

    func reopenWithRevealedSecret() {
        state.withLock {
            $0.isOpen = true
            $0.revealed = [UUID()]
        }
    }

    var snapshot: State { state.withLock { $0 } }
}

@MainActor
@Suite("Session end withdraws suggestions", .serialized)
struct SuggestionSessionEndTests {
    @Test("lock, sleep and session changes close the clipboard panel", .bug(id: 3685))
    func notificationsCloseClipboardPanel() async {
        let workspaceCenter = NotificationCenter()
        let screenLockCenter = NotificationCenter()
        let panel = ClipboardPanelSessionStub()
        let controller: DictationController<ContinuousClock>? = nil
        let (ended, continuation) = AsyncStream.makeStream(of: Void.self)
        var ends = ended.makeAsyncIterator()
        let onEnd: @Sendable () -> Void = {
            Task { @MainActor in
                await controller?.endForSessionEnding()
                panel.close()
                continuation.yield(())
            }
        }
        let workspaceObservers = DictationSessionEndObserver.observe(
            in: workspaceCenter, onEnd: onEnd)
        let screenLockObserver = DictationSessionEndObserver.observeScreenLock(
            in: screenLockCenter, onEnd: onEnd)
        defer {
            workspaceObservers.forEach(workspaceCenter.removeObserver)
            screenLockCenter.removeObserver(screenLockObserver)
            continuation.finish()
        }

        for notice in DictationSessionEndObserver.notices {
            panel.reopenWithRevealedSecret()
            workspaceCenter.post(name: notice, object: nil)
            #expect(await ends.next() != nil)
            #expect(!panel.snapshot.isOpen)
            #expect(panel.snapshot.revealed.isEmpty)
        }

        panel.reopenWithRevealedSecret()
        screenLockCenter.post(name: DictationSessionEndObserver.screenIsLocked, object: nil)
        #expect(await ends.next() != nil)
        #expect(!panel.snapshot.isOpen)
        #expect(panel.snapshot.revealed.isEmpty)
    }

    @Test("session resign, display sleep, system sleep and screen lock stop suggestion work")
    func notificationsStopSuggestionWork() async throws {
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-session-end-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let workspaceCenter = NotificationCenter()
        let screenLockCenter = NotificationCenter()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true))
        defer { coordinator.stop() }
        coordinator.observeSessionEnd(in: workspaceCenter, screenLockCenter: screenLockCenter)

        for notice in DictationSessionEndObserver.notices {
            coordinator.noteActivity()
            coordinator.armSelectionMonitor(for: .certain("completion"), at: NSRange(location: 12, length: 0))
            #expect(coordinator.isTickerScheduled)
            #expect(coordinator.isSelectionPolling)

            workspaceCenter.post(name: notice, object: nil)
            await Task.yield()

            #expect(coordinator.armedOffer == nil)
            #expect(!coordinator.isSelectionPolling)
            #expect(!coordinator.isTickerScheduled)
        }

        coordinator.noteActivity()
        coordinator.armSelectionMonitor(for: .certain("completion"), at: NSRange(location: 12, length: 0))
        screenLockCenter.post(name: DictationSessionEndObserver.screenIsLocked, object: nil)
        await Task.yield()

        #expect(coordinator.armedOffer == nil)
        #expect(!coordinator.isSelectionPolling)
        #expect(!coordinator.isTickerScheduled)
    }
}
