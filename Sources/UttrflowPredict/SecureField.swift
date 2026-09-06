/// Decides whether a field hides what is typed, so its contents are never read, stored, or drawn from.
public enum SecureField {
    /// The role and subrole a password field is published under, by the two conventions in use.
    public static let secureRole = "AXSecureTextField"

    /// Whether the field declares itself secure, judged without reading its value.
    public static func isDeclaredSecure(
        role: String?, subrole: String?, identifier: String?, placeholder: String?,
        description: String?
    ) -> Bool {
        if role == secureRole || subrole == secureRole { return true }
        return [identifier, placeholder, description].contains { $0.map(namesASecret) ?? false }
    }

    /// Whether a name betrays a password field that did not publish the secure role, as web fields do.
    static func namesASecret(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("password") || lower.contains("passwd")
            || lower.contains("passcode")
    }

    /// Whether a value reads back as mask characters alone, which a field showing dots but not declaring itself does.
    public static func looksMasked(_ value: String) -> Bool {
        guard value.count >= 3 else { return false }
        let masks: Set<Character> = ["•", "●", "*", "◦", "·", "‣", "∗", "\u{2022}", "\u{25CF}"]
        return value.allSatisfy { masks.contains($0) }
    }
}
