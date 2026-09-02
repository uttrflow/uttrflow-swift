/// Where candidates come from, so the engine can be tested without a database.
public protocol PredictionStore: Sendable {
    /// What the user might be finishing, given what they have typed into this field.
    func candidates(for surface: Surface, matching typed: String) async throws -> [Candidate]

    /// What usually follows what they last entered here, for a field they have not started typing in.
    func successors(for surface: Surface, after previous: String) async throws -> [Candidate]
}
