// Recognises a clip that is made to be shared, however random it looks.

import CryptoKit
import Foundation

/// Public keys, certificates, wallet addresses and a published example token. See Docs/clipboard-secrets.md.
enum PublicMaterialShape {
    /// PEM labels whose body is public; anything else under `-----BEGIN` may be a key.
    private static let publicPEMLabels: Set<Substring> = [
        "PUBLIC KEY", "RSA PUBLIC KEY", "CERTIFICATE", "TRUSTED CERTIFICATE", "CERTIFICATE REQUEST",
        "NEW CERTIFICATE REQUEST", "X509 CRL", "PGP PUBLIC KEY BLOCK", "PGP SIGNATURE",
    ]

    /// OpenSSH public key algorithm names before any `@` vendor suffix, the first word of an `authorized_keys` line.
    private static let sshAlgorithms: Set<Substring> = [
        "ssh-ed25519", "ssh-rsa", "ssh-dss", "sk-ssh-ed25519", "sk-ecdsa-sha2-nistp256", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384",
        "ecdsa-sha2-nistp521",
    ]

    /// The widely published example token; its signing key is printed beside it, so it opens nothing.
    private static let publishedExampleTokens = [
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ"
            + ".SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    ]

    /// Whether any `-----BEGIN` in the text opens something other than a public object.
    static func hasNonPublicPEM(_ text: String) -> Bool {
        text.ranges(of: "-----BEGIN").contains { opening in
            let label = text[opening.upperBound...].prefix { $0 != "-" && !$0.isNewline }
            return !publicPEMLabels.contains(Substring(label.trimmingPrefix(" ")))
        }
    }

    /// Whether the whole clip is public material and nothing else.
    static func matches(_ text: String) -> Bool {
        let trimmed = text.trimmingPrefix(while: \.isWhitespace)
        if trimmed.hasPrefix("-----BEGIN") { return isOnlyPublicPEM(trimmed) }
        let lines = trimmed.split(whereSeparator: \.isNewline)
        guard let first = lines.first, first.utf8.count >= 26 else { return false }
        if sshAlgorithms.contains(first.prefix { $0 != " " && $0 != "@" }) { return lines.allSatisfy(isSSHPublicKey) }
        let word = first.prefix { !$0.isWhitespace }
        return lines.count == 1 && word.count == first.count && isWalletAddress(first)
    }

    /// The text with the published example tokens taken out, so what surrounds them is still judged.
    static func withoutPublishedExamples(_ text: String) -> String {
        publishedExampleTokens.reduce(text) { $0.replacing($1, with: "") }
    }

    /// Markers around base64 lines only: a line of anything else beside them is not part of the object.
    private static func isOnlyPublicPEM(_ text: Substring) -> Bool {
        var rest = text
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("-----") {
            guard line.allSatisfy(isBase64) else { return false }
        }
        while let marker = rest.firstRange(of: "-----") {
            let after = rest[marker.upperBound...]
            guard let close = after.firstRange(of: "-----") else { return false }
            let label = after[..<close.lowerBound]
            let name = label.hasPrefix("BEGIN ") ? label.dropFirst(6) : label.hasPrefix("END ") ? label.dropFirst(4) : ""
            guard publicPEMLabels.contains(name) else { return false }
            rest = after[close.upperBound...]
        }
        return true
    }

    private static func isBase64(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "+/=\r ".contains(character))
    }

    /// `algorithm AAAA… [comment]`, with a comment too short and too plain to carry anything else.
    private static func isSSHPublicKey(_ line: Substring) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words.count <= 5, sshAlgorithms.contains(words[0].prefix { $0 != "@" }), words[1].hasPrefix("AAAA"),
            words[1].allSatisfy(isBase64)
        else { return false }
        return !words.dropFirst(2).contains { $0.contains("=") }
    }

    private static func isWalletAddress(_ word: Substring) -> Bool {
        if word.hasPrefix("0x") {
            return word.count == 42 && word.dropFirst(2).allSatisfy { $0.isASCII && $0.isHexDigit }
        }
        return isBase58CheckAddress(word) || isBech32Address(word) || isMoneroAddress(word)
    }

    private static let base58 = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)

    /// A Bitcoin-family address: its checksum passes for one random string in four billion.
    private static func isBase58CheckAddress(_ word: Substring) -> Bool {
        guard (26...35).contains(word.utf8.count) else { return false }
        var bytes: [UInt8] = []
        for scalar in word.utf8 {
            guard var carry = base58.firstIndex(of: scalar) else { return false }
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        let leadingZeros = word.utf8.prefix { $0 == base58[0] }.count
        let decoded = [UInt8](repeating: 0, count: leadingZeros) + bytes.reversed()
        guard decoded.count > 4 else { return false }
        let hash = SHA256.hash(data: Data(SHA256.hash(data: Data(decoded.dropLast(4)))))
        return zip(hash, decoded.suffix(4)).allSatisfy { $0 == $1 }
    }

    /// A SegWit address (BIP-173 or BIP-350), checked by its own checksum.
    private static func isBech32Address(_ word: Substring) -> Bool {
        let lowered = word.lowercased()
        guard lowered.hasPrefix("bc1") || lowered.hasPrefix("ltc1"), word == lowered || word == word.uppercased(),
            let separator = lowered.lastIndex(of: "1")
        else { return false }
        let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        let human = lowered[..<separator].unicodeScalars.map { Int($0.value) }
        var values = human.map { $0 >> 5 } + [0] + human.map { $0 & 31 }
        for character in lowered[lowered.index(after: separator)...] {
            guard let value = alphabet.firstIndex(of: character) else { return false }
            values.append(value)
        }
        let generator = [0x3B6A_57B2, 0x2650_8E6D, 0x1EA1_19FA, 0x3D42_33DD, 0x2A14_62B3]
        let check = values.reduce(1) { state, value in
            let high = state >> 25
            let next = (state & 0x1FF_FFFF) << 5 ^ value
            return generator.indices.reduce(next) { (high >> $1) & 1 == 1 ? $0 ^ generator[$1] : $0 }
        }
        return check == 1 || check == 0x2BC8_30A3
    }

    /// A Monero address: 95 base58 characters opening with its network's 4 or 8; nothing issued has that shape.
    private static func isMoneroAddress(_ word: Substring) -> Bool {
        word.utf8.count == 95 && (word.hasPrefix("4") || word.hasPrefix("8"))
            && word.utf8.allSatisfy(base58.contains)
    }
}
