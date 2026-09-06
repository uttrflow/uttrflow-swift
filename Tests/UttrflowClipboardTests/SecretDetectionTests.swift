// Tests for credential detection.

import Testing

@testable import UttrflowClipboard

/// The one detection rule with a cost attached to being wrong; every credential below is invented.
@Suite("What must not be legible on a shared screen")
struct SecretDetectionTests {
    @Test(
        "masks a connection string that carries a password",
        arguments: [
            "postgres://admin:s3cr3tpassw0rd@db.example.com:5432/production",
            "postgresql://user:pass@localhost/dev",
            "mongodb+srv://root:letmein@cluster0.example.mongodb.net/",
            "mysql://svc_billing:Xy7!kQ2m@10.0.0.4/orders",
            "redis://default:9fbe1a4c7d@cache.example.com:6379",
            "amqp://guest:guest@rabbit.internal:5672/",
            "DATABASE_URL=postgres://admin:hunter2@db.example.com/app",
        ])
    func connectionStrings(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    /// A URL with a port, or a username and no password, is still just a URL.
    @Test(
        "leaves a URL that carries no password alone",
        arguments: [
            "https://example.com:8443/health",
            "https://readonly@github.com/uttrflow/uttrflow-mac",
            "http://localhost:5432/",
        ])
    func urlsWithoutPasswords(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .link)
    }

    /// Assembled rather than written out, because GitHub's push protection matches these shapes as-is.
    private static let gitLabToken = "glpat-" + "x7Kd9Pq2LmRt4Vw8Nz1C"
    private static let shopifyToken = "shpat_" + "a1b2c3d4e5f6a7b8" + "c9d0e1f2a3b4c5d6"

    @Test(
        "masks a vendor-issued key",
        arguments: [
            "sk-proj-Qv7RkT2mXeL9pAz4NbHc8FwJ",
            "sk-ant-api03-Kk3fD9wQzR2mNvB7xLpT4eYsGh1JcVdA",
            "sk_live_51HxQmvKz8RtYnPbW3LcE",
            "pk_test_7yQmXvKz8RtYnPbW3LcE",
            "ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8",
            "gho_ZzYyXxWwVvUuTtSsRrQqPpOoNnMmLlKk",
            "github_pat_11ABCDEFG0aBcDeFgHiJkLmNoPqRsTuVwXyZ",
            gitLabToken,
            "xoxb-2913847561-3847561290-KdMx8Qw2Lp",
            "AKIAIOSFODNN7EXAMPLE",
            "ASIAY34FZKBOKMUTVV7A",
            "AIzaSyD3mK9pQvXr2NtLw8ZbYc4FeGhJkMnOpQr",
            shopifyToken,
        ])
    func vendorKeys(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    /// The prefix on its own is prose about keys, not a key.
    @Test(
        "does not mask talk about keys",
        arguments: ["sk-", "our sk- keys rotate monthly", "AKIA", "ghp_ tokens are legacy now"])
    func talkAboutKeys(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    @Test("masks a JSON web token, alone or in a header")
    func jsonWebTokens() {
        let token =
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            + ".eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ"
            + ".SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        #expect(ClipKindDetector.kind(of: token) == .secret)
        #expect(ClipKindDetector.kind(of: "Authorization: Bearer \(token)") == .secret)
        // `alg: none` leaves the signature empty and the payload every bit as readable.
        #expect(ClipKindDetector.kind(of: "eyJhbGciOiJub25lIn0.eyJzdWIiOiIxIn0.") == .secret)
    }

    @Test("masks a PEM block, wherever the copy started")
    func pemBlocks() {
        let key = """
            -----BEGIN OPENSSH PRIVATE KEY-----
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtz
            c2gtZWQyNTUxOQAAACDkQ2VydGlmaWNhdGVOb3RSZWFsbHlBS2V5QXRBbGxIZXJl
            -----END OPENSSH PRIVATE KEY-----
            """
        #expect(ClipKindDetector.kind(of: key) == .secret)
        #expect(ClipKindDetector.kind(of: "-----BEGIN CERTIFICATE-----\nMIIB…") == .secret)
    }

    @Test(
        "masks a line that names a secret and then gives one",
        arguments: [
            "API_KEY=9f2b7c4e1a8d3f6b",
            "api_key: 9f2b7c4e1a8d3f6b",
            "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            "password = \"hunter2\"",
            "export GITHUB_TOKEN=abc123def456ghi789",
            "client_secret: 'Qv7RkT2mXeL9pAz4'",
            "  \"privateKey\": \"MIIEvQIBADANBg\",",
        ])
    func namedSecrets(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    /// A whole environment file is caught by any one of its lines.
    @Test("masks an environment file pasted whole")
    func environmentFile() {
        let env = """
            NODE_ENV=production
            PORT=3000
            DATABASE_HOST=db.example.com
            STRIPE_SECRET=sk_live_51HxQmvKz8RtYnPbW3LcE
            """
        #expect(ClipKindDetector.kind(of: env) == .secret)
    }

    /// Naming a secret is not giving one: a type annotation, a placeholder and a prompt are not secrets.
    @Test(
        "does not mask a mention of a secret with nothing behind it",
        arguments: [
            "var password: String",
            "let apiKey: String?",
            "password = nil",
            "Change your password: now",
            "token: true",
        ])
    func mentionsWithoutValues(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    @Test(
        "masks a long generated token nobody standardised",
        arguments: [
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            "Qv7RkT2mXeL9pAz4NbHc8FwJdY3gS6uH",
            "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
            "5f4dcc3b5aa765d61d8327deb882cf99e4a9c8b2",
            "dGhpcy1pcy1hLXZlcnktbG9uZy1iYXNlNjQtdG9rZW4tMTIz",
        ])
    func generatedTokens(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    /// The statistical rule is the loosest one, so its gates matter.
    @Test(
        "does not reach for the entropy rule where it has no business",
        arguments: [
            "shortenough123",
            "abcdefghijklmnopqrstuvwxyz",
            "com.uttrflow.clipboard.watcher.queue1",
            "/Users/naveen/Library/Application1",
            "~/Developer/uttrflow/Sources/Clipboard2",
            "https://example.com/a/verylongpathsegment12345",
            "The quick brown fox jumps over the lazy dog again and again for 24 chars.",
        ])
    func entropyGates(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    /// A multi-line clip is a document, and documents legitimately carry digests.
    @Test("does not mask a document because one line of it looks random")
    func documentsWithDigests() {
        let diff = """
            commit 5f4dcc3b5aa765d61d8327deb882cf99e4a9c8b2
            Author: Someone
                let total = items.count;
            """
        #expect(ClipKindDetector.kind(of: diff) == .code)
    }

    /// Ordinary writing is never a secret, however long.
    @Test(
        "leaves ordinary things alone",
        arguments: [
            "hello",
            "Remember to email Priya about the invoice.",
            "https://example.com/docs#installation",
            "#ff00aa",
            "brew install jq",
            "func greet() { print(\"hi\") }",
        ])
    func ordinaryThings(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    /// Secret is asked first because each of these is also something else.
    @Test("wins over every other kind when a clip is both")
    func secretWinsTies() {
        #expect(ClipKindDetector.kind(of: "postgres://admin:hunter2@db.example.com/app") == .secret)
        #expect(
            ClipKindDetector.kind(of: "curl -H 'Authorization: Bearer sk-proj-Qv7RkT2mXeL9pAz4Nb'")
                == .secret)
        #expect(ClipKindDetector.kind(of: "export API_KEY=9f2b7c4e1a8d3f6b") == .secret)
    }
}
