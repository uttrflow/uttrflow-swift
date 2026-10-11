import Foundation

/// Recognizes short credential labels without treating command-like text as a prompt.
enum CredentialPrompt {
    private static let terms: Set<String> = [
        "password", "passwort", "kennwort", "passphrase", "passe", "contraseña", "pin",
        "passcode", "code", "otp", "token", "पासवर्ड", "पासफ़्रेज़", "पिन", "कोड", "टोकन",
    ]

    private static let ambiguousBareTerms: Set<String> = ["code"]

    private static let introducers: Set<String> = [
        "a", "again", "authentication", "confirm", "current", "de", "empty", "enter", "factor",
        "for", "input", "mfa", "mot", "new", "no", "of", "old", "one", "please", "provide",
        "repeat", "reenter", "retype", "same", "security", "the", "time", "two", "type", "unix",
        "verification", "your",
    ]

    private static let tokenIntroducers: Set<String> = ["access", "api", "personal"]

    private static let colons: Set<Character> = [":", "：", "﹕", "︓"]

    static func matches(_ line: String) -> Bool {
        let prefix = line.prefix(ShellPrompt.searchLimit)
        let colonIndices = prefix.indices.filter { colons.contains(prefix[$0]) }
        guard !colonIndices.isEmpty else {
            guard prefix.endIndex == line.endIndex else { return false }
            let label = String(prefix).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return terms.contains(label) && !ambiguousBareTerms.contains(label)
        }
        // A colon inside a quoted or URL-shaped owner is not the end of the label, so each colon is tried.
        return colonIndices.contains { colon in
            let label = String(prefix[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if label == "token" {
                return prefix[prefix.index(after: colon)...].allSatisfy(\.isWhitespace)
            }
            return introducesCredential(label)
        }
    }

    private static func introducesCredential(_ label: String) -> Bool {
        let words = label.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let credentialIndex = words.firstIndex(where: terms.contains) else { return false }
        if credentialIndex == 0 {
            return startsCredentialPrompt(label, term: words[credentialIndex])
        }

        let introduction = words[..<credentialIndex]
        if introduction.allSatisfy({
            introducers.contains($0)
                || (words[credentialIndex] == "token" && tokenIntroducers.contains($0))
        }) {
            return true
        }
        if introduction.elementsEqual(["sudo"]), label.hasPrefix("[sudo]") { return true }
        guard let range = label.range(of: words[credentialIndex]) else { return false }
        let prefix = label[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard label[range.upperBound...].allSatisfy(\.isWhitespace) else { return false }
        return isPossessiveCredentialPrompt(prefix)
    }

    /// A leading term takes one introduced qualifier or one simple `for` subject.
    private static func startsCredentialPrompt(_ label: String, term: String) -> Bool {
        guard let range = label.range(of: term) else { return false }
        let suffix = label[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return !ambiguousBareTerms.contains(term) }
        if suffix.first == "(", suffix.last == ")" {
            let qualifier = suffix.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            return introducers.contains(qualifier)
        }
        let words = suffix.split(whereSeparator: \.isWhitespace)
        guard words.count == 2, words.first == "for" else { return false }
        return isCredentialOwner(String(words[1]))
    }

    /// An owner is one name, `user@host` or URL, optionally quoted, never a command argument or path.
    private static func isCredentialOwner(_ quotedOwner: String) -> Bool {
        let owner = addressPart(of: unquoted(quotedOwner))
        let parts = owner.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        return owner.allSatisfy { character in
            character.isLetter || character.isNumber || "@._-".contains(character)
        } && !owner.hasPrefix(".") && !owner.hasSuffix(".")
    }

    private static func unquoted(_ owner: String) -> String {
        let pairs: [(Character, Character)] = [("'", "'"), ("\"", "\""), ("‘", "’"), ("“", "”")]
        guard owner.count >= 2, let first = owner.first, let last = owner.last,
            pairs.contains(where: { $0.0 == first && $0.1 == last })
        else { return owner }
        return String(owner.dropFirst().dropLast())
    }

    /// A URL owner is judged by its `user@host` part; the scheme is letters and the path is at most `/`.
    private static func addressPart(of owner: String) -> String {
        guard let separator = owner.range(of: "://") else { return owner }
        let scheme = owner[..<separator.lowerBound]
        guard !scheme.isEmpty, scheme.allSatisfy(\.isLetter) else { return owner }
        let rest = owner[separator.upperBound...]
        return String(rest.hasSuffix("/") ? rest.dropLast() : rest)
    }

    /// A possessive owner stands alone, or follows only words that introduce a prompt.
    private static func isPossessiveCredentialPrompt(_ prefix: String) -> Bool {
        let possessive = prefix.hasSuffix("'s") ? "'s" : prefix.hasSuffix("’s") ? "’s" : nil
        guard let possessive else { return false }
        let ownerPhrase = prefix.dropLast(possessive.count).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = ownerPhrase.split(whereSeparator: \.isWhitespace)
        guard let owner = words.last, isCredentialOwner(String(owner)) else { return false }
        return words.dropLast().allSatisfy { introducers.contains(String($0)) }
    }
}
