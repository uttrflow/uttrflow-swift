// A stable identity for the exact audio a passage was scored from.
public import Foundation
private import CryptoKit

/// Identifies the recording a score rests on, so a baseline tells a new take from its own (Docs/eval-methodology.md).
public enum RecordingIdentity {
    /// A digest of `audio`'s bytes, prefixed so it is never confused with ``forCatalogueSample(s3Key:)``.
    public static func digest(of audio: Data) -> String {
        "sha256:" + SHA256.hash(data: audio).map { String(format: "%02x", $0) }.joined()
    }

    /// The catalogue's key for a sample, as stable as a digest without the harness holding the bytes.
    public static func forCatalogueSample(s3Key: String) -> String {
        "s3:\(s3Key)"
    }
}
