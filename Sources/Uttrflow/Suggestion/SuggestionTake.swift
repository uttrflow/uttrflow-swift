import Foundation
import OSLog
import UttrflowCore
import UttrflowInput
import UttrflowPredict
import UttrflowPredictCapture

/// Takes an accepted suggestion into the field, queues the taken line for capture, and says whether the accept key goes back.
@MainActor
struct SuggestionTake {
    /// Writes the trimmed suggestion after `typed` into the field of the window numbered, or nil when nothing was needed.
    typealias Insert = (Suggestion, String, UInt32) async throws(TextInsertionError) -> TextInsertionMethod?

    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    let insert: Insert
    let acceptances: AcceptanceQueue
    let capture: CaptureSession
    /// Called when the insertion was refused for lost accessibility trust.
    let trustLost: () -> Void

    /// Puts the tail into the field and queues the taken line for capture, reporting uncertain writes.
    func take(
        _ text: String, after typed: String, in reading: FieldReading?, closingPunctuation: String,
        recordsAcceptance: Bool = true
    ) async -> UttrflowPredict.AcceptanceOutcome {
        // What the gates left is a whole line, so taking it may replace characters as well as add.
        guard let windowNumber = reading?.surface?.windowNumber else {
            Self.log.error("the drawn field has no identifiable window; giving the key back")
            return .refused
        }
        var via = "nothing"
        let accepted = Suggestion.certain(text).trimmed(after: typed, matching: closingPunctuation)
        do throws(TextInsertionError) {
            via = try await insert(accepted, typed, windowNumber)?.rawValue ?? via
        } catch {
            // A refusal for lost trust withdraws suggestions and tells the menu bar, as the next activation would.
            if error == .accessibilityDenied { trustLost() }
            let outcome = Self.acceptanceOutcome(for: error)
            if outcome == .refused {
                Self.log.error("\(SuggestionLog.landedNowhere(error, typed: typed), privacy: .public)")
            } else {
                Self.log.error("\(SuggestionLog.deliveryUnconfirmed(error, typed: typed), privacy: .public)")
            }
            return outcome
        }
        Self.log.debug("\(SuggestionLog.accept(text: text, typed: typed, via: via), privacy: .public)")
        // Taking one word leaves the offer open, so the corpus does not hear a full acceptance.
        guard recordsAcceptance, let reading else { return .inserted }
        let moment = Date()
        let log = Self.log
        let bytes = AcceptanceQueue.estimatedBytes(
            for: [
                text, typed, reading.bundleIdentifier, reading.role, reading.subrole, reading.identifier,
                reading.placeholder, reading.accessibilityDescription, reading.document, reading.windowTitle,
                reading.applicationName,
            ], surface: reading.surface)
        _ = acceptances.enqueue(
            { [capture] in
                do {
                    _ = try await capture.accepted(text, over: typed, in: reading, at: moment)
                } catch {
                    // The session holds the acceptance and retries it before the next event.
                    log.error("An accepted suggestion's corpus write failed and is held for a retry")
                }
            }, estimatedBytes: bytes)
        return .inserted
    }

    /// Returns the accept stroke only when the field is known to be unchanged.
    static func acceptKeyToReturnIfTakeFails(
        _ stroke: UttrflowCore.KeyStroke, taking: () async -> UttrflowPredict.AcceptanceOutcome,
        requestFreshRead: () -> Void,
        completed: (UttrflowPredict.AcceptanceOutcome) -> Void = { _ in }
    ) async -> UttrflowCore.KeyStroke? {
        let outcome = await taking()
        completed(outcome)
        if outcome == .mayHaveWritten { requestFreshRead() }
        return outcome == .refused ? stroke : nil
    }

    /// Whether an insertion error proves that no suggestion text reached the field.
    static func acceptanceOutcome(for error: TextInsertionError) -> UttrflowPredict.AcceptanceOutcome {
        switch error {
        case .noFocusedTextField, .accessibilityDenied, .insertionRejected, .insertionNeedsCopy,
            .insertionTargetChanged, .insertionFieldClosed:
            .refused
        case .clipboardUnavailable, .clipboardChanged, .insertionTimedOut, .insertionCancelled,
            .insertionUnconfirmed, .insertionInterrupted:
            .mayHaveWritten
        }
    }
}
