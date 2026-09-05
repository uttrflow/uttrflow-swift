#if UTTRFLOW_CLOUD
    // A hosted cleanup model and its JSON bodies, compiled in only under UTTRFLOW_CLOUD.

    public import Foundation
    public import UttrflowCore

    /// A hosted model, compiled in only under `UTTRFLOW_CLOUD`; it receives text and context, never audio.
    public struct HTTPCleanupModel: CleanupModel {
        /// Where the cleanup call is posted.
        private let endpoint: URL
        /// The session the call goes through.
        private let session: URLSession

        /// Points the model at a service.
        public init(endpoint: URL, session: URLSession = .shared) {
            self.endpoint = endpoint
            self.session = session
        }

        /// Always available; the service handles any language.
        public func availability(for language: LanguageCode?) async -> TransformerAvailability {
            .available
        }

        /// Posts the instructions and text as JSON and returns the reply's text.
        public func rewrite(
            _ text: String, instructions: String, kind: TransformerKind
        ) async throws(TransformationError) -> String {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(
                CleanupCall(instructions: instructions, text: text)
            )

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw TransformationError.transformFailed(kind: kind, description: "the service refused")
                }
                return try JSONDecoder().decode(CleanupReply.self, from: data).text
            } catch let error as TransformationError {
                throw error
            } catch {
                throw .transformFailed(kind: kind, description: error.localizedDescription)
            }
        }
    }

    /// The request body.
    private struct CleanupCall: Encodable {
        /// The system instructions.
        let instructions: String
        /// The text to rewrite.
        let text: String
    }

    /// The response body.
    private struct CleanupReply: Decodable {
        /// The rewritten text.
        let text: String
    }

#endif
