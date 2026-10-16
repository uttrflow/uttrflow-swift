// Recognises an authenticator seed carried in an `otpauth` address.

import Foundation

/// An `otpauth://` or `otpauth-migration://` address, whose `secret` or `data` value generates every one-time code. See Docs/clipboard-secrets.md.
enum AuthenticatorSeedShape {
    /// The fewest characters a seed needs to be one rather than a placeholder.
    private static let shortestSeed = 8

    /// Whether any address in the text is an authenticator seed, reading each address once.
    static func matches(_ text: String) -> Bool {
        var rest = Substring(text)
        while let scheme = rest.range(of: "otpauth", options: .caseInsensitive) {
            let address = rest[scheme.lowerBound...].prefix { !$0.isWhitespace && $0 != "\"" && $0 != "'" }
            rest = rest[scheme.upperBound...]
            let lowered = address.lowercased()
            guard lowered.hasPrefix("otpauth://") || lowered.hasPrefix("otpauth-migration://"),
                let query = address.firstIndex(of: "?")
            else { continue }
            let hasSeed = address[address.index(after: query)...].split(separator: "&").contains { pair in
                let name = pair.prefix { $0 != "=" }.lowercased()
                let value = String(pair.dropFirst(name.count + 1))
                return (name == "secret" || name == "data") && value.count >= shortestSeed
                    && !CredentialPlaceholder.matches(value)
            }
            if hasSeed { return true }
        }
        return false
    }
}
