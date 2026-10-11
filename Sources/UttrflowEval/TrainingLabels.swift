// Training labels from the passage that was read, with reader deviations kept out of every fit.
import UttrflowCore

/// What one aligned span says about the recogniser; a closed class built from one `WordErrorRate` operation.
enum SpanLabel: Sendable, Hashable {
    case correct(String)
    case substituted(truth: String, heard: String)
    case dropped(String)
    case inserted(String)

    init(_ operation: WordErrorRate.Operation) {
        switch operation {
        case .match(let word): self = .correct(word)
        case .substitution(let reference, let hypothesis):
            self = .substituted(truth: reference, heard: hypothesis)
        case .deletion(let word): self = .dropped(word)
        case .insertion(let word): self = .inserted(word)
        }
    }

    var isError: Bool {
        switch self {
        case .correct: false
        case .substituted, .dropped, .inserted: true
        }
    }
}

/// One labelled span: its label, the passage word it sits at (an insertion sits before it), and its trust.
struct LabelledSpan: Sendable, Equatable {
    let label: SpanLabel
    let passageIndex: Int
    let reliability: Reliability

    /// Whether the passage is trusted as the truth at this span.
    enum Reliability: Sendable, Equatable {
        case reliable
        /// Two independent decodings agree here and both disagree with the passage: the reader deviated.
        case unreliable
    }
}

/// The labels one decoding of a passage gives a fit; see "Training labels" in Docs/dictation-quality.md.
struct TrainingLabels: Sendable, Equatable {
    let spans: [LabelledSpan]

    /// The spans a fit may read.
    var fittable: [LabelledSpan] { spans.filter { $0.reliability == .reliable } }

    /// How many spans were kept out of the fit as reader deviations; reported with every fit.
    var excludedSpanCount: Int { spans.count { $0.reliability == .unreliable } }

    /// Labels `decoding` against `passage`; an error is unreliable when an independent decoding makes it too.
    static func label(
        passage: [String], decoding: [String], corroborating: [[String]]
    ) -> TrainingLabels {
        let seen = Set(corroborating.flatMap { keyed(passage: passage, decoding: $0) })
        let spans = keyed(passage: passage, decoding: decoding).map { key in
            LabelledSpan(
                label: key.label, passageIndex: key.passageIndex,
                reliability: key.label.isError && seen.contains(key) ? .unreliable : .reliable)
        }
        return TrainingLabels(spans: spans)
    }

    /// Labels text under `normaliser`, the same words the scorer compares.
    static func label(
        passage: String, decoding: String, corroborating: [String], normaliser: TextNormaliser = .standard
    ) -> TrainingLabels {
        label(
            passage: normaliser.words(passage), decoding: normaliser.words(decoding),
            corroborating: corroborating.map(normaliser.words))
    }

    /// The labels of many passages as one, so a fit reports one excluded count.
    static func combined(_ labels: [TrainingLabels]) -> TrainingLabels {
        TrainingLabels(spans: labels.flatMap(\.spans))
    }

    /// Where a span sits and what it is; two decodings make the same error when their keys are equal.
    private struct SpanKey: Hashable {
        let passageIndex: Int
        let label: SpanLabel
        /// Which insertion this is within one gap, so a doubled insertion is two keys.
        let ordinal: Int
    }

    private static func keyed(passage: [String], decoding: [String]) -> [SpanKey] {
        var keys: [SpanKey] = []
        var passageIndex = 0
        var insertionsInGap = 0
        for operation in WordErrorRate.measure(reference: passage, hypothesis: decoding).alignment {
            let label = SpanLabel(operation)
            if case .inserted = label {
                keys.append(SpanKey(passageIndex: passageIndex, label: label, ordinal: insertionsInGap))
                insertionsInGap += 1
                continue
            }
            keys.append(SpanKey(passageIndex: passageIndex, label: label, ordinal: 0))
            passageIndex += 1
            insertionsInGap = 0
        }
        return keys
    }
}
