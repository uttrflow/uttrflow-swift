// The suggestion model's scores, loads and releases run as work nobody is waiting for yet.

/// Wraps the suggestion model so every score, load and release runs at utility priority, and no score runs while `mayRun` says no. See `Docs/performance.md`.
public struct DiscretionaryModel<Model: ReleasableModel>: CandidateScoring {
    private let model: Model
    private let mayRun: @Sendable () -> Bool

    /// Takes the model and the question asked before each score, such as Low Power Mode and thermal pressure.
    public init(_ model: Model, mayRun: @escaping @Sendable () -> Bool) {
        self.model = model
        self.mayRun = mayRun
    }

    /// Not ready while the Mac asks for less, so the verifier scores nothing and stays silent.
    public var isReady: Bool {
        get async {
            guard mayRun() else { return false }
            return await model.isReady
        }
    }

    public func logLikelihood(of candidate: String, following context: String) async -> Double? {
        guard mayRun() else { return nil }
        return try? await DiscretionaryGenerator.discretionary { [model] in
            await model.logLikelihood(of: candidate, following: context)
        }
    }

    /// Loads the weights at utility priority, whatever the Mac's conditions, since somebody asked for the feature.
    public func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await DiscretionaryGenerator.discretionary { [model] in
            try await model.prepare(onProgress: onProgress)
        }
    }

    /// Drops the weights at utility priority.
    public func release() async {
        _ = try? await DiscretionaryGenerator.discretionary { [model] in await model.release() }
    }
}

extension DiscretionaryModel {
    /// Sets what the idle-releasing model inside tells when a query's reload finds the weights gone from disk.
    public func whenReloadFails<Inner>(_ handler: @escaping @Sendable () -> Void) async
    where Model == IdleReleasingModel<Inner> {
        await model.whenReloadFails(handler)
    }
}
