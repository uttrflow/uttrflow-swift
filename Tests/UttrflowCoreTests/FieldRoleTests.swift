import Testing

@testable import UttrflowCore

struct FieldRoleTests {
    @Test(
        arguments: [
            ("AXTextField", false, "To", FieldRole.recipient),
            ("AXTextField", false, "Cc:", .recipient),
            ("AXTextField", false, "Subject", .subject),
            ("AXTextField", false, "URL", .addressBar),
            ("AXTextField", false, "Search mail", .search),
            ("AXSearchField", false, "Subject", .search),
            ("AXTextArea", true, "Message body", .message),
            ("AXTextField", false, "First name", .singleLine),
            ("AXGroup", nil, nil, .unknown),
        ] as [(String, Bool?, String?, FieldRole)])
    func roleComesFromTheRoleThenTheLabelThenTheLineCount(
        role: String, multiline: Bool?, label: String?, expected: FieldRole
    ) {
        #expect(FieldRole(accessibilityRole: role, isMultiline: multiline, label: label) == expected)
    }

    @Test func labelWordsMatchWholeWordsOnly() {
        #expect(
            FieldRole(accessibilityRole: "AXTextField", isMultiline: false, label: "Total") == .singleLine)
    }

    @Test func contextCarriesACleanedBoundedLabelAndNoneWhenSecure() {
        let label = AppContext(fieldLabel: " Sub\u{0}ject\n line ").fieldLabel
        #expect(label == "Sub ject line")
        let long = String(repeating: "a", count: AppContext.fieldLabelLimit + 5)
        #expect(AppContext(fieldLabel: long).fieldLabel?.count == AppContext.fieldLabelLimit)
        #expect(AppContext(fieldLabel: " \n ").fieldLabel == nil)
        #expect(AppContext(isSecure: true, fieldLabel: "Subject").fieldLabel == nil)
        #expect(AppContext(accessibilityRole: "AXTextField", fieldLabel: "Subject").fieldRole == .subject)
    }
}
