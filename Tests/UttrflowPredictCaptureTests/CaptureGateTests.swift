import Testing

@testable import UttrflowPredictCapture

private let allowed = CapturePreferences(consent: ["com.example.terminal": .allowed])

private func field(_ role: String = "AXTextArea", subrole: String? = nil) -> FieldReading {
    FieldReading(bundleIdentifier: "com.example.terminal", role: role, subrole: subrole)
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

    @Test("An application nobody has been asked about is refused, and the refusal asks.")
    func unknownApplicationAsks() {
        let refusal = CaptureGate.refusal(
            toRecord: "git status", from: field(), given: CapturePreferences())
        #expect(refusal == .consentNotGiven)
        #expect(refusal?.asksTheUser == true)
    }

    @Test("An application the user said no to is refused without asking again.")
    func declinedApplicationIsQuiet() {
        let declined = CapturePreferences(consent: ["com.example.terminal": .declined])
        let refusal = CaptureGate.refusal(toRecord: "git status", from: field(), given: declined)
        #expect(refusal == .consentDeclined)
        #expect(refusal?.asksTheUser == false)
    }

    @Test("A value one character long is refused, because completing it could never save a keystroke.")
    func oneCharacterIsRefused() {
        #expect(CaptureGate.refusal(toRecord: "y", from: field(), given: allowed) == .tooShort)
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

    @Test("The credential rules are the clipboard's, asked rather than copied.")
    func secretRuleIsShared() {
        #expect(CaptureGate.looksLikeSecret("AKIAIOSFODNN7EXAMPLE"))
        #expect(!CaptureGate.looksLikeSecret("git commit -m 'fix the thing'"))
    }
}

@Suite("Asking an application's permission once")
struct CapturePreferencesTests {
    @Test("An application nobody has said anything about is unknown, and being unknown means asking.")
    func unknownAsks() {
        let preferences = CapturePreferences()
        #expect(preferences.state(of: "com.example.app") == .unknown)
        #expect(preferences.decision(for: "com.example.app") == .refuseAndAsk)
    }

    @Test("Opting in is the only answer that lets anything be learned.")
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
        preferences.record(.allowed, for: "com.example.terminal")
        #expect(preferences.decision(for: "com.example.browser") == .refuseAndAsk)
    }

    @Test("Every state has a decision, so no application can fall through the rule.")
    func everyStateDecides() {
        let decisions = ConsentState.allCases.map(CapturePreferences.decision(for:))
        #expect(Set(decisions) == Set(ConsentDecision.allCases))
    }
}
