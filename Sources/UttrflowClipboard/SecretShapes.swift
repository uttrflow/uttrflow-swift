// Recognises a credential.

import Foundation

/// Recognises a credential, keener to say yes than no. See Docs/clipboard-secrets.md.
public enum SecretShapes {
    /// Counts the characters the single-pass readers take while bound, so a test can bound the work without a clock.
    @TaskLocal package static var tally: ScanTally?

    public static func matches(_ text: String) -> Bool {
        if text.contains(pemHeader) { return true }
        if hasJSONWebToken(text) { return true }
        if hasCredentialledURL(text) { return true }
        if text.firstMatch(of: vendorKey) != nil { return true }
        if hasNamedSecret(text) { return true }
        if CardNumberShape.matches(text) { return true }
        return hasHighEntropyToken(text)
    }

    // MARK: - Exact shapes

    /// The first line of any PEM object; certificates are masked alongside keys, and that is fine.
    private static let pemHeader = "-----BEGIN"

    /// A JWT anywhere in the text, so `Bearer eyJ…` is caught; the signature may be empty.
    static func hasJSONWebToken(_ text: String) -> Bool {
        var read = 0
        defer { tally?.record(read) }
        return JSONWebTokenScan.matches(text, read: &read)
    }

    /// A connection string carrying a password, which needs a colon in the userinfo before the `@`.
    static func hasCredentialledURL(_ text: String) -> Bool {
        var read = 0
        defer { tally?.record(read) }
        return CredentialledURLScan.matches(text, read: &read)
    }

    /// Keys whose issuers gave them a prefix, each with a minimum length so prose about `sk-` is not one.
    nonisolated(unsafe) static let vendorKey =
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

    /// Whether any line names a secret and gives one, as `API_KEY=…` does; `var password: String` supplies only a type.
    static func hasNamedSecret(_ text: String) -> Bool {
        var scan = NamedSecretScan(text)
        defer { tally?.record(scan.read) }
        return scan.matches()
    }

    // MARK: - A secret because of how it looks

    /// Hex long enough to be a digest or a key rather than a number.
    private static let hexTokenLength = 32

    /// The shortest token the statistical rule looks at; below it randomness reads like an identifier.
    private static let entropicTokenLength = 24

    /// Bits per character above which a token counts as generated; measured. See Docs/clipboard-secrets.md.
    private static let entropyFloor = 3.8

    /// Whether any word on a one-line clip looks generated; multi-line clips are documents, left alone.
    static func hasHighEntropyToken(_ text: String) -> Bool {
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
