import Foundation
import OSLog
import UttrflowCore
import UttrflowPredict
import UttrflowPredictCapture

enum SuggestionConsentPersistence {
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")

    @MainActor
    static func recordChanges(
        from before: SuggestionPreferences,
        to after: SuggestionPreferences,
        using capture: CaptureSession,
        onFailure: ((any Error) -> Void)?
    ) async {
        for application in after.turnedOff.subtracting(before.turnedOff) {
            await record(.declined, for: application, using: capture, onFailure: onFailure)
        }
        let newlyAllowed = after.turnedOn.subtracting(before.turnedOn)
            .union(before.turnedOff.subtracting(after.turnedOff).filter { after.state(of: $0).isOn })
        for application in newlyAllowed {
            await record(.allowed, for: application, using: capture, onFailure: onFailure)
        }
    }

    @MainActor
    private static func record(
        _ state: ConsentState,
        for application: String,
        using capture: CaptureSession,
        onFailure: ((any Error) -> Void)?
    ) async {
        do {
            try await capture.record(state, for: application)
        } catch {
            log.error(
                "could not save application consent: \(SuggestionLog.failure(error), privacy: .public)"
            )
            onFailure?(error)
        }
    }
}
