public import struct Foundation.Data

private import CryptoKit

/// Proof Key for Code Exchange, RFC 7636, which is what a program holding no secret has instead.
public struct PKCEPair: Sendable, Equatable {
    /// Sent to the token endpoint, and nowhere else, ever.
    public let verifier: String

    /// Sent in the authorisation URL. Base64url of the verifier's SHA-256, unpadded.
    public let challenge: String

    /// - Parameter randomBytes: 32 bytes of randomness, injected so a test can pin the pair.
    public init(randomBytes: Data) {
        // 43 unreserved characters, the minimum RFC 7636 §4.1 permits and the shape it wants.
        verifier = PKCEPair.base64URL(randomBytes)
        challenge = PKCEPair.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Base64url unpadded: `=` is not unreserved, and percent-encoding it breaks raw comparison.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
