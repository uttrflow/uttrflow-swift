// Tests that every dictation state shows on the menu bar with the floating button on and off.

import Foundation
import Testing
import UttrflowCore
import UttrflowPipeline
import UttrflowUX

@testable import Uttrflow

/// The menu bar carries every dictation state alone when the button is off; `Docs/app-dock.md` lists each.
@Suite("Every dictation state has a menu bar form")
struct MenuBarSurfaceTableTests {
    /// One sample of each state, named as the table in `Docs/app-dock.md` names its row.
    private static let samples: [(row: String, state: DictationState)] = [
        ("`idle`", .idle),
        ("`recording`", .recording),
        ("`transcribing`", .transcribing),
        ("`tidying`", .tidying),
        ("`inserting`", .inserting(into: nil)),
        ("`inserted`, confirmed", .inserted(outcome(.typed, .confirmed))),
        ("`inserted`, unconfirmed", .inserted(outcome(.typed, .unconfirmed))),
        ("`inserted`, partial", .inserted(outcome(.typed, .confirmed, missedPieces: 1))),
        ("`inserted`, copied", .inserted(outcome(.clipboard, .notReported))),
        ("`failed`, informational", .failed(failure(.informational))),
        ("`failed`, recoverable or degraded", .failed(failure(.recoverable))),
        ("`failed`, recoverable or degraded", .failed(failure(.degraded))),
        ("`failed`, blocking", .failed(failure(.blocking))),
        ("`discarded`", .discarded(DictationDiscard(spokenFor: .seconds(90), keptRecording: UUID()))),
    ]

    private static func outcome(
        _ method: TextInsertionMethod, _ arrival: InsertionArrival, missedPieces: Int = 0
    ) -> DictationOutcome {
        DictationOutcome(
            text: "Hello.", method: method, cleanedBy: .rules, arrival: arrival, missedPieces: missedPieces)
    }

    private static func failure(_ severity: FailureSeverity) -> DictationFailure {
        DictationFailure(message: "Didn't catch that.", recovery: nil, severity: severity)
    }

    /// Exhaustive, so a new `DictationState` case does not compile until it has a sample above.
    private static func isSampled(_ state: DictationState) -> Bool {
        switch state {
        case .idle, .recording, .transcribing, .tidying, .inserting, .inserted, .failed, .discarded:
            samples.contains { sameCase($0.state, state) }
        }
    }

    private static func sameCase(_ lhs: DictationState, _ rhs: DictationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.transcribing, .transcribing),
            (.tidying, .tidying), (.inserting, .inserting), (.inserted, .inserted), (.failed, .failed),
            (.discarded, .discarded):
            true
        default: false
        }
    }

    private var table: String {
        get throws {
            let doc = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // UttrflowTests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // the package
                .appending(path: "Docs/app-dock.md")
            return try String(contentsOf: doc, encoding: .utf8)
        }
    }

    @Test("lists every sampled state as a row of the surface table")
    func everyStateHasARow() throws {
        let table = try table
        for sample in Self.samples {
            #expect(Self.isSampled(sample.state))
            #expect(table.contains("| \(sample.row) |"), "no row for \(sample.row)")
        }
    }

    @Test("shows every state but rest on the menu bar, with the floating button on and off")
    func noStateLooksLikeRest() {
        let rest = MenuBarPresenter.present(MenuBarState())
        for sample in Self.samples where sample.row != "`idle`" {
            for floatingButtonShown in [true, false] {
                let state = AppDelegate.menuBarDictation(
                    for: sample.state, floatingButtonShown: floatingButtonShown)
                let shown = MenuBarPresenter.present(state)
                let context = "\(sample.row), button shown: \(floatingButtonShown)"
                #expect(shown.icon != rest.icon, "\(context) shows the resting icon")
                #expect(shown.statusLine != rest.statusLine, "\(context) shows the resting line")
                #expect(shown.accessibilityLabel != rest.accessibilityLabel, "\(context) speaks rest")
            }
        }
    }

    @Test("lights the menu bar for every failure once the floating button is off")
    func failureWithoutTheButtonNeedsAttention() {
        for sample in Self.samples {
            guard case .failed = sample.state else { continue }
            let state = AppDelegate.menuBarDictation(for: sample.state, floatingButtonShown: false)
            #expect(MenuBarPresenter.present(state).isAttentionNeeded, "\(sample.row)")
        }
    }
}
