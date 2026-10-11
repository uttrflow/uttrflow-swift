/// Recognizes values that documentation uses in place of a credential.
enum CredentialPlaceholder {
    private static let markers: Set<String> = ["your", "example", "placeholder", "changeme", "xxx"]
    private static let publishedAWSExamples: Set<String> = [
        "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    ]

    /// Whether a value visibly stands in for a credential.
    static func matches(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let assignedValue =
            trimmed.split(separator: "=", omittingEmptySubsequences: false).last.map(String.init)
            ?? trimmed
        if isRepeatedPlaceholder(trimmed) || isRepeatedVendorPlaceholder(trimmed)
            || isRepeatedVendorPlaceholder(assignedValue) || isEllipsisPlaceholder(trimmed)
            || isEllipsisPlaceholder(assignedValue)
            || publishedAWSExamples.contains(trimmed) || publishedAWSExamples.contains(assignedValue)
            || isVariableReference(trimmed)
            || isAnglePlaceholder(trimmed)
        {
            return true
        }
        return trimmed.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains {
            markers.contains(String($0))
        }
    }

    /// Whether a connection string's password is a documented placeholder.
    static func hasPlaceholderURLPassword(_ value: String) -> Bool {
        guard let scheme = value.range(of: "://"),
            let at = value[scheme.upperBound...].firstIndex(of: "@"),
            let colon = value[scheme.upperBound..<at].lastIndex(of: ":")
        else { return false }
        let password = String(value[value.index(after: colon)..<at]).lowercased()
        return ["password", "pass", "secret"].contains(password) || matches(password)
    }

    private static func isRepeatedPlaceholder(_ value: String) -> Bool {
        let characters = Array(value)
        guard characters.count >= 3, let first = characters.first else { return false }
        return ["x", "X", "*", "."].contains(first) && characters.allSatisfy { $0 == first }
    }

    private static func isRepeatedVendorPlaceholder(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        for prefix in ["ghp_", "sk-"] where lowercased.hasPrefix(prefix) {
            return isRepeatedPlaceholder(String(value.dropFirst(prefix.count)))
        }
        return false
    }

    private static func isEllipsisPlaceholder(_ value: String) -> Bool {
        value == "..." || ["sk-...", "ghp_..."].contains(value.lowercased())
    }

    private static func isVariableReference(_ value: String) -> Bool {
        value.hasPrefix("$") && (value.count > 1)
    }

    private static func isAnglePlaceholder(_ value: String) -> Bool {
        value.hasPrefix("<") && value.hasSuffix(">")
    }
}
