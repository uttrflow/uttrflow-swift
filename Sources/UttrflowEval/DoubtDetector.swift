// A doubt flag chosen from measured precision and recall, and the ceiling candidate generation sets on any flag.

/// Chooses where a doubt feature flags from the data, scores the flag on voices held out of the choice, and measures how often the right word is offered at all.
package enum DoubtDetector {
    /// One recognised word as the detector sees it.
    package struct Judged: Sendable, Equatable {
        /// The feature's certainty, whether the word is wrong, and the voice or speaker that read it.
        package let scored: WordDoubtEvaluation.Scored
        /// Whether today's gate heard the word surely, so a wrong one is a confident error no fixed flag reaches.
        package let heardSurely: Bool
        /// Whether candidate generation offers the word that was read, so a flag on it could be put right.
        package let offered: Bool

        package init(scored: WordDoubtEvaluation.Scored, heardSurely: Bool, offered: Bool) {
            self.scored = scored
            self.heardSurely = heardSurely
            self.offered = offered
        }
    }

    /// A detector's measured result at one required precision.
    package struct Result: Sendable, Equatable {
        /// The flag chosen on every word: flag at or below this certainty; nil when no flag reaches the precision.
        package let threshold: Double?
        /// Wrong words flagged, over all wrong words, each flagged by a threshold chosen without its own voice.
        package let recall: GroupCalibration.Share
        /// Flags that are wrong words, over all flags, on the same held-out flags.
        package let precision: GroupCalibration.Share
        /// Wrong words today's gate heard surely that are flagged, over all such words.
        package let confidentRecall: GroupCalibration.Share
        /// Wrong words whose read word candidate generation offers, over all wrong words: the most any scorer can fix.
        package let ceiling: GroupCalibration.Share
        /// Wrong words both flagged and offered, over all wrong words: the most this flag and these candidates can fix.
        package let reachable: GroupCalibration.Share
    }

    /// Chooses the flag on all words and scores it on each voice with a flag chosen on the other voices.
    package static func evaluate(_ words: [Judged], atPrecision precision: Double) -> Result {
        let flags = heldOutFlags(words.map(\.scored), atPrecision: precision)
        let wrong = words.indices.filter { words[$0].scored.isWrong }
        let confident = wrong.filter { words[$0].heardSurely }
        let flagged = words.indices.filter { flags[$0] }
        return Result(
            threshold: WordDoubtEvaluation.threshold(words.map(\.scored), atPrecision: precision),
            recall: .init(count: wrong.count { flags[$0] }, total: wrong.count),
            precision: .init(count: flagged.count { words[$0].scored.isWrong }, total: flagged.count),
            confidentRecall: .init(count: confident.count { flags[$0] }, total: confident.count),
            ceiling: .init(count: wrong.count { words[$0].offered }, total: wrong.count),
            reachable: .init(count: wrong.count { flags[$0] && words[$0].offered }, total: wrong.count))
    }

    /// Whether each word is flagged by the threshold chosen on every other cluster, so no voice grades its own flag.
    package static func heldOutFlags(
        _ words: [WordDoubtEvaluation.Scored], atPrecision precision: Double
    ) -> [Bool] {
        var thresholds: [String: Double?] = [:]
        for cluster in Set(words.map(\.cluster)) {
            thresholds[cluster] = WordDoubtEvaluation.threshold(
                words.filter { $0.cluster != cluster }, atPrecision: precision)
        }
        return words.map { word in
            guard let threshold = thresholds[word.cluster] ?? nil else { return false }
            return word.certainty <= threshold
        }
    }

    /// Each certainty less its sentence's median, so a word is doubted for standing out from the words around it.
    package static func relativeToSentence(_ certainties: [Double]) -> [Double] {
        guard !certainties.isEmpty else { return [] }
        let sorted = certainties.sorted()
        let middle = sorted.count / 2
        let median =
            sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return certainties.map { $0 - median }
    }
}
