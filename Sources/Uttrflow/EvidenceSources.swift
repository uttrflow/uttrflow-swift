// The rows the app writes to the evidence ledger, from dictation, the dictionary and History. See `Docs/learned-state.md`.

import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowPredictCapture

/// Builds evidence rows from what already happened on this Mac; it reads no text into a row beyond ids, counts and heard-to-meant keys.
enum EvidenceSources {
    /// One `use` row per dictionary entry a landed dictation used.
    static func uses(of ids: [UUID], day: Int) -> [EvidenceRow] {
        ids.map { EvidenceRow(kind: .use, subject: $0.uuidString, day: day, provenance: .dictation) }
    }

    /// One `revert` row for a correction the user undid.
    static func revert(of id: UUID, day: Int) -> EvidenceRow {
        EvidenceRow(kind: .revert, subject: id.uuidString, day: day, provenance: .undo)
    }

    /// The rows one undone correction writes: a revert against its entry, and a veto of its one heard-to-meant pairing.
    static func undone(_ reverted: RecordedCorrection, day: Int) -> [EvidenceRow] {
        [revert(of: reverted.entryID, day: day)]
            + ConfusionPairs.vetoing(heard: reverted.heard, meant: reverted.wrote, day: day)
    }

    /// The `pairConfirmed` row for an edit that replaced inserted words with others, punctuation aside; none for an addition, a removal or a run too long to be one entry.
    static func pair(kept edit: EditedSpan, day: Int) -> [EvidenceRow] {
        let bare = { (words: [String]) in
            words.map { $0.trimmingCharacters(in: .punctuationCharacters) }.filter { !$0.isEmpty }
        }
        let heard = bare(edit.old)
        let meant = bare(edit.new)
        guard (1...PhoneticIndex.maximumWordsPerEntry).contains(heard.count),
            (1...PhoneticIndex.maximumWordsPerEntry).contains(meant.count)
        else { return [] }
        return ConfusionPairs.confirming(
            heard: heard.joined(separator: " "), meant: meant.joined(separator: " "), day: day)
    }

    /// Rows for History's dictations older than anything the ledger already holds, so no dictation counts twice.
    static func backfill(
        _ records: [DictationRecord], entries: [DictionaryEntry], ledger: [EvidenceRow],
        overrides: DestinationOverrides
    ) -> [EvidenceRow] {
        guard !ledger.contains(where: { $0.provenance == .migration }) else { return [] }
        let firstLive = ledger.map(\.day).min() ?? Int.max
        return records.reversed().flatMap { record -> [EvidenceRow] in
            let day = EvidenceRow.day(of: record.when)
            guard day < firstLive else { return [] }
            let app = AppContext(
                applicationName: record.applicationName, bundleIdentifier: record.applicationIdentifier)
            let destination = DestinationClassifier.classify(app, overrides: overrides)
            let used = DictionaryAppearances.used(entries, applied: [], writtenIn: record.text)
            return
                (uses(of: used, day: day) + StyleSignals.rows(for: record.text, into: destination, day: day))
                .map {
                    EvidenceRow(
                        kind: $0.kind, subject: $0.subject, weight: $0.weight, day: $0.day,
                        provenance: .migration)
                }
        }
    }

    /// Appends History's pre-ledger dictations to the ledger once, when there is one; a refused write is retried on the next sweep.
    static func backfill(
        _ ledger: EvidenceLedgerStore?, from records: [DictationRecord], dictionary: PersonalDictionaryStore,
        overrides: DestinationOverrides, keeping window: RetentionWindow
    ) async {
        guard let ledger else { return }
        let rows = backfill(
            records, entries: await dictionary.allEntries(), ledger: await ledger.rows(keeping: window),
            overrides: overrides)
        if !rows.isEmpty { try? await ledger.append(rows, keeping: window) }
    }
}
