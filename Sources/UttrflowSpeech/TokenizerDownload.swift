internal import Foundation

// The one file in UttrflowSpeech allowed to open a connection, and it is a file that does
// nothing else. Scripts/offline_audit.sh names it as an island for exactly that reason:
// the rule "no network anywhere between the key going down and the text appearing" is
// only checkable when every exception is a whole file with one job, rather than a
// function sitting among the ones that run during a dictation.
//
// Reached only from a model install, which the user asks for and which plainly needs the
// network. Nothing on the loading or decoding path can reach it.

/// Fetches a model's tokenizer from the repository that publishes it.
///
/// Done at install time, over plain HTTPS, rather than left to WhisperKit's loader. The
/// loader only reaches for a tokenizer when it is about to decode, which is the one
/// moment this product has promised not to need a network.
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

        // Atomic so a connection dropping mid-write cannot leave a truncated file that
        // the next launch would count as a working tokenizer.
        try data.write(to: destination.appending(path: name), options: .atomic)
    }
}

/// Why a tokenizer could not be fetched.
///
/// Carries a sentence rather than a case per cause because nothing branches on it: the
/// store folds it into ``SpeechEngineError/modelDownloadFailed(description:)``, whose
/// own message is already written for the user, and this text is for the log.
struct TokenizerFetchFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}
