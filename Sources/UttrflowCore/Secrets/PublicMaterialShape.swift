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

    /// OpenSSH public key algorithm names before any `@` suffix, the first word of a key line.
    private static let sshAlgorithms: Set<Substring> = [
        "ssh-ed25519", "ssh-rsa", "ssh-dss", "sk-ssh-ed25519", "sk-ecdsa-sha2-nistp256",
        "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384",
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
        if sshAlgorithms.contains(first.prefix { !$0.isWhitespace && $0 != "@" }) {
            return lines.allSatisfy(isSSHPublicKey)
        }
        let word = first.prefix { !$0.isWhitespace }
        return lines.count == 1 && first[word.endIndex...].allSatisfy(\.isWhitespace) && isWalletAddress(word)
    }

    /// The text with the published example tokens taken out, so what surrounds them is still judged.
    static func withoutPublishedExamples(_ text: String) -> String {
        publishedExampleTokens.reduce(text) { $0.replacing($1, with: "") }
    }

    /// BEGIN and END pairs of one public label around base64 lines, with only blank space between blocks.
    private static func isOnlyPublicPEM(_ text: Substring) -> Bool {
        var open: Substring?
        for line in text.split(whereSeparator: \.isNewline) {
            let plain = line.trimmingPrefix(while: \.isWhitespace)
            if plain.isEmpty { continue }
            if plain.hasPrefix("-----BEGIN ") {
                guard open == nil, let label = label(of: plain, after: "-----BEGIN ") else { return false }
                open = label
            } else if plain.hasPrefix("-----END ") {
                guard let current = open, label(of: plain, after: "-----END ") == current else {
                    return false
                }
                open = nil
            } else {
                guard open != nil, isBase64Line(plain) else { return false }
            }
        }
        return open == nil
    }

    /// The public label of a marker line that is nothing but the marker.
    private static func label(of line: Substring, after opening: String) -> Substring? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("-----") else { return nil }
        let name = Substring(trimmed.dropFirst(opening.count).dropLast(5))
        return publicPEMLabels.contains(name) ? name : nil
    }

    /// Base64 characters, with padding only at the end, so `name=value` is not a body line.
    private static func isBase64Line(_ line: Substring) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        let unpadded = body.prefix { $0 != "=" }
        return unpadded.allSatisfy(isBase64) && body.dropFirst(unpadded.count).allSatisfy { $0 == "=" }
    }

    private static func isBase64(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "+/=".contains(character))
    }

    /// `algorithm AAAA… [comment]`, with a comment too short and too plain to carry anything else.
    private static func isSSHPublicKey(_ line: Substring) -> Bool {
        let words = line.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words.count <= 5, sshAlgorithms.contains(words[0].prefix { $0 != "@" }),
            words[1].hasPrefix("AAAA"),
            words[1].allSatisfy(isBase64)
        else { return false }
        let comment = words.dropFirst(2).joined(separator: " ")
        return !comment.contains("=") && !SecretShapes.matches(comment)
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
        guard lowered.hasPrefix("bc1") || lowered.hasPrefix("ltc1"),
            word == lowered || word == word.uppercased(),
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
