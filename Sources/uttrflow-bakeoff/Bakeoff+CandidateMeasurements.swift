import ArgumentParser
import Foundation

extension Bakeoff {
    enum MeasurementStorage {
        case singleCase
        case fullRun(ResultStore, baselineURL: URL?)

        func save(_ measurement: Measurement) throws {
            guard case .fullRun(let store, let baselineURL) = self else { return }
            if let baselineURL, store.fileURL(for: measurement).standardizedFileURL == baselineURL {
                throw CleanExit.message(
                    "Comparison output would overwrite its baseline; choose a different --results-path."
                )
            }
            try store.save(measurement)
        }
    }

    /// Saves each finished candidate before the next begins, keeping the shared run header.
    static func measureCandidates(
        baselines: [() async throws -> Measurement],
        locals: () throws -> [() async throws -> Measurement],
        header: RunHeader, storage: MeasurementStorage
    ) async throws -> [Measurement] {
        var measured: [Measurement] = []
        func keep(_ measurement: Measurement) throws {
            var completed = measurement
            completed.header = header
            try storage.save(completed)
            measured.append(completed)
        }
        for measure in baselines { try keep(try await measure()) }
        for measure in try locals() { try keep(try await measure()) }
        return measured
    }
}
