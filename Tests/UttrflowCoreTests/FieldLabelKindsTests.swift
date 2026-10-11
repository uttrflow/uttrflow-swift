import Foundation
import Testing

@testable import UttrflowCore

struct FieldLabelKindsTests {
    @Test(
        arguments: [
            ("Full name", FieldRole.name),
            ("First name", .name),
            ("Last name", .name),
            ("Your name", .name),
            ("Name", .name),
            ("Surname", .name),
            ("Pura naam", .name),
            ("Name of the street", .address),
            ("Street address", .address),
            ("Address line 2", .address),
            ("City", .address),
            ("House number", .address),
            ("Ghar ka pata", .address),
            ("Billing postcode", .postalCode),
            ("ZIP / Postal code", .postalCode),
            ("Pincode", .postalCode),
            ("Email", .email),
            ("Work email address", .email),
            ("E-mail", .email),
            ("Phone number", .phone),
            ("Mobile", .phone),
            ("Telephone (daytime)", .phone),
            ("Date of birth", .date),
            ("Due date", .date),
            ("Start date (DD/MM/YYYY)", .date),
            ("Janam tithi", .date),
            ("Quantity", .number),
            ("Number of guests", .number),
            ("Order number", .number),
            ("Age", .number),
            ("Website", .webAddress),
            ("Company URL", .webAddress),
            ("Title", .title),
            ("Post headline", .title),
            ("Search the docs", nil),
            ("Subject", nil),
            ("To", nil),
            ("Notes", nil),
            ("Comments", nil),
            ("", nil),
        ] as [(String, FieldRole?)])
    func labelNamesItsKind(label: String, expected: FieldRole?) {
        #expect(FieldLabelKinds.kind(of: label) == expected)
    }

    @Test(
        arguments: [
            "Name or email", "Email or phone", "Name and address", "Street and postcode",
            "City or postcode", "Website or email", "Title and date", "Name, email and phone",
            "Naam ya mobile", "Phone aur email", "Email phone", "Date postcode", "Description",
            "Anything else?", "Your answer", "Details", "Value", "Field 1", "Message", "Reason",
        ])
    func ambiguousOrUnnamedLabelsAbstain(label: String) {
        #expect(FieldLabelKinds.kind(of: label) == nil)
    }

    @Test func onlyAOneLineOrUnknownFieldTakesItsLabelsKind() {
        #expect(FieldLabelKinds.role(structural: .singleLine, label: "Billing postcode") == .postalCode)
        #expect(FieldLabelKinds.role(structural: .unknown, label: "Full name") == .name)
        #expect(FieldLabelKinds.role(structural: .singleLine, label: "Subject") == .singleLine)
        #expect(FieldLabelKinds.role(structural: .singleLine, label: nil) == .singleLine)
        for role in [FieldRole.search, .message, .recipient, .subject, .addressBar] {
            #expect(FieldLabelKinds.role(structural: role, label: "Full name") == role)
        }
    }

    @Test func situationCarriesTheKindAndASecureFieldNone() {
        let postcode = AppContext(
            accessibilityRole: "AXTextField", isMultiline: false, fieldLabel: "Postcode")
        #expect(SituationResolver.resolve(from: postcode).intent.fieldRole == .postalCode)
        let area = AppContext(accessibilityRole: "AXTextArea", isMultiline: true, fieldLabel: "Address")
        #expect(SituationResolver.resolve(from: area).intent.fieldRole == .message)
        let secure = AppContext(
            isSecure: true, accessibilityRole: "AXTextField", isMultiline: false, fieldLabel: "Card number")
        #expect(SituationResolver.resolve(from: secure).intent.fieldRole == .singleLine)
        let unlabelled = AppContext(accessibilityRole: "AXTextField", isMultiline: false)
        #expect(SituationResolver.resolve(from: unlabelled).intent.fieldRole == .singleLine)
    }

    @Test func tableIsBundledAndNamesOnlyLabelKinds() {
        #expect(FieldLabelKinds.table.source == .bundled)
        for row in FieldLabelKinds.table.rows {
            #expect((row.cue == .joiner) == (row.kind == nil), "\(row.id)")
            if let kind = row.kind { #expect(FieldLabelKinds.labelKinds.contains(kind), "\(row.id)") }
            #expect(row.id == row.id.lowercased().split(separator: " ").joined(separator: " "), "\(row.id)")
        }
    }

    @Test func aLabelReadStaysWellUnderTwoMilliseconds() {
        let label = String(repeating: "Billing street address line ", count: 3)
        _ = FieldLabelKinds.kind(of: label)
        let clock = ContinuousClock()
        let samples = (0..<200).map { _ in clock.measure { _ = FieldLabelKinds.kind(of: label) } }.sorted()
        #expect(samples[189] < .milliseconds(2))
    }
}
