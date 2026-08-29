public import struct Foundation.Data

private import CryptoKit

/// Proof Key for Code Exchange, RFC 7636.
///
/// The app holds no secret — anything shipped inside a downloadable binary is readable by
/// anybody who has the binary — so the thing that proves the code is being spent by the
/// program that asked for it is a value invented per attempt and kept in memory.
///
/// The verifier never leaves this process. Only its SHA-256 digest travels, in the URL the
/// browser is sent to, where it is public by design: knowing the digest does not let
/// anybody produce the value that made it.
public struct PKCEPair: Sendable, Equatable {
    /// Sent to the token endpoint, and nowhere else, ever.
    public let verifier: String

    /// Sent in the authorisation URL. Base64url of the verifier's SHA-256, unpadded.
    public let challenge: String

    /// Generates a fresh pair.
    ///
    /// - Parameter randomBytes: 32 bytes of randomness. Injected so a test can pin the
    ///   pair and check the digest against a value computed by something other than this
    ///   function.
    public init(randomBytes: Data) {
        // Base64url of 32 random bytes is 43 characters from the unreserved set, which is
        // exactly the minimum length RFC 7636 §4.1 permits and the shape it requires. The
        // spec's upper bound is 128; there is no reason to go longer than the digest that
        // covers it.
        verifier = PKCEPair.base64URL(randomBytes)
        challenge = PKCEPair.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Base64url without padding, which is what the specification asks for and what every
    /// server implements. Padding characters are not in the unreserved set and would have
    /// to be percent-encoded in a query string, where a server comparing raw strings would
    /// then never match.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
