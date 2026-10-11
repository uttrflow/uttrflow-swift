public import UttrflowCore
import UttrflowDictionary

// The guard's judgement of offered readings where their doubtful runs stand.
extension MeaningPreservationGuard {
    /// The readings the rewrite wrote where a doubtful run stood, so the entries that taught them are counted used.
    public func readingsTaken(
        draft: Draft, rewritten: String, offering doubtful: [DoubtfulSpan]
    ) -> [Reading] {
        guard !doubtful.isEmpty else { return [] }
        return Self.readingVerdict(doubtful, in: RewriteAlignment(kept: draft.text, rewritten: rewritten))
            .taken
    }

    /// A doubtful run may be written where it stands as it was heard or as a reading offered for it, inflected or not, and as nothing else.
    static func readingVerdict(
        _ doubtful: [DoubtfulSpan], in alignment: RewriteAlignment
    ) -> (verdict: GuardVerdict, excused: Set<Int>, taken: [Reading]) {
        var excused: Set<Int> = []
        var taken: [Reading] = []
        guard !doubtful.isEmpty else { return (.accepted, excused, taken) }
        for span in doubtful {
            for (ordinal, place) in alignment.keptRuns(spelled: DoubtfulSpan.closedUp(span.heard))
                .enumerated()
            {
                let touched = alignment.changes.filter { $0.kept.overlaps(place) }
                // A run the rewrite left where it stood is the run as it was heard, and needs no reading.
                guard let first = touched.first, let last = touched.last else { continue }
                let start = min(place.lowerBound, first.kept.lowerBound)
                let end = max(place.upperBound, last.kept.upperBound)
                // A change reaching past the run took its neighbours with it, so they are expected here too.
                let before = alignment.keptSpelling(of: start..<place.lowerBound)
                let after = alignment.keptSpelling(of: place.upperBound..<end)
                // The rewrite may inflect its input run, such as "payment sheet" into "payment sheets", and change it no further.
                func writes(_ reading: String) -> Bool {
                    let wanted = DoubtfulSpan.closedUp(reading)
                    return WordForms.inflections(of: wanted).union([wanted]).map { before + $0 + after }
                        .contains(alignment.standing(in: start..<end))
                }
                let offered = span.candidates.filter { writes($0.spelling) }
                // A mention another span doubted is judged by that span alone.
                let spelling = DoubtfulSpan.closedUp(span.heard)
                if !span.isDoubted(at: ordinal),
                    doubtful.contains(where: {
                        DoubtfulSpan.closedUp($0.heard) == spelling && $0.isDoubted(at: ordinal)
                    })
                {
                    continue
                }
                // A later mention of the same words was offered nothing, so it stands as it was heard.
                guard span.isDoubted(at: ordinal) else {
                    guard
                        Self.reading(
                            among: offered, heard: span.heard,
                            standing: alignment.standingAsWritten(in: start..<end)) == nil
                    else {
                        return (
                            .rejected(
                                reason:
                                    "the rewrite read '\(span.heard)' as a reading offered for another mention",
                                kind: .unofferedReading),
                            excused, taken
                        )
                    }
                    continue
                }
                guard writes(span.heard) || !offered.isEmpty else {
                    return (
                        .rejected(
                            reason: "the rewrite read '\(span.heard)' as a word it was not offered",
                            kind: .unofferedReading),
                        excused, taken
                    )
                }
                if let reading = Self.reading(
                    among: offered, heard: span.heard, standing: alignment.standingAsWritten(in: start..<end))
                {
                    taken.append(reading)
                }
                // A reading rightly written here is the one substitution the survival check must let past.
                for change in touched { excused.formUnion(change.kept.clamped(to: place)) }
            }
        }
        return (.accepted, excused, taken)
    }

    /// The offered reading written in the run's place, told from the heard words by its capitals and spaces when it closes up alike.
    private static func reading(
        among offered: [Reading], heard: String, standing written: String
    ) -> Reading? {
        let asHeard = RewriteAlignment.asWritten(heard)
        return offered.first { reading in
            let spelled = RewriteAlignment.asWritten(reading.spelling)
            // Capitals alone are what a sentence gives its first word, so they are no sign the model chose the reading.
            guard spelled.lowercased() != asHeard.lowercased() else { return false }
            return written.contains(spelled)
        }
    }
}
