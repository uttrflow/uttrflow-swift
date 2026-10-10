import Foundation
import UttrflowCore
import UttrflowHistory
import UttrflowPipeline

enum DictationRecordMapping {
    static func record(
        for state: DictationState, when: Date, id: UUID, keeping: HistoryKeeping = .everything
    ) -> DictationRecord? {
        switch state {
        case .inserted(let outcome):
            guard let text = outcome.wordsToKeep,
                keeping.keeps(applicationIdentifier: outcome.insertedIntoIdentifier)
            else { return nil }
            return DictationRecord(
                id: id, text: text, when: when, applicationName: outcome.insertedInto,
                applicationIdentifier: outcome.insertedIntoIdentifier, spokenFor: outcome.spokenFor,
                changes: RecordedChanges(
                    corrections: outcome.changes.corrections.map {
                        RecordedCorrection(
                            heard: $0.heard, wrote: $0.wrote, wordRange: $0.wordRange,
                            entryID: $0.entryID, reason: $0.reason,
                            heardConfidence: $0.heardConfidence, evidence: $0.evidence,
                            writtenWordIndex: $0.writtenWordIndex)
                    },
                    snippets: outcome.changes.snippets.map {
                        RecordedSnippet(
                            snippetID: $0.snippetID, matched: $0.matched,
                            expansion: $0.expansion)
                    },
                    spokenWords: outcome.changes.spokenWords),
                cleanedBy: outcome.cleanedBy, arrival: RecordedArrival(outcome.arrival),
                changeLedger: outcome.changes.changeLedger, slowCause: outcome.slowCause,
                heard: outcome.heardToKeep)
        case .failed(let failure):
            guard let text = failure.wordsToKeep, keeping.keeps(applicationIdentifier: nil)
            else { return nil }
            return DictationRecord(id: id, text: text, when: when, arrival: .notInserted)
        case .idle, .recording, .transcribing, .tidying, .inserting, .executed, .discarded:
            return nil
        }
    }
}
