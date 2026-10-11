// Holds parsed alias words briefly, without putting shell configuration in a learned store.

/// A reader that can supply plain command bodies as well as alias names.
protocol AliasExpansionReading: Sendable {
    func aliasExpansions() async -> [String: [String]]?
    func aliasMetadata() async -> AliasExpansionSnapshot?
}

extension AliasExpansionReading {
    func aliasMetadata() async -> AliasExpansionSnapshot? {
        guard let words = await aliasExpansions() else { return nil }
        return AliasExpansionSnapshot.metadata(words, declared: Set(words.keys))
    }
}

/// One answer and its identity, so a consumer can discard verdicts made under an earlier answer.
struct AliasExpansionSnapshot: Sendable {
    let words: [String: [String]]?
    let revision: UInt64
    var blockedCommands: Set<Int> = []
    var uncertainAliases: Set<Int> = []

    static func metadata(_ words: [String: [String]], declared: Set<String>) -> Self {
        let bounded = AliasExpansionCache<ContinuousClock>.bounded(words)
        let names = bounded.keys.sorted()
        return Self(
            words: bounded, revision: 0,
            blockedCommands: CommandGrammar.shadowed(declared.filter { bounded[$0] == nil }),
            uncertainAliases: Set(
                names.indices.filter {
                    uncertain(names[$0], words: words, retained: bounded, declared: declared)
                }))
    }

    func remappedUncertainty(to retained: [String: [String]]) -> Set<Int> {
        let original = (words ?? [:]).keys.sorted()
        let names = retained.keys.sorted()
        return Set(
            names.indices.filter {
                guard let previous = original.firstIndex(of: names[$0]) else { return false }
                return uncertainAliases.contains(previous)
            })
    }

    private static func uncertain(
        _ name: String, words: [String: [String]], retained: [String: [String]], declared: Set<String>
    ) -> Bool {
        var command = [name]
        var seen: Set<String> = []
        while let first = command.first {
            if declared.contains(first), retained[first] == nil { return true }
            if let body = words[first] {
                guard seen.insert(first).inserted else { return true }
                command = body + command.dropFirst()
                if body.first != first { continue }
                if !CommandGrammar.shadowableCommands.contains(first) { return true }
            }
            guard let resolved = command.first, CommandGrammar.wrappers.contains(resolved) else {
                return false
            }
            CommandGrammar.removeWrapper(from: &command)
        }
        return false
    }
}

/// One bounded machine-wide answer, refreshed off the typing path and purged even when nobody asks again.
actor AliasExpansionCache<C: Clock> where C.Duration == Duration {
    static var aliasLimit: Int { 200 }
    static var byteLimit: Int { 65_536 }
    private let reader: (any AliasExpansionReading)?
    private let clock: C
    private var words: [String: [String]]?
    private var blockedCommands: Set<Int> = []
    private var uncertainAliases: Set<Int> = []
    private var expires: C.Instant?
    private var retry: C.Instant?
    private var refresh: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0

    init(reader: (any AliasExpansionReading)?, clock: C) {
        self.reader = reader
        self.clock = clock
    }

    func snapshot() -> AliasExpansionSnapshot {
        guard let reader else { return AliasExpansionSnapshot(words: [:], revision: revision) }
        let now = clock.now
        if let expires, now >= expires.advanced(by: .seconds(2)) { purge() }
        if refresh == nil, retry.map({ now >= $0 }) ?? true {
            let generation = generation
            refresh = Task {
                let answer = await reader.aliasMetadata()
                guard generation == self.generation else { return }
                self.record(answer)
            }
        }
        return AliasExpansionSnapshot(
            words: words, revision: revision, blockedCommands: blockedCommands,
            uncertainAliases: uncertainAliases)
    }

    /// The active read, so a test can wait for a cancelled reader that still completes.
    var pendingRead: Task<Void, Never>? { refresh }

    var pendingExpiry: Task<Void, Never>? { expiry }
    var retainedAliasCount: Int { words?.count ?? 0 }

    func settle() async {
        while let refresh { await refresh.value }
    }

    func forgetEverything() {
        generation &+= 1
        refresh?.cancel()
        refresh = nil
        retry = nil
        purge()
    }

    private func record(_ answer: AliasExpansionSnapshot?) {
        refresh = nil
        let now = clock.now
        retry = now.advanced(by: .seconds(60))
        guard let answer, let incoming = answer.words else { return }
        let admitted = AliasExpansionSnapshot.metadata(incoming, declared: Set(incoming.keys))
        words = admitted.words
        blockedCommands = admitted.blockedCommands.union(
            answer.blockedCommands.intersection(CommandGrammar.shadowableCommands.indices))
        uncertainAliases = admitted.uncertainAliases.union(answer.remappedUncertainty(to: words ?? [:]))
        expires = retry
        revision &+= 1
        expiry?.cancel()
        let revision = revision
        let deadline = now.advanced(by: .seconds(62))
        expiry = Task {
            do { try await clock.sleep(until: deadline, tolerance: nil) } catch { return }
            guard revision == self.revision else { return }
            self.purge()
        }
    }

    private func purge() {
        expiry?.cancel()
        expiry = nil
        expires = nil
        if words != nil { revision &+= 1 }
        words = nil
        blockedCommands = []
        uncertainAliases = []
    }

    /// Counts UTF-8 content and its word separators; an entry that will not fit is omitted whole.
    static func bounded(_ answer: [String: [String]]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var bytes = 0
        for name in answer.keys.sorted() {
            guard result.count < aliasLimit, let body = answer[name], !body.isEmpty else { continue }
            let size = name.utf8.count + 1 + body.reduce(0) { $0 + $1.utf8.count + 1 }
            guard size <= byteLimit - bytes else { continue }
            result[name] = body
            bytes += size
        }
        return result
    }
}
