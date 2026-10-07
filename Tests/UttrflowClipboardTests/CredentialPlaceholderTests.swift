import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("Documented credential placeholders")
struct CredentialPlaceholderTests {
    @Test(
        "leaves credential placeholders and vendor examples unmasked",
        arguments: [
            "API_KEY=your-key-here",
            "API_KEY=placeholder-value",
            "API_KEY=changeme-please",
            "API_KEY=<your-api-key>",
            "OPENAI_API_KEY=sk-...",
            "export GITHUB_TOKEN=ghp_" + String(repeating: "x", count: 36),
            "STRIPE_SECRET_KEY=sk_test_your_key_here",
            "PASSWORD=********",
            "DB_PASSWORD=${DB_PASSWORD}",
            "DB_PASSWORD=$DB_PASSWORD",
            "DATABASE_URL=postgres://user:password@localhost:5432/mydb",
            "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
            "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            "API_KEY=xxxxxxxxxxxx",
            "API_KEY=........",
            "# .env.example\nAPI_KEY=your-key-here\nPASSWORD=********",
        ])
    func documentationPlaceholders(_ text: String) {
        #expect(!SecretShapes.matches(text))
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    @Test(
        "leaves common words in a URL password field unmasked",
        arguments: [
            "postgres://user:password@localhost/db", "postgres://user:pass@localhost/db",
            "postgres://user:secret@localhost/db",
        ])
    func commonURLPasswordWords(_ text: String) {
        #expect(!SecretShapes.matches(text))
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    @Test("does not exempt a generated credential with an embedded placeholder word")
    func embeddedPlaceholderWordRemainsSecret() {
        let text = "API_KEY=Qv7RkT2mXeL9pAz4NbHc8FwJdY3gS6uHexample"
        #expect(SecretShapes.matches(text))
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test("does not treat repeated secret characters inside a vendor token as a placeholder")
    func repeatedVendorTokenRemainsSecret() {
        let text = "OPENAI_API_KEY=sk-" + String(repeating: "A", count: 24)
        #expect(SecretShapes.matches(text))
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }
}
