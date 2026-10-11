// Whether two accuracy runs measure the same text under the same instrument.
extension AccuracyBaseline {
    /// Why these two runs are not about the same thing, if they are not; growth is not a reason.
    func incomparability(
        with report: AccuracyBaseline, shared: [String],
        before: [String: BaselineEntry], after: [String: BaselineEntry]
    ) -> String? {
        if report.label != label {
            return "the baseline measured \(label) and this run measured \(report.label), "
                + "so the rates are not comparable"
        }
        if let mismatch = recogniserMismatch(report.recogniser) { return mismatch }
        if shared.isEmpty {
            return "the baseline and this run share no samples"
        }
        if let mismatch = normalisationMismatch(report.normalisation) { return mismatch }
        let respelt = shared.filter { before[$0]?.scoresOutput != after[$0]?.scoresOutput }
        if !respelt.isEmpty {
            return "the baseline and this run judge a different text (recogniser or romanised output) for "
                + respelt.joined(separator: ", ") + " — re-measure the baseline"
        }
        let changedInstrument = shared.filter {
            before[$0]?.scoresOutput == true
                && before[$0]?.outputNormalisation != after[$0]?.outputNormalisation
        }
        if !changedInstrument.isEmpty {
            return "the output normalisation changed for " + changedInstrument.joined(separator: ", ")
                + " — re-measure the baseline"
        }
        let (mismatched, unverifiable) = audioIdentityIssues(shared, before, after)
        if !mismatched.isEmpty {
            return "the recording changed since the baseline for "
                + mismatched.joined(separator: ", ") + ", so the movement there is not the engine's"
        }
        if !unverifiable.isEmpty {
            return "no recording identity to check " + unverifiable.joined(separator: ", ")
                + " against the baseline, so a replacement recording cannot be ruled out"
        }
        return nil
    }

    /// Why the recogniser pins differ, if they do; a new baseline saved in the same change clears it.
    private func recogniserMismatch(_ measured: String?) -> String? {
        guard measured != recogniser else { return nil }
        guard let recogniser else {
            return "the baseline does not record which model it is for — save a new baseline"
        }
        return "baseline is for a different model (\(recogniser), this run \(measured ?? "unrecorded")) "
            + "— save a new baseline in the same change"
    }

    /// Where a shared case ID's audio provably changed, and where it cannot be checked either way.
    private func audioIdentityIssues(
        _ shared: [String], _ before: [String: BaselineEntry], _ after: [String: BaselineEntry]
    ) -> (mismatched: [String], unverifiable: [String]) {
        var mismatched: [String] = []
        var unverifiable: [String] = []
        for caseID in shared {
            switch (before[caseID]?.recordingIdentity, after[caseID]?.recordingIdentity) {
            case (let some?, let other?):
                if some != other { mismatched.append(caseID) }
            case (nil, nil):
                // Neither side ever tracked identity; no signal either way, so the pair is left alone.
                break
            default:
                // One side tracked identity and the other did not — a legacy baseline meeting a fresh run.
                unverifiable.append(caseID)
            }
        }
        return (mismatched.sorted(), unverifiable.sorted())
    }

    private func normalisationMismatch(_ measured: [NormalisationRule]) -> String? {
        if measured != normalisation {
            if normalisation.isEmpty {
                return "the baseline's normalisation rules are not recorded (a legacy baseline) "
                    + "— re-measure the baseline so the new rules are saved alongside it"
            }
            if measured.isEmpty {
                return "the run's normalisation rules are not recorded (a legacy result file) "
                    + "— re-measure the run so the rules are saved alongside the scores"
            }
            return "the normalisation rules changed since the baseline, so the rates are not comparable "
                + "— re-measure the baseline so the new rules are saved alongside it"
        }
        return nil
    }
}
