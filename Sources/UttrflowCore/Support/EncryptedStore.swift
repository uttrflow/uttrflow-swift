// Encrypts complete local-store files and migrates decoded legacy JSON in place.

public import CryptoKit
public import Foundation
import os
import Security
import Synchronization

/// A source of the installation key used to seal local store files.
public protocol StoreKeyProviding: Sendable {
    /// Loads or creates the key only when the caller has established that the file is new or legacy.
    func key(createIfMissing: Bool) throws -> SymmetricKey
}

/// A provider that can revoke the shared installation key after a full personalisation reset.
public protocol StoreKeyRevoking: Sendable {
    /// Removes the key, making every retained envelope under it unreadable.
    func revokeKey() throws
}

/// The shared versioned envelope for encrypted local JSON files.
public struct EncryptedStore: Sendable {
    private static let log = Logger(subsystem: LocalStore.productionIdentifier, category: "store-encryption")
    private static let magic = Data("UTTFLOWE".utf8)
    private static let version: UInt8 = 1
    private static let nonceLength = 12
    private static let tagLength = 16
    private let keys: StoreKeyCache

    /// Returns the number of leading bytes in this store's sealed-file header.
    public static let sealedHeaderLength = magic.count

    /// Uses the production Keychain provider unless a test supplies an isolated provider.
    public init(keys: (any StoreKeyProviding)? = nil) {
        self.keys = StoreKeyCache(keys ?? KeychainStoreKeyProvider())
    }

    /// Reads, authenticates and decodes one JSON file, migrating valid legacy JSON atomically.
    public func read<Value: Decodable & Encodable & Sendable>(
        _ type: Value.Type, from url: URL, now: Date = Date()
    ) -> StoredList<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable(setAside: LocalStore.setAside(url, now: now))
        }
        let isEnvelope = data.starts(with: Self.magic)
        do {
            let payload: Data
            if isEnvelope {
                let key: SymmetricKey
                do {
                    key = try keys.key(createIfMissing: false)
                } catch StoreKeyError.unavailable(let status) where status == Int32(errSecItemNotFound) {
                    Self.log.error(
                        "Encrypted store key is missing for \(url.lastPathComponent, privacy: .public)")
                    return .unreadable(setAside: LocalStore.setAside(url, now: now))
                } catch {
                    Self.log.error(
                        "Encrypted store key is unavailable for \(url.lastPathComponent, privacy: .public)")
                    return .unreadable(setAside: nil)
                }
                payload = try Self.open(data, key: key, name: url.lastPathComponent)
            } else {
                payload = data
            }
            let value: Value
            do {
                value = try JSONDecoder().decode(type, from: payload)
            } catch {
                if !isEnvelope { return .unreadable(setAside: LocalStore.setAside(url, now: now)) }
                throw error
            }
            if !isEnvelope {
                do {
                    let key = try keys.key(createIfMissing: true)
                    try PrivateFile.write(Self.seal(payload, key: key, name: url.lastPathComponent), to: url)
                } catch {
                    Self.log.error(
                        "Legacy store migration failed for \(url.lastPathComponent, privacy: .public)")
                    return .unreadable(setAside: nil)
                }
            }
            return .read(value)
        } catch {
            Self.log.error(
                "Encrypted store could not be authenticated or decoded for \(url.lastPathComponent, privacy: .public)"
            )
            return .unreadable(setAside: LocalStore.setAside(url, now: now))
        }
    }

    /// Writes JSON only after sealing it with filename-bound authenticated data.
    public func write<Value: Encodable & Sendable>(_ value: Value, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        var key: SymmetricKey
        do {
            let existing = try Data(contentsOf: url)
            guard existing.starts(with: Self.magic) else { throw StoreKeyError.legacyFileNeedsMigration }
            key = try keys.key(createIfMissing: false)
            _ = try Self.open(existing, key: key, name: url.lastPathComponent)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            key = try keys.key(createIfMissing: true)
        }
        try PrivateFile.write(Self.seal(data, key: key, name: url.lastPathComponent), to: url)
    }

    /// Encrypts bytes for a logical filename while leaving file I/O to the caller.
    public func seal(_ payload: Data, for logicalName: String) throws -> Data {
        let key = try keys.key(createIfMissing: true)
        return try Self.seal(payload, key: key, name: logicalName)
    }

    /// A keyed hash of `text` under this installation's key, separated by `purpose`, so equal text matches without being stored.
    public func digest(of text: String, for purpose: String) throws -> String {
        let key = try keys.key(createIfMissing: true)
        let subkey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key, info: Data(purpose.utf8), outputByteCount: 32)
        let code = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: subkey)
        return code.map { String(format: "%02x", $0) }.joined()
    }

    /// A keyed digest of `payload` under a key derived from the installation key for `purpose`, so equal inputs match without either being readable.
    public func keyedDigest(of payload: Data, purpose: String) throws -> Data {
        let key = try keys.key(createIfMissing: true)
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key, info: Data(purpose.utf8), outputByteCount: 32)
        return Data(HMAC<SHA256>.authenticationCode(for: payload, using: derived))
    }

    /// Revokes the shared key after all reset targets have been deleted successfully.
    public func revokeKey() throws {
        try keys.revokeKey()
    }

    /// Opens a sealed binary asset, refusing when the installation key is missing or the file was changed.
    public func open(_ envelope: Data, for logicalName: String) throws -> Data {
        let key = try keys.key(createIfMissing: false)
        return try Self.open(envelope, key: key, name: logicalName)
    }

    /// Whether bytes carry this store's versioned envelope header.
    public static func isSealed(_ payload: Data) -> Bool { payload.starts(with: magic) }

    private static func seal(_ payload: Data, key: SymmetricKey, name: String) throws -> Data {
        let box = try AES.GCM.seal(payload, using: key, authenticating: Data(name.utf8))
        guard let combined = box.combined else { throw CocoaError(.fileWriteUnknown) }
        var envelope = magic
        envelope.append(version)
        envelope.append(combined)
        return envelope
    }

    private static func open(_ envelope: Data, key: SymmetricKey, name: String) throws -> Data {
        let headerLength = magic.count + 1
        guard envelope.count >= headerLength + nonceLength + tagLength,
            envelope.prefix(magic.count) == magic,
            envelope[magic.count] == version
        else { throw CocoaError(.fileReadCorruptFile) }
        let combined = envelope.dropFirst(headerLength)
        let box = try AES.GCM.SealedBox(combined: Data(combined))
        return try AES.GCM.open(box, using: key, authenticating: Data(name.utf8))
    }
}

/// Holds the first key a provider returns so later seals and opens skip the provider's lookup.
final class StoreKeyCache: Sendable {
    private let provider: any StoreKeyProviding
    private let cached = Mutex<SymmetricKey?>(nil)

    init(_ provider: any StoreKeyProviding) { self.provider = provider }

    /// Failures are not cached, so a key that is missing or locked now is read again on the next call.
    func key(createIfMissing: Bool) throws -> SymmetricKey {
        if let key = cached.withLock({ $0 }) { return key }
        let key = try provider.key(createIfMissing: createIfMissing)
        cached.withLock { $0 = key }
        return key
    }

    func revokeKey() throws {
        guard let revoking = provider as? any StoreKeyRevoking else {
            throw StoreKeyError.revocationUnsupported
        }
        defer { cached.withLock { $0 = nil } }
        try revoking.revokeKey()
    }
}

/// Keeps one non-synchronizable, device-only key in the stable production Keychain service.
public struct KeychainStoreKeyProvider: StoreKeyProviding, StoreKeyRevoking {
    /// The versioned service shared across product upgrades.
    public static let service = "com.uttrflow.local-store.encryption.v1"

    private let fileURL: URL

    /// Uses the stable per-user key file when the data-protection Keychain lacks its entitlement.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    private static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return LocalStoreEntry.encryptionKey.location(in: support)
    }

    /// Reads the current user's key and creates it only for a new or successfully decoded legacy store.
    public func key(createIfMissing: Bool) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: NSUserName(),
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        return try resolveKeychainResult(
            status: status, data: item as? Data, createIfMissing: createIfMissing
        ) {
            data in
            var insertion = query
            insertion[kSecValueData as String] = data
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(insertion as CFDictionary, nil)
        }
    }

    func resolveKeychainResult(
        status: OSStatus,
        data: Data?,
        createIfMissing: Bool,
        add: (Data) -> OSStatus
    ) throws -> SymmetricKey {
        if status == errSecSuccess {
            guard let data, data.count == 32 else { throw StoreKeyError.invalidKey }
            return SymmetricKey(data: data)
        }
        if status == errSecMissingEntitlement {
            return try fileKey(createIfMissing: createIfMissing)
        }
        guard status == errSecItemNotFound else {
            throw StoreKeyError.unavailable(Int32(status))
        }

        // An ad-hoc fallback key on disk stays authoritative when a later build gains Keychain access.
        do {
            return try fileKey(createIfMissing: false)
        } catch StoreKeyError.unavailable(let missing) where missing == Int32(errSecItemNotFound) {
            guard createIfMissing else { throw StoreKeyError.unavailable(Int32(errSecItemNotFound)) }
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let addStatus = add(keyData)
        if addStatus == errSecSuccess { return key }
        if addStatus == errSecMissingEntitlement {
            return try fileKey(createIfMissing: true)
        }
        throw StoreKeyError.unavailable(Int32(addStatus))
    }

    /// Deletes the stable local-store item; deleting an already absent key is a completed reset.
    public func revokeKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: NSUserName(),
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound || status == errSecMissingEntitlement
        else {
            throw StoreKeyError.unavailable(Int32(status))
        }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    private func fileKey(createIfMissing: Bool) throws -> SymmetricKey {
        do {
            let data = try Data(contentsOf: fileURL)
            guard data.count == 32 else { throw StoreKeyError.invalidKey }
            return SymmetricKey(data: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            guard createIfMissing else { throw StoreKeyError.unavailable(Int32(errSecItemNotFound)) }
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try PrivateFile.write(data, to: fileURL)
        return key
    }
}

/// A Keychain refusal is retained so callers cannot mistake it for an empty store.
public enum StoreKeyError: Error, Sendable {
    /// The Security framework status that prevented the key read or write.
    case unavailable(Int32)
    /// A caller must decode a plaintext file through `read` before replacing it.
    case legacyFileNeedsMigration
    /// The injected provider cannot revoke its key, so a full reset must fail closed.
    case revocationUnsupported
    /// A stored installation key does not have the required 256-bit size.
    case invalidKey

    /// Whether the Keychain definitively has no installation key stored.
    public var isMissing: Bool {
        guard case .unavailable(let status) = self else { return false }
        return status == Int32(errSecItemNotFound)
    }
}
