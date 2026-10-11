import Foundation
import Testing
import UttrflowCore
import UttrflowPipeline
import UttrflowUX

@testable import Uttrflow

@Suite("Dictation menu mapping is independent of app coordination")
struct MenuBarDictationMappingTests {
    @Test("unfinished and command outcomes retain their exact activity")
    func activityProjection() {
        let samples: [(DictationState, DictationActivity)] = [
            (.idle, .idle), (.recording, .listening), (.transcribing, .working),
            (.tidying, .working), (.inserting(into: nil), .working),
            (.discarded(DictationDiscard(spokenFor: .seconds(90), keptRecording: UUID())), .discarded),
            (.executed("Example action."), .executed),
        ]
        for (state, activity) in samples {
            for shown in [false, true] {
                let mapped = MenuBarDictationMapping.state(for: state, floatingButtonShown: shown)
                #expect(mapped.activity == activity)
                #expect(mapped.outcomeQuality == .complete)
                #expect(mapped.failure == nil)
            }
        }
    }

    @Test("completion retains arrival and missed-speech quality")
    func completionProjection() {
        let samples: [(TextInsertionMethod, InsertionArrival, Int, DictationActivity, OutcomeQuality)] = [
            (.typed, .confirmed, 0, .inserted, .complete),
            (.typed, .unconfirmed, 0, .unconfirmed, .complete),
            (.typed, .confirmed, 1, .partial, .partial),
            (.typed, .unconfirmed, 1, .unconfirmed, .partial),
            (.clipboard, .notReported, 0, .copied, .complete),
            (.clipboard, .notReported, 1, .copied, .partial),
        ]
        for (method, arrival, missed, activity, quality) in samples {
            let outcome = DictationOutcome(
                text: "Example text.", method: method, cleanedBy: .rules, arrival: arrival,
                missedPieces: missed)
            let mapped = MenuBarDictationMapping.state(for: .inserted(outcome), floatingButtonShown: false)
            #expect(mapped.activity == activity)
            #expect(mapped.outcomeQuality == quality)
            #expect(mapped.failure == nil)
        }
    }

    @Test("failures retain detail, recovery and severity on the surface actually shown")
    func failureProjection() {
        for severity in [FailureSeverity.informational, .recoverable, .degraded, .blocking] {
            for shown in [false, true] {
                let failure = DictationFailure(
                    message: "Example notice. Example detail.", recovery: .retry, severity: severity)
                let mapped = MenuBarDictationMapping.state(for: .failed(failure), floatingButtonShown: shown)
                #expect(mapped.activity == .idle)
                #expect(mapped.outcomeQuality == .complete)
                #expect(mapped.failure?.headline == "Example notice.")
                #expect(mapped.failure?.detail == "Example detail.")
                #expect(mapped.failure?.severity == severity)
                #expect(mapped.failure?.action?.recovery == .retry)
                #expect(
                    mapped.failure?.placement == (shown && severity != .blocking ? .floatingButton : .menuBar)
                )
            }
        }
    }
}
