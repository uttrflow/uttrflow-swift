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
    private let writeFile: @Sendable (Data, URL) throws -> Void
    private let removeFile: @Sendable (URL) throws -> Void

    /// Returns the number of leading bytes in this store's sealed-file header.
    public static let sealedHeaderLength = magic.count

    /// Uses the Keychain unless a test supplies a provider; a nil `markerURL` makes the legacy window trust the key alone.
    public init(keys: (any StoreKeyProviding)? = nil, markerURL: URL? = nil) {
        self.keys = StoreKeyCache(keys ?? KeychainStoreKeyProvider(), markerURL: markerURL)
        self.writeFile = { data, url in try PrivateFile.write(data, to: url) }
        self.removeFile = { url in try FileManager.default.removeItem(at: url) }
    }

    /// The production `markLegacyMigrationComplete` writes here; shared across this Mac's stores.
    public static func productionLegacyMigrationMarkerURL() -> URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return support.map { LocalStoreEntry.legacyMigrationMarker.location(in: $0) }
    }

    init(
        keys: any StoreKeyProviding,
        writeFile: @escaping @Sendable (Data, URL) throws -> Void,
        removeFile: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.removeItem(at: url)
        },
        markerURL: URL? = nil
    ) {
        self.keys = StoreKeyCache(keys, markerURL: markerURL)
        self.writeFile = writeFile
        self.removeFile = removeFile
    }

    /// Records, idempotently, that every plaintext file is sealed, so a later launch can refuse newly planted plaintext.
    public func markLegacyMigrationComplete() throws {
        try keys.markLegacyMigrationComplete(write: writeFile)
    }

    /// Reads and authenticates one JSON file, or migrates valid legacy JSON.
    public func read<Value: Decodable & Encodable & Sendable>(
        _ type: Value.Type, from url: URL, now: Date = Date()
    ) -> StoredList<Value> {
        read(type, from: url, now: now, recoveringPreviousGeneration: false)
    }

    /// Reads as above and optionally recovers a prior sealed generation for an opted-in caller.
    package func read<Value: Decodable & Encodable & Sendable>(
        _ type: Value.Type, from url: URL, now: Date = Date(),
        recoveringPreviousGeneration: Bool
    ) -> StoredList<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            if recoveringPreviousGeneration, let recovered = recover(type, from: url, now: now) {
                return .read(recovered)
            }
            return .unreadable(setAside: sealedSetAside(url, now: now))
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
                    return .unreadable(setAside: sealedSetAside(url, now: now))
                } catch {
                    Self.log.error(
                        "Encrypted store key is unavailable for \(url.lastPathComponent, privacy: .public)")
                    return .unreadable(setAside: nil)
                }
                payload = try Self.open(data, key: key, name: url.lastPathComponent)
            } else {
                switch acceptsLegacyPlaintext() {
                case .open: payload = data
                case .closed:
                    Self.log.error(
                        "Refused a plaintext \(url.lastPathComponent, privacy: .public) after encryption began"
                    )
                    return .unreadable(setAside: LocalStore.setAside(url, now: now))
                case .unknown: return .unreadable(setAside: nil)
                }
            }
            guard
                let decoded = LocalStore.decodeKeepingReadable(
                    type, from: payload, readFrom: url, now: now,
                    onPreservedOriginal: { copy, isQuarantineRecord in
                        if isEnvelope && !isQuarantineRecord { return true }
                        return sealSetAsideCopy(copy)
                    })
            else {
                if recoveringPreviousGeneration, let recovered = recover(type, from: url, now: now) {
                    return .read(recovered)
                }
                return .unreadable(setAside: sealedSetAside(url, now: now))
            }
            if decoded.droppedCount > 0, !decoded.preservationSucceeded {
                return .recovered(
                    decoded.value, droppedCount: decoded.droppedCount, quarantineRecords: [],
                    preservedOriginal: nil, preservationSucceeded: false)
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
            if decoded.droppedCount == 0 { return .read(decoded.value) }
            return .recovered(
                decoded.value, droppedCount: decoded.droppedCount,
                quarantineRecords: decoded.quarantineRecords, preservedOriginal: decoded.preservedOriginal,
                preservationSucceeded: decoded.preservationSucceeded)
        } catch {
            if isEnvelope, recoveringPreviousGeneration,
                let recovered = recover(type, from: url, now: now)
            {
                return .read(recovered)
            }
            Self.log.error(
                "Encrypted store could not be authenticated or decoded for \(url.lastPathComponent, privacy: .public)"
            )
            return .unreadable(setAside: sealedSetAside(url, now: now))
        }
    }

    /// Sets an unreadable file aside and seals a plaintext copy in place, so the copy is never readable beside the encrypted store.
    func sealedSetAside(_ url: URL, now: Date) -> URL? {
        guard let copy = LocalStore.copySetAside(url, now: now) else { return nil }
        guard sealSetAsideCopy(copy) else {
            try? FileManager.default.removeItem(at: copy)
            return nil
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return nil
        }
        return copy
    }

    /// Seals a preserved legacy plaintext copy while leaving an encrypted envelope unchanged.
    private func sealSetAsideCopy(_ copy: URL) -> Bool {
        guard let data = try? Data(contentsOf: copy) else { return false }
        if Self.isSealed(data) { return true }
        do {
            let key = try keys.key(createIfMissing: true)
            try PrivateFile.write(Self.seal(data, key: key, name: copy.lastPathComponent), to: copy)
            guard let sealed = try? Data(contentsOf: copy), Self.isSealed(sealed) else { return false }
            return true
        } catch {
            Self.log.error("Could not seal a set-aside \(copy.lastPathComponent, privacy: .public)")
            return false
        }
    }

    /// Seals JSON with filename-bound authenticated data.
    public func write<Value: Encodable & Sendable>(
        _ value: Value, to url: URL
    ) throws {
        try write(value, to: url, preservingPreviousGeneration: false)
    }

    /// Seals JSON and optionally preserves the prior generation for an opted-in caller.
    package func write<Value: Encodable & Sendable>(
        _ value: Value, to url: URL, preservingPreviousGeneration: Bool
    ) throws {
        let data = try JSONEncoder().encode(value)
        var key: SymmetricKey
        var previous: Data?
        do {
            let existing = try Data(contentsOf: url)
            guard existing.starts(with: Self.magic) else { throw StoreKeyError.legacyFileNeedsMigration }
            key = try keys.key(createIfMissing: false)
            _ = try Self.open(existing, key: key, name: url.lastPathComponent)
            previous = existing
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            key = try keys.key(createIfMissing: true)
            if preservingPreviousGeneration {
                try removeIfPresent(PrivateFile.backupURL(for: url))
                let folder = url.deletingLastPathComponent()
                if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
                    try PrivateFile.synchronizeDirectory(at: folder)
                }
            }
        }
        if preservingPreviousGeneration, let previous {
            try PrivateFile.preserveSealedGeneration(previous, from: url)
        }
        try writeFile(Self.seal(data, key: key, name: url.lastPathComponent), url)
    }

    /// Removes a store and its previous generation so a deliberate reset cannot restore deleted data.
    package func remove(_ url: URL) throws {
        let backup = PrivateFile.backupURL(for: url)
        try removeIfPresent(backup)
        let folder = url.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try PrivateFile.synchronizeDirectory(at: folder)
        }
        try removeIfPresent(url)
        if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try PrivateFile.synchronizeDirectory(at: folder)
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        do {
            try removeFile(url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
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

    /// Whether a file without the envelope header may still be a legacy file, which is only so while this installation has no key.
    public func acceptsLegacyPlaintext() -> LegacyWindow { keys.legacyWindow() }

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

    private func recover<Value: Decodable & Sendable>(
        _ type: Value.Type, from url: URL, now: Date
    ) -> Value? {
        let backupURL = PrivateFile.backupURL(for: url)
        guard let backup = try? Data(contentsOf: backupURL), backup.starts(with: Self.magic),
            let key = try? keys.key(createIfMissing: false),
            let payload = try? Self.open(backup, key: key, name: url.lastPathComponent),
            let value = try? JSONDecoder().decode(type, from: payload)
        else { return nil }

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
            LocalStore.setAside(url, now: now) == nil
        {
            return nil
        }
        do {
            try PrivateFile.restore(backup, to: url)
            Self.log.notice(
                "Restored the previous encrypted store generation for \(url.lastPathComponent, privacy: .public)"
            )
            return value
        } catch {
            Self.log.error(
                "Could not restore the previous encrypted store generation for \(url.lastPathComponent, privacy: .public)"
            )
            return nil
        }
    }
}

/// Whether plaintext may still be migrated: only in a process that found no installation key, since the key exists from the first seal on.
public enum LegacyWindow: Sendable {
    /// No key existed when this process first asked, so plaintext is a pre-encryption file.
    case open
    /// A key already existed, so plaintext was written by something other than this app.
    case closed
    /// The key could not be looked up, so the file is left untouched until it can.
    case unknown
}

/// Holds the first key a provider returns so later seals and opens skip the provider's lookup.
final class StoreKeyCache: Sendable {
    private let provider: any StoreKeyProviding
    private let cached = Mutex<SymmetricKey?>(nil)
    private let window = Mutex<LegacyWindow?>(nil)
    private let markerURL: URL?
    private let markerWritten = Mutex(false)

    init(_ provider: any StoreKeyProviding, markerURL: URL? = nil) {
        self.provider = provider
        self.markerURL = markerURL
    }

    /// Decided by this process's first lookup; stays `.open` until every plaintext store calls `markLegacyMigrationComplete`.
    func legacyWindow() -> LegacyWindow {
        if let decided = window.withLock({ $0 }) { return decided }
        do { _ = try key(createIfMissing: false) } catch {
            guard (error as? StoreKeyError)?.isMissing == true else { return .unknown }
        }
        if window.withLock({ $0 }) == .closed, !migrationMarkerPresent() {
            window.withLock { $0 = .open }
        }
        return window.withLock { $0 } ?? .unknown
    }

    /// Writes an empty marker file once per process; subsequent calls are no-ops.
    func markLegacyMigrationComplete(write: @Sendable (Data, URL) throws -> Void) throws {
        guard let url = markerURL else { return }
        let already = markerWritten.withLock { written in
            if written { return true }
            written = true
            return false
        }
        guard !already else { return }
        let folder = url.deletingLastPathComponent()
        try PrivateFile.makeDirectory(at: folder)
        try write(Data(), url)
    }

    private func migrationMarkerPresent() -> Bool {
        guard let url = markerURL else { return true }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Failures are not cached, so a key that is missing or locked now is read again on the next call.
    func key(createIfMissing: Bool) throws -> SymmetricKey {
        if let key = cached.withLock({ $0 }) { return key }
        let key: SymmetricKey
        do {
            key = try provider.key(createIfMissing: false)
            decideWindow(.closed)
        } catch let error as StoreKeyError where error.isMissing {
            decideWindow(.open)
            guard createIfMissing else { throw error }
            key = try provider.key(createIfMissing: true)
        }
        cached.withLock { $0 = key }
        return key
    }

    private func decideWindow(_ decided: LegacyWindow) {
        window.withLock { current in if current == nil { current = decided } }
    }

    func revokeKey() throws {
        guard let revoking = provider as? any StoreKeyRevoking else {
            throw StoreKeyError.revocationUnsupported
        }
        defer {
            cached.withLock { $0 = nil }
            window.withLock { $0 = nil }
        }
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
