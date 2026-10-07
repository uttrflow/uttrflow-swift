// The persona as a projection over the evidence ledger, never a store of its own. See `Docs/learned-state.md`.

import UttrflowCore
import struct Foundation.Date
import struct Foundation.UUID

/// How much recent evidence says each dictionary entry belongs to this user, computed on read.
enum PersonaProjection {
    /// Recent kept uses per entry: `use` rows minus `revert` rows after the latest `restore`, on the `WorkingSet` recency curve.
    static func standing(of rows: [EvidenceRow], now: Date) -> [UUID: Double] {
        let today = EvidenceRow.day(of: now)
        var restored: [String: Int] = [:]
        for row in rows where row.kind == .restore {
            restored[row.subject] = max(restored[row.subject] ?? row.day, row.day)
        }
        var standing: [UUID: Double] = [:]
        for row in rows {
            guard let id = UUID(uuidString: row.subject) else { continue }
            let sign: Double
            switch row.kind {
            case .use: sign = 1
            case .revert:
                // A restore marks every revert on or before its day as ignored, never subtracted away.
                if let marker = restored[row.subject], row.day <= marker { continue }
                sign = -1
            case .restore, .sighting, .styleMessage, .styleWords, .styleSentences, .styleShortMessage,
                .styleClosingStop, .spellingPreference, .spellingPreferenceCleared, .pairConfirmed, .pairVetoed:
                continue
            }
            let age = Double(max(0, today - row.day))
            let decay = WorkingSet.recencyHalfLifeInDays / (WorkingSet.recencyHalfLifeInDays + age)
            standing[id, default: 0] += sign * Double(row.weight) * decay
        }
        return standing.filter { $0.value > 0 }
    }
}
