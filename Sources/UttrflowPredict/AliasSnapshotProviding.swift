// Shares one metadata owner between the index and deterministic clock controls.

protocol AliasSnapshotProviding: Sendable {
    func snapshot() async -> AliasExpansionSnapshot
    func settle() async
    func forgetEverything() async
}

extension AliasExpansionCache: AliasSnapshotProviding {}
