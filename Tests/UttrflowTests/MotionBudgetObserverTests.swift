// Tests for the observer that keeps the motion budget current.

import AppKit
import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import Uttrflow

@MainActor
@Suite("Keeping the motion budget current")
struct MotionBudgetObserverTests {
    /// A budget the test changes by hand, standing in for the system.
    private final class Source {
        var budget = MotionBudget()
    }

    /// A workspace with its own notification centre, so no notice reaches the real one.
    private struct FakeWorkspace: MotionWorkspace {
        var reducesMotion = false
        let notificationCenter = NotificationCenter()
    }

    @Test("reads the budget when it is made")
    func readsAtStart() {
        let source = Source()
        source.budget = MotionBudget(reducesMotion: true)

        let observer = MotionBudgetObserver(read: { source.budget })

        #expect(observer.budget == MotionBudget(reducesMotion: true))
    }

    @Test("re-reads the budget on each notice that can change it", arguments: [0, 1, 2])
    func rereadsOnNotice(_ index: Int) {
        let source = Source()
        let workspace = FakeWorkspace()
        let observer = MotionBudgetObserver(read: { source.budget }, workspace: workspace)
        let notice = MotionBudget.changeNotices(in: workspace)[index]
        source.budget = MotionBudget(energy: EnergyConditions(isLowPowerMode: true))

        notice.centre.post(name: notice.name, object: nil)

        #expect(observer.budget == source.budget)
    }

    @Test("keeps the same value when a refresh finds nothing changed")
    func refreshWithoutChange() {
        let source = Source()
        let observer = MotionBudgetObserver(read: { source.budget })

        observer.refresh()

        #expect(observer.budget == MotionBudget())
    }

    @Test("listens for power, thermal and Reduce Motion notices")
    func theNotices() {
        let workspace = FakeWorkspace()
        let notices = MotionBudget.changeNotices(in: workspace)
        let names = notices.map(\.name)

        #expect(names.contains(.NSProcessInfoPowerStateDidChange))
        #expect(names.contains(ProcessInfo.thermalStateDidChangeNotification))
        #expect(names.contains(NSWorkspace.accessibilityDisplayOptionsDidChangeNotification))
        #expect(notices.last?.centre === workspace.notificationCenter)
    }

    @Test("reads Reduce Motion from the workspace it is given")
    func readsTheGivenWorkspace() {
        #expect(MotionBudget.current(in: FakeWorkspace(reducesMotion: true)).reducesMotion)
        #expect(!MotionBudget.current(in: FakeWorkspace(reducesMotion: false)).reducesMotion)
    }

    @Test("a private workspace notice refreshes only its own observer")
    func privateWorkspaceNoticesStayIndependent() {
        let firstSource = Source()
        let secondSource = Source()
        let firstWorkspace = FakeWorkspace()
        let secondWorkspace = FakeWorkspace()
        let first = MotionBudgetObserver(read: { firstSource.budget }, workspace: firstWorkspace)
        let second = MotionBudgetObserver(read: { secondSource.budget }, workspace: secondWorkspace)
        firstSource.budget = MotionBudget(reducesMotion: true)
        secondSource.budget = MotionBudget(reducesMotion: true)

        firstWorkspace.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)

        #expect(first.budget == firstSource.budget)
        #expect(second.budget == MotionBudget())
        secondWorkspace.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(second.budget == secondSource.budget)
    }

    @Test("the system workspace is the shared one")
    func theSystemWorkspace() {
        let system = SystemWorkspace()

        #expect(system.notificationCenter === NSWorkspace.shared.notificationCenter)
        #expect(MotionBudget.changeNotices.last?.centre === system.notificationCenter)
    }

    @Test("session loss, screen sleep, and system sleep each end dictation")
    func dictationSessionEndNotices() {
        let center = NotificationCenter()
        let received = Mutex(0)
        let observers = DictationSessionEndObserver.observe(in: center) {
            received.withLock { $0 += 1 }
        }
        defer { observers.forEach(center.removeObserver) }

        for notice in DictationSessionEndObserver.notices {
            center.post(name: notice, object: nil)
        }

        #expect(received.withLock { $0 } == 3)
    }

    @Test("a screen lock ends dictation")
    func screenLockEndsDictation() {
        let center = NotificationCenter()
        let received = Mutex(0)
        let observer = DictationSessionEndObserver.observeScreenLock(in: center) {
            received.withLock { $0 += 1 }
        }
        defer { center.removeObserver(observer) }

        center.post(name: DictationSessionEndObserver.screenIsLocked, object: nil)

        #expect(received.withLock { $0 } == 1)
    }

    @Test("returned session-end tokens stop every callback when removed")
    func removingSessionEndTokensStopsCallbacks() {
        let center = NotificationCenter()
        let received = Mutex(0)
        let callback: @Sendable () -> Void = { received.withLock { $0 += 1 } }
        let observers =
            DictationSessionEndObserver.observe(in: center, onEnd: callback)
            + [DictationSessionEndObserver.observeScreenLock(in: center, onEnd: callback)]
        defer { observers.forEach(center.removeObserver) }

        let notices = DictationSessionEndObserver.notices + [DictationSessionEndObserver.screenIsLocked]
        for notice in notices { center.post(name: notice, object: nil) }
        #expect(received.withLock { $0 } == 4)

        observers.forEach(center.removeObserver)
        for notice in notices { center.post(name: notice, object: nil) }
        #expect(received.withLock { $0 } == 4)
    }

    @Test("shares one observer that starts from the system's reading")
    func sharedReadsTheSystem() {
        #expect(MotionBudgetObserver.shared.budget == MotionBudget.current())
    }
}
