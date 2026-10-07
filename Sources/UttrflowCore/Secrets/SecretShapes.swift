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
                url: ClipBytes.contains(bytes, "://") || ClipBytes.contains(bytes, "hooks.slack.com"),
                dockerAuth: ClipBytes.contains(bytes, "\"auth\"")
            )
        }
        if literals.pem, text.contains(pemHeader) { return true }
        if literals.jwt, hasJSONWebToken(text) { return true }
        if literals.dockerAuth, DockerAuthShape.matches(text) { return true }
        if literals.url, hasCredentialledURL(text) || hasBearerURL(text) || hasTokenUserinfoURL(text) {
            return true
        }
        if VendorKeyWindows.matches(text, pattern: vendorKey, tally: patternTally) { return true }
        if NamedSecretStems.present(in: text), hasNamedSecret(text) { return true }
        if CardNumberShape.matches(text) { return true }
        if hasCommandCredential(text) { return true }
        if BIP39RecoveryPhrase.matches(text) { return true }
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

    /// A URL whose userinfo is one generated token with no colon, as `https://<token>@host/repo` carries it.
    static func hasTokenUserinfoURL(_ text: String) -> Bool {
        var read = 0
        defer { tally?.record(read) }
        var rest = Substring(text)
        while let scheme = rest.firstRange(of: "://") {
            let userinfo = rest[scheme.upperBound...].prefix { !($0.isWhitespace || "/@:".contains($0)) }
            read += 3 + userinfo.count
            let after = userinfo.endIndex
            if after < rest.endIndex, rest[after] == "@", rest.index(after: after) < rest.endIndex,
                !rest[rest.index(after: after)].isWhitespace, looksGenerated(String(userinfo))
            {
                return true
            }
            rest = rest[after...]
        }
        return false
    }

    /// A password handed to a command as an argument, or an authorization header's value.
    static func hasCommandCredential(_ text: String) -> Bool {
        var read = 0
        defer { tally?.record(read) }
        return CommandCredentialShape.matches(text, read: &read)
    }

    /// A chat webhook, or a URL signed or carrying a token, which acts for whoever holds it.
    static func hasBearerURL(_ text: String) -> Bool {
        var read = 0
        defer { tally?.record(read) }
        return BearerURLShape.matches(text, read: &read)
    }

    /// Keys whose issuers gave them a prefix, each with a minimum length so prose about `sk-` is not one; built from `VendorKeyPrefixes`, with simple word boundaries so a window cut before `x.sk-` reads as the whole clip does.
    nonisolated(unsafe) static let vendorKey: Regex<Substring> =
        ((try? Regex(VendorKeyPrefixes.patternSource, as: Substring.self))
        ?? Regex(verbatim: "\u{0}\u{0}never")).wordBoundaryKind(.simple)

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

    /// The shortest single-token password the statistical rule looks at; below it randomness reads like an identifier.
    private static let entropicTokenLength = 12

    /// Bits per character above which a token counts as generated; measured. See Docs/clipboard-secrets.md.
    private static let entropyFloor = 3.8

    /// Data payloads and package integrity digests are encoded content, not credentials.
    private static func isNonCredentialEntropyValue(_ token: String) -> Bool {
        if isBase64DataURIValue(token) { return true }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"',"))
        guard value.hasPrefix("sha"), let separator = value.firstIndex(of: "-") else { return false }
        let algorithm = value[..<separator]
        guard let bits = Int(algorithm.dropFirst(3)), [256, 384, 512].contains(bits),
            let digest = Data(base64Encoded: String(value[value.index(after: separator)...]))
        else { return false }
        return digest.count == bits / 8
    }

    /// Recognises a complete data URI, including common HTML and CSS wrappers copied with one word.
    private static func isBase64DataURIValue(_ token: String) -> Bool {
        if token.prefix(5).lowercased() == "data:" {
            return isValidBase64DataURI(token[...])
        }

        if token.lowercased().hasPrefix("src=") {
            var value = String(token.dropFirst(4))
            if value.hasSuffix(">") {
                value.removeLast()
                if value.hasSuffix("/") { value.removeLast() }
            }
            if let quote = value.first, quote == "\"" || quote == "'" {
                guard value.last == quote else { return false }
                value.removeFirst()
                value.removeLast()
            }
            return isValidBase64DataURI(value[...])
        }

        guard let url = token.range(of: "url(", options: .caseInsensitive) else { return false }
        let property = token[..<url.lowerBound]
        guard property.isEmpty || property.hasSuffix(":") else { return false }

        var contents = String(token[url.upperBound...])
        if contents.hasSuffix("}") { contents.removeLast() }
        if contents.hasSuffix(";") { contents.removeLast() }
        guard contents.hasSuffix(")") else { return false }
        contents.removeLast()
        if let quote = contents.first, quote == "\"" || quote == "'" {
            guard contents.last == quote else { return false }
            contents.removeFirst()
            contents.removeLast()
        }
        return isValidBase64DataURI(contents[...])
    }

    /// Requires a MIME type, the base64 marker and a decodable payload before exempting entropy.
    private static func isValidBase64DataURI(_ uri: Substring) -> Bool {
        guard uri.prefix(5).lowercased() == "data:", let comma = uri.firstIndex(of: ",") else { return false }
        let metadataStart = uri.index(uri.startIndex, offsetBy: 5)
        let metadata = uri[metadataStart..<comma]
        guard metadata.lowercased().hasSuffix(";base64") else { return false }
        let fields = metadata.dropLast(";base64".count).split(
            separator: ";", omittingEmptySubsequences: false)
        let parameters: ArraySlice<Substring>
        if let first = fields.first, !first.isEmpty {
            let mime = first.split(separator: "/", omittingEmptySubsequences: false)
            guard mime.count == 2, mime.allSatisfy(isMIMEComponent) else { return false }
            parameters = fields.dropFirst()
        } else {
            parameters = fields.dropFirst()
        }
        guard parameters.allSatisfy(isMIMEParameter) else { return false }
        return Data(base64Encoded: String(uri[uri.index(after: comma)...])) != nil
    }

    /// Checks one MIME type component or parameter against the ASCII token characters.
    private static func isMIMEComponent(_ value: Substring) -> Bool {
        let punctuation = "!#$%&'*+-.^_`|~"
        return !value.isEmpty
            && value.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || punctuation.contains($0))
            }
    }

    /// Requires each media-type parameter to have a nonempty token name and value.
    private static func isMIMEParameter(_ value: Substring) -> Bool {
        let pair = value.split(separator: "=", omittingEmptySubsequences: false)
        return pair.count == 2 && pair.allSatisfy(isMIMEComponent)
    }

    /// URI schemes whose opaque forms are ordinary links rather than generated credentials.
    private static let entropyExemptURISchemes: Set<String> = ["mailto", "spotify", "magnet", "urn", "tel"]

    /// Whether any word on a one-line clip looks generated; multi-line clips are documents, left alone.
    static func hasHighEntropyToken(_ text: String) -> Bool {
        guard !isQuotedPath(text),
            !DeveloperReferenceShape.isCompleteWindowsPath(text)
        else { return false }
        return ClipBytes.read(text) { _, bytes in asciiHighEntropyToken(bytes) }
            ?? hasHighEntropyTokenByCharacter(text)
    }

    /// The statistical rule read character by character, which any clip can be.
    static func hasHighEntropyTokenByCharacter(_ text: String) -> Bool {
        guard !isQuotedPath(text),
            !DeveloperReferenceShape.isCompleteWindowsPath(text)
        else { return false }
        guard !text.contains(where: \.isNewline) else { return false }
        return text.split(whereSeparator: \.isWhitespace).contains { word in
            var run: [UInt8] = []
            for scalar in word.unicodeScalars {
                guard scalar.isASCII else {
                    let value = String(decoding: run, as: UTF8.self)
                    if wordLooksGenerated(run) && !isNonCredentialEntropyValue(value) { return true }
                    run.removeAll(keepingCapacity: true)
                    continue
                }
                run.append(UInt8(scalar.value))
            }
            let value = String(decoding: run, as: UTF8.self)
            return wordLooksGenerated(run) && !isNonCredentialEntropyValue(value)
        }
    }

    /// The quote marks a one-line structure such as `{"key":"value"}` frames its values with.
    private static let quoteMarks: [Character] = ["\"", "'"]

    /// A word cut at its quote marks when each kind is paired, so a quoted value is judged alone; else the word whole.
    private static func quotedPieces<Element: Equatable>(
        of word: [Element], marks: [Element]
    ) -> [ArraySlice<Element>] {
        let paired = marks.allSatisfy { mark in word.count(where: { $0 == mark }).isMultiple(of: 2) }
        guard paired, word.contains(where: marks.contains) else { return [word[...]] }
        return word.split(whereSeparator: marks.contains)
    }

    private static func quotedPieces(of word: [Character]) -> [ArraySlice<Character>] {
        quotedPieces(of: word, marks: quoteMarks)
    }

    /// The statistical rule read over the bytes of an ASCII clip, where a byte is a character; `nil` for any other clip.
    private static func asciiHighEntropyToken(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard ClipBytes.isASCII(bytes) else { return nil }
        guard !bytes.contains(where: { (0x0A...0x0D).contains($0) }) else { return false }
        var start = 0
        for offset in 0...bytes.count
        where offset == bytes.count || bytes[offset] == 0x20 || bytes[offset] == 0x09 {
            if offset > start {
                let token = UnsafeBufferPointer(rebasing: bytes[start..<offset])
                if asciiWordLooksGenerated(token),
                    !isNonCredentialEntropyValue(String(decoding: token, as: UTF8.self))
                {
                    return true
                }
            }
            start = offset + 1
        }
        return false
    }

    /// `quotedPieces` over an ASCII word, copying it only when it holds a quote mark.
    private static func asciiWordLooksGenerated(_ word: UnsafeBufferPointer<UInt8>) -> Bool {
        var start = 0
        var end = word.count
        while start < end, !isTokenByte(word[start]) { start += 1 }
        while end > start, !isTokenByte(word[end - 1]) { end -= 1 }
        guard start < end else { return false }
        let token = UnsafeBufferPointer(rebasing: word[start..<end])
        let marks: [UInt8] = [0x22, 0x27]
        guard token.contains(where: marks.contains) else { return looksGenerated(token) }
        return quotedPieces(of: Array(token), marks: marks).contains { piece in
            piece.withUnsafeBufferPointer { looksGenerated($0) }
        }
    }

    /// A scalar-delimited token returned by the Character path, using the byte path's boundary and alphabet rules.
    private static func wordLooksGenerated(_ word: [UInt8]) -> Bool {
        word.withUnsafeBufferPointer { asciiWordLooksGenerated($0) }
    }

    /// `looksGenerated` for an ASCII token, byte for character.
    private static func looksGenerated(_ token: UnsafeBufferPointer<UInt8>) -> Bool {
        func opens(_ prefix: StaticString) -> Bool {
            token.count >= prefix.utf8CodeUnitCount
                && (0..<prefix.utf8CodeUnitCount).allSatisfy { token[$0] == prefix.utf8Start[$0] }
        }
        guard
            !(opens("/") || opens("~/") || opens("./") || opens("../") || ClipBytes.contains(token, "://")
                || hasKnownURIScheme(token))
        else { return false }
        func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }
        func isLetter(_ byte: UInt8) -> Bool { (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) }
        if token.count >= hexTokenLength,
            token.allSatisfy({ isDigit($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0) })
        {
            return true
        }
        guard token.count >= entropicTokenLength,
            token.allSatisfy({
                isDigit($0) || isLetter($0) || "+/=_-!@#$%^&*()[]{}:;,.?~`\\|<>\"'".utf8.contains($0)
            }),
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
        // Decoded only past the floor, which few tokens reach, so the common path stays byte-wise.
        guard bits >= entropyFloor else { return false }
        return !isEntropyExemption(String(decoding: token, as: UTF8.self))
    }

    static func looksGenerated(_ token: String) -> Bool {
        guard !isEntropyExemptAddress(token) else { return false }
        guard !isUUID(token) else { return false }

        // Hex has a sixteen-symbol alphabet and can never reach the general floor.
        if token.count >= hexTokenLength, token.allSatisfy({ $0.isHexDigit && $0.isASCII }) { return true }

        guard token.count >= entropicTokenLength,
            token.allSatisfy(isTokenCharacter),
            token.contains(where: \.isNumber),
            token.contains(where: \.isLetter)
        else { return false }
        return entropy(of: token) >= entropyFloor && !isEntropyExemption(token)
    }

    /// Whether a token is a UUID, a path, or joined words rather than a generated credential.
    private static func isEntropyExemption(_ token: String) -> Bool {
        isEntropyExemptAddress(token) || isUUID(token) || isJoinedWords(token)
            || DeveloperReferenceShape.matches(token)
    }

    /// Whether a token has the canonical 8-4-4-4-12 hexadecimal UUID shape.
    private static func isUUID(_ token: String) -> Bool {
        let groups = token.split(separator: "-", omittingEmptySubsequences: false)
        return groups.count == 5
            && zip(groups, [8, 4, 4, 4, 12]).allSatisfy { group, length in
                group.count == length && group.allSatisfy { $0.isHexDigit && $0.isASCII }
            }
    }

    /// Whether a token is words joined by `-`, `_`, `/` or `.`, like a branch, slug, or bundle id.
    static func isJoinedWords(_ token: String) -> Bool {
        let segments = token.split(separator: /[-_\/.]/, omittingEmptySubsequences: false)
        return segments.count >= 3 && segments.allSatisfy(isWordLike)
    }

    /// A one-case word optionally numbered (`v2`), or a number with a short suffix (`2nd`); random pieces mix case.
    private static func isWordLike(_ segment: Substring) -> Bool {
        let letters = segment.prefix(while: \.isLetter)
        let rest = segment.dropFirst(letters.count)
        if letters.isEmpty {
            let digits = rest.prefix(while: \.isNumber)
            let suffix = rest.dropFirst(digits.count)
            return !digits.isEmpty && suffix.count <= 2 && suffix.allSatisfy(\.isLowercase)
        }
        guard rest.allSatisfy(\.isNumber) else { return false }
        let tail = letters.dropFirst()
        return tail.allSatisfy(\.isLowercase) || letters.allSatisfy(\.isUppercase)
    }

    /// Uses the byte scanner's exact alphabet; Swift classifies some of its symbols outside punctuation.
    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1
            && character.unicodeScalars.first.map {
                $0.isASCII
                    && isTokenByte(UInt8($0.value))
            } == true
    }

    /// Whether a byte belongs to the statistical token alphabet.
    private static func isTokenByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
            || "+/=_-!@#$%^&*()[]{}:;,.?~`\\|<>\"'".utf8.contains(byte)
    }

    /// A path or known URI shares base64's alphabet, so entropy alone cannot distinguish it from a credential.
    private static func isEntropyExemptAddress(_ token: String) -> Bool {
        PathShape.starts.contains(where: token.hasPrefix) || token.contains("://") || hasKnownURIScheme(token)
    }

    private static func isQuotedPath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline), let first = trimmed.first,
            (first == "\"" || first == "'"), trimmed.last == first
        else { return false }
        let path = String(trimmed.dropFirst().dropLast())
        return PathShape.matches(path) || DeveloperReferenceShape.isCompleteWindowsPath(path)
    }

    private static func hasKnownURIScheme(_ token: String) -> Bool {
        guard let colon = token.firstIndex(of: ":") else { return false }
        return entropyExemptURISchemes.contains(token[..<colon].lowercased())
    }

    private static func hasKnownURIScheme(_ token: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let colon = token.firstIndex(of: 0x3A), colon > 0 else { return false }
        let scheme = String(decoding: token[..<colon], as: UTF8.self).lowercased()
        return entropyExemptURISchemes.contains(scheme)
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
