/// The outcome of running an operation across a list of candidates.
public enum FallbackOutcome<Success: Sendable>: Sendable {
    case succeeded(Success)
    /// Every candidate was tried and every one failed, in order.
    case exhausted(errors: [any Error])
}

/// Tries an operation against candidates in preference order and returns the first
/// success.
///
/// Two separate parts of the pipeline need exactly this — picking a transformer that
/// supports the spoken language, and picking an insertion strategy the focused app
/// accepts — so the retry-and-degrade logic lives here once rather than in both.
public enum FallbackRunner {
    /// Runs `attempt` against each candidate until one succeeds.
    ///
    /// - Returns: ``FallbackOutcome/succeeded(_:)`` with the first success, or
    ///   ``FallbackOutcome/exhausted(errors:)`` carrying one error per candidate in
    ///   the order they were tried. An empty `candidates` list is exhausted with no
    ///   errors.
    public static func firstSuccess<Candidate, Success: Sendable>(
        among candidates: [Candidate],
        attempt: (Candidate) async throws -> Success
    ) async -> FallbackOutcome<Success> {
        var errors: [any Error] = []
        errors.reserveCapacity(candidates.count)

        for candidate in candidates {
            do {
                return .succeeded(try await attempt(candidate))
            } catch {
                errors.append(error)
            }
        }

        return .exhausted(errors: errors)
    }
}
