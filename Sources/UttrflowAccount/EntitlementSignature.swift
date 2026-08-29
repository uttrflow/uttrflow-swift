public import CryptoKit

public import struct Foundation.Data

extension Entitlement {
    /// Names the shape of ``signedPayload`` inside the bytes themselves.
    ///
    /// A backend that signs a different shape then fails immediately and completely,
    /// rather than happening to agree on three fields out of four; and a second shape
    /// can one day be introduced beside this one rather than on top of it.
    public static let signatureFormat = "uttrflow-entitlement-v1"

    /// The exact bytes a signature covers.
    ///
    /// Length-prefixed rather than joined with a separator, because a separator is
    /// something a value can contain: an account identifier holding the delimiter could
    /// otherwise be read as a different account and a different plan, and one signature
    /// would cover two meanings. Prefixing each field with its byte count leaves no
    /// second reading.
    ///
    /// The display name and email address are outside it on purpose. They change
    /// whenever the user renames themselves at their provider, so signing them would
    /// sign people out for editing their own profile — and they decide nothing about
    /// what anybody may do.
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

    /// The expiry as whole seconds, which is the only form a backend in another
    /// language can be relied upon to reproduce byte for byte.
    ///
    /// Converted through `Int(exactly:)` rather than `Int(_:)` because the date arrives
    /// from a decoded file: `Int(_: Double)` traps on a value too large to fit, so a
    /// number somebody put in that file by hand would crash the app on launch. Anything
    /// unrepresentable becomes zero, which no real signature covers, so the entitlement
    /// is rejected instead — the whole point being that a mangled file signs the user
    /// out and never stops Uttrflow opening.
    private var expirySeconds: Int {
        Int(exactly: expiresAt.timeIntervalSince1970.rounded(.down)) ?? 0
    }
}

/// Decides whether an entitlement really came from the backend.
///
/// A protocol rather than the concrete verifier everywhere, so the session store can be
/// tested against a forgery without anyone holding a private key.
public protocol EntitlementVerifying: Sendable {
    func isAuthentic(_ entitlement: Entitlement) -> Bool
}

/// Checks an entitlement's Ed25519 signature against a public key compiled into the
/// binary.
///
/// This is what makes the offline promise safe to keep. A cached entitlement is
/// believed on a Mac that has not seen the network for a month because the signature
/// says the backend wrote it, not because the app is being trusting.
public struct Ed25519EntitlementVerifier: EntitlementVerifying {
    /// The public key a release build checks entitlements against.
    ///
    /// Set, as of the first deployment, to the public half of the key `api.uttrflow.com`
    /// signs with. The private half exists only in that deployment's parameter store;
    /// there is no keypair in this repository and there never has been.
    ///
    /// Empty rather than 32 zero bytes, which is the obvious placeholder and a trap.
    /// The all-zero Ed25519 public key decodes to a point of order four, and CryptoKit
    /// verifies without the cofactor — so an all-zero *signature* satisfies the equation
    /// against it for roughly one message in four. That placeholder would not fail
    /// closed: it would hand a subscription to anybody willing to try their account
    /// identifier a few times, with a signature they could type out from memory. Bytes
    /// that are not a key at all verify nothing, which is the only safe thing for a
    /// placeholder to do, and `rejectsTheDegenerateKeyThatWouldAcceptAForgery` in the
    /// tests keeps it that way.
    public static let releasePublicKeyBytes = Data(base64Encoded: releasePublicKeyBase64) ?? Data()

    /// The 32 raw bytes of the backend's Ed25519 public key, base64.
    ///
    /// A public key, so it belongs in source: publishing it is how a build can be checked
    /// against the deployment it was made for, and `/v1/health` publishes the same value
    /// so the two can be compared without asking anybody for anything.
    ///
    /// Rotating it is a new release of the app, not a deployment — every cached
    /// entitlement was signed by its partner, and a build carrying the wrong one signs
    /// everybody out. Which is why the fingerprint is in the health response.
    public static let releasePublicKeyBase64 = "LeiRCoiWvlNeluY30RoE/VvVNIKLnCAM9VC86b9lseM="

    /// The verifier the shipping app uses.
    public static let release = Ed25519EntitlementVerifier(publicKeyBytes: releasePublicKeyBytes)

    /// The key, or `nil` when the bytes handed over were not one — which is exactly what
    /// ``releasePublicKeyBytes`` is until somebody sets it.
    ///
    /// An optional rather than a failable initialiser so that a build with no key
    /// configured still runs, and fails closed while it does: every entitlement is
    /// rejected, the user is sent to sign in, and the sign-in refuses to keep what it
    /// cannot verify. Unmistakable, and impossible to confuse with working.
    private let publicKey: Curve25519.Signing.PublicKey?

    public init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// - Parameter publicKeyBytes: The 32 raw bytes of the backend's public key.
    ///   Anything else — including nothing — yields a verifier that believes no
    ///   entitlement at all.
    public init(publicKeyBytes: Data) {
        publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyBytes)
    }

    /// Whether this verifier holds a key at all.
    ///
    /// Asked by the wiring that chooses between the real backend and the development one:
    /// a build with no key configured cannot believe anything the real backend signs, and
    /// pointing it at one would produce a sign-in that fails at the last step with a
    /// signature error nobody can act on.
    public var isConfigured: Bool { publicKey != nil }

    public func isAuthentic(_ entitlement: Entitlement) -> Bool {
        guard let publicKey, let signature = Data(base64Encoded: entitlement.signature) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: entitlement.signedPayload)
    }
}

extension Curve25519.Signing.PrivateKey {
    /// Signs `entitlement`, returning it with ``Entitlement/signature`` filled in.
    ///
    /// Here rather than only in the development service because it is the other half of
    /// ``Ed25519EntitlementVerifier``, and the two being read side by side is what keeps
    /// the payload they agree on from drifting. It is also the executable specification
    /// the real backend has to match.
    public func signing(_ entitlement: Entitlement) -> Entitlement {
        // Signing a block of bytes with a key that already exists has no failure mode;
        // the API throws for consistency with the ones that do. Left empty if it ever
        // did, because an unsigned entitlement is one that verifies nowhere — even the
        // branch that cannot happen fails closed.
        var signature = ""
        if let bytes = try? self.signature(for: entitlement.signedPayload) {
            signature = bytes.base64EncodedString()
        }
        return Entitlement(
            account: entitlement.account, plan: entitlement.plan, expiresAt: entitlement.expiresAt,
            signature: signature)
    }
}
