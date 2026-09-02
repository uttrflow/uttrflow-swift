public import CryptoKit

public import struct Foundation.Data

extension Entitlement {
    /// Names the payload's shape inside the bytes, so a different shape fails completely.
    public static let signatureFormat = "uttrflow-entitlement-v1"

    /// The exact bytes a signature covers, length-prefixed. See `Docs/entitlements.md`.
    public var signedPayload: Data {
        var payload = Data(Self.signatureFormat.utf8)
        for field in [
            account.identifier, account.provider.rawValue, plan.rawValue, String(expirySeconds),
        ] {
            let bytes = Data(field.utf8)
            payload.append(Data("\n\(bytes.count):".utf8))
            payload.append(bytes)
        }
        return payload
    }

    /// The expiry in whole seconds, through `Int(exactly:)` so a hand-edited file cannot trap.
    private var expirySeconds: Int {
        Int(exactly: expiresAt.timeIntervalSince1970.rounded(.down)) ?? 0
    }
}

/// Decides whether an entitlement came from the backend, as a seam a forgery can be tested through.
public protocol EntitlementVerifying: Sendable {
    func isAuthentic(_ entitlement: Entitlement) -> Bool
}

/// Checks an Ed25519 signature against a compiled-in key, which is what makes the offline promise safe.
public struct Ed25519EntitlementVerifier: EntitlementVerifying {
    /// The key a release build verifies against. Empty, never 32 zero bytes. See `Docs/entitlements.md`.
    public static let releasePublicKeyBytes = Data(base64Encoded: releasePublicKeyBase64) ?? Data()

    /// The backend's public key, base64, which belongs in source. See `Docs/entitlements.md`.
    public static let releasePublicKeyBase64 = "LeiRCoiWvlNeluY30RoE/VvVNIKLnCAM9VC86b9lseM="

    /// The verifier the shipping app uses.
    public static let release = Ed25519EntitlementVerifier(publicKeyBytes: releasePublicKeyBytes)

    /// The key, or `nil` for bytes that are not one — a build that runs and believes nothing.
    private let publicKey: Curve25519.Signing.PublicKey?

    public init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// - Parameter publicKeyBytes: The key's 32 raw bytes; anything else believes nothing.
    public init(publicKeyBytes: Data) {
        publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes)
    }

    /// Whether a key is configured, which is what decides between the real backend and the development one.
    public var isConfigured: Bool { publicKey != nil }

    public func isAuthentic(_ entitlement: Entitlement) -> Bool {
        guard let publicKey, let signature = Data(base64Encoded: entitlement.signature) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: entitlement.signedPayload)
    }
}

extension Curve25519.Signing.PrivateKey {
    /// Signs `entitlement`, and is the executable specification the real backend matches.
    public func signing(_ entitlement: Entitlement) -> Entitlement {
        // Left empty if it ever threw: an unsigned entitlement verifies nowhere.
        var signature = ""
        if let bytes = try? self.signature(for: entitlement.signedPayload) {
            signature = bytes.base64EncodedString()
        }
        return Entitlement(
            account: entitlement.account, plan: entitlement.plan, expiresAt: entitlement.expiresAt,
            signature: signature)
    }
}
