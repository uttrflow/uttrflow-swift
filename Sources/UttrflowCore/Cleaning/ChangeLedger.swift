// What the passes did to a draft, by position and pass, read from each word's own edit chain.

/// One pass's change at one written position, holding no word, so History can keep it. See Docs/core-history-undo.md.
public struct ChangeLedgerEntry: Sendable, Equatable, Codable {
    /// Index among the written words: the word the change produced, or, for a removal, the word that now follows the gap.
    public let writtenIndex: Int
    public let pass: PassID
    public let kind: Kind
    /// How strongly the pass's replacement beat what was heard, bucketed; `nil` when the pass weighed none.
    public let evidence: OverrideEvidence.Bucket?

    /// What the pass did, without the words it did it to.
    public enum Kind: String, Sendable, Equatable, Codable {
        case removed
        case replaced
        case inserted
    }

    public init(writtenIndex: Int, pass: PassID, kind: Kind, evidence: OverrideEvidence.Bucket? = nil) {
        self.writtenIndex = writtenIndex
        self.pass = pass
        self.kind = kind
        self.evidence = evidence
    }

    /// The written word this change produced, or for a removal the word after the gap; `nil` when unlocated.
    public func location(in written: [String]) -> ChangeLocation? {
        if writtenIndex >= 0, writtenIndex < written.count { return .word(written[writtenIndex]) }
        if kind == .removed, writtenIndex == written.count { return .end }
        return nil
    }

    /// The words a ledger's indices count: present words that are not layout marks, read the way a draft reads text.
    public static func writtenWords(of text: String) -> [String] {
        Draft(keepingLineBreaks: text).words.filter { !$0.isLayoutMark }.map(\.text)
    }
}

/// Where in the written text one ledger entry lands.
public enum ChangeLocation: Sendable, Equatable {
    /// At this written word.
    case word(String)
    /// After the last written word: something was removed from the end.
    case end
}

extension Draft {
    /// Every edit in every word's chain at its written index (present non-layout words), with no re-alignment.
    public var changeLedger: [ChangeLedgerEntry] {
        var entries: [ChangeLedgerEntry] = []
        var written = 0
        for word in words where !word.isLayoutMark {
            for edit in word.edits {
                entries.append(
                    ChangeLedgerEntry(
                        writtenIndex: written, pass: edit.by, kind: Self.kind(edit.kind),
                        evidence: edit.evidence?.bucket))
            }
            if word.isPresent { written += 1 }
        }
        return entries
    }

    private static func kind(_ kind: Word.Edit.Kind) -> ChangeLedgerEntry.Kind {
        switch kind {
        case .removed: .removed
        case .replaced: .replaced
        case .inserted: .inserted
        }
    }
}
