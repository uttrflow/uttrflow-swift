public import UttrflowCore

// How the guard judges a reference tidy-up, shared by the false-refusal gate and the bake-off report.
extension MeaningPreservationGuard {
    /// The verdict on an expected text against its own cleaned draft, under the situation's formatter as the engine uses it.
    public func verdict(onReference expected: String, spoken: String, in situation: Situation) -> GuardVerdict
    {
        let draft = CleaningPipeline.standard.run(Draft(keepingLineBreaks: spoken))
        let formatter = DestinationFormatter.standard(for: situation)
        return verdict(
            draft: draft, rewritten: expected, layout: formatter.layout, grammar: formatter.grammar)
    }
}
