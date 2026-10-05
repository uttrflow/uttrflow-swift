import Foundation

/// Recognises Docker config's base64-encoded `user:password` credential field.
enum DockerAuthShape {
    /// Whether a JSON `auth` value decodes to a nonempty user and password pair.
    static func matches(_ text: String) -> Bool {
        for match in text.matches(of: #/"auth"\s*:\s*"([A-Za-z0-9+/]+={0,2})"/#) {
            guard let data = Data(base64Encoded: String(match.1)),
                let credential = String(data: data, encoding: .utf8),
                let separator = credential.firstIndex(of: ":"),
                separator > credential.startIndex,
                credential.index(after: separator) < credential.endIndex
            else { continue }
            return true
        }
        return false
    }
}
