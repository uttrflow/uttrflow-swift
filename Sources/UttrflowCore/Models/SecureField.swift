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

    /// The roles a form names a secret field under; a message, a row or a page naming one is only talking about it.
    static let namedFieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Whether an element seen beside the focused field is secure: the secure role anywhere, a secret's name only on a field.
    public static func isDeclaredSecureOnScreen(
        role: String?, subrole: String?, identifier: String?, placeholder: String?,
        description: String?
    ) -> Bool {
        if role == secureRole || subrole == secureRole { return true }
        guard let role, namedFieldRoles.contains(role) else { return false }
        return isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description)
    }

    /// The whole rule both dictation boundaries ask: declared secure, or else a value of mask characters alone, read only then.
    public static func isSecure(
        role: String?, subrole: String?, identifier: String?, placeholder: String?,
        description: String?, value: () -> String?
    ) -> Bool {
        let declared = isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description)
        return declared || (value().map(looksMasked) ?? false)
    }

    /// The field's value, never fetched from a field declared secure and dropped when it reads back as mask characters alone.
    public static func readableValue(
        role: String?, subrole: String?, identifier: String?, placeholder: String?,
        description: String?, value: () -> String?
    ) -> String? {
        let declared = isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: description)
        guard !declared, let read = value(), !looksMasked(read) else { return nil }
        return read
    }

    /// Whether a name betrays a field whose value must never be learned, as web fields do.
    static func namesASecret(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let wordSet = Set(words)
        let phrase = words.joined(separator: " ")
        let compact = words.joined()

        let sensitiveCompacts = [
            "password", "passwd", "passcode", "currentpassword", "newpassword",
            "onetimecode", "verificationcode", "authcode", "authenticationcode", "2facode",
            "mfacode", "totpcode", "securitycode", "cardsecuritycode", "cardverificationcode",
            "cardnumber", "ccnumber", "creditcard", "creditcardnumber", "cccsc",
            "securityanswer", "securityquestion", "recoveryanswer", "recoveryquestion",
            "recoverycode", "recoveryphrase", "socialsecurity", "socialsecuritynumber",
            "accountnumber", "routingnumber", "dateofbirth",
        ]
        if sensitiveCompacts.contains(where: compact.contains) { return true }

        let sensitivePhrases = [
            "one time code", "verification code", "auth code", "authentication code",
            "2fa code", "mfa code", "totp code", "security code", "card security",
            "card verification", "card number", "credit card", "security answer",
            "security question", "recovery answer", "recovery question", "recovery code",
            "recovery phrase", "social security", "account number", "routing number",
            "date of birth",
        ]
        if sensitivePhrases.contains(where: phrase.contains) { return true }

        let codes = ["otp", "cvv", "cvc", "csc", "pin", "ssn"]
        if codes.contains(where: wordSet.contains) { return true }
        let pieces = text.split { !$0.isLetter && !$0.isNumber }
        return pieces.contains { piece in
            codes.contains { gluesCode($0, into: piece) || gluesLowercaseCode($0, into: piece) }
        }
    }

    /// Whether a lowercase word glues a short code to a whole field word; `mapping` and a postal `pincode` do not.
    static func gluesLowercaseCode(_ code: String, into word: Substring) -> Bool {
        guard word.allSatisfy({ $0.isLowercase || $0.isNumber }), word.count > code.count else {
            return false
        }
        if word.hasPrefix(code) {
            let rest = String(word.dropFirst(code.count))
            // A pin code is a postal code in India; a PIN is not named that way.
            if CredentialWords.codeSuffixes.contains(rest), !(code == "pin" && rest == "code") { return true }
        }
        if word.hasSuffix(code) {
            return CredentialWords.codePrefixes.contains(String(word.dropLast(code.count)))
        }
        return false
    }

    /// Whether a camelCase word opens or closes with a short code at a case boundary, as `otpField` or `userPin` do.
    static func gluesCode(_ code: String, into word: Substring) -> Bool {
        let chars = Array(word)
        let width = code.count
        guard chars.count > width else { return false }
        let head = chars[..<width]
        if String(head).lowercased() == code {
            let next = chars[width]
            let headIsCaps = head.allSatisfy(\.isUppercase)
            if next.isUppercase && !headIsCaps || next.isNumber { return true }
            if headIsCaps && next.isUppercase && chars.count > width + 1 && chars[width + 1].isLowercase {
                return true
            }
        }
        let tail = chars[(chars.count - width)...]
        guard String(tail).lowercased() == code, let first = tail.first, first.isUppercase else {
            return false
        }
        return chars[chars.count - width - 1].isLowercase
    }

    /// Whether a value reads back as mask characters alone, which a field showing dots but not declaring itself does.
    public static func looksMasked(_ value: String) -> Bool {
        guard value.count >= 3 else { return false }
        let masks: Set<Character> = ["•", "●", "*", "◦", "·", "‣", "∗", "\u{2022}", "\u{25CF}"]
        return value.allSatisfy { masks.contains($0) }
    }
}
