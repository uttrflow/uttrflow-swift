import Synchronization
import UttrflowCore

/// Counts each feed result once per Sparkle cycle and each archive at its request callback.
final class UpdateRequestActivity: Sendable {
    private let feedWasCounted = Mutex(false)
    private let ledger: NetworkActivityLedger

    init(ledger: NetworkActivityLedger = .shared) {
        self.ledger = ledger
    }

    func feedLoaded() { countFeedOnce() }

    func feedFailed() { countFeedOnce() }

    func archiveWillDownload() { ledger.record(.updateCheck) }

    func checkDidFinish() { feedWasCounted.withLock { $0 = false } }

    private func countFeedOnce() {
        let shouldRecord = feedWasCounted.withLock { wasCounted -> Bool in
            guard !wasCounted else { return false }
            wasCounted = true
            return true
        }
        if shouldRecord { ledger.record(.updateCheck) }
    }
}
