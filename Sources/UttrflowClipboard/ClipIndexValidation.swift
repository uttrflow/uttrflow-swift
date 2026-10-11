// Inspects clipboard indexes before a cached store can replace their contents.

import Foundation
import UttrflowCore

/// Validates an index without changing its bytes or the store's bookkeeping.
enum ClipIndexValidation {
    /// Returns an unsupported version, or nil when the encoded index is supported.
    static func inspect(
        _ data: Data, fileName: String, using encryptedStore: EncryptedStore?
    ) throws(ClipboardStoreError) -> Int? {
        guard EncryptedStore.isSealed(data) else { return try inspectPayload(data) }
        guard data.count > EncryptedStore.sealedHeaderLength else { throw .couldNotWrite }
        let version = data[EncryptedStore.sealedHeaderLength]
        guard version == EncryptedStore.currentEnvelopeVersion else { return Int(version) }
        // Without its key an existing sealed index cannot be inspected safely.
        guard let encryptedStore else { throw .couldNotWrite }
        let payload: Data
        do {
            payload = try encryptedStore.open(data, for: fileName)
        } catch {
            // An unavailable key and failed authentication both leave the index opaque.
            throw .couldNotWrite
        }
        return try inspectPayload(payload)
    }

    /// Checks payload shape before decoding could discard unknown fields.
    private static func inspectPayload(_ payload: Data) throws(ClipboardStoreError) -> Int? {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: payload)
        } catch {
            throw .couldNotWrite
        }
        // A bare array is the only supported unversioned clipboard payload.
        if root is [Any] {
            try validateSupportedPayload(payload)
            return nil
        }
        guard let object = root as? [String: Any], let version = object["version"] as? Int else {
            throw .couldNotWrite
        }
        guard version == 1 || version == ClipboardIndex.currentVersion else { return version }
        try validateSupportedPayload(payload)
        return nil
    }

    /// Requires both known keys and decodable records before allowing replacement.
    private static func validateSupportedPayload(_ payload: Data) throws(ClipboardStoreError) {
        guard ClipboardIndex.containsOnlyKnownJSONKeys(in: payload),
            (try? JSONDecoder().decode(ClipboardIndex.self, from: payload)) != nil
        else { throw .couldNotWrite }
    }
}
