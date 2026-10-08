import Testing

@testable import UttrflowCore

struct FieldRoleTests {
    @Test(
        arguments: [
            ("AXTextField", false, "To", FieldRole.singleLine),
            ("AXTextField", false, "Cc:", .singleLine),
            ("AXTextField", false, "Subject", .singleLine),
            ("AXTextField", false, "URL", .singleLine),
            ("AXTextField", false, "Search mail", .singleLine),
            ("AXSearchField", false, "Subject", .search),
            ("AXTextArea", true, "Message body", .message),
            ("AXTextField", false, "First name", .singleLine),
            ("AXGroup", nil, nil, .unknown),
        ] as [(String, Bool?, String?, FieldRole)])
    func structurePrecedesRoleLikeLabels(
        role: String, multiline: Bool?, label: String?, expected: FieldRole
    ) {
        #expect(FieldRole(accessibilityRole: role, isMultiline: multiline, label: label) == expected)
    }

    @Test func labelWordsMatchWholeWordsOnly() {
        #expect(
            FieldRole(accessibilityRole: "AXTextField", isMultiline: false, label: "Total") == .singleLine)
        #expect(
            FieldRole(accessibilityRole: "AXTextField", isMultiline: false, label: "Message to Alice")
                == .singleLine)
        #expect(
            FieldRole(accessibilityRole: "AXTextField", isMultiline: false, label: "Search results notes")
                == .singleLine)
        #expect(
            FieldRole(
                accessibilityRole: "AXTextField", isMultiline: false, label: "Description (URL optional)")
                == .singleLine)
        for label in ["Subject", "To"] {
            #expect(
                FieldRole(accessibilityRole: "AXTextField", isMultiline: false, label: label)
                    == .singleLine,
                "\(label) cannot override the structural text-field role")
        }
    }

    @Test func structureWinsOverRoleLikeWordsInTheLabel() {
        #expect(
            FieldRole(accessibilityRole: "AXTextArea", isMultiline: true, label: "Message to Alice")
                == .message)
        #expect(
            FieldRole(accessibilityRole: "AXTextField", isMultiline: true, label: "Search results")
                == .message)
        #expect(
            FieldRole(
                accessibilityRole: "AXTextField", isMultiline: false, label: "Subject",
                subrole: SecureField.secureRole) == .unknown)
    }

    @Test func contextCarriesACleanedBoundedLabelAndNoneWhenSecure() {
        let label = AppContext(fieldLabel: " Sub\u{0}ject\n line ").fieldLabel
        #expect(label == "Sub ject line")
        let long = String(repeating: "a", count: AppContext.fieldLabelLimit + 5)
        #expect(AppContext(fieldLabel: long).fieldLabel?.count == AppContext.fieldLabelLimit)
        #expect(AppContext(fieldLabel: " \n ").fieldLabel == nil)
        #expect(AppContext(isSecure: true, fieldLabel: "Subject").fieldLabel == nil)
        #expect(AppContext(accessibilityRole: "AXTextField", fieldLabel: "Subject").fieldRole == .singleLine)
        #expect(
            AppContext(
                accessibilityRole: "AXTextField", accessibilitySubrole: SecureField.secureRole,
                fieldLabel: "Subject"
            ).fieldRole == .unknown)
    }
}
