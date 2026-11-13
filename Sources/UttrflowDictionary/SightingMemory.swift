// Where pending title sightings outlive a quit: hashed rows in the evidence ledger. See Docs/app-dictionary.md.

public import UttrflowCore
public import struct Foundation.Date

/// Keeps pending sightings as keyed hashes in the evidence ledger, under History retention.
public struct SightingMemory: Sendable {
    /// The domain separating these hashes from any other keyed hash made with the same key.
    static let purpose = "uttrflow.dictionary.sighting.v1"

    private let ledger: EvidenceLedgerStore
    private let window: @Sendable (Date) -> RetentionWindow
    /// The keyed hash a lowercased term is counted under; `nil` when the installation key is unavailable.
    let digest: @Sendable (String) -> String?

    /// `window` gives History's retention at a moment; `encryptedStore` holds the per-install key.
    public init(
        ledger: EvidenceLedgerStore, encryptedStore: EncryptedStore,
        window: @escaping @Sendable (Date) -> RetentionWindow
    ) {
        self.init(ledger: ledger, window: window) {
            try? encryptedStore.digest(of: $0, for: Self.purpose)
        }
    }

    /// Only a test passes its own `digest`.
    init(
        ledger: EvidenceLedgerStore, window: @escaping @Sendable (Date) -> RetentionWindow,
        digest: @escaping @Sendable (String) -> String?
    ) {
        self.ledger = ledger
        self.window = window
        self.digest = digest
    }

    /// The sighting rows still inside retention at `moment`.
    func rows(at moment: Date) async -> [EvidenceRow] {
        await ledger.rows(keeping: window(moment)).filter { $0.kind == .sighting }
    }

    /// Appends rows, refusing when the ledger on disk cannot be read.
    func append(_ rows: [EvidenceRow], at moment: Date) async throws {
        try await ledger.append(rows, keeping: window(moment))
    }
}
