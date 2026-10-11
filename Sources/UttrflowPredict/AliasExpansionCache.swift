// Holds parsed alias words briefly, without putting shell configuration in a learned store.

/// A reader that can supply plain command bodies as well as alias names.
protocol AliasExpansionReading: Sendable {
    func aliasExpansions() async -> [String: [String]]?
}

/// One answer and its identity, so a consumer can discard verdicts made under an earlier answer.
struct AliasExpansionSnapshot: Sendable {
    let words: [String: [String]]?
    let revision: UInt64
}

/// One bounded machine-wide answer, refreshed off the typing path and purged even when nobody asks again.
actor AliasExpansionCache<C: Clock> where C.Duration == Duration {
    static var aliasLimit: Int { 200 }
    static var byteLimit: Int { 65_536 }
    private let reader: (any AliasExpansionReading)?
    private let clock: C
    private var words: [String: [String]]?
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
                let answer = await reader.aliasExpansions()
                guard generation == self.generation else { return }
                self.record(answer)
            }
        }
        return AliasExpansionSnapshot(words: words, revision: revision)
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

    private func record(_ answer: [String: [String]]?) {
        refresh = nil
        let now = clock.now
        retry = now.advanced(by: .seconds(60))
        guard let answer else { return }
        words = Self.bounded(answer)
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
