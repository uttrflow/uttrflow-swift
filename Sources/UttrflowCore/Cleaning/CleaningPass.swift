/// What a pass may take out of the text, which the meaning guard holds each of its removals to. See `Docs/cleanup.md`.
public enum RemovalGrant: Sendable, Equatable {
    /// A sound that was never a word, so never a numeral or a word written in capitals.
    case sound
    /// The first saying of words said again straight after it.
    case repetition
    /// The half of a correction the speaker took back, with the trigger that announced it.
    case retraction
    /// Words the pass wrote as the mark, numeral or contraction beside them.
    case conversion
}

/// One cleaning that needs no model: a pure function over a draft that records every word it touches.
public protocol CleaningPass: Sendable {
    static var id: PassID { get }
    /// What the pass may remove; a pass that does not say only turns words into what it writes.
    static var removes: RemovalGrant { get }
    func apply(_ draft: Draft) -> Draft
}

extension CleaningPass {
    public static var removes: RemovalGrant { .conversion }

    /// The pass's identifier, reachable from a value as well as from the type.
    public var id: PassID { Self.id }

    /// The pass's grant, reachable from a value as well as from the type.
    public var removes: RemovalGrant { Self.removes }
}

/// An ordered list of passes, run one after another over the same draft.
public struct CleaningPipeline: Sendable {
    public let passes: [any CleaningPass]

    public init(passes: [any CleaningPass]) {
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
