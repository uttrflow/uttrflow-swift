import Testing

@testable import UttrflowCore

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
        #expect(
            SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil,
                description: nil, title: "Card number"))
        #expect(
            SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil,
                description: nil, title: "Password"))
    }

    @Test(
        "Web fields that name one-time codes, card data, PINs and recovery answers are secure.",
        arguments: [
            "one-time-code",
            "otp",
            "Verification code",
            "cc-csc",
            "Card security code",
            "cc-number",
            "Credit card number",
            "PIN",
            "Security answer",
            "recovery_answer",
            "Recovery answer",
            "recoveryQuestion",
            "Recovery code",
            "recovery-phrase",
            "SSN",
            "Date of birth",
        ])
    func sensitiveWebFieldNamesAreSecure(name: String) {
        #expect(
            SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: name, placeholder: nil,
                description: nil))
    }

    @Test(
        "A camelCase name that glues a short code to another word is secure.",
        arguments: [
            "otpField", "otpInput", "enterOtp", "OTPCode", "pinCode", "pinEntry", "userPin",
            "cvvNumber", "cardCvv", "cvcInput", "cscValue", "ssnField", "userSSN", "pin2",
        ])
    func gluedShortCodesAreSecure(name: String) {
        #expect(SecureField.namesASecret(name))
    }

    @Test(
        "An all-lowercase name that glues a short code to a whole field word is secure.",
        arguments: ["otpcode", "cardcvv", "ssnfield", "userotp", "atmpin", "cvvnumber", "pininput"])
    func lowercaseGluedShortCodesAreSecure(name: String) {
        #expect(SecureField.namesASecret(name))
    }

    @Test(
        "An all-lowercase word holding a code's letters, or a postal pin code, is not secure.",
        arguments: ["mapping", "shipping", "pincode", "topping", "spinbox", "cvsreceipt"])
    func lowercaseWordsWithCodeLettersAreNotSecure(name: String) {
        #expect(!SecureField.namesASecret(name))
    }

    @Test(
        "A word that merely starts or ends with a short code's letters is not secure.",
        arguments: ["pinterest", "Pinned", "spinner", "shipping", "Topping", "cvsReceipt", "Spin"])
    func wordsContainingCodeLettersAreNotSecure(name: String) {
        #expect(!SecureField.namesASecret(name))
    }

    @Test("A recovery field that names an email address or a phone number is not secure.")
    func recoveryContactIsNotSecure() {
        #expect(!SecureField.namesASecret("Recovery email"))
        #expect(!SecureField.namesASecret("recovery_phone"))
    }

    @Test("An ordinary field is not secure.")
    func ordinaryIsNotSecure() {
        #expect(
            !SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: "search", placeholder: "Search",
                description: nil))
        #expect(
            !SecureField.isDeclaredSecure(
                role: "AXTextField", subrole: nil, identifier: "shipping_address",
                placeholder: "Promo code", description: nil))
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

@Suite("Reading a value only from a field that does not hide it")
struct SecureFieldReadableValueTests {
    @Test("A field declared secure by its subrole is never asked for its value.")
    func declaredSecureValueIsNeverFetched() {
        var asked = false
        let value = SecureField.readableValue(
            role: "AXTextField", subrole: "AXSecureTextField", identifier: nil, placeholder: nil,
            description: nil,
            value: {
                asked = true; return "correct-horse-battery"
            })
        #expect(value == nil)
        #expect(!asked)
    }

    @Test("A field named for a password is never asked for its value.")
    func namedSecureValueIsNeverFetched() {
        var asked = false
        let value = SecureField.readableValue(
            role: "AXTextField", subrole: nil, identifier: nil, placeholder: "Password",
            description: nil,
            value: {
                asked = true; return "correct-horse-battery"
            })
        #expect(value == nil)
        #expect(!asked)
    }

    @Test("A value of mask characters alone is dropped once read.")
    func maskedValueIsDropped() {
        let value = SecureField.readableValue(
            role: "AXTextField", subrole: nil, identifier: nil, placeholder: nil, description: nil,
            value: { "••••••••" })
        #expect(value == nil)
    }

    @Test("An ordinary field's value comes back as it is.")
    func plainValueIsKept() {
        let value = SecureField.readableValue(
            role: "AXTextArea", subrole: nil, identifier: nil, placeholder: nil, description: nil,
            value: { "see you at six" })
        #expect(value == "see you at six")
    }

    @Test(
        "On screen, a secret's name marks only a field, while the secure role marks every element",
        arguments: [
            ("AXTextField", nil, "Password", true), ("AXTextArea", nil, "One-time code", true),
            ("AXComboBox", nil, "Card number", true), ("AXSearchField", nil, "PIN", true),
            ("AXStaticText", nil, "what's the wifi password?", false),
            ("AXGroup", nil, "send me the OTP", false),
            ("AXCell", nil, "card number ending 4242", false),
            ("AXWebArea", nil, "Reset your password", false),
            ("AXStaticText", "AXSecureTextField", nil, true), ("AXSecureTextField", nil, nil, true),
        ] as [(String, String?, String?, Bool)])
    func secureOnScreen(role: String, subrole: String?, description: String?, secure: Bool) {
        #expect(
            SecureField.isDeclaredSecureOnScreen(
                role: role, subrole: subrole, identifier: nil, placeholder: nil, description: description)
                == secure)
    }
}
