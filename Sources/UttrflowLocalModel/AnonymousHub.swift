// The hub client every model download goes through, and the two things it refuses to do.

import Foundation
import HuggingFace
import UttrflowCore

/// The client model downloads use: nobody's token, and huggingface.co whatever the environment says. See `Docs/predict-llm.md`.
enum AnonymousHub {
    /// A client that sends no `Authorization` header and reads no `HF_ENDPOINT`.
    static func client() -> HubClient {
        NetworkActivityLedger.shared.record(.modelDownload)
        // Both named rather than defaulted: `HubClient()` resolves a token and follows HF_ENDPOINT.
        return HubClient(host: HubClient.defaultHost, tokenProvider: .none)
    }
}
