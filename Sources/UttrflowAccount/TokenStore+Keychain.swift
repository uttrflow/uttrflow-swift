public import UttrflowCore
import Foundation
import Security

/// The refresh token in this Mac's Keychain; small so reading it is the review. See Docs/account-keychain.md.
public struct KeychainTokenStore: TokenStore {
    /// The service name the item is filed under, versioned so a different token shape can sit beside it.
    public static let defaultService = "com.uttrflow.session.refresh-token.v1"

    /// The Keychain service name.
    private let service: String
    /// The unix user, so two people sharing a Mac do not share a session.
    private let account: String

    /// The file-based item's per-build name, or `nil` to disable that fallback rather than share a name.
    private let fileAccount: String?

    /// `account` defaults to the unix user; only a test passes a `service`.
    public init(service: String = defaultService, account: String? = nil) {
        let account = account ?? NSUserName()
        self.service = service
        self.account = account
        self.fileAccount = Self.codeIdentity().map { "\(account) · \($0)" }
    }

    /// The two keychains in the order tried; an ad-hoc build gets the second. See Docs/account-keychain.md.
    private enum Keychain: CaseIterable {
        /// The one to want; needs a keychain-access-group entitlement, so a team identifier.
        case dataProtection
        /// Where an ad-hoc build lands, under a name of its own per build.
        case file
    }

    /// The attributes naming this Mac's item in `keychain`, or `nil` when this build may not have one there.
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

    /// Reads both keychains in order, so an update from an ad-hoc build to a notarised one keeps the session.
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

    /// Deletes then adds in the first keychain that takes it, and throws when neither does; never silent.
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

    /// Removes it from both, so a sign-out leaves no live credential in the keychain this build is not using.
    public func clear() {
        for keychain in Keychain.allCases {
            guard let query = query(keychain) else { continue }
            _ = SecItemDelete(query as CFDictionary)
        }
    }

    /// The code directory hash as hex, which the file-based ACL is pinned to; `nil` disables the fallback.
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
