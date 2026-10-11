/// The machine facts that can attest a captured verification operation.
struct EnvironmentVerification: Sendable {
    enum Metadata: Sendable { case disabled, enabled }
    let index: EnvironmentIndex
    let metadata: Metadata

    /// Everything the machine vouches for among these kinds here, absent when none has answered yet or the field is not a directory.
    func known(
        of kinds: [EnvironmentKind], in surface: Surface, now: ContinuousClock.Instant
    ) async -> Set<String>? {
        await knownAndComplete(of: kinds, in: surface, now: now)?.known
    }

    /// Git names are case-sensitive even on a case-insensitive filesystem.
    func attests(
        _ lookup: Verification.Lookup, in surface: Surface, now: ContinuousClock.Instant
    ) async -> Bool {
        for kind in lookup.kinds {
            guard let known = await known(of: [kind], in: surface, now: now) else { continue }
            if Verification.attests(
                lookup.word, known, caseSensitive: requiresCaseSensitiveMatch(kind))
            {
                return true
            }
        }
        return false
    }

    func requiresCaseSensitiveMatch(_ kind: EnvironmentKind) -> Bool {
        switch kind {
        case .branch, .gitAlias: true
        case .subcommand(of: "git"): true
        case .entries, .directories, .executable, .alias, .subcommand: false
        }
    }

    /// The same union, plus whether every kind asked has actually answered, so a still-refreshing kind is never read as a "no".
    func knownAndComplete(
        of kinds: [EnvironmentKind], in surface: Surface, now: ContinuousClock.Instant
    ) async -> (known: Set<String>, complete: Bool)? {
        guard let directory = EnvironmentSource.workingDirectory(of: surface) else { return nil }
        var known: Set<String>?
        var complete = true
        for kind in kinds {
            guard let values = await index.values(of: kind, in: directory, now: now) else {
                complete = false
                continue
            }
            known = (known ?? []).union(values)
        }
        guard let known else { return nil }
        return (known, complete)
    }

    func aliases(in surface: Surface) async -> AliasExpansionSnapshot {
        guard case .enabled = metadata, EnvironmentSource.workingDirectory(of: surface) != nil else {
            return AliasExpansionSnapshot(words: [:], revision: 0)
        }
        return await index.aliasSnapshot()
    }

    func currentRevision(for operation: VerificationOperation) async -> UInt64? {
        guard case .enabled = metadata, EnvironmentSource.workingDirectory(of: operation.surface) != nil
        else { return nil }
        return await index.aliasSnapshot().revision
    }

    func forgetAliases() async {
        guard case .enabled = metadata else { return }
        await index.forgetAliases()
    }

    func attestation(
        for token: CompletionToken, in operation: VerificationOperation
    ) -> Verification.Attestation? {
        Verification.attestation(for: token, aliases: operation.aliases)
    }

    func choices(for typed: String, in operation: VerificationOperation) -> Verification.Attestation? {
        guard EnvironmentSource.workingDirectory(of: operation.surface) != nil else { return nil }
        let token = CompletionToken(typed) ?? CompletionToken(leading: typed, token: "")
        return Verification.choices(for: token, aliases: operation.aliases)
    }

    func mayPersist(_ token: CompletionToken, in operation: VerificationOperation) -> Bool {
        !LineShape.of(token, metadata: operation.aliases).isAliasDependent
            && Verification.isClosedVocabulary(for: token, aliases: operation.aliases)
    }

    func isComplete(_ operation: VerificationOperation) -> Bool { operation.aliases.words != nil }
}
