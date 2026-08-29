public import UttrflowCore
import Foundation
import Security

/// The refresh token, in this Mac's Keychain.
///
/// Small on purpose: reading it is the review, because nothing here can be exercised by a
/// test that does not touch the login keychain of whoever is running it.
///
/// Four decisions are worth stating.
///
/// **`kSecAttrAccessibleAfterFirstUnlock`.** The app relaunches at login and refreshes in
/// the background; `WhenUnlocked` would fail those and look like a spontaneous sign-out.
/// It is not `ThisDeviceOnly`, so a Mac restored from an encrypted backup keeps its
/// session, which is the behaviour a person expects from a machine that was replaced.
///
/// **`kSecUseDataProtectionKeychain`, and a fallback.** It is asked for first, because
/// without it this lands in the old file-based keychain where a signed build and an
/// unsigned one see different items. But it cannot be *insisted* on: it needs a
/// keychain-access-group entitlement, that needs a team identifier, and an ad-hoc build
/// has neither — `SecItemAdd` answers `errSecMissingEntitlement` (-34018) and the sign-in
/// is lost. So both are tried, for writing and for reading, and a token that lands in
/// neither is reported rather than swallowed.
///
/// **Delete then add, rather than `SecItemUpdate`.** Rotation happens hourly and an update
/// that misses leaves the previous token behind, which is a live credential nobody is
/// tracking any more.
///
/// **The file-based item is named after this build.** That is the one part of this that
/// looks like an over-complication and is not, so the measurement is written down below.
///
/// ## Why the fallback cannot share one name
///
/// The file-based keychain guards each item with an access control list naming the
/// application that created it, and for ad-hoc code that name is pinned to the code
/// directory hash — which changes on every single build. Pinning the *designated
/// requirement* to the bundle identifier, which is what keeps TCC grants alive across a
/// rebuild, does not help here: the keychain's list is not the designated requirement.
/// Both were measured, on macOS 26.5.1, with two ad-hoc builds of one bundle sharing an
/// item:
///
///     read   -25293  errSecAuthFailed      (a login-password dialog, with UI allowed)
///     delete -25244  cannot remove it
///     add    -25299  errSecDuplicateItem
///
/// So one shared name is not merely awkward, it is a trap. The first build to sign in owns
/// it for ever; every later build is refused all three operations, and — because `store`
/// deletes before adding and the delete is refused too — every later sign-in ends in
/// ``AccountError/sessionCouldNotBeKept`` with no way out but deleting the item by hand in
/// Keychain Access. Suppressing the dialog is not on offer either:
/// `SecKeychainSetUserInteractionAllowed` is the switch for it, it is deprecated, and this
/// package compiles warnings as errors.
///
/// Giving each build its own name closes all of it. A rebuild finds nothing of its own
/// (-25300, no list consulted, no dialog), signs in once, and keeps its session from then
/// on. Verified by compiling this file into two ad-hoc-signed app bundles differing only
/// in code hash: one stores, relaunches and rotates; the other reads nil silently, signs
/// in, and keeps its own; neither disturbs the other; both sign out clean.
///
/// The cost is one stale item per ad-hoc build that ever signed in, which ``clear()``
/// cannot reach because it belongs to a build that no longer exists. They are harmless and
/// visible under this service name; to sweep them:
///
///     security delete-generic-password -s com.uttrflow.session.refresh-token.v1
///
/// A Developer ID build never reaches any of this: it has a team identifier, so the data
/// protection keychain takes the token on the first attempt.
public struct KeychainTokenStore: TokenStore {
    /// The service name the item is filed under. Versioned, so a future token of a
    /// different shape can be introduced beside this one rather than on top of it.
    public static let defaultService = "com.uttrflow.session.refresh-token.v1"

    private let service: String
    private let account: String

    /// The name the file-based item is filed under, or `nil` when there must not be one.
    ///
    /// Absent only when this build cannot read its own code identity, and then the
    /// fallback is disabled rather than allowed to share a name with another build — see
    /// the measurement above for what sharing one costs.
    private let fileAccount: String?

    /// - Parameters:
    ///   - service: The Keychain service name. Only a test has a reason to pass one.
    ///   - account: Which account on this Mac. Defaults to the unix user, so two people
    ///     sharing a machine do not share a session.
    public init(service: String = defaultService, account: String? = nil) {
        let account = account ?? NSUserName()
        self.service = service
        self.account = account
        self.fileAccount = Self.codeIdentity().map { "\(account) · \($0)" }
    }

    /// The two keychains this can land in, in the order they are tried.
    ///
    /// `dataProtection` is the one to want. `file` exists because a build signed ad-hoc —
    /// every local build, and every build a developer runs — is refused the first with
    /// `errSecMissingEntitlement`, since the data-protection keychain requires a
    /// keychain-access-group entitlement and that requires a team identifier a `--sign -`
    /// build does not have. Adding the entitlement anyway is worse than not having it:
    /// the process is killed on launch.
    private enum Keychain: CaseIterable {
        case dataProtection
        case file
    }

    /// The attributes identifying this Mac's item in `keychain`, or `nil` when there is no
    /// item there to identify — which is only ever the file-based one, in a build whose own
    /// code identity could not be read.
    private func query(_ keychain: Keychain) -> [String: Any]? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        switch keychain {
        case .dataProtection:
            query[kSecAttrAccount as String] = account
            query[kSecUseDataProtectionKeychain as String] = true
        case .file:
            guard let fileAccount else { return nil }
            query[kSecAttrAccount as String] = fileAccount
        }
        return query
    }

    /// Reads from whichever keychain holds it.
    ///
    /// Both, in order, rather than the one that was written to: which keychain a build can
    /// use is a property of how it was signed, so a token written by an ad-hoc build and
    /// read by a notarised one — the same Mac, after an update — is stored in one and
    /// looked for in the other. Asking both makes that update keep the session instead of
    /// silently ending it.
    public func refreshToken() -> String? {
        for keychain in Keychain.allCases {
            guard var lookup = query(keychain) else { continue }
            lookup[kSecReturnData as String] = true
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
                let data = item as? Data, let token = String(data: data, encoding: .utf8)
            else { continue }
            return token
        }
        return nil
    }

    /// - Throws: ``AccountError/sessionCouldNotBeKept`` when neither keychain took it.
    ///
    /// This used to discard the `OSStatus` on the reasoning that a token which could not
    /// be stored costs one sign-in. It does not: it costs every sign-in, for ever, and it
    /// does not look like a Keychain problem from the user's chair. It looks like signing
    /// in does nothing at all — which is exactly what a build signed ad-hoc did, silently,
    /// because `errSecMissingEntitlement` was thrown away here and the empty read that
    /// followed was reported upwards as "signed out".
    public func store(_ refreshToken: String) throws(AccountError) {
        clear()
        for keychain in Keychain.allCases {
            guard var insert = query(keychain) else { continue }
            insert[kSecValueData as String] = Data(refreshToken.utf8)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(insert as CFDictionary, nil) == errSecSuccess { return }
        }
        throw .sessionCouldNotBeKept
    }

    /// Removes it from both, so a sign-out cannot leave a live credential in the keychain
    /// this build happens not to be using.
    public func clear() {
        for keychain in Keychain.allCases {
            guard let query = query(keychain) else { continue }
            _ = SecItemDelete(query as CFDictionary)
        }
    }

    /// The code directory hash of whatever is running this, as hexadecimal.
    ///
    /// The same value the file-based keychain's access control list is pinned to for
    /// ad-hoc code, which is exactly why it is the right thing to name the item after: two
    /// builds that would be refused each other's item are given different names, and never
    /// meet.
    ///
    /// - Returns: `nil` when the running code cannot be identified, which disables the
    ///   fallback rather than letting two builds share a name.
    private static func codeIdentity() -> String? {
        var running: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &running) == errSecSuccess, let running else {
            return nil
        }
        var onDisk: SecStaticCode?
        guard SecCodeCopyStaticCode(running, SecCSFlags(), &onDisk) == errSecSuccess,
            let onDisk
        else { return nil }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(onDisk, SecCSFlags(), &information) == errSecSuccess,
            let unique = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data
        else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }
}
