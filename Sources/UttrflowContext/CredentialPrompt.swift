import Foundation

/// Recognizes short credential labels without treating command-like text as a prompt.
enum CredentialPrompt {
    private static let terms: Set<String> = [
        "password", "passwort", "kennwort", "passphrase", "passe", "contraseña", "pin",
        "passcode", "code", "otp", "token", "पासवर्ड", "पासफ़्रेज़", "पिन", "कोड", "टोकन",
    ]

    private static let ambiguousBareTerms: Set<String> = ["code", "token"]

    private static let introducers: Set<String> = [
        "a", "again", "authentication", "confirm", "current", "de", "empty", "enter", "factor",
        "for", "input", "mfa", "mot", "new", "no", "of", "old", "one", "please", "provide",
        "repeat", "reenter", "retype", "same", "security", "the", "time", "two", "type", "unix",
        "verification", "your",
    ]

    private static let colons: Set<Character> = [":", "：", "﹕", "︓"]

    static func matches(_ line: String) -> Bool {
        let prefix = line.prefix(ShellPrompt.searchLimit)
        guard let colon = prefix.firstIndex(where: colons.contains) else {
            guard prefix.endIndex == line.endIndex else { return false }
            let label = String(prefix).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return terms.contains(label) && !ambiguousBareTerms.contains(label)
        }
        let label = String(prefix[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return introducesCredential(label)
    }

    private static func introducesCredential(_ label: String) -> Bool {
        let words = label.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let credentialIndex = words.firstIndex(where: terms.contains) else { return false }
        if credentialIndex == 0 {
            return startsCredentialPrompt(label, term: words[credentialIndex])
        }

        let introduction = words[..<credentialIndex]
        if introduction.allSatisfy(introducers.contains) { return true }
        if introduction.elementsEqual(["sudo"]), label.hasPrefix("[sudo]") { return true }
        guard let range = label.range(of: words[credentialIndex]) else { return false }
        let prefix = label[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard label[range.upperBound...].allSatisfy(\.isWhitespace) else { return false }
        return isPossessiveCredentialPrompt(prefix)
    }

    /// A leading term is a prompt only as a complete label or before a simple `for` subject.
    private static func startsCredentialPrompt(_ label: String, term: String) -> Bool {
        guard let range = label.range(of: term) else { return false }
        let suffix = label[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return !ambiguousBareTerms.contains(term) }
        let words = suffix.split(whereSeparator: \.isWhitespace)
        guard words.count == 2, words.first == "for" else { return false }
        return isCredentialOwner(String(words[1]))
    }

    /// An owner is one name or email address, never a command argument or path.
    private static func isCredentialOwner(_ owner: String) -> Bool {
        let parts = owner.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        if parts.count == 2, !parts[1].contains(".") { return false }
        return owner.allSatisfy { character in
            character.isLetter || character.isNumber || "@._-".contains(character)
        } && !owner.hasPrefix(".") && !owner.hasSuffix(".")
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
