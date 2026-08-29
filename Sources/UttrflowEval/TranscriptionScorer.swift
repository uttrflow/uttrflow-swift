public import UttrflowCore

/// Scores one transcript against the passage that was read.
///
/// The counterpart of ``Scorer``, and deliberately a different measurement. A rewrite
/// can say the same thing in other words and still be right, so clean-up is scored on
/// word overlap. A transcript that says other words is wrong however elegantly it puts
/// them, so a recogniser is scored on the edits it takes to repair — see
/// ``WordErrorRate``. What the two do share is the rule that some words must survive
/// whatever happens to the rest, and they share the implementation of it.
public enum TranscriptionScorer {
    /// - Parameters:
    ///   - transcript: What the engine said.
    ///   - passage: What was read aloud.
    ///   - normaliser: The rules both sides are put through before being compared. Kept
    ///     on the score, because the rate means nothing without them.
    ///   - stages: Timings gathered while producing the transcript.
    ///   - failure: Set when the engine produced nothing.
    ///   - cohortID: Who read it and where. Carried on the score rather than looked up
    ///     later, because a results file has to stay readable on its own: the recording
    ///     it came from may have been re-attributed, or deleted, by the time anybody
    ///     reads the numbers.
    /// - Returns: The rate, the terms lost and the timings, under the rules applied.
    public static func score(
        _ transcript: String,
        against passage: TranscriptionCase,
        normaliser: TextNormaliser = .standard,
        stages: [StageMeasurement] = [],
        failure: TranscriptionFailure? = nil,
        cohortID: String? = nil
    ) -> PassageScore {
        // An unreadable recording is the harness's fault. Scoring it would charge the
        // engine for a file it was never given, so the passage is reported as a failure
        // with no rate at all rather than as a perfect score for nobody or a total loss
        // for the wrong party.
        if let failure, !failure.isScorable {
            return PassageScore(
                caseID: passage.id, language: passage.language, stressor: passage.stressor,
                wordErrorRate: nil, answeredIn: .latin, scoredAgainst: .latin,
                stages: stages, failure: failure, normalisation: normaliser.rules,
                stresses: passage.stresses, cohortID: cohortID
            )
        }

        let answeredIn = Script.of(transcript)
        let comparison = comparable(transcript, answeredIn: answeredIn, against: passage)
        let referenceWords = normaliser.words(comparison.reference)
        let hypothesisWords = normaliser.words(comparison.hypothesis)

        return PassageScore(
            caseID: passage.id,
            language: passage.language,
            stressor: passage.stressor,
            wordErrorRate: .measure(reference: referenceWords, hypothesis: hypothesisWords),
            answeredIn: answeredIn,
            scoredAgainst: comparison.script,
            lost: lostTerms(from: passage, in: hypothesisWords, normaliser: normaliser),
            transcript: transcript,
            stages: stages,
            failure: failure,
            normalisation: normaliser.rules,
            stresses: passage.stresses,
            cohortID: cohortID
        )
    }

    /// Picks the form of the passage to compare against, transliterating only as a last
    /// resort.
    ///
    /// Whisper answers Hindi in Devanagari, so the corpus holds both forms of every
    /// Hindi and Hinglish passage and each script is scored against its own. Comparing a
    /// Devanagari transcript with a romanised reference would measure the absence of a
    /// transliterator rather than anything the recogniser did, and would report roughly
    /// 100% error on a perfect transcript.
    ///
    /// When there is no matching form — an English passage that came back in Devanagari,
    /// which would be a real and interesting failure — the transcript is romanised by ICU
    /// and the score is marked as an upper bound rather than being thrown away.
    private static func comparable(
        _ transcript: String, answeredIn: Script, against passage: TranscriptionCase
    ) -> (reference: String, hypothesis: String, script: Script) {
        if let matching = passage.reference(in: answeredIn) {
            return (matching, transcript, answeredIn)
        }
        // Both sides through ICU rather than only the transcript. A catalogue sample may
        // be written in Devanagari and nothing else, and romanising the transcript alone
        // would then compare Latin with Devanagari and report a perfect transcript as
        // 100% wrong. Romanising Latin is a no-op, so the English-answered-in-Devanagari
        // case is unchanged.
        let reference = passage.forms.first ?? ""
        return (reference.transliteratedToLatin, transcript.transliteratedToLatin, .latin)
    }

    /// Terms the passage insisted on that the transcript does not contain.
    ///
    /// Matched with ``Scorer/containsPhrase(_:in:)`` — the same rule the transformation
    /// half uses, that a multi-word term has to survive as a consecutive run rather than
    /// as scattered words — but over this half's normalisation, so "3.11" and "get_user"
    /// stay whole and a term is not lost to a comma.
    private static func lostTerms(
        from passage: TranscriptionCase, in hypothesis: [String], normaliser: TextNormaliser
    ) -> [String] {
        passage.mustKeep.filter { !Scorer.containsPhrase(normaliser.words($0), in: hypothesis) }
    }
}
