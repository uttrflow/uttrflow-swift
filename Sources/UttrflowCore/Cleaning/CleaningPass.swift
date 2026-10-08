/// What a pass may take out of the text, which the meaning guard holds each of its removals to. See `Docs/cleanup.md`.
public enum RemovalGrant: Sendable, Equatable {
    /// A sound that was never a word, so never a numeral or a word written in capitals.
    case sound
    /// A stammer or incomplete first saying whose restart remains in the text.
    case repetition
    /// The half of a correction the speaker took back, with the trigger that announced it.
    case retraction
    /// Words the pass wrote as the mark, numeral or contraction beside them.
    case conversion
}

/// A property a pass keeps on every draft, which one property suite checks against generated input.
public enum PassLaw: Sendable, Hashable, CaseIterable {
    /// Running the pass on its own output changes nothing.
    case idempotent
    /// Every word it leaves, ignoring case, was already a word of the draft.
    case addsNoWords
    /// The draft's digits come out in the same order, none added and none dropped.
    case keepsDigits
    /// A draft with no Devanagari and no control character comes out with none.
    case latinOnly
}

/// The scope a piece pass asks about: the words of one piece, never its neighbours or the piece count.
public enum PieceScope {}

/// The scope a whole-text pass asks about: the joined message, which no piece holds.
public enum WholeTextScope {}

/// One cleaning that needs no model: a pure function over a draft that records every word it touches.
public protocol CleaningPass: Sendable {
    /// Which text the pass's question is about; a pass adopts `PieceCleaningPass` or `WholeTextCleaningPass` to say.
    associatedtype Scope
    static var id: PassID { get }
    /// What the pass may remove; a pass that does not say only turns words into what it writes.
    static var removes: RemovalGrant { get }
    /// The laws the pass keeps; every pass states them, an empty set included, so none is left unchecked.
    static var laws: Set<PassLaw> { get }
    func apply(_ draft: Draft) -> Draft
}

/// A pass whose question is answered by one piece alone, so it is right on any piece of a message.
public protocol PieceCleaningPass: CleaningPass where Scope == PieceScope {}

/// A pass that may run only after every piece of one message has been joined.
public protocol WholeTextCleaningPass: CleaningPass where Scope == WholeTextScope {}

extension CleaningPass {
    public static var removes: RemovalGrant { .conversion }

    /// The pass's identifier, reachable from a value as well as from the type.
    public var id: PassID { Self.id }

    /// The pass's grant, reachable from a value as well as from the type.
    public var removes: RemovalGrant { Self.removes }

    /// The pass's laws, reachable from a value as well as from the type.
    public var laws: Set<PassLaw> { Self.laws }
}

/// An ordered list of passes, run one after another over the same draft.
public struct CleaningPipeline: Sendable {
    public let passes: [any CleaningPass]

    public init(passes: [any CleaningPass]) {
        self.passes = passes
    }

    /// A pipeline for one piece, which the compiler keeps free of any whole-text pass.
    public init(piece passes: [any PieceCleaningPass]) {
        self.passes = passes
    }

    /// A pipeline for the joined message, which the compiler keeps free of any piece pass.
    public init(wholeText passes: [any WholeTextCleaningPass]) {
        self.passes = passes
    }

    /// The identifiers of the passes, in the order they run.
    public var ids: [PassID] { passes.map(\.id) }

    /// What each pass may remove, keyed by the identifier its removals are recorded under.
    public var grants: [PassID: RemovalGrant] {
        Dictionary(passes.map { ($0.id, $0.removes) }, uniquingKeysWith: { first, _ in first })
    }

    public func run(_ draft: Draft) -> Draft {
        passes.reduce(draft) { $1.apply($0) }
    }

    /// The same pipeline with the named passes left out, keeping the order of the rest.
    public func without(_ excluded: [PassID]) -> CleaningPipeline {
        CleaningPipeline(passes: passes.filter { !excluded.contains($0.id) })
    }
}
