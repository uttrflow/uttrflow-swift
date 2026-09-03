import Foundation

/// Recognises a credential, and is deliberately keener to say yes than no.
///
/// The two ways of being wrong here do not cost the same. A false positive masks
/// something harmless: the row shows dots, the user presses Return and the clip is
/// pasted exactly as it always was, and one keystroke reveals it if they want to read
/// it. A false negative leaves a live production password legible on a panel that gets
/// opened in meetings, on shared screens and on recorded calls. So every threshold
/// below is set where a plausible secret is caught even when a plausible non-secret
/// comes with it, and the rules are ordered cheapest-first only because they are all
/// consulted anyway.
///
/// The rules are shapes, not entropy alone. A shape — `ghp_`, `eyJ`, `-----BEGIN` — is
/// exact and ages well, and the statistical rule at the end is the net beneath them for
/// the tokens nobody has standardised.
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

    /// The first line of any PEM object. Certificates are caught alongside private keys
    /// and that is fine: a certificate masked costs a preview, and telling the two apart
    /// by their label is one label away from being wrong about the one that matters.
    private static let pemHeader = "-----BEGIN"

    /// A JWT: three base64url segments, the first of which begins `eyJ` because that is
    /// what `{"` encodes to, and every JWT header is an object.
    ///
    /// Matched anywhere in the text rather than as the whole of it, so that
    /// `Authorization: Bearer eyJ…` — how a token is usually copied — is caught too. The
    /// signature is allowed to be empty, because an `alg: none` token is still something
    /// nobody should read off a screen.
    nonisolated(unsafe) private static let jsonWebToken =
        #/eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*/#

    /// A connection string carrying a username and password: `scheme://user:pass@host`.
    ///
    /// The password is what makes it a secret, so the userinfo must have a colon in it.
    /// That is what keeps `https://example.com:8443/path` out — the colon there is
    /// before a port, and there is no `@` — and keeps `https://token@github.com/repo`
    /// out too, which carries a username and no password.
    nonisolated(unsafe) private static let credentialledURL =
        #/[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s:/@]+:[^\s:/@]+@\S/#

    /// Keys whose issuers gave them a prefix, which is the most reliable signal there is.
    ///
    /// Every entry pairs a prefix with a minimum length, so that the prefix appearing in
    /// prose — someone writing about `sk-` keys — is not itself mistaken for one.
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

    /// `API_KEY=…`, `password: …`, `client_secret = …` — the shape of an environment
    /// file, a configuration line and a pasted credential alike.
    ///
    /// Anchored to the end of a *line* rather than the end of the text, so that a whole
    /// `.env` file pasted in one go is caught by any one of its lines.
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

    /// Whether any line names a secret and then gives one.
    ///
    /// The value has to earn it. `var password: String` names a secret and supplies only
    /// a type, and masking every model in the codebase that has a password field would
    /// be noise rather than protection. So a value counts when it is quoted, or has a
    /// digit in it, or is long — which `String`, `nil` and `true` are not, and which a
    /// real credential essentially always is.
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

    /// The shortest token the statistical rule will look at.
    ///
    /// Below this, randomness cannot be told from a long identifier: a 20-character
    /// token and `applicationDidFinishLaunching` score alike, and the rule would spend
    /// its accuracy on strings nobody was trying to protect.
    private static let entropicTokenLength = 24

    /// Bits per character above which a token is treated as generated rather than
    /// written.
    ///
    /// Measured, not chosen. Over three thousand random base64 strings at each length,
    /// a floor of 4.0 catches 96% of 24-character tokens and everything longer, while
    /// 3.8 catches 99.8% of 24-character tokens and everything longer. The four
    /// percentage points between them are the shortest, unluckiest, most repetitive
    /// keys — and a key is no less live for having drawn a repeated character.
    ///
    /// So 3.8, and the cost is paid knowingly: long identifiers with a digit in them
    /// score between 3.7 and 4.1, so `invoice_2024_q3_final_v2_signed` is masked and so
    /// is a deep source path. That is the trade this whole file is built on. A masked
    /// row still pastes on Return and reveals on one keystroke; an unmasked key is on
    /// the screen of whoever is watching.
    private static let entropyFloor = 3.8

    /// Whether any single word on a one-line clip looks generated.
    ///
    /// Only one-line clips, and deliberately. A multi-line clip is a document, a diff or
    /// a source file, and those legitimately carry commit hashes, checksums and encoded
    /// blobs; masking a whole file because one line of it contains a digest would hide
    /// far more than it protected. What multi-line clips do carry — `.env` lines, PEM
    /// blocks, bearer headers — every rule above already catches by shape.
    private static func hasHighEntropyToken(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        return text.split(whereSeparator: \.isWhitespace).contains { looksGenerated(String($0)) }
    }

    private static func looksGenerated(_ token: String) -> Bool {
        guard !isPathLike(token) else { return false }

        // Hex gets its own rule because its alphabet is only sixteen symbols wide, so it
        // can never reach the general floor however random it is.
        if token.count >= hexTokenLength, token.allSatisfy(\.isHexDigit) { return true }

        guard token.count >= entropicTokenLength,
            token.allSatisfy(isTokenCharacter),
            token.contains(where: \.isNumber),
            token.contains(where: \.isLetter)
        else { return false }
        return entropy(of: token) >= entropyFloor
    }

    /// The alphabet every generated token is drawn from: base64, base64url and hex all
    /// fit inside it. Requiring the *whole* token to fit is what excludes prose, since
    /// a full stop, a comma or a colon anywhere in it is disqualifying.
    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter && character.isASCII
            || character.isNumber && character.isASCII
            || "+/=_-".contains(character)
    }

    /// A path shares its alphabet with base64 — slashes, dashes, digits — and a deep
    /// one is long enough to be mistaken for a key. Anything that opens like a path is
    /// left to the general rules, which will call it text.
    private static func isPathLike(_ token: String) -> Bool {
        token.hasPrefix("/") || token.hasPrefix("~/") || token.hasPrefix("./")
            || token.hasPrefix("../") || token.contains("://")
    }

    /// Shannon entropy of the token's own characters, in bits per character.
    ///
    /// Of the string itself rather than of an assumed alphabet, because that is the
    /// question being asked: a token drawn at random uses most of its symbols once,
    /// where a word or a path repeats a handful of letters many times over.
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
