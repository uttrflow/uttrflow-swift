// Recognises a credential.

import Foundation

/// Recognises a credential, keener to say yes than no. See Docs/clipboard-secrets.md.
public enum SecretShapes {
    /// Counts the characters the single-pass readers take while bound, so a test can bound the work without a clock.
    @TaskLocal package static var tally: ScanTally?

    /// Counts the characters handed to the vendor-key and card-number patterns while bound.
    @TaskLocal package static var patternTally: ScanTally?

    public static func matches(_ text: String) -> Bool {
        var text = text
        text.makeContiguousUTF8()
        // Each shape below needs its literal in the bytes, so a clip without one skips that reading.
        let literals = ClipBytes.read(text) { _, bytes in
            (
                pem: ClipBytes.contains(bytes, "-----BEGIN"), jwt: ClipBytes.contains(bytes, "eyJ"),
                url: ClipBytes.contains(bytes, "://")
            )
        }
        if literals.pem, text.contains(pemHeader) { return true }
        if literals.jwt, hasJSONWebToken(text) { return true }
        if literals.url, hasCredentialledURL(text) { return true }
        if VendorKeyWindows.matches(text, pattern: vendorKey, tally: patternTally) { return true }
        if NamedSecretStems.present(in: text), hasNamedSecret(text) { return true }
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
        ClipBytes.read(text) { _, bytes in asciiHighEntropyToken(bytes) }
            ?? hasHighEntropyTokenByCharacter(text)
    }

    /// The statistical rule read character by character, which any clip can be.
    static func hasHighEntropyTokenByCharacter(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        return text.split(whereSeparator: \.isWhitespace).contains { looksGenerated(String($0)) }
    }

    /// The statistical rule read over the bytes of an ASCII clip, where a byte is a character; `nil` for any other clip.
    private static func asciiHighEntropyToken(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard ClipBytes.isASCII(bytes) else { return nil }
        guard !bytes.contains(where: { (0x0A...0x0D).contains($0) }) else { return false }
        var start = 0
        for offset in 0...bytes.count
        where offset == bytes.count || bytes[offset] == 0x20 || bytes[offset] == 0x09 {
            if offset > start, looksGenerated(UnsafeBufferPointer(rebasing: bytes[start..<offset])) {
                return true
            }
            start = offset + 1
        }
        return false
    }

    /// `looksGenerated` for an ASCII token, byte for character.
    private static func looksGenerated(_ token: UnsafeBufferPointer<UInt8>) -> Bool {
        func opens(_ prefix: StaticString) -> Bool {
            token.count >= prefix.utf8CodeUnitCount
                && (0..<prefix.utf8CodeUnitCount).allSatisfy { token[$0] == prefix.utf8Start[$0] }
        }
        guard !(opens("/") || opens("~/") || opens("./") || opens("../") || ClipBytes.contains(token, "://"))
        else { return false }
        func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
        func isLetter(_ byte: UInt8) -> Bool { (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) }
        if token.count >= hexTokenLength,
            token.allSatisfy({ isDigit($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0) })
        {
            return true
        }
        guard token.count >= entropicTokenLength,
            token.allSatisfy({ isDigit($0) || isLetter($0) || "+/=_-".utf8.contains($0) }),
            token.contains(where: isDigit),
            token.contains(where: isLetter)
        else { return false }
        var counts = [Int](repeating: 0, count: 128)
        for byte in token { counts[Int(byte)] += 1 }
        let length = Double(token.count)
        let bits = counts.reduce(into: 0.0) { total, count in
            guard count > 0 else { return }
            let share = Double(count) / length
            total -= share * log2(share)
        }
        return bits >= entropyFloor
    }

    private static func looksGenerated(_ token: String) -> Bool {
        guard !isPathLike(token) else { return false }

        // Hex has a sixteen-symbol alphabet and can never reach the general floor.
        if token.count >= hexTokenLength, token.allSatisfy({ $0.isHexDigit && $0.isASCII }) { return true }

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
