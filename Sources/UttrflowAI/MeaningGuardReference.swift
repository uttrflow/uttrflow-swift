public import UttrflowCore

// How the guard judges a reference tidy-up, shared by the false-refusal gate and the bake-off report.
extension MeaningPreservationGuard {
    /// The verdict on an expected text against the draft and readings the engine would hand the model for this request.
    public func verdict(
        onReference expected: String, for request: TransformationRequest
    ) async -> GuardVerdict {
        let prepared = await ModelDraft(request, steps: .default, doubtful: .standard)
        return verdict(
            draft: prepared.draft, rewritten: expected, offering: prepared.readings,
            layout: prepared.formatter.layout, grammar: prepared.formatter.grammar,
            grants: prepared.pipeline.grants)
    }
}
