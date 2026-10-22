// Recognises an authenticator seed carried in a URI.

import Foundation

/// An `otpauth://` or `otpauth-migration://` URI, whose `secret` or `data` generates every future one-time code.
enum AuthenticatorSeedShape {
    private static let schemes = ["otpauth://", "otpauth-migration://"]
    private static let seedParameters: Set<String> = ["secret", "data"]

    /// Whether any URI in the text names one of the schemes and carries a non-empty seed parameter.
    static func matches(_ text: String, read: inout Int) -> Bool {
        read += text.utf8.count
        for scheme in schemes {
            var from = text.startIndex
            while let found = text.range(of: scheme, options: .caseInsensitive, range: from..<text.endIndex) {
                let uri = text[found.upperBound...].prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
                if hasSeed(uri) { return true }
                from = found.upperBound
            }
        }
        return false
    }

    /// Whether the query of a URI holds a seed parameter with a value.
    private static func hasSeed(_ uri: Substring) -> Bool {
        guard let query = uri.firstIndex(of: "?") else { return false }
        return uri[uri.index(after: query)...].split(whereSeparator: { $0 == "&" || $0 == ";" }).contains {
            pair in
            let name = pair.prefix { $0 != "=" }
            return seedParameters.contains(name.lowercased()) && pair.count > name.count + 1
        }
    }
}
