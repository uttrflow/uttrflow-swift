import Testing

@testable import UttrflowContext

struct FieldNamesTests {
    private static func names(role: String? = "AXTextField", placeholder: String? = nil) -> FieldNames {
        FieldNames(role: role, subrole: nil, identifier: nil, placeholder: placeholder, description: nil)
    }

    @Test func declaredSecureFieldIsSecureWithoutItsValueBeingRead() {
        var asked = false
        let secure = Self.names(role: "AXSecureTextField").isSecure(value: {
            asked = true
            return "plain"
        })
        #expect(secure)
        #expect(!asked)
    }

    @Test func fieldNamedForASecretIsDeclaredSecure() {
        #expect(Self.names(placeholder: "Password").isDeclaredSecure)
    }

    @Test func undeclaredFieldIsSecureOnlyWhenItsValueIsMaskCharacters() {
        #expect(Self.names().isSecure(value: { "•••••" }))
        #expect(!Self.names().isSecure(value: { "hello" }))
        #expect(!Self.names().isSecure(value: { nil }))
    }
}

struct FieldLabelTests {
    private static func names(
        role: String = "AXTextField", placeholder: String? = nil, description: String? = nil,
        title: String? = nil
    ) -> FieldNames {
        FieldNames(
            role: role, subrole: nil, identifier: nil, placeholder: placeholder, description: description,
            title: title)
    }

    @Test func labelPrefersTitleThenPlaceholderThenDescription() {
        #expect(Self.names(placeholder: "Search", description: "Field", title: "Subject").label == "Subject")
        #expect(Self.names(placeholder: "Search", description: "Field", title: " ").label == "Search")
        #expect(Self.names(description: "Field").label == "Field")
        #expect(Self.names().label == nil)
    }

    @Test func secureFieldHasNoLabel() {
        #expect(Self.names(role: "AXSecureTextField", title: "Subject").label == nil)
    }

    @Test func titleIsReadInTheSameBatchAsTheSecureNames() {
        let log = MessageLog()
        let field = Node(
            id: 1, role: "AXTextField",
            answers: ["AXRole": .value("AXTextField"), "AXTitle": .value("Subject")])
        let names = FocusedFieldRead.names(of: field, in: FakeTree(root: field, messages: log))
        #expect(names.title == "Subject")
        #expect(log.asked == [FocusedFieldRead.nameAttributes.joined(separator: "+")])
    }
}
