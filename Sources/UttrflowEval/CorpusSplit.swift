// Which clean-up cases a change may be tuned against, and which are kept back to judge it.

/// The half of the corpus a case belongs to; a held-out case is never shown to a prompt, rule or lexicon. See `Docs/bakeoff-method.md`.
public enum CorpusSplit: String, Sendable, Equatable, CaseIterable, Codable {
    /// Cases a prompt, rule or lexicon author may read and tune against.
    case development
    /// Cases kept back, so a score on them says whether a change generalises.
    case heldout

    /// One case in this many is held out.
    public static let heldOutEvery: UInt64 = 5

    /// Decided by the case id alone, so adding or reordering cases never moves an existing one across.
    public init(caseID: String) {
        self = Self.digest(caseID) % Self.heldOutEvery == 0 ? .heldout : .development
    }

    /// FNV-1a over the id's bytes, because `Hasher` is seeded per process and would move cases between runs.
    static func digest(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }

    /// The prompt fragments that copy a held-out case, as `id: fragment`, so a test can name the leak.
    public static func leaks(of cases: [EvaluationCase], into fragments: [String]) -> [String] {
        let fragments = fragments.map { $0.lowercased() }
        return cases.filter { $0.split == .heldout }.flatMap { testCase in
            [testCase.spoken, testCase.expected].map { $0.lowercased() }.filter { $0.count >= minimumCopy }
                .flatMap { text in fragments.filter { $0.contains(text) }.map { "\(testCase.id): \($0)" } }
        }
    }

    /// Shorter texts, such as a single name, appear in prompts by coincidence rather than by copying.
    static let minimumCopy = 12
}

extension EvaluationCase {
    /// Whether a change may be tuned against this case.
    public var split: CorpusSplit { CorpusSplit(caseID: id) }
}
