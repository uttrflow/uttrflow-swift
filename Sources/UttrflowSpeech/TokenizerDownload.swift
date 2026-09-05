internal import Foundation

// The one file in UttrflowSpeech allowed to open a connection; Scripts/offline_audit.sh names it.

/// Fetches a model's tokenizer at install time, so WhisperKit never reaches for one while decoding.
func downloadTokenizer(for model: SpeechModel, into destination: URL) async throws {
    for name in TokenizerAssets.fileNames {
        guard
            let url = URL(
                string: "https://huggingface.co/\(model.tokenizerRepository)/resolve/main/\(name)")
        else {
            throw TokenizerFetchFailure(reason: "\(model.tokenizerRepository) is not an address")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TokenizerFetchFailure(
                reason: "\(model.tokenizerRepository) answered \(status) for \(name)")
        }

        // Atomic, so a dropped connection cannot leave a truncated file that passes as a tokenizer.
        try data.write(to: destination.appending(path: name), options: .atomic)
    }
}

/// Why a tokenizer could not be fetched; a sentence for the log, since nothing branches on it.
struct TokenizerFetchFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}
