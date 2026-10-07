public import UttrflowCore

// The guard's checks as one ordered list, so a new check is a row and the order is data.
/// What every guard check reads: the draft, the rewrite and the policy, with the costly derivations made once and only when a check asks.
final class GuardInput {
    let draft: Draft
    /// The text the rewrite is measured against; the draft's own text unless a caller judged a bare string.
    let original: String
    let rewritten: String
    let doubtful: [DoubtfulSpan]
    let echoed: String
    let layout: LayoutPolicy
    let grammar: GrammarPolicy
    let grants: [PassID: RemovalGrant]
    let excusingPreamble: Bool

    init(
        draft: Draft, rewritten: String, doubtful: [DoubtfulSpan], echoed: String, layout: LayoutPolicy,
        grammar: GrammarPolicy, grants: [PassID: RemovalGrant]
    ) {
        self.draft = draft
        original = draft.text
        self.rewritten = MeaningPreservationGuard.respellingClockTimes(rewritten, as: draft.text)
        self.doubtful = doubtful
        self.echoed = echoed
        self.layout = layout
        self.grammar = grammar
        self.grants = grants
        excusingPreamble = MeaningPreservationGuard.rewriteStartsWithOfferedReading(
            draft: draft, rewritten: self.rewritten, offering: doubtful)
    }

    /// An input for the text checks alone, which read only the two strings.
    init(text: String, rewritten: String, excusingPreamble: Bool) {
        draft = Draft(text: text)
        original = text
        self.rewritten = rewritten
        doubtful = []
        echoed = ""
        layout = [.paragraphs, .lists]
        grammar = .repair
        grants = [:]
        self.excusingPreamble = excusingPreamble
    }

    lazy var restored = MeaningPreservationGuard.restored(
        RemovalAudit.unauthorised(in: draft, grants: grants))
    /// What a rewrite may write back as the speaker's: the words a pass overreached on, with the rest of the run it took them in.
    lazy var restorable = MeaningPreservationGuard.grammarTokens(
        RemovalAudit.restorable(in: draft, grants: grants).joined(separator: " ")
    ).filter(\.isPlain)
    lazy var alignment = RewriteAlignment(kept: original, rewritten: rewritten)
    lazy var readings = MeaningPreservationGuard.readingVerdict(doubtful, in: alignment)
}

/// One named check of a rewrite.
struct GuardCheck: Sendable {
    let name: String
    /// Whether a rewrite opening with the reading offered for the first doubtful run is excused from this check.
    let excusedByOfferedReading: Bool
    let judge: @Sendable (GuardInput) -> GuardVerdict

    init(
        _ name: String, excusedByOfferedReading: Bool = false,
        judge: @escaping @Sendable (GuardInput) -> GuardVerdict
    ) {
        self.name = name
        self.excusedByOfferedReading = excusedByOfferedReading
        self.judge = judge
    }

    /// This check's verdict, skipped where an offered reading excuses it.
    func verdict(on input: GuardInput) -> GuardVerdict {
        excusedByOfferedReading && input.excusingPreamble ? .accepted : judge(input)
    }
}

extension MeaningPreservationGuard {
    /// The checks on the text's overall shape, in the order the first refusal is taken.
    static let textChecks: [GuardCheck] = [
        GuardCheck("empty") { emptyVerdict(original: $0.original, rewritten: $0.rewritten) },
        GuardCheck("preamble", excusedByOfferedReading: true) {
            preambleVerdict(original: $0.original, rewritten: $0.rewritten)
        },
        GuardCheck("length") { lengthVerdict(original: $0.original, rewritten: $0.rewritten) },
        GuardCheck("numbers") { numberVerdict(original: $0.original, rewritten: $0.rewritten) },
        GuardCheck("symbols") { symbolVerdict(original: $0.original, rewritten: $0.rewritten) },
    ]

    /// Every check of a rewrite, in the order the first refusal is taken.
    static let checks: [GuardCheck] =
        textChecks + [
            GuardCheck("spokenPunctuation") {
                spokenPunctuationVerdict(draft: $0.draft, rewritten: $0.rewritten)
            },
            GuardCheck("removal") {
                removalVerdict($0.restored, kept: $0.original, rewritten: $0.rewritten, echoed: $0.echoed)
            },
            GuardCheck("readings") { $0.readings.verdict },
            GuardCheck("confidentHomophone") {
                confidentHomophoneVerdict($0.draft, aligned: $0.alignment, excusing: $0.readings.excused)
            },
            GuardCheck("layout") {
                layoutVerdict(kept: $0.original, rewritten: $0.rewritten, layout: $0.layout)
            },
            GuardCheck("grammar") {
                grammarVerdict(
                    $0.alignment, excusing: $0.readings.excused, echoed: $0.echoed, allowing: $0.doubtful,
                    restoring: $0.restorable, policy: $0.grammar,
                    styled: MeaningPreservationGuard.styledCapitals(in: $0.draft))
            },
        ]

    /// The first refusal among the checks, in order.
    static func verdict(of checks: [GuardCheck], on input: GuardInput) -> GuardVerdict {
        for check in checks {
            let verdict = check.verdict(on: input)
            if !verdict.isAccepted { return verdict }
        }
        return .accepted
    }

    /// Every check that refuses the rewrite, by name, for diagnosis rather than the first refusal alone.
    public func failingChecks(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan] = [], echoed: String = "",
        layout: LayoutPolicy = [.paragraphs, .lists],
        grammar: GrammarPolicy = .repair,
        grants: [PassID: RemovalGrant] = CleaningPipeline.standard.grants
    ) -> [(name: String, verdict: GuardVerdict)] {
        let input = GuardInput(
            draft: draft, rewritten: rewritten, doubtful: doubtful, echoed: echoed, layout: layout,
            grammar: grammar, grants: grants)
        return Self.checks.compactMap { check in
            let verdict = check.verdict(on: input)
            return verdict.isAccepted ? nil : (check.name, verdict)
        }
    }
}
