// The recogniser's per-word doubt, carried to the outcome as word positions with no text.

/// Why a run of written words is doubtful.
public enum DoubtKind: UInt8, Sendable, Equatable, CaseIterable {
    case lowScore
    case soundAlikeClass
    case overridden
    case numberLike
    case negatorAdjacent
    case nameLike
}

/// A run of written words the recogniser was unsure of, located by word index in the written text.
public struct DoubtfulWordSpan: Sendable, Equatable {
    /// Word indices in the written text, half open.
    public let range: Range<Int>
    public let kind: DoubtKind
    /// How strong the evidence is, bucketed so no score leaks the recogniser's internals.
    public let evidence: UInt8

    public init(range: Range<Int>, kind: DoubtKind, evidence: UInt8) {
        self.range = range
        self.kind = kind
        self.evidence = evidence
    }
}

/// The doubtful words of one dictation, or the fact that the engine or path gave no real evidence.
public enum DoubtfulWords: Sendable, Equatable {
    /// The engine or path had no per-word evidence; not the same as nothing being doubtful.
    case notAvailable
    /// Spans placed on the written text, and how many the aligner could not place.
    case placed([DoubtfulWordSpan], unplaced: Int)
}
