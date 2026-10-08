// What a History row's "What changed" reads: the stored change ledger, located in the stored text.
public import UttrflowCore

/// One change the clean-up made, read from the ledger rather than by aligning texts. See Docs/core-history-undo.md.
public struct WhatChangedLine: Sendable, Equatable {
    public let pass: PassID
    public let kind: ChangeLedgerEntry.Kind
    /// How strongly the replacement beat what was heard, bucketed; `nil` when the pass weighed none.
    public let evidence: OverrideEvidence.Bucket?
    /// Where it landed in the stored text; `nil` when the ledger points past it.
    public let location: ChangeLocation?

    public init(
        pass: PassID, kind: ChangeLedgerEntry.Kind, evidence: OverrideEvidence.Bucket?,
        location: ChangeLocation?
    ) {
        self.pass = pass
        self.kind = kind
        self.evidence = evidence
        self.location = location
    }
}

extension DictationRecord {
    /// Every ledgered change, in ledger order; `nil` when the row has no ledger and the caller falls back to alignment.
    public var whatChanged: [WhatChangedLine]? {
        guard let changeLedger else { return nil }
        let written = ChangeLedgerEntry.writtenWords(of: text)
        return changeLedger.map {
            WhatChangedLine(
                pass: $0.pass, kind: $0.kind, evidence: $0.evidence, location: $0.location(in: written))
        }
    }
}
