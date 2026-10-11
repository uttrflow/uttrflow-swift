import Foundation
import Synchronization

/// What one candidate wrote for each case across repeated runs, and how often it changed its answer.
final class OutputSpread: Sendable {
    private let outputs = Mutex<[String: [String]]>([:])

    /// Keeps one run's text for a case.
    func record(_ text: String, forCase id: String) {
        outputs.withLock { $0[id, default: []].append(text) }
    }

    /// The cases whose runs did not all write the same text, as distinct texts out of runs, in id order.
    var flipped: [(id: String, distinct: Int, runs: Int)] {
        outputs.withLock { outputs in
            outputs.compactMap { id, texts in
                let distinct = Set(texts).count
                return distinct > 1 ? (id, distinct, texts.count) : nil
            }.sorted { $0.id < $1.id }
        }
    }

    /// The share of recorded cases whose runs all agreed; 1 when nothing was recorded.
    var stableShare: Double {
        let total = outputs.withLock { $0.count }
        guard total > 0 else { return 1 }
        return Double(total - flipped.count) / Double(total)
    }

    /// The summary line, then one line per flipped case.
    var lines: [String] {
        let total = outputs.withLock { $0.count }
        let runs = outputs.withLock { $0.values.map(\.count).max() ?? 0 }
        let flips = flipped
        let head =
            "  run-to-run: \(total - flips.count) of \(total) cases never flipped over \(runs) runs "
            + "(\(String(format: "%.1f", stableShare * 100))%)"
        return [head] + flips.map { "  flips \($0.id): \($0.distinct) distinct outputs in \($0.runs) runs" }
    }
}
