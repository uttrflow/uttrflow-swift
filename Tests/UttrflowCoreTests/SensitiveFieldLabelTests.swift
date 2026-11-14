// Tests which field labels make a plain text field as private as a secure one.
import Testing

@testable import UttrflowCore

@Suite("Fields labelled as a card number, a code or an identity number")
struct SensitiveFieldLabelTests {
    @Test(
        "a label asking for a card, a code, an account or an identity number makes the field secure",
        arguments: [
            "Card number", "Credit card number", "Debit card number (16 digits)", "Security code",
            "CVV", "CVC", "One-time code", "Verification code", "OTP", "Passcode", "Passphrase",
            "Recovery key", "Account number", "Routing number", "Social security number",
            "Aadhaar number", "Passport number", "Enter your card number",
        ])
    func sensitive(label: String) {
        let context = AppContext(fieldLabel: label)
        #expect(context.isSecure)
        #expect(context.fieldLabel == nil)
        #expect(context.adding(onScreenNames: ["Ada"]).onScreenNames.isEmpty)
    }

    @Test(
        "a label that only shares a word with those is an ordinary field",
        arguments: [
            "Card game name", "Passwordless sign in help", "Business card design", "Gift card message",
            "Number of guests", "Phone number", "Order number", "House number", "Account name",
            "Account holder", "Code review comment", "Promo code", "Coupon code", "Key points",
            "Recovery plan", "Verification status", "Passport photo caption", "Routing key words",
            "Security deadline", "Name on the card",
        ])
    func ordinary(label: String) {
        let context = AppContext(fieldLabel: label)
        #expect(!context.isSecure)
        #expect(context.fieldLabel == label)
    }

    @Test("a field the system calls secure stays secure whatever its label says")
    func systemSecureStands() {
        #expect(AppContext(isSecure: true, fieldLabel: "Notes").isSecure)
    }

    @Test("the kind a label names can be read back as sensitive")
    func roleIsNamed() {
        #expect(FieldLabelKinds.kind(of: "Card number") == .sensitive)
        #expect(FieldLabelKinds.kind(of: "Card game name") == .name)
    }
}
