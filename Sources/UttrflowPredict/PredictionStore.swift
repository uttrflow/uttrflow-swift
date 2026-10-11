/// Where candidates come from, so the engine can be tested without a database.
public protocol PredictionStore: Sendable {
    /// What the user might be finishing, given what they have typed into this field.
    func candidates(for surface: Surface, matching typed: String) async throws -> [Candidate]
}

/// Selects remembered completions before the machine's own completions, as the suggestion coordinator does.
public enum CandidateSources {
    /// Remembered history wins when it has a completion; otherwise the machine supplies the candidates.
    public static func candidates(
        from store: any PredictionStore, environment: EnvironmentSource,
        for surface: Surface, matching typed: String, now: ContinuousClock.Instant
    ) async -> [Candidate] {
        let remembered = (try? await store.candidates(for: surface, matching: typed)) ?? []
        guard remembered.isEmpty else { return remembered }
        return await environment.candidates(for: surface, matching: typed, now: now)
    }
}
