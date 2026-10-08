// The corpus sink with the one thing it ignores, an edit inside inserted text, handed to the dictation side.

import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore
import struct Foundation.Date

/// Sends finished values to the corpus and each edit of inserted words to `heard`, which learns heard-to-meant pairs.
struct EditHearingSink: CaptureSink {
    let store: PredictStore
    let heard: @Sendable (EditedSpan) async -> Void

    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) async throws {
        try await store.record(text, in: surface, after: previous, selfSourced: selfSourced, at: moment)
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) async throws {
        try await store.supersede(text, with: replacement, in: surface)
    }

    func recordAccepted(_ text: String, in surface: Surface) async throws {
        try await store.recordAccepted(text, in: surface)
    }

    func retractAcceptance(_ text: String, in surface: Surface) async throws {
        try await store.retractAcceptance(text, in: surface)
    }

    func recordEditedSpan(_ edit: EditedSpan, in surface: Surface) async throws {
        await heard(edit)
    }
}
