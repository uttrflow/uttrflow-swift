import Testing

@testable import UttrflowClipboard

/// The one detection rule with a cost attached to being wrong.
///
/// Every credential below is invented — the shapes are real, the values are not — but
/// they are shaped exactly as the issuers shape them, because a rule tested against
/// made-up shapes is a rule that has not been tested.
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

    /// A URL with a port, or with a username and no password, is still just a URL. This
    /// is the boundary the connection-string rule is drawn around.
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

    /// Two of these are assembled rather than written out, and only two.
    ///
    /// Every string here is invented — that is the point of the suite, and none of them
    /// opens anything. But GitHub's push protection matches on shape, not on whether a
    /// token is real, and these fixtures match by construction: their entire job is to
    /// satisfy the patterns in ``SecretShapes``. Written as literals, the GitLab and
    /// Shopify ones make this repository unpushable without clicking "allow" on a
    /// false-positive form — and so does every fork, for every contributor, for ever.
    ///
    /// The detector is fed exactly the same characters either way; only the bytes on
    /// disk differ. The rest are left as literals because the scanner does not object to
    /// them: AWS publishes `AKIAIOSFODNN7EXAMPLE` as its own example, and the others
    /// carry checks that an invented value fails.
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

    /// The prefix on its own is prose about keys, not a key. The minimum lengths in the
    /// rules exist so that writing about this feature does not set off the feature.
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

    /// A whole environment file is caught by any one of its lines, which is the reason
    /// that rule is anchored to a line ending rather than to the end of the text.
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

    /// Naming a secret is not the same as giving one. A type annotation, a placeholder
    /// and a prompt all mention a password and none of them is one — and masking every
    /// model in a codebase that has a password field would be noise, not protection.
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

    /// The statistical rule is the loosest one here, so its gates matter. A short token,
    /// one with no digit in it, one with a full stop in it, one that opens like a path,
    /// and a whole paragraph are all left alone.
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

    /// A multi-line clip is a document, and documents legitimately carry digests. A diff
    /// with a commit hash in it is code, not a credential — masking the whole file to
    /// hide one hash would hide far more than it protected.
    @Test("does not mask a document because one line of it looks random")
    func documentsWithDigests() {
        let diff = """
            commit 5f4dcc3b5aa765d61d8327deb882cf99e4a9c8b2
            Author: Someone
                let total = items.count;
            """
        #expect(ClipKindDetector.kind(of: diff) == .code)
    }

    /// Ordinary writing is never a secret, however long it is. This is the population
    /// the whole file is trying not to touch.
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

    /// Secret is asked first, and this is why: each of these is genuinely also something
    /// else, and being right about the something else would put a credential on screen.
    @Test("wins over every other kind when a clip is both")
    func secretWinsTies() {
        #expect(ClipKindDetector.kind(of: "postgres://admin:hunter2@db.example.com/app") == .secret)
        #expect(
            ClipKindDetector.kind(of: "curl -H 'Authorization: Bearer sk-proj-Qv7RkT2mXeL9pAz4Nb'")
                == .secret)
        #expect(ClipKindDetector.kind(of: "export API_KEY=9f2b7c4e1a8d3f6b") == .secret)
    }
}
