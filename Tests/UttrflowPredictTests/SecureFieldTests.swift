import Testing

@testable import UttrflowPredict

@Suite("Recognising a field that hides what is typed")
struct SecureFieldTests {
    @Test("The AppKit secure role is secure.")
    func roleIsSecure() {
        #expect(
            SecureField.isDeclaredSecure(
                role: "AXSecureTextField", subrole: nil, identifier: nil, placeholder: nil,
                description: nil))
    }

    @Test("The secure subrole is secure, whatever the role says.")
    func subroleIsSecure() {
        #expect(
            SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: "AXSecureTextField", identifier: nil, placeholder: nil,
                description: nil))
    }

    @Test("A web password field that names itself is secure even without the role.")
    func nameBetraysAPasswordField() {
        #expect(
            SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: "login_password", placeholder: nil,
                description: nil))
        #expect(
            SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: nil, placeholder: "Passcode",
                description: nil))
    }

    @Test("An ordinary field is not secure.")
    func ordinaryIsNotSecure() {
        #expect(
            !SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: "search", placeholder: "Search",
                description: nil))
    }

    @Test("A value of mask characters alone reads as masked, so a dots-only field is caught.")
    func masksAreDetected() {
        #expect(SecureField.looksMasked("••••••••"))
        #expect(SecureField.looksMasked("********"))
    }

    @Test("Ordinary text and a tiny value are not mistaken for a mask.")
    func realTextIsNotMasked() {
        #expect(!SecureField.looksMasked("hello world"))
        #expect(!SecureField.looksMasked("**"))
        #expect(!SecureField.looksMasked(""))
    }
}

@Suite("The one secure-field rule both dictation boundaries ask")
struct SecureFieldRuleTests {
    @Test("a declared secure field is secure without its value being read")
    func declaredSkipsTheValue() {
        var read = false
        let secure = SecureField.isSecure(
            role: SecureField.secureRole, subrole: nil, identifier: nil, placeholder: nil,
            description: nil,
            value: {
                read = true
                return "hunter"
            })

        #expect(secure)
        #expect(!read)
    }

    @Test("an undeclared field showing only mask characters is secure")
    func maskedValueIsSecure() {
        #expect(
            SecureField.isSecure(
                role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil, description: nil,
                value: { "••••••" }))
    }

    @Test("an ordinary field, or one that will not say, is not secure")
    func ordinaryIsNot() {
        #expect(
            !SecureField.isSecure(
                role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil, description: nil,
                value: { "see you at noon" }))
        #expect(
            !SecureField.isSecure(
                role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil, description: nil,
                value: { nil }))
    }
}
