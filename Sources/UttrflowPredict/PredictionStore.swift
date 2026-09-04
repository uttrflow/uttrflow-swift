/// Where candidates come from, so the engine can be tested without a database.
public protocol PredictionStore: Sendable {
    /// What the user might be finishing, given what they have typed into this field.
    func candidates(for surface: Surface, matching typed: String) async throws -> [Candidate]
}
