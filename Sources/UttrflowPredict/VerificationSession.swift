/// The remembered verdicts whose operation identity still belongs to one verifier.
struct VerificationSession {
    private var cache = VerdictCache()
    private(set) var generation: UInt64 = 0
    private var aliasRevision: UInt64?
    var count: Int { cache.count }

    mutating func begin(
        in surface: Surface, aliases: AliasExpansionSnapshot, generation: UInt64
    )
        -> VerificationOperation
    {
        if generation == self.generation, EnvironmentSource.workingDirectory(of: surface) != nil,
            aliasRevision.map({ aliases.revision >= $0 }) ?? true
        {
            if let aliasRevision, aliasRevision != aliases.revision { cache.forgetEverything() }
            aliasRevision = aliases.revision
        }
        return VerificationOperation(surface: surface, generation: generation, aliases: aliases)
    }

    func isCurrent(_ operation: VerificationOperation) -> Bool {
        operation.generation == generation
            && (EnvironmentSource.workingDirectory(of: operation.surface) == nil
                || operation.aliases.revision == aliasRevision)
    }

    func held<Value: Sendable>(
        _ value: Value, in operation: VerificationOperation, revision: UInt64?
    ) -> Value? {
        guard isCurrent(operation), revision.map({ $0 == operation.aliases.revision }) ?? true else {
            return nil
        }
        return value
    }

    mutating func publish(
        _ verdict: Verdict, for key: VerdictCache.Key?, in operation: VerificationOperation, revision: UInt64?
    ) -> Verdict? {
        guard let verdict = held(verdict, in: operation, revision: revision) else { return nil }
        if let key { cache.remember(verdict, for: key) }
        return verdict
    }

    mutating func verdict(for key: VerdictCache.Key) -> Verdict? { cache.verdict(for: key) }
    mutating func remember(_ verdict: Verdict, for key: VerdictCache.Key) {
        cache.remember(verdict, for: key)
    }
    mutating func forgetEverything() {
        generation &+= 1
        aliasRevision = nil
        cache.forgetEverything()
    }
}
