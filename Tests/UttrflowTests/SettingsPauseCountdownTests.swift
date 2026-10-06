// Tests the Settings pause refresh with a clock that advances only when asked.

import Foundation
import Testing
import UttrflowCore
import UttrflowSettings
import UttrflowTestSupport
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("The Settings pause countdown")
struct SettingsPauseCountdownTests {
    @Test("updates each minute and redraws after the half-hour pause expires")
    func ticksThroughTheDeadline() async throws {
        var settings = Settings.default
        settings.suggestions.isEnabled = true
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        settings.suggestions.setPaused(true, at: startedAt)
        let until = try #require(settings.suggestions.pausedUntil)
        let session = SettingsSession(settings: settings, tab: .suggestions)
        let clock = ManualClock()
        let clockStart = clock.now
        var ticks = 0

        #expect(SettingsPauseCountdown.deadline(in: session) == until)
        var anotherTab = session
        anotherTab.tab = .general
        #expect(SettingsPauseCountdown.deadline(in: anotherTab) == nil)
        var searchFromAnotherTab = anotherTab
        searchFromAnotherTab.query = "pause"
        let visiblePauseRow = searchFromAnotherTab.presentation(at: startedAt)
            .pane.groups.flatMap(\.rows).first { row in
                guard case .action(_, let change) = row.control else { return false }
                if case .pauseSuggestions = change { return true }
                return false
            }
        #expect(visiblePauseRow != nil)
        #expect(SettingsPauseCountdown.deadline(in: searchFromAnotherTab) == until)

        var searchWithoutPauseRow = anotherTab
        searchWithoutPauseRow.query = "keyboard"
        #expect(
            searchWithoutPauseRow.presentation(at: startedAt)
                .pane.groups.flatMap(\.rows).allSatisfy { row in
                    guard case .action(_, let change) = row.control else { return true }
                    if case .pauseSuggestions = change { return false }
                    return true
                })
        #expect(SettingsPauseCountdown.deadline(in: searchWithoutPauseRow) == nil)

        let task = Task {
            await SettingsPauseCountdown.follow(
                until: until,
                clock: clock,
                now: {
                    let elapsed = clockStart.duration(to: clock.now).components
                    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                    return startedAt.addingTimeInterval(seconds)
                },
                onTick: { ticks += 1 })
        }

        await clock.waitUntilSomethingIsWaiting()
        for expectedTicks in 1...29 {
            await clock.advanceWhenSomethingIsWaiting(by: .milliseconds(60_500))
            await clock.waitUntilSomethingIsWaiting()
            #expect(ticks == expectedTicks)
        }
        await clock.advanceWhenSomethingIsWaiting(by: .seconds(46))
        await task.value

        #expect(ticks == 30)
        let finishedAt = startedAt.addingTimeInterval(1_800.5)
        let pane = SettingsPresenter.pane(
            for: .suggestions, settings: settings, capabilities: .everything,
            personalisation: .nothing, at: finishedAt)
        let pause = pane.groups.flatMap(\.rows).first { $0.id == "pauseSuggestions" }
        #expect(pause?.control == .action(title: "Pause 30 min", change: .pauseSuggestions(isOn: true)))
    }

    @Test("stops without refreshing when its view task is cancelled")
    func cancellationStopsTheTicker() async {
        let clock = ManualClock()
        let until = Date(timeIntervalSince1970: 1_700_001_800)
        let clockStart = clock.now
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var ticks = 0
        let task = Task {
            await SettingsPauseCountdown.follow(
                until: until,
                clock: clock,
                now: {
                    startedAt.addingTimeInterval(
                        Double(clockStart.duration(to: clock.now).components.seconds))
                },
                onTick: { ticks += 1 })
        }

        await clock.waitUntilSomethingIsWaiting()
        task.cancel()
        await task.value

        #expect(ticks == 0)
    }
}
