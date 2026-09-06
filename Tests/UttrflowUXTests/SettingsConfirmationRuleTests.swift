// Tests that every reset row asks a question exactly when SettingsReset says it must.
import Testing

import UttrflowSettings
@testable import UttrflowUX

/// Enough of a dictionary and a history for every removal row to be pressable.
private let filled = SettingsPersonalisation(
    learnedWords: 34, addedWords: 12, transcripts: 142)

/// Every removal the settings window offers, across all of its tabs.
private func everyRemoval() -> [SettingsRemoval] {
    SettingsTab.allCases
        .map { SettingsPresenter.pane(for: $0, settings: Settings(), personalisation: filled) }
        .flatMap(\.groups).flatMap(\.rows)
        .compactMap { row in
            guard case .removal(let removal) = row.control else { return nil }
            return removal
        }
}

@Suite("Every reset is asked about exactly as SettingsReset says it must be")
struct SettingsConfirmationRuleTests {
    /// The rule lives on ``SettingsReset`` and the wording on the row; this holds the two to one answer.
    @Test("the row a case is drawn with carries a question exactly when the case demands one")
    func rowsAgreeWithTheRule() {
        let removals = everyRemoval()

        // Every case is drawn somewhere, or the check below proves nothing.
        for reset in [SettingsReset.learnedWords, .everything] {
            #expect(
                removals.contains { $0.reset == reset },
                "\(reset) has no row, so nothing holds its confirmation rule")
        }

        for removal in removals {
            #expect(
                (removal.confirmation != nil) == removal.reset.isConfirmed,
                """
                \(removal.reset) says isConfirmed == \(removal.reset.isConfirmed) \
                but its row \(removal.confirmation == nil ? "asks nothing" : "asks a question").
                """)
            #expect(SettingsSession.isAnswerable(removal))
        }
    }

    /// The runtime half: a row built without its question must not delete anything.
    @Test("a confirmed reset built with no question removes nothing")
    func aConfirmedResetWithNoQuestionIsRefused() {
        var session = SettingsSession(settings: Settings(), personalisation: filled)
        let malformed = SettingsRemoval(reset: .everything, title: "Reset", confirmation: nil)

        #expect(SettingsSession.isAnswerable(malformed) == false)
        #expect(session.request(malformed) == nil)
    }

    @Test("and the reset that needs no question still runs on one press")
    func anUnconfirmedResetStillRuns() {
        var session = SettingsSession(settings: Settings(), personalisation: filled)
        let forget = SettingsRemoval(reset: .learnedWords, title: "Forget", confirmation: nil)

        #expect(session.request(forget) == .learnedWords)
    }
}
