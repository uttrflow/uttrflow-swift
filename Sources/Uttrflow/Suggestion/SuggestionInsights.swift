import UttrflowPredictStore

extension SuggestionCoordinator {
    /// Reads the stored counts shown on Insights.
    func insightCounts() async throws -> PredictionCorpusCounts {
        try await store.corpusCounts()
    }
}
