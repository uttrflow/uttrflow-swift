// The rows the app writes to the evidence ledger, from dictation, the dictionary and History. See `Docs/learned-state.md`.

import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import struct Foundation.UUID

/// Builds evidence rows from what already happened on this Mac; it reads no text into a row, only ids and counts.
enum EvidenceSources {
    /// One `use` row per dictionary entry a landed dictation used.
    static func uses(of ids: [UUID], day: Int) -> [EvidenceRow] {
        ids.map { EvidenceRow(kind: .use, subject: $0.uuidString, day: day, provenance: .dictation) }
    }

    /// One `revert` row for a correction the user undid.
    static func revert(of id: UUID, day: Int) -> EvidenceRow {
        EvidenceRow(kind: .revert, subject: id.uuidString, day: day, provenance: .undo)
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
