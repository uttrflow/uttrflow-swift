import Testing

import UttrflowCore

@testable import UttrflowPredictCapture

private let allowed = CapturePreferences(
    consent: ["com.example.terminal": .allowed, "com.example.browser": .allowed])

private func field(_ role: String = "AXTextArea", subrole: String? = nil) -> FieldReading {
    FieldReading(bundleIdentifier: "com.example.terminal", role: role, subrole: subrole)
}

private func terminalField() -> FieldReading {
    FieldReading(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea")
}

@Suite("What is refused before anything is written")
struct CaptureGateTests {
    @Test("An ordinary value in an allowed application is not refused.")
    func ordinaryValuePasses() {
        #expect(CaptureGate.refusal(toRecord: "git status", from: field(), given: allowed) == nil)
    }

    @Test("A password field is refused before consent is even consulted.")
    func secureFieldIsRefusedFirst() {
        let secure = FieldReading(bundleIdentifier: "com.example.unknown", role: "AXSecureTextField")
        #expect(
            CaptureGate.refusal(toRecord: "hunter2000", from: secure, given: CapturePreferences())
                == .secureField)
    }

    @Test("A field its reader found secure only by its masked value is refused.")
    func maskedOnlyFieldIsRefused() {
        let masked = FieldReading(
            bundleIdentifier: "com.example.terminal", role: "AXTextField", isKnownSecure: true)
        #expect(masked.isSecure)
        #expect(CaptureGate.refusal(toRecord: "hunter2000", from: masked, given: allowed) == .secureField)
    }

    @Test("A one-time-code field is refused before consent is even consulted.")
    func sensitiveFieldNameIsRefusedFirst() {
        let otp = FieldReading(
            bundleIdentifier: "com.example.unknown", role: "AXTextField",
            identifier: "one-time-code")
        #expect(
            CaptureGate.refusal(toRecord: "123456", from: otp, given: CapturePreferences()) == .secureField)
    }

    @Test(
        "One consent rule on both paths: unasked and allowed are learned, declined is refused.",
        arguments: [
            (CapturePreferences(), nil),
            (allowed, nil),
            (
                CapturePreferences(consent: ["com.example.terminal": .declined]),
                CaptureRefusal.consentDeclined
            ),
        ] as [(CapturePreferences, CaptureRefusal?)])
    func oneConsentRule(preferences: CapturePreferences, expected: CaptureRefusal?) {
        let edit = EditedSpan(position: 0, old: ["tuesday"], new: ["thursday"])
        #expect(CaptureGate.refusal(toRecord: "git status", from: field(), given: preferences) == expected)
        #expect(CaptureGate.refusal(toHear: edit, from: field(), given: preferences) == expected)
    }

    @Test("An application the user said no to is refused without asking again.")
    func declinedApplicationIsQuiet() {
        let declined = CapturePreferences(consent: ["com.example.terminal": .declined])
        let refusal = CaptureGate.refusal(toRecord: "git status", from: field(), given: declined)
        #expect(refusal == .consentDeclined)
    }

    /// The switch lowercases what it writes and the field reading does not, so the two must still meet (#668).
    @Test("An application said no to under one spelling is refused under the other.")
    func aDeclineHoldsWhateverTheCase() {
        var preferences = CapturePreferences()
        preferences.record(.declined, for: "com.example.terminal")

        let mixedCase = FieldReading(bundleIdentifier: "com.Example.Terminal", role: "AXTextArea")
        let refusal = CaptureGate.refusal(
            toRecord: "git status", from: mixedCase, given: preferences)

        #expect(refusal == .consentDeclined)
    }

    /// A file written before the two stores agreed holds both spellings, and the refusal is the one to keep.
    @Test("A file holding both spellings is read as the refusal, not the allow.")
    func aRefusalOutlivesAnAllowInAnOlderFile() {
        let both = CapturePreferences(
            consent: ["com.example.terminal": .declined, "com.Example.Terminal": .allowed])

        #expect(both.consent == ["com.example.terminal": .declined])
        #expect(
            CaptureGate.refusal(toRecord: "git status", from: field(), given: both)
                == .consentDeclined)
    }

    @Test("A value one character long is refused, because completing it could never save a keystroke.")
    func oneCharacterIsRefused() {
        #expect(CaptureGate.refusal(toRecord: "y", from: field(), given: allowed) == .tooShort)
    }

    @Test(
        "A list line holding only its marker is refused as too short.",
        arguments: ["- ", "* ", "1. ", "12)", "- [ ] ", "[x]", "• "])
    func markerAloneIsRefused(line: String) {
        #expect(CaptureGate.refusal(toRecord: line, from: field(), given: allowed) == .tooShort)
    }

    @Test("A list item with its text after the marker is learned.")
    func markedItemPasses() {
        #expect(CaptureGate.refusal(toRecord: "- Buy milk", from: field(), given: allowed) == nil)
        #expect(CaptureGate.refusal(toRecord: "1. Buy milk", from: field(), given: allowed) == nil)
    }

    @Test("Short all-digit values in non-terminal fields are refused as form secrets.")
    func shortNumericWebValuesAreRefused() {
        let browser = FieldReading(bundleIdentifier: "com.example.browser", role: "AXTextField")

        for value in ["12", "1234", "123456", "01011990", "12 34", "123 456", "12-3456", "4111.1111"] {
            #expect(CaptureGate.refusal(toRecord: value, from: browser, given: allowed) == .sensitiveValue)
        }
    }

    @Test(
        "Identity, phone, account and card numbers of any length are refused, with or without separators.",
        arguments: [
            "123456789", "123 45 6789", "9876543210", "98765-43210", "123456789012", "1234 5678 9012",
            "4000123412341234", "4000-1234-1234-1234", "1 2 3 4 5 6 7 8 9",
        ])
    func longNumericWebValuesAreRefused(value: String) {
        let browser = FieldReading(bundleIdentifier: "com.example.browser", role: "AXTextField")
        #expect(CaptureGate.refusal(toRecord: value, from: browser, given: allowed) == .sensitiveValue)
    }

    @Test("Malformed digit groups remain ordinary text.")
    func malformedGroupedNumbersPass() {
        for value in ["1--2", "-1234"] {
            #expect(CaptureGate.refusal(toRecord: value, from: field(), given: allowed) == nil)
        }
        // A number ending in a full stop alone is an ordered-list marker, refused as too short to be an item.
        #expect(CaptureGate.refusal(toRecord: "1234.", from: field(), given: allowed) == .tooShort)
    }

    @Test(
        "Short all-digit values still pass in terminals, where numbers are ordinary commands and arguments.")
    func shortNumericTerminalValuesPass() {
        let terminalAllowed = CapturePreferences(consent: ["com.apple.terminal": .allowed])
        #expect(CaptureGate.refusal(toRecord: "123456", from: terminalField(), given: terminalAllowed) == nil)
        #expect(
            CaptureGate.refusal(toRecord: "123456789012", from: terminalField(), given: terminalAllowed)
                == nil)
    }

    @Test("A destructive command is refused, so it can never be stored to complete later.")
    func destructiveCommandIsRefused() {
        #expect(
            CaptureGate.refusal(toRecord: "rm -rf build", from: field(), given: allowed)
                == .destructive)
        #expect(
            CaptureGate.refusal(toRecord: "git push --force", from: field(), given: allowed)
                == .destructive)
    }

    @Test("A line the shell reader cannot resolve is refused rather than taken as safe.")
    func unresolvedSubstitutionIsRefused() {
        for line in ["rm -rf $(find . -name node_modules)", "git branch -D `git branch --merged`"] {
            #expect(CaptureGate.refusal(toRecord: line, from: field(), given: allowed) == .destructive)
        }
    }

    @Test("A credential is refused by the same rules the clipboard hides one with.")
    func secretsAreRefused() {
        let secrets = [
            "export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMIK7MDENGbPxRfiCYEXAMPLEKEY",
            "-----BEGIN RSA PRIVATE KEY-----",
            "psql postgres://someone:s3cretpassword@db.example.com/records",
        ]
        for secret in secrets {
            #expect(CaptureGate.refusal(toRecord: secret, from: field(), given: allowed) == .looksLikeSecret)
        }
    }

    @Test(
        "A password passed to a command or sent in a header is refused from a terminal.",
        arguments: [
            "curl -u admin:Hunter2x https://api.example.com",
            "mysql -u root -pS3cretPass appdb",
            "sshpass -p 'S3cret!' ssh deploy@db.example.com",
            "docker login -u ci -p S3cr3tValue registry.example.com",
            "docker login --password S3cr3t",
            "htpasswd -b .htpasswd alice Mead0wlark",
            "ssh-keygen -t ed25519 -N 'correct horse'",
            "openssl pkcs12 -export -passout pass:sunshine",
            "curl -H \"Authorization: Basic YWxpY2U6czNjcjN0\" https://api.example.com",
            "curl -H \"Authorization: Bearer 8fK2pQ7xLm4Rt9vW3nB6cY1zH5jD0sAe\"",
            "git clone https://0123456789abcdef0123456789abcdef01234567@git.example.com/org/repo.git",
        ])
    func commandCredentialsAreRefused(_ line: String) {
        let terminal = CapturePreferences(consent: ["com.apple.Terminal": .allowed])
        #expect(
            CaptureGate.refusal(toRecord: line, from: terminalField(), given: terminal) == .looksLikeSecret)
    }

    @Test("The credential rules are the clipboard's, asked rather than copied.")
    func secretRuleIsShared() {
        #expect(CaptureGate.looksLikeSecret("AKIAIOSFODNN7EXAMPLE"))
        #expect(!CaptureGate.looksLikeSecret("git commit -m 'fix the thing'"))
    }

    @Test(
        "A credential on any line of a multi-line value is a secret, as it is on one line.",
        arguments: [
            ("docker run", "  -e DB=a8Kd93jfLq02xZpVnQ7r", "  img"),
            ("curl https://api.example.com", "  -d a8Kd93jfLq02xZpVnQ7rT5", "  --fail"),
            ("echo start", "Bearer a8Kd93jfLq02xZpVnQ7r", "echo done"),
            ("echo start", "secret a8Kd93jfLq02xZpV", "echo done"),
        ])
    func continuationLineSecretIsRefused(lines: (String, String, String)) {
        let oneLine = [lines.0, lines.1, lines.2].joined(separator: " ")
        let continued = [lines.0, lines.1, lines.2].joined(separator: "\n")
        #expect(CaptureGate.looksLikeSecret(oneLine))
        #expect(CaptureGate.looksLikeSecret(continued))
        #expect(CaptureGate.refusal(toRecord: continued, from: field(), given: allowed) == .looksLikeSecret)
    }

    @Test("A multi-line value with no credential on any line is not a secret.")
    func multiLineOrdinaryValuePasses() {
        #expect(!CaptureGate.looksLikeSecret("docker run \\\n  -e MODE=production \\\n  img"))
    }
}

@Suite("Asking an application's permission once")
struct CapturePreferencesTests {
    @Test("An application nobody has said anything about is unknown, and is learned from by default.")
    func unknownProceeds() {
        let preferences = CapturePreferences()
        #expect(preferences.state(of: "com.example.app") == .unknown)
        #expect(preferences.decision(for: "com.example.app") == .proceed)
    }

    @Test("Opting in lets the application be learned from.")
    func allowedProceeds() {
        var preferences = CapturePreferences()
        preferences.record(.allowed, for: "com.example.app")
        #expect(preferences.decision(for: "com.example.app") == .proceed)
    }

    @Test("Declining refuses without ever asking again.")
    func declinedIsQuiet() {
        var preferences = CapturePreferences()
        preferences.record(.declined, for: "com.example.app")
        #expect(preferences.decision(for: "com.example.app") == .refuseQuietly)
    }

    @Test("Answering again replaces the earlier answer.")
    func answersAreReplaced() {
        var preferences = CapturePreferences()
        preferences.record(.allowed, for: "com.example.app")
        preferences.record(.declined, for: "com.example.app")
        #expect(preferences.state(of: "com.example.app") == .declined)
    }

    @Test("One application's answer says nothing about another's.")
    func consentIsPerApplication() {
        var preferences = CapturePreferences()
        preferences.record(.declined, for: "com.example.terminal")
        #expect(preferences.decision(for: "com.example.browser") == .proceed)
    }

    @Test("Every state has a decision, so no application can fall through the rule.")
    func everyStateDecides() {
        let decisions = ConsentState.allCases.map(CapturePreferences.decision(for:))
        #expect(Set(decisions) == Set(ConsentDecision.allCases))
    }
}
