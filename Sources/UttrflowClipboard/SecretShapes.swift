// Recognises a credential.

import Foundation

/// Recognises a credential, keener to say yes than no. See Docs/clipboard-secrets.md.
public enum SecretShapes {
    public static func matches(_ text: String) -> Bool {
        if text.contains(pemHeader) { return true }
        if text.firstMatch(of: jsonWebToken) != nil { return true }
        if text.firstMatch(of: credentialledURL) != nil { return true }
        if text.firstMatch(of: vendorKey) != nil { return true }
        if hasNamedSecret(text) { return true }
        return hasHighEntropyToken(text)
    }

    // MARK: - Exact shapes

    /// The first line of any PEM object; certificates are masked alongside keys, and that is fine.
    private static let pemHeader = "-----BEGIN"

    /// A JWT anywhere in the text, so `Bearer eyJ…` is caught; the signature may be empty.
    nonisolated(unsafe) private static let jsonWebToken =
        #/eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*/#

    /// A connection string carrying a password, which needs a colon in the userinfo before the `@`.
    nonisolated(unsafe) private static let credentialledURL =
        #/[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s:/@]+:[^\s:/@]+@\S/#

    /// Keys whose issuers gave them a prefix, each with a minimum length so prose about `sk-` is not one.
    nonisolated(unsafe) private static let vendorKey =
        #/
        sk-(?:ant-)?[A-Za-z0-9_\-]{16,}          # OpenAI, Anthropic
        | (?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{10,}   # Stripe
        | gh[pousr]_[A-Za-z0-9]{16,}             # GitHub, short form
        | github_pat_[A-Za-z0-9_]{20,}           # GitHub, fine-grained
        | glpat-[A-Za-z0-9_\-]{16,}              # GitLab
        | xox[baprse]-[A-Za-z0-9\-]{10,}         # Slack
        | (?:AKIA|ASIA)[0-9A-Z]{16}              # AWS access key id
        | AIza[0-9A-Za-z_\-]{35}                 # Google
        | npm_[A-Za-z0-9]{30,}                   # npm
        | dop_v1_[a-f0-9]{40,}                   # DigitalOcean
        | shpat_[a-fA-F0-9]{32}                  # Shopify
        | SG\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}  # SendGrid
        /#

    // MARK: - A secret because of what it is called

    /// `API_KEY=…`, `password: …`, `client_secret = …`, anchored per line so a whole `.env` is caught.
    nonisolated(unsafe) private static let namedSecret =
        #/
        (?i)
        \b(?: api[_\-]?keys? | secrets? | tokens? | passwords? | passwd | pwd
            | credentials? | private[_\-]?key | access[_\-]?key | auth[_\-]?token
            | client[_\-]?secret )
        \b["']? \s* [:=] \s*
        (?<value> "[^"\n]+" | '[^'\n]+' | [^\s"'\n]+ )
        \s*[,;]?\s*$
        /#
        .anchorsMatchLineEndings()

    /// Whether any line names a secret and gives one; `var password: String` supplies only a type.
    private static func hasNamedSecret(_ text: String) -> Bool {
        text.matches(of: namedSecret).contains { match in
            let raw = String(match.value)
            let isQuoted = raw.count >= 2 && (raw.hasPrefix("\"") || raw.hasPrefix("'"))
            let value = isQuoted ? String(raw.dropFirst().dropLast()) : raw
            return isQuoted || value.contains(where: \.isNumber) || value.count >= 12
        }
    }

    // MARK: - A secret because of how it looks

    /// Hex long enough to be a digest or a key rather than a number.
    private static let hexTokenLength = 32

    /// The shortest token the statistical rule looks at; below it randomness reads like an identifier.
    private static let entropicTokenLength = 24

    /// Bits per character above which a token counts as generated; measured. See Docs/clipboard-secrets.md.
    private static let entropyFloor = 3.8

    /// Whether any word on a one-line clip looks generated; multi-line clips are documents, left alone.
    private static func hasHighEntropyToken(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        return text.split(whereSeparator: \.isWhitespace).contains { looksGenerated(String($0)) }
    }

    private static func looksGenerated(_ token: String) -> Bool {
        guard !isPathLike(token) else { return false }

        // Hex has a sixteen-symbol alphabet and can never reach the general floor.
        if token.count >= hexTokenLength, token.allSatisfy(\.isHexDigit) { return true }

        guard token.count >= entropicTokenLength,
            token.allSatisfy(isTokenCharacter),
            token.contains(where: \.isNumber),
            token.contains(where: \.isLetter)
        else { return false }
        return entropy(of: token) >= entropyFloor
    }

    /// The alphabet every generated token is drawn from; a full stop or comma anywhere disqualifies.
    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter && character.isASCII
            || character.isNumber && character.isASCII
            || "+/=_-".contains(character)
    }

    /// A path shares base64's alphabet, so anything that opens like one is left to the general rules.
    private static func isPathLike(_ token: String) -> Bool {
        PathShape.starts.contains(where: token.hasPrefix) || token.contains("://")
    }

    /// Shannon entropy of the token's own characters, in bits per character.
    private static func entropy(of token: String) -> Double {
        var counts: [Character: Int] = [:]
        for character in token { counts[character, default: 0] += 1 }
        let length = Double(token.count)
        return counts.values.reduce(into: 0.0) { total, count in
            let share = Double(count) / length
            total -= share * log2(share)
        }
    }
}
