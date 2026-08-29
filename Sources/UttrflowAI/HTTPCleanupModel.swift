#if UTTRFLOW_CLOUD

    public import Foundation
    public import UttrflowCore

    /// A hosted language model.
    ///
    /// Compiled in only when `UTTRFLOW_CLOUD` is defined, which V1 does not do — the
    /// shipping binary contains no network path at all, and the requirements are
    /// explicit that it must not. Enabling it later is this flag plus a base URL, not a
    /// redesign, because it reuses ``GenerativeTextTransformer`` and therefore inherits
    /// the same prompt and the same meaning checks as the on-device model.
    ///
    /// Audio never reaches it. Only text and, later, context — which is the privacy
    /// principle the requirements set out for any hosted stage.
    public struct HTTPCleanupModel: CleanupModel {
        private let endpoint: URL
        private let session: URLSession

        public init(endpoint: URL, session: URLSession = .shared) {
            self.endpoint = endpoint
            self.session = session
        }

        public func availability(for language: LanguageCode?) async -> TransformerAvailability {
            .available
        }

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

    private struct CleanupCall: Encodable {
        let instructions: String
        let text: String
    }

    private struct CleanupReply: Decodable {
        let text: String
    }

#endif
