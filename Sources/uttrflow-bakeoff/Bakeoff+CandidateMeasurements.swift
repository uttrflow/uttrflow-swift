import ArgumentParser
import Foundation

extension Bakeoff {
    /// Saves each finished candidate before the next begins, keeping the shared run header.
    static func measureCandidates(
        baselines: [() async throws -> Measurement],
        locals: () throws -> [() async throws -> Measurement],
        header: RunHeader, outputStore: ResultStore, baselineURL: URL?, storesResults: Bool
    ) async throws -> [Measurement] {
        var measured: [Measurement] = []
        func keep(_ measurement: Measurement) throws {
            var completed = measurement
            completed.header = header
            if storesResults {
                if let baselineURL,
                    outputStore.fileURL(for: completed).standardizedFileURL == baselineURL
                {
                    throw CleanExit.message(
                        "Comparison output would overwrite its baseline; choose a different --results-path."
                    )
                }
                try outputStore.save(completed)
            }
            measured.append(completed)
        }
        for measure in baselines { try keep(try await measure()) }
        for measure in try locals() { try keep(try await measure()) }
        return measured
    }
}
