// Refreshes the Settings page while its visible Suggestions pause is running.

import Foundation
import UttrflowUX

@MainActor
enum SettingsPauseCountdown {
    /// Returns a deadline only while the pause row is visible in the selected pane or search results.
    static func deadline(in session: SettingsSession) -> Date? {
        let pauseRowIsVisible = session.presentation.pane.groups
            .flatMap(\.rows).contains { row in
                guard case .action(_, let change) = row.control else { return false }
                if case .pauseSuggestions = change { return true }
                return false
            }
        guard pauseRowIsVisible else { return nil }
        return session.settings.suggestions.pausedUntil
    }

    /// Ticks once a minute and once after the deadline, stopping when SwiftUI cancels its task.
    static func follow<C: Clock>(
        until deadline: Date,
        clock: C,
        now: @MainActor () -> Date,
        onTick: @MainActor () -> Void
    ) async where C.Duration == Duration {
        while !Task.isCancelled {
            let remaining = deadline.timeIntervalSince(now())
            guard remaining > 0 else { return }
            try? await clock.sleep(for: .seconds(min(60, remaining) + 0.5))
            guard !Task.isCancelled else { return }
            onTick()
        }
    }
}
