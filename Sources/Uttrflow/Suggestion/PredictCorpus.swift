import Foundation
import UttrflowPredictCapture
import UttrflowPredictStore
import UttrflowUX

/// What AI suggestions learned on this Mac, opened on demand so Settings can forget it while the loop is off.
struct PredictCorpus: SuggestionCorpus {
    /// The directory the corpus and its consent file live in.
    let container: URL

    private var corpusPath: String {
        PredictStore.defaultFile(in: container).path(percentEncoded: false)
    }

    private var consent: CapturePreferencesFile {
        CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false))
    }

    /// How many lines each application taught, or none when the corpus was never created or will not open.
    func learnedSuggestions() async -> [String: Int] {
        guard let store = try? existingStore() else { return [:] }
        return (try? await store.entryCountsByApplication()) ?? [:]
    }

    /// Forgets every line one application taught, leaving every other application's.
    func forgetSuggestions(from bundleIdentifier: String) async throws {
        guard let store = try existingStore() else { return }
        try await store.forget(bundleIdentifier: bundleIdentifier)
    }

    /// Forgets every line and every application the loop has met.
    func forgetEverySuggestion() async throws {
        if let store = try existingStore() { try await store.forgetEverything() }
        try consent.remove()
    }

    /// The corpus when there is one on disk, so asking never creates an empty file.
    private func existingStore() throws -> PredictStore? {
        guard FileManager.default.fileExists(atPath: corpusPath) else { return nil }
        return try PredictStore(path: corpusPath)
    }
}
