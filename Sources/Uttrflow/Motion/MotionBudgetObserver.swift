// Keeps the motion budget current for SwiftUI views as Reduce Motion, Low Power Mode and thermal state change.

import AppKit
import Observation

/// The motion budget views draw from, re-read after every notice in `MotionBudget.changeNotices`.
@MainActor
@Observable
final class MotionBudgetObserver {
    /// The one the app's views share.
    static let shared = MotionBudgetObserver(read: { MotionBudget.current() })

    /// What the system allows now.
    private(set) var budget: MotionBudget

    @ObservationIgnored private let read: @MainActor () -> MotionBudget
    @ObservationIgnored private var observers: [(centre: NotificationCenter, token: any NSObjectProtocol)] =
        []

    /// Reads the budget with `read` now, and again whenever the system says it may have changed.
    init(
        read: @escaping @MainActor () -> MotionBudget,
        workspace: any MotionWorkspace = SystemWorkspace()
    ) {
        self.read = read
        budget = read()
        observers = MotionBudget.changeNotices(in: workspace).map { notice in
            let token = notice.centre.addObserver(forName: notice.name, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            return (notice.centre, token)
        }
    }

    /// Re-reads the budget, publishing only a change so views do not redraw for nothing.
    func refresh() {
        let now = read()
        if now != budget { budget = now }
    }

    isolated deinit {
        for observer in observers { observer.centre.removeObserver(observer.token) }
    }
}
