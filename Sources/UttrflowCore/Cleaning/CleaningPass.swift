/// One cleaning that needs no model: a pure function over a draft that records every word it touches.
public protocol CleaningPass: Sendable {
    static var id: PassID { get }
    func apply(_ draft: Draft) -> Draft
}

extension CleaningPass {
    /// The pass's identifier, reachable from a value as well as from the type.
    public var id: PassID { Self.id }
}

/// An ordered list of passes, run one after another over the same draft.
public struct CleaningPipeline: Sendable {
    public let passes: [any CleaningPass]

    public init(passes: [any CleaningPass]) {
        self.passes = passes
    }

    /// The identifiers of the passes, in the order they run.
    public var ids: [PassID] { passes.map(\.id) }

    public func run(_ draft: Draft) -> Draft {
        passes.reduce(draft) { $1.apply($0) }
    }

    /// The same pipeline with the named passes left out, keeping the order of the rest.
    public func without(_ excluded: [PassID]) -> CleaningPipeline {
        CleaningPipeline(passes: passes.filter { !excluded.contains($0.id) })
    }
}
