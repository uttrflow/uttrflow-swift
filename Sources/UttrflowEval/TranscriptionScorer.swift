// Scores one transcript against the passage that was read.
public import UttrflowCore

/// Scores one transcript by the edits needed to repair it; ``Scorer`` scores rewrites by overlap.
public enum TranscriptionScorer {
    /// Scores `transcript` against `passage` under `normaliser`; `stages` and `cohortID` ride on the score.
    public static func score(
        _ transcript: String,
        against passage: TranscriptionCase,
        normaliser: TextNormaliser = .standard,
        stages: [StageMeasurement] = [],
        failure: TranscriptionFailure? = nil,
        cohortID: String? = nil
    ) -> PassageScore {
        // An unreadable recording is the harness's fault, so it reports as a failure with no rate.
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

    /// Picks the reference form matching the transcript's script, transliterating only as a last resort.
    private static func comparable(
        _ transcript: String, answeredIn: Script, against passage: TranscriptionCase
    ) -> (reference: String, hypothesis: String, script: Script) {
        if let matching = passage.reference(in: answeredIn) {
            return (matching, transcript, answeredIn)
        }
        // Both sides go through ICU, since a Devanagari-only reference would otherwise never match.
        let reference = passage.forms.first ?? ""
        return (reference.transliteratedToLatin, transcript.transliteratedToLatin, .latin)
    }

    /// Terms the passage insists on that the transcript lacks as a consecutive run, under this normalisation.
    private static func lostTerms(
        from passage: TranscriptionCase, in hypothesis: [String], normaliser: TextNormaliser
    ) -> [String] {
        passage.mustKeep.filter { !Scorer.containsPhrase(normaliser.words($0), in: hypothesis) }
    }
}
