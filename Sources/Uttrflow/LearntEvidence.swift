// The one gate between the app's learners and the evidence ledger: the switch in Settings, then each application's answer.

import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowHistory
import UttrflowPipeline
import UttrflowPredictCapture
import UttrflowSettings

/// Writes rows learnt from an application, in order, unless the person declined it or turned learning off.
@MainActor
final class LearntEvidence {
    /// The answer every dictation learner reads before it writes, the pipeline's and History's backfill included.
    let consent: any LearningConsent
    /// The newest write, so each waits for the one before it.
    private(set) var pending: Task<Void, Never>?
    private let ledger: EvidenceLedgerStore?
    private let settings: UserDefaultsSettingsStore

    /// A gate over `ledger` that reads the switch and the answers kept in `container` at each write.
    init(ledger: EvidenceLedgerStore?, settings: UserDefaultsSettingsStore, container: URL) {
        self.ledger = ledger
        self.settings = settings
        // The same answers typing capture keeps, so one refusal covers both.
        consent = SwitchedLearningConsent(
            isOn: { settings.load().learnsFromDictation },
            answers: KeptOutOfHistory(
                keeping: { HistoryKeeping(settings.load()) },
                answers: CapturePreferencesFile(
                    path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false))))
    }

    /// Appends `rows` learnt in `application` inside History's window, once consent says it may.
    func note(_ rows: [EvidenceRow], from application: String?) {
        guard let ledger, !rows.isEmpty else { return }
        let window = RetentionWindow(days: settings.load().transcriptRetentionDays, now: Date())
        let previous = pending
        pending = Task { [consent] in
            await previous?.value
            do {
                try await ledger.append(rows, keeping: window, learntIn: application, consent: consent)
            } catch {
                AppDelegate.log.error("evidence not saved: \(ErrorLog.failure(error), privacy: .public)")
            }
        }
    }
}

/// Declines an application whose dictations History leaves out, so nothing about it is learnt either.
private struct KeptOutOfHistory: LearningConsent {
    /// What History keeps, read at each question so a change in Settings counts at once.
    let keeping: @Sendable () -> HistoryKeeping
    /// What was said about each application History does keep.
    let answers: any LearningConsent

    /// Declined where History keeps nothing of this application, otherwise what was said about it.
    func state(of bundleIdentifier: String?) -> ConsentState {
        guard keeping().keeps(applicationIdentifier: bundleIdentifier) else { return .declined }
        return answers.state(of: bundleIdentifier)
    }
}

extension HistoryKeeping {
    /// What History may keep, from the two saved choices.
    init(_ settings: Settings) {
        self.init(
            keepsNothing: settings.keepsNoTranscripts,
            excludedApplications: Set(settings.historyExcludedApplications))
    }
}

extension UttrflowPipeline.DictationOutcome {
    /// Whether this dictation may add style or retry rows: not a secure field, a private window or a recording.
    var teachesEvidence: Bool { !intoSecureField && !fromPrivateWindow && !isFromRecording }
}

extension UttrflowHistory.DictationRecord {
    /// Whether History may backfill evidence from it; secure fields and credentials never reach History at all.
    var teachesEvidence: Bool { !fromPrivateWindow }
}
