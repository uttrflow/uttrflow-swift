// The user's own answer to whether a text is a secret, which outranks the detector's guess.

import CryptoKit
import Foundation
import UttrflowCore

/// What the not-secret file holds: keyed digests of texts the user unmasked, never the texts.
struct NotSecretIndex: Codable, Sendable, Equatable {
    static let currentVersion = 1

    let version: Int
    let digests: [String]
}

/// The user's answers about which texts are secrets; only "not a secret" crosses a launch. See `Docs/clipboard-secrets.md`.
struct ClipSecrecyOverrides {
    /// Separates these digests from every other keyed hash made with the installation key.
    static let purpose = "com.uttrflow.clipboard.not-secret.v1"

    private let file: URL
    private let encryptedStore: EncryptedStore?

    /// The persisted "not a secret" answers, or `nil` before the file has been read.
    private var notSecret: Set<String>?
    /// The "treat as secret" answers given in this process, never written, because a secret leaves nothing on disk.
    private var secret: Set<String> = []
    /// Whether the file holds answers this build could not read, so it must not be replaced.
    private var isUnreadable = false

    init(file: URL, encryptedStore: EncryptedStore?) {
        self.file = file
        self.encryptedStore = encryptedStore
    }

    /// The clip with the user's answer about its text in place of the detector's, when there is one.
    mutating func applied(to clip: Clip) -> Clip {
        guard clip.image == nil else { return clip }
        if clip.kind == .secret {
            let answers = persisted()
            guard !answers.isEmpty, let digest = digest(of: clip.text), answers.contains(digest) else {
                return clip
            }
            return clip.reclassified(as: ClipKindDetector.classification(of: clip.text, askingSecret: false))
        }
        guard !secret.isEmpty, let digest = digest(of: clip.text), secret.contains(digest) else {
            return clip
        }
        return clip.reclassified(as: ClipClassification(kind: .secret, language: nil))
    }

    /// Records that `text` is not a secret, on disk before any clip relies on it.
    mutating func markNotSecret(_ text: String) throws(ClipboardStoreError) {
        guard let digest = digest(of: text) else { throw .couldNotWrite }
        var answers = persisted()
        answers.insert(digest)
        try write(answers)
        secret.remove(digest)
    }

    /// Records that `text` is a secret for this process and withdraws any earlier "not a secret".
    mutating func markSecret(_ text: String) throws(ClipboardStoreError) {
        guard let digest = digest(of: text) else { throw .couldNotWrite }
        var answers = persisted()
        if answers.remove(digest) != nil { try write(answers) }
        secret.insert(digest)
    }

    /// Forgets every answer, on disk and in memory, as resetting personalisation promises.
    mutating func forget() throws(ClipboardStoreError) {
        do {
            try removeFile()
            try LocalStore.removeSetAside(file)
        } catch {
            throw ClipboardStore.writeFailure(error)
        }
        notSecret = []
        secret = []
        isUnreadable = false
    }

    /// Whether the persisted answers are known, so a stored clip may be judged without them.
    mutating func areKnown() -> Bool {
        _ = persisted()
        return !isUnreadable
    }

    /// The persisted answers, read from the file once.
    private mutating func persisted() -> Set<String> {
        if let notSecret { return notSecret }
        let stored =
            encryptedStore.map { $0.read(NotSecretIndex.self, from: file) }
            ?? LocalStore.read(NotSecretIndex.self, from: file)
        // A newer build's answers are still answers; only rewriting them, or an unreadable file, is refused.
        switch stored {
        case .missing: break
        default: isUnreadable = (stored.value?.version ?? .max) > NotSecretIndex.currentVersion
        }
        let answers = Set(stored.value?.digests ?? [])
        notSecret = answers
        return answers
    }

    /// Writes the whole set, or removes the file when it is empty; memory changes only once the disk has.
    private mutating func write(_ answers: Set<String>) throws(ClipboardStoreError) {
        // A file still there and unreadable may hold answers, so it is never replaced.
        guard !isUnreadable || !FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
        else { throw .couldNotWrite }
        do {
            if answers.isEmpty {
                try removeFile()
            } else {
                let index = NotSecretIndex(version: NotSecretIndex.currentVersion, digests: answers.sorted())
                if let encryptedStore {
                    try encryptedStore.write(index, to: file)
                } else {
                    try PrivateFile.write(JSONEncoder().encode(index), to: file)
                }
            }
        } catch {
            throw ClipboardStore.writeFailure(error)
        }
        notSecret = answers
        isUnreadable = false
    }

    private func removeFile() throws {
        if let encryptedStore { return try encryptedStore.remove(file) }
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// A keyed digest under the installation key; a store built without one, in tests and tools, uses a plain one.
    private func digest(of text: String) -> String? {
        if let encryptedStore { return try? encryptedStore.digest(of: text, for: Self.purpose) }
        let hash = SHA256.hash(data: Data((Self.purpose + "\n" + text).utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
