// How a forgotten line is remembered without being kept: a keyed digest that matches it and reveals nothing.
private import CryptoKit
private import Foundation
import UttrflowCore

/// Turns a line into the marker that keeps it forgotten, keyed so the marker cannot be checked against a guess.
struct ForgottenMarker {
    /// Separates this digest from every other use of the installation key.
    static let purpose = "com.uttrflow.predict.forgotten.v1"

    private let digest: (Data) throws -> Data

    /// Keys with the shared local-store key, or with a secret made once per corpus where none is supplied.
    init(_ database: Database) throws(PredictStoreError) {
        if let encryptedStore = database.encryptedStore {
            digest = { try encryptedStore.keyedDigest(of: $0, purpose: Self.purpose) }
            return
        }
        let key = try Self.installSecret(in: database)
        digest = { Data(HMAC<SHA256>.authenticationCode(for: $0, using: key)) }
    }

    /// The marker for one canonical line, as lowercase hex.
    func callAsFunction(_ text: String) throws(PredictStoreError) -> String {
        do {
            return try digest(Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        } catch {
            throw .query("the key that keeps lines forgotten is unavailable")
        }
    }

    /// Reads the corpus's own secret, creating it on first use.
    private static func installSecret(in database: Database) throws(PredictStoreError) -> SymmetricKey {
        let stored = try database.rows("SELECT secret FROM install_secret LIMIT 1", { _ in }) { $0.text(0) }
        if let encoded = stored.first, let data = Data(base64Encoded: encoded) {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let encoded = key.withUnsafeBytes { Data($0).base64EncodedString() }
        try database.execute("DELETE FROM install_secret")
        try database.run("INSERT INTO install_secret (secret) VALUES (?)") { $0.bind(1, encoded) }
        return key
    }
}
