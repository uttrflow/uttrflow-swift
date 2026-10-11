// The one function that turns a doubtful span and one candidate reading into the vector every scorer weighs.

import Foundation
package import UttrflowCore

/// How often the user has written each word, which is all a span feature reads of the persona.
package struct SpanPersonaSnapshot: Sendable, Equatable, Codable {
    /// Times each lower-cased word was written.
    package let counts: [String: Int]

    package init(counts: [String: Int]) {
        self.counts = counts
    }

    /// How often the user wrote every word of `text`, summed.
    func frequency(of text: String) -> Int {
        WordShape.words(text).reduce(0) { $0 + (counts[$1] ?? 0) }
    }
}

/// The features of a candidate reading of a doubtful span, computed here for the fit tool and the app alike.
package enum SpanFeatures {
    /// The version of this list and of every rule below; it moves with the golden file, and a fit refuses another.
    package static let specVersion = 1

    /// One feature: its identifier, and the value it takes when its evidence is missing.
    package struct Feature: Sendable, Equatable {
        package let identifier: String
        package let ifMissing: Double
    }

    /// Two-way chance, the entropy of a token the decoder could not tell from one other.
    private static let missingEntropy = -log(2.0)

    /// The features in vector order, each with its rule for a missing value.
    package static let features: [Feature] = [
        // Mean token probability of the span; missing with no decoder evidence.
        Feature(identifier: "decoderMeanProbability", ifMissing: 0.5),
        // Negated mean token entropy of the span; missing with no decoder evidence.
        Feature(identifier: "decoderNegatedEntropy", ifMissing: missingEntropy),
        // First token's probability less its strongest runner-up's; missing with no decoder evidence.
        Feature(identifier: "decoderFirstMargin", ifMissing: 0),
        // Position of the first source that offered the reading; never missing.
        Feature(identifier: "sourceRank", ifMissing: 0),
        // Number of sources that offered the reading; never missing.
        Feature(identifier: "sourceAgreement", ifMissing: 1),
        // Characters of the reading over characters of the span as heard; missing when nothing was heard.
        Feature(identifier: "lengthRatio", ifMissing: 1),
        // Phonetic distance from the span as heard; missing when the lexicon lists neither word.
        Feature(identifier: "phoneticDistance", ifMissing: 4),
        // Context log10 probability of the reading less the span's; missing with no language model.
        Feature(identifier: "contextLeadLog10", ifMissing: 0),
        // Log of one plus the persona's count for the reading less that for the span; missing with no persona.
        Feature(identifier: "personaLogLead", ifMissing: 0),
    ]

    /// The identifiers in vector order.
    package static var identifiers: [String] { features.map(\.identifier) }

    /// What a feature needs beyond the reading and its set, each absent when unknown.
    package struct Evidence: Sendable {
        /// The decoder's token evidence for the span as heard.
        package let tokens: [TokenEvidence]
        package let context: InterpolatedLanguageModel?
        package let persona: SpanPersonaSnapshot?

        package init(
            tokens: [TokenEvidence] = [], context: InterpolatedLanguageModel? = nil,
            persona: SpanPersonaSnapshot? = nil
        ) {
            self.tokens = tokens
            self.context = context
            self.persona = persona
        }
    }

    /// The vector for one hypothesis of `set`, as long as `features` and finite in every place.
    package static func vector(
        of hypothesis: Hypothesis, in set: HypothesisSet, evidence: Evidence
    ) -> [Double] {
        let spelling = hypothesis.reading.spelling
        let heardWords = ContextSpanScorer.words([set.heard])
        let readingWords = ContextSpanScorer.words([spelling])
        let certainty = DecoderCertainty(tokens: evidence.tokens)
        let first = evidence.tokens.first
        let values: [Double?] = [
            certainty?.meanProbability,
            certainty?.negatedEntropy,
            first.map { exp($0.logProb) - ($0.alternatives.max().map(exp) ?? 0) },
            Double(hypothesis.features.firstSource),
            Double(hypothesis.features.agreement),
            set.heard.isEmpty ? nil : Double(spelling.count) / Double(set.heard.count),
            phoneticDistance(heardWords, readingWords),
            evidence.context.map { model in
                let before = words(set.before)
                let after = words(set.after)
                return Double(
                    model.log10Probability(ofSpan: readingWords, between: before, and: after)
                        - model.log10Probability(ofSpan: heardWords, between: before, and: after))
            },
            evidence.persona.map {
                log(1 + Double($0.frequency(of: spelling))) - log(1 + Double($0.frequency(of: set.heard)))
            },
        ]
        return zip(values, features).map { value, feature in
            guard let value, value.isFinite else { return feature.ifMissing }
            return value
        }
    }

    private static func words(_ texts: [String]) -> [String] { ContextSpanScorer.words(texts) }

    private static func phoneticDistance(_ heard: [String], _ reading: [String]) -> Double? {
        guard heard.count == 1, reading.count == 1 else { return nil }
        return PhonemeLexicon.shared.distance(heard[0], reading[0])
    }
}
