import Foundation
import OSLog
import UttrflowContext
import UttrflowCore
import UttrflowPredict
import UttrflowPredictStore

protocol RejectedSuggestionStore: Sendable {
    func recordRejected(_ text: String, in surface: Surface) async throws
}

extension PredictStore: RejectedSuggestionStore {}

/// Records rejected suggestions, retries failed writes and suppresses uncertain lines for this session.
@MainActor
final class RejectedSuggestionRecorder {
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")
    private static let limit = 32
    private let store: any RejectedSuggestionStore
    private var unwritten: [PendingRejection] = []
    private var suppressed: Set<RejectedSuggestion> = []
    private var nextID: UInt64 = 0
    private var isRetrying = false

    init(store: any RejectedSuggestionStore) {
        self.store = store
    }

    /// Records a rejection or holds it for retry, suppressing it when the write fails.
    func record(_ text: String, in surface: Surface) async {
        do {
            try await store.recordRejected(text, in: surface)
        } catch {
            let rejection = RejectedSuggestion(text: text, surface: surface)
            unwritten.append(PendingRejection(id: claimID(), rejection: rejection))
            if unwritten.count > Self.limit {
                let discarded = unwritten.removeFirst()
                removeSuppressionIfNoPendingWrite(for: discarded.rejection)
            }
            suppressed.insert(rejection)
            Self.log.error(
                "A rejected suggestion's corpus write failed and is held for retry: \(SuggestionLog.failure(error), privacy: .public)"
            )
        }
    }

    /// Retries held rejection writes in order, stopping at the first repeated failure.
    func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        while let pending = unwritten.first {
            do {
                try await store.recordRejected(pending.rejection.text, in: pending.rejection.surface)
                if unwritten.first?.id == pending.id { unwritten.removeFirst() }
                removeSuppressionIfNoPendingWrite(for: pending.rejection)
            } catch {
                Self.log.error(
                    "A rejected suggestion's corpus retry failed: \(SuggestionLog.failure(error), privacy: .public)"
                )
                return
            }
        }
    }

    /// Drops held writes and suppressions for the forgotten applications, or all of them when `bundleIdentifier` is nil.
    func forget(bundleIdentifier: String? = nil) {
        let key = bundleIdentifier.map(ApplicationKey.of)
        let isForgotten = { (rejection: RejectedSuggestion) in
            key == nil || rejection.surface.bundleIdentifier == key
        }
        unwritten.removeAll { isForgotten($0.rejection) }
        suppressed = suppressed.filter { !isForgotten($0) }
    }

    /// Gives a held rejection a stable identity through actor reentrancy.
    private func claimID() -> UInt64 {
        defer { nextID &+= 1 }
        return nextID
    }

    /// Keeps a refusal suppressed only while a failed write for that same line remains queued.
    private func removeSuppressionIfNoPendingWrite(for rejection: RejectedSuggestion) {
        guard !unwritten.contains(where: { $0.rejection == rejection }) else { return }
        suppressed.remove(rejection)
    }

    /// Whether the failed write keeps this line unavailable in its surface this session.
    func suppresses(_ text: String, in surface: Surface) -> Bool {
        suppressed.contains(RejectedSuggestion(text: text, surface: surface))
    }
}

private struct RejectedSuggestion: Hashable {
    let text: String
    let surface: Surface

    func hash(into hasher: inout Hasher) {
        hasher.combine(TextMatching.caseFoldedKey(text))
        hasher.combine(surface)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.surface == rhs.surface
            && TextMatching.caseFoldedKey(lhs.text) == TextMatching.caseFoldedKey(rhs.text)
    }
}

private struct PendingRejection {
    let id: UInt64
    let rejection: RejectedSuggestion
}
