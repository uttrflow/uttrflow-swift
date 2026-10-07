public import UttrflowCore

// How the guard judges a reference tidy-up, shared by the false-refusal gate and the bake-off report.
extension MeaningPreservationGuard {
    /// The verdict on an expected text against the draft the engine would hand the model, cleaned and judged under the situation's own formatter and passes.
    public func verdict(onReference expected: String, spoken: String, in situation: Situation) -> GuardVerdict
    {
        let formatter = DestinationFormatter.standard(for: situation)
        let pipeline = CleaningPipeline.beforeModel(for: formatter, situation: situation)
        let draft = pipeline.run(Draft(keepingLineBreaks: spoken))
        return verdict(
            draft: draft, rewritten: expected, layout: formatter.layout, grammar: formatter.grammar,
            grants: pipeline.grants)
    }
}
