// Tests for credential detection.

import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowClipboard
@testable import UttrflowCore

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

    @Test("masks Telegram bot tokens in single-line and multiline text")
    func telegramBotAddresses() {
        let address = "https://api.telegram.org/bot123456789:AbCdEfGhIjKlMnOpQrStUvWxYz012345678/sendMessage"
        #expect(ClipKindDetector.kind(of: address) == .secret)
        #expect(ClipKindDetector.kind(of: "curl -X POST \(address)\n# send this request") == .secret)
        #expect(ClipKindDetector.kind(of: "https://api.telegram.org/bot123456789/sendMessage") == .link)
        let file = "https://api.telegram.org/file/"
        #expect(
            ClipKindDetector.kind(of: file + "bot123456789:AbCdEfGhIjKlMnOpQrStUvWxYz012345678/photos/f.jpg")
                == .secret)
        #expect(ClipKindDetector.kind(of: file + "bot123456789/photos/f.jpg") == .link)
        #expect(
            ClipKindDetector.kind(
                of: "https://example.com/bot123456789:AbCdEfGhIjKlMnOpQrStUvWxYz012345678/sendMessage")
                == .link)
    }

    /// An invented hex key, built from pieces so no history scanner reads a whole credential here.
    private static let hexKey = ["9f2b", "7c4e", "1a8d", "3f6b"].joined()

    /// An invented 64-hex key base, built the same way.
    private static let keyBase = String(repeating: "0123456789abcdef", count: 4)

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

    @Test(
        "masks checksum-valid English wallet recovery phrases",
        arguments: [
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            "abandon amount liar amount expire adjust cage candy arch gather drum bullet absurd math exhibit",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent",
            "abandon amount liar amount expire adjust cage candy arch gather drum bullet absurd math era live bid rhythm alien crouch saddle",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",
        ])
    func walletRecoveryPhrases(_ phrase: String) {
        #expect(ClipKindDetector.kind(of: phrase) == .secret)
    }

    @Test("requires a valid recovery phrase checksum and leaves ordinary sentences alone")
    func walletRecoveryPhraseNearMisses() {
        let invalidChecksum =
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon above"
        let ordinarySentence = "the quick brown fox jumps over the lazy dog and then runs"
        #expect(ClipKindDetector.kind(of: invalidChecksum) != .secret)
        #expect(ClipKindDetector.kind(of: ordinarySentence) != .secret)
    }

    @Test("masks a valid recovery phrase when it is surrounded by text")
    func walletRecoveryPhraseInSurroundingText() {
        let text =
            "Backup note: abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about. Keep offline."
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test("masks numbered and case-varied recovery phrases at every supported length")
    func walletRecoveryPhraseFormattingVariants() {
        let phrases = [
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            "abandon amount liar amount expire adjust cage candy arch gather drum bullet absurd math exhibit",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon agent",
            "abandon amount liar amount expire adjust cage candy arch gather drum bullet absurd math era live bid rhythm alien crouch saddle",
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art",
        ]

        for phrase in phrases {
            let words = phrase.split(separator: " ")
            let numbered = words.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " ")
            let capitalized = words.map { $0.capitalized }.joined(separator: " ")
            let uppercase = phrase.uppercased()

            #expect(ClipKindDetector.kind(of: numbered) == .secret)
            #expect(ClipKindDetector.kind(of: capitalized) == .secret)
            #expect(ClipKindDetector.kind(of: uppercase) == .secret)
        }

        let prose =
            "1. abandon 2. amount 3. liar 4. amount 5. expire 6. adjust 7. this 8. is 9. ordinary 10. prose 11. with 12. numbers"
        #expect(ClipKindDetector.kind(of: prose) != .secret)
    }

    @Test("masks vendor tokens in multiline clips without matching prose")
    func vendorTokensInMultilineClips() {
        let tokens = [
            "xapp-" + "1-A0123456789-0123456789-0123456789abcdef",
            "whsec_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6",
            "hf_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6",
            "pypi-" + "AgEIcHlwaS5vcmcCJDI1MmQ2MzRhLTAxMjMtNDU2Ny04OWFi",
            "dckr_pat_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6",
            "lin_api_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6",
            "sbp_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6",
            "hvs." + "CAESID0123456789abcdefghijABCDEFGHIJKL",
        ]
        let prefixes = ["xapp-", "whsec_", "hf_", "pypi-", "dckr_pat_", "lin_api_", "sbp_", "hvs."]

        for token in tokens {
            #expect(ClipKindDetector.kind(of: token) == .secret, "Must mask \(token.prefix(8))")
            #expect(
                ClipKindDetector.kind(of: "NOTE=staging\nTOKEN=\(token)") == .secret,
                "Must mask multiline \(token.prefix(8))")
        }

        for prefix in prefixes {
            let prose = "The \(prefix) prefix appears in this documentation."
            #expect(ClipKindDetector.kind(of: prose) != .secret, "Must leave prose about \(prefix) alone")
        }
    }

    @Test("masks generated passwords with every symbol the byte scanner accepts")
    func generatedPasswordsWithPunctuation() {
        let token = "K9x" + "$+<=>^|~`\\" + "Qz7Tr2Bn8LmVa"
        #expect(SecretShapes.hasHighEntropyTokenByCharacter(token))
        #expect(ClipKindDetector.kind(of: token) == .secret)
        #expect(ClipKindDetector.kind(of: "K9x$Qz7^Tr2=Bn8<") == .secret)
        #expect(ClipKindDetector.kind(of: "K9x$Qz7Tr2Bn8LmVa") == .secret)

        for symbol in Array("$+<=>^|~`\\") {
            let userinfo = "K9x" + String(symbol) + "Qz7Tr2Bn8LmVa"
            #expect(
                SecretShapes.hasTokenUserinfoURL("https://\(userinfo)@host.example/repo"),
                "URL userinfo containing \(symbol) must use the same generated-token alphabet")
        }
    }

    @Test("keeps generated credentials detectable beside non-ASCII characters")
    func generatedCredentialsAtNonASCIIBoundaries() {
        let tokens = [
            Self.keyBase,
            "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            "Zx9kLmQ2rT7pQ3vB8nW4yH6sAbCdEfGh",
            "K9x$Qz7Tr2Bn8LmVa",
        ]
        let boundaries = ["’", "é", "\u{200B}", "😀", "\u{0301}", "\u{00A0}"]

        for token in tokens {
            let byteResult = SecretShapes.hasHighEntropyToken(token)
            #expect(byteResult)
            #expect(SecretShapes.hasHighEntropyTokenByCharacter(token) == byteResult)
            for boundary in boundaries {
                for text in [boundary + token, token + boundary] {
                    #expect(
                        SecretShapes.hasHighEntropyTokenByCharacter(text) == byteResult,
                        "Character path changed the result for \(text.debugDescription)")
                    #expect(
                        SecretShapes.hasHighEntropyToken(text) == byteResult,
                        "Detection changed the result for \(text.debugDescription)")
                    #expect(SecretShapes.matches(text), "Missed \(text.debugDescription)")
                }
            }
        }
    }

    @Test("keeps bearer URLs and card numbers detectable beside non-ASCII characters")
    func bearerURLsAndCardsAtNonASCIIBoundaries() {
        let webhook = "hooks.slack.com/services/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"
        for boundary in ["’", "é", "\u{200B}", "😀", "\u{0301}", "\u{00A0}"] {
            for text in [boundary + webhook, webhook + boundary] {
                #expect(SecretShapes.matches(text), "Missed \(text.debugDescription)")
                #expect(ClipKindDetector.kind(of: text) == .secret)
            }
        }

        #expect(SecretShapes.matches("4111111111111111\u{0301}"))
        #expect(ClipKindDetector.kind(of: "4111111111111111\u{0301}") == .secret)
    }

    @Test(
        "leaves canonical UUIDs as ordinary text",
        arguments: [
            "eaff309c-ad68-4386-b070-c415ed7e70ca",
            "4283fefc-63f0-4e9f-a7d3-f51c8b47a2e6",
            "123e4567-e89b-12d3-a456-426614174000",
            "00000000-0000-4000-8000-000000000000",
        ])
    func uuids(_ text: String) {
        #expect(!SecretShapes.looksGenerated(text))
        #expect(ClipKindDetector.kind(of: text) == .text)
    }

    @Test("the byte and character readers leave canonical UUIDs alone")
    func uuidReadersAgree() {
        let examples = [
            "99512f9b-a5c5-4507-a498-a66ccae430d7",
            "99512F9B-A5C5-4507-A498-A66CCAE430D7",
        ]
        for uuid in examples {
            #expect(!SecretShapes.hasHighEntropyToken(uuid))
            #expect(!SecretShapes.hasHighEntropyTokenByCharacter(uuid))
            #expect(
                SecretShapes.hasHighEntropyToken(uuid) == SecretShapes.hasHighEntropyTokenByCharacter(uuid))
        }

        var random = Seeded(seed: 441_900)
        for _ in 0..<1_000 {
            let uuid = Self.randomUUID(&random)
            #expect(!SecretShapes.hasHighEntropyToken(uuid), "byte reader masked \(uuid)")
            #expect(!SecretShapes.hasHighEntropyTokenByCharacter(uuid), "character reader masked \(uuid)")
            #expect(
                SecretShapes.hasHighEntropyToken(uuid) == SecretShapes.hasHighEntropyTokenByCharacter(uuid))
        }
    }

    private static func randomUUID(_ random: inout Seeded) -> String {
        let alphabet = Array("0123456789abcdef")
        let groups = [8, 4, 4, 4, 12].map { length in
            var group = ""
            for _ in 0..<length {
                group.append(alphabet[Int(random.next() % UInt64(alphabet.count))])
            }
            return group
        }
        return groups.joined(separator: "-")
    }

    @Test("keeps masking generated tokens and rejects malformed UUID lookalikes")
    func uuidLookalikesAndRealSecrets() {
        #expect(ClipKindDetector.kind(of: "K9x$Qz7Tr2Bn8LmVa") == .secret)
        #expect(SecretShapes.looksGenerated("eaff309c-ad68-4386-b070-c415ed7e70c"))
        #expect(SecretShapes.looksGenerated("eaff309c-ad68-4386-b070-c415ed7e70ca-extra"))
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
            "password: contraseñasecreta",
            "password: ⱡⱡⱡⱡⱡⱡⱡⱡⱡⱡⱡⱡ",
            "SECRET_KEY = \"django-insecure-abcdefghijklmnop\"",
            "secret_key: \"abcd1234efgh5678\"",
            "secret-keys = abcd1234efgh5678",
            "SECRETKEY=abcd1234efgh5678",
            "X=123\nENCRYPTION_KEY=" + hexKey,
            "X=123\nencryption-key=" + hexKey,
            "X=123\nencryptionkey=" + hexKey,
            "X=123\nSIGNING_KEY=" + hexKey,
            "X=123\nsigning-key=" + hexKey,
            "X=123\nsigningkey=" + hexKey,
            "X=123\nMASTER_KEY=" + hexKey,
            "X=123\nmaster-key=" + hexKey,
            "X=123\nmasterkey=" + hexKey,
            "X=123\nAPP_KEY=" + hexKey,
            "X=123\napp-key=" + hexKey,
            "X=123\nappkey=" + hexKey,
            "X=123\nJWT_KEY=" + hexKey,
            "X=123\njwt-key=" + hexKey,
            "X=123\njwtkey=" + hexKey,
            "Endpoint=https://example.invalid/\nAccountKey=" + hexKey + "==",
            "X=123\nSharedAccessKey=" + hexKey,
            "X=123\nSharedAccessSignature=sv2023" + hexKey,
            "X=123\nAZURE_STORAGE_KEY=" + hexKey,
            "Accept: */*\nOcp-Apim-Subscription-Key: " + hexKey,
            "Accept: */*\nX-Auth-Key: " + hexKey,
        ])
    func namedSecrets(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test(
        "masks a passphrase, as SSH, GPG and Wi-Fi files call it",
        arguments: [
            "passphrase: Zx9kLmQ2rT7p",
            "PASSPHRASE=Zx9kLmQ2rT7p",
            "wpa_passphrase=correcthorsebattery",
            "GPG_PASSPHRASES = \"Zx9kLmQ2rT7p\"",
        ])
    func passphrases(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test(
        "masks a named secret followed by a comment, or inside a one-line object",
        arguments: [
            "password = \"Zx9kLmQ2rT7p\"  # rotate monthly",
            "export API_KEY=\"abc123def456\" # dev",
            "API_KEY=abc123def456 // staging",
            "token: 'Zx9kLmQ2rT7p', // old one",
            "{\"apiKey\":\"Zx9kLmQ2rT7p\"}",
            "{\"user\": \"deploy\", \"password\": \"Zx9kLmQ2rT7p\"}",
            "const config = { apiKey: \"Zx9kLmQ2rT7p\", region: \"us\" };",
            "[{'secret': 'Zx9kLmQ2rT7p'}]",
        ])
    func commentsAndObjects(_ text: String) {
        #expect(SecretShapes.hasNamedSecret(text))
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test("masks credential fields copied from common config files and headers")
    func structuredCredentials() {
        let session = "Zx9kLmQ2rT7pQ3vB8nW4yH6sAbCdEf"
        let dockerAuth = Data("user:password".utf8).base64EncodedString()
        let privateKey = Data(
            "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAKE\n-----END PRIVATE KEY-----".utf8
        )
        .base64EncodedString()
        let dockerMulti = """
            {
              "auths": {
                "registry.example.com": {
                  "auth": "\(dockerAuth)"
                }
              }
            }
            """
        let cases = [
            (
                "A=1\nSECRET_KEY_BASE=" + Self.keyBase,
                "A=1 SECRET_KEY_BASE=" + Self.keyBase
            ),
            (
                "# credentials\nmachine example.com login u password hunter2x9\ndefault login other password k9hunter",
                "machine example.com login u password hunter2x9"
            ),
            (
                "Host: example.com\nCookie: session=\(session)\nAccept: */*",
                "Cookie: session=\(session)"
            ),
            (
                "HTTP/1.1 200 OK\nSet-Cookie: __Host-session=\(session); Path=/; HttpOnly\nContent-Type: text/plain",
                "Set-Cookie: __Host-session=\(session); Path=/; HttpOnly"
            ),
            (
                dockerMulti,
                #"{"auths":{"registry.example.com":{"auth":"\#(dockerAuth)"}}}"#
            ),
            (
                "apiVersion: v1\nkind: Config\nusers:\n- name: deploy\n  user:\n    client-key-data: \(privateKey)",
                "client-key-data: \(privateKey)"
            ),
        ]

        for (multiline, singleLine) in cases {
            #expect(ClipKindDetector.kind(of: multiline) == .secret, "Must mask \(multiline.prefix(32))")
            #expect(ClipKindDetector.kind(of: singleLine) == .secret, "Must also mask its one-line form")
        }
    }

    @Test("masks generated session cookies at every position in a Cookie header")
    func sessionCookiesBeyondTheFirstTwoPairs() {
        let session = "Zx9kLmQ2rT7pQ3vB8nW4yH6sAbCdEf"
        for prefix in ["", "a=1; ", "a=1; b=2; ", "a=1; b=2; c=3; d=4; "] {
            #expect(
                ClipKindDetector.kind(of: "Host: example.com\nCookie: \(prefix)session=\(session)") == .secret
            )
        }
        #expect(ClipKindDetector.kind(of: "Cookie: theme=dark; layout=compact") != .secret)
    }

    @Test("does not treat cookie prose or an auth type declaration as a credential")
    func structuredCredentialFalsePositives() {
        #expect(ClipKindDetector.kind(of: "A sentence about cookies is ordinary prose.") != .secret)
        #expect(ClipKindDetector.kind(of: "var auth: String") != .secret)
        #expect(ClipKindDetector.kind(of: "Cookie: theme=dark; layout=compact") != .secret)
        #expect(ClipKindDetector.kind(of: #"{"auth":"not-a-base64-user-password"}"#) != .secret)
    }

    /// Quote marks frame a value rather than belong to it, so each quoted value is judged on its own.
    @Test("judges each quoted value of a one-line structure on its own")
    func quotedValuesJudgedAlone() {
        for key in ["auth", "name", "branch"] {
            #expect(ClipKindDetector.kind(of: #"{"\#(key)":"not-a-base64-user-password"}"#) != .secret)
            #expect(ClipKindDetector.kind(of: "{'\(key)':'release-2nd-build-v2'}") != .secret)
            #expect(ClipKindDetector.kind(of: #"{"\#(key)":"Zx9kLmQ2rT7pQ3vB8nW4"}"#) == .secret)
            #expect(ClipKindDetector.kind(of: "{'\(key)':'Zx9kLmQ2rT7pQ3vB8nW4'} é") == .secret)
        }
        #expect(ClipKindDetector.kind(of: #"Zx9kLm"Q2rT7pQ3vB8nW4"#) == .secret)
    }

    /// A quoted value followed by more of an expression, or a bare value run into a `#`, is not a value that ended.
    @Test(
        "does not mask a quoted string that only starts an expression",
        arguments: [
            "log(\"token: \" + t + \" done\")",
            "print(\"password: \", pw)",
            "password = \"a\" + suffix",
            "token=abc#def more",
        ])
    func quotedExpressions(_ text: String) {
        #expect(SecretShapes.hasNamedSecret(text) == false)
    }

    @Test(
        "masks a webhook or signed address, which works for whoever holds it",
        arguments: [
            "https://hooks.slack.com/services/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",
            "https://discord.com/api/webhooks/123456789012345678/Zx9kLmQ2rT7pQ3vB8nW4yH6sAbCdEf",
            "https://example.webhook.office.com/webhookb2/0000-1111@2222-3333/IncomingWebhook/abcd/4444",
            "https://example.blob.core.windows.net/c/f?sv=2022-11-02&se=2026-01-01&sp=r&sig=Zx9kLmQ2rT7p%3D",
            "https://bucket.s3.amazonaws.com/f?X-Amz-Expires=300&X-Amz-Signature=0a1b2c3d4e5f6a7b",
            "https://example.com/reset?token=Zx9kLmQ2rT7pQ3vB",
            "https://example.com/callback#access_token=Zx9kLmQ2rT7pQ3vB&type=bearer",
            "Post to \"https://hooks.slack.com/services/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\" today",
        ])
    func bearerAddresses(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test(
        "masks generated query credentials and shaped webhooks",
        arguments: [
            "https://api.example.com/v1?token=Zx9kLmQ2rT7pQ3vB",
            "https://api.example.com/v1?access_token=Zx9kLmQ2rT7pQ3vB",
            "https://api.example.com/v1?sig=Zx9kLmQ2rT7pQ3vB",
            "https://api.example.com/v1?signature=Zx9kLmQ2rT7pQ3vB",
            "https://api.example.com/v1?X-Goog-Signature=Zx9kLmQ2rT7pQ3vB",
            "https://hooks.slack.com/services/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",
            "hooks.slack.com/services/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",
            "https://discord.com/api/webhooks/123456789012345678/Zx9kLmQ2rT7pQ3vB8nW4yH6sAbCdEf",
        ])
    func generatedBearerAddresses(_ text: String) {
        #expect(SecretShapes.matches(text))
    }

    @Test("masks generated credentials in common URL parameter spellings")
    func generatedCredentialsInURLParameters() {
        let names = [
            "X-Amz-Security-Token", "X_Amz_Security_Token", "apikey", "api-key", "api_key",
            "key", "auth", "jwt", "password", "code",
        ]
        let value = "Zx9kLmQ2rT7p" + "Q3vB"

        for name in names {
            let text = "https://api.example.com/v1?\(name)=\(value)"
            #expect(
                ClipKindDetector.kind(of: text) == .secret,
                "Must mask a generated value for \(name)")
        }
    }

    @Test("does not mask short or ordinary URL parameter values")
    func ordinaryValuesInCredentialURLParameters() {
        let names = [
            "X-Amz-Security-Token", "X_Amz_Security_Token", "apikey", "api-key", "api_key",
            "key", "auth", "jwt", "password", "code",
        ]

        for name in names {
            for value in ["home", "en"] {
                let text = "https://api.example.com/v1?\(name)=\(value)"
                #expect(!SecretShapes.matches(text), "Must leave \(name)=\(value) alone")
                #expect(ClipKindDetector.kind(of: text) == .link, "Must classify \(name)=\(value) as a link")
            }
        }
    }

    @Test(
        "leaves URL placeholders and webhook documentation pages alone",
        arguments: [
            "https://api.example.com/v1?token=YOUR_TOKEN_HERE",
            "https://api.example.com/v1?access_token=ACCESS_TOKEN",
            "https://api.example.com/v1?token=REPLACE_ME_PLEASE",
            "https://api.example.com/v1?token=${TOKEN}",
            "https://api.example.com/v1?token=$API_TOKEN",
            "https://api.example.com/v1?token=<YOUR_TOKEN>",
            "https://api.example.com/v1?token=xxxxxxxxxxxx",
            "https://api.example.com/v1?sig=00000000",
            "https://api.example.com/v1?X-Goog-Signature=REDACTED",
            "https://api.example.com/v1?token=unsubscribe",
            "https://api.example.com/v1?token=undefined",
            "https://api.example.com/v1?signature=required",
            "https://hooks.slack.com/services/apps/overview",
            "https://discord.com/api/webhooks/docs/overview",
        ])
    func placeholderBearerAddresses(_ text: String) {
        #expect(!SecretShapes.matches(text))
        #expect(ClipKindDetector.kind(of: text) == .link)
    }

    @Test(
        "masks a webhook nested in another address, a percent-encoded token name, and a host with a closing dot",
        arguments: [
            "https://example.com/r?next=https://hooks.slack.com/services/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",
            "https://example.com/r?a=1&redirect=https://hooks.slack.com/services/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#x",
            "https://web.archive.org/web/2024/https://discord.com/api/webhooks/123456789012345678/Zx9kLmQ2rT7pQ3vB8nW4yH6sAbCdEf",
            "https://api.example.com/x?access%5Ftoken=Zx9kLmQ2rT7pQ3vB",
            "https://api.example.com/x?ACCESS%5ftoken=Zx9kLmQ2rT7pQ3vB",
            "https://api.example.com/x?%74oken=Zx9kLmQ2rT7pQ3vB",
            "https://hooks.slack.com./services/T0AB1CD2E/B0FG3HI4J/Zx9kLmQ2rT7pQ3vB8nW4yH6s",
            "https://discord.com./api/webhooks/123456789012345678/Zx9kLmQ2rT7pQ3vB8nW4yH6sAbCdEf",
        ])
    func disguisedBearerAddresses(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test(
        "leaves an ordinary address with a query alone",
        arguments: [
            "https://hooks.slack.com/",
            "https://discord.com/api/webhooks",
            "https://example.com/search?q=token&page=2",
            "https://example.com/login?token=",
            "https://example.com/login?token={token}",
            "https://example.com/watch?v=dQw4w9WgXcQ&t=42",
            "https://example.com/r?next=https://hooks.slack.com/",
            "https://example.com/r?next=https://example.org/services/a/b/c",
            "https://example.com/x?q%5Fx=Zx9kLmQ2rT7pQ3vB",
            "https://example.com/x?%zztoken=Zx9kLmQ2rT7pQ3vB",
            "https://hooks.slack.com../services/a/b/c",
        ])
    func ordinaryAddresses(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .link)
    }

    @Test("masks quoted named secrets whose value contains an escaped quote")
    func escapedQuotesInNamedSecrets() {
        let dotenv = #"password="abc123\"def456""#
        #expect(SecretShapes.hasNamedSecret(dotenv))
        #expect(ClipKindDetector.kind(of: dotenv) == .secret)

        let json = #"""
            {
              "password": "abc123\"def456",
              "enabled": true
            }
            """#
        #expect(SecretShapes.hasNamedSecret(json))
        #expect(ClipKindDetector.kind(of: json) == .secret)
    }

    @Test("counts odd and even backslash runs before a quote")
    func quoteEscapingParity() {
        #expect(ClipKindDetector.kind(of: #"password="abc123\"def456""#) == .secret)
        #expect(ClipKindDetector.kind(of: #"password="abc123\\\"def456""#) == .secret)
        #expect(ClipKindDetector.kind(of: #"password="abc123\\""#) == .secret)
        #expect(!SecretShapes.hasNamedSecret(#"password="abc123\\"def456""#))
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

    /// A short invented value with digits, built from pieces so no history scanner reads a whole credential here.
    private static let shortValue = ["Kq7", "v2m", "X"].joined()

    /// A longer invented value with digits, built the same way.
    private static let longValue = ["Rt4", "Vw8N", "z1Cq", "7mKd", "L"].joined()

    /// Names written the way variables are, with a prefix or in camelCase, which a whole-word rule never reached.
    static let prefixedNames = [
        "DB_PASSWORD", "GITHUB_TOKEN", "JWT_SECRET", "STRIPE_API_KEY", "db_password", "dbPassword",
        "SMTP_PASS", "POSTGRES_PASSWORD", "AWS_SECRET_ACCESS_KEY", "DATABASE_PASSWORD",
    ]

    @Test(
        "masks a prefixed or camelCase secret name with a short value on one line", arguments: prefixedNames)
    func prefixedNameOneLine(_ name: String) {
        #expect(ClipKindDetector.kind(of: name + "=" + Self.shortValue) == .secret)
    }

    @Test("masks a prefixed or camelCase secret name inside an environment block", arguments: prefixedNames)
    func prefixedNameInBlock(_ name: String) {
        let env = "APP_ENV=production\n" + name + "=" + Self.longValue + "\nPORT=8080"
        #expect(ClipKindDetector.kind(of: env) == .secret)
    }

    @Test("masks a passphrase of letters under a prefixed name in a block")
    func passphraseInBlock() {
        let passphrase = ["correct", "horse", "battery", "staple", "one"].joined()
        let env =
            "APP_ENV=production\nDATABASE_HOST=db.example.com\nDATABASE_PASSWORD=" + passphrase
            + "\nPORT=8080"
        #expect(ClipKindDetector.kind(of: env) == .secret)
    }

    @Test("masks a short exported token followed by another export")
    func exportedTokenInBlock() {
        let block = "export GITHUB_TOKEN=" + Self.shortValue + "\nexport NODE_ENV=production"
        #expect(ClipKindDetector.kind(of: block) == .secret)
    }

    @Test("masks a prefixed name in YAML and a camelCase name in JSON")
    func configFiles() {
        let yaml = "database:\n  host: db.example.com\n  db_password: " + Self.shortValue + "\n  port: 5432"
        #expect(ClipKindDetector.kind(of: yaml) == .secret)
        let json = "{\n  \"dbPassword\": \"" + Self.shortValue + "\",\n  \"port\": 5432\n}"
        #expect(ClipKindDetector.kind(of: json) == .secret)
    }

    @Test("masks a connection string that gives a password and no user")
    func passwordOnlyConnectionString() {
        #expect(
            ClipKindDetector.kind(of: "redis://:" + Self.shortValue + "@cache.example.com:6379") == .secret)
    }

    /// The keyword's own end still needs a boundary, so a longer word that starts with one is not a name.
    @Test(
        "does not mask a word that only starts with a secret's name",
        arguments: [
            "passwordless login", "token_count: 128000", "tokenizer: 12345", "passwords_enabled: true",
        ])
    func longerWords(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    /// A digit-bearing value under a name that ends in a keyword is masked, since the rule cannot tell a limit from a PIN.
    @Test("masks a numeric setting whose name ends in a secret's name")
    func numericSettingUnderKeyword() {
        #expect(ClipKindDetector.kind(of: "max_tokens: 4096") == .secret)
    }

    /// Naming a secret is not giving one: a type annotation, a placeholder and a prompt are not secrets.
    @Test(
        "does not mask a mention of a secret with nothing behind it",
        arguments: [
            "var password: String",
            "var signing_key: String",
            "var key: String",
            "var accountKey: String",
            "X=123\npublic_key=" + hexKey,
            "let apiKey: String?",
            "password = nil",
            "Change your password: now",
            "token: true",
            "password: 忘れた場合は管理者に連絡してください",
            "secret: 这是一个秘密不要告诉别人",
            "APIキーの設定方法 token: 設定画面から発行してください",
            "pwd: 三",
            "token: 一つ目",
            "注文番号 ００１２３４５６７８９００１２３４５６７８９００１２３４５６７８９",
        ])
    func mentionsWithoutValues(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    /// Code that loads a credential names it and points elsewhere, which is not giving one.
    @Test(
        "does not mask a line that only reads a secret from somewhere else",
        arguments: [
            "let token = request.token",
            "const apiKey = process.env.API_KEY;",
            "secret = settings.SECRET_KEY",
            "password = getpass.getpass()",
            "token = os.environ[\"GITHUB_TOKEN\"]",
            "self.accessToken = accessToken",
            "let password = passwordField.text ?? \"\"",
            "if password == confirmPassword {",
        ])
    func references(_ text: String) {
        #expect(SecretShapes.hasNamedSecret(text) == false)
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    /// Quoted values, values with digits and long bare words still count, built from pieces so no scanner flags the source.
    @Test(
        "still masks a named secret whose value is given rather than pointed at",
        arguments: [
            "password = \"" + "correct.horse.battery" + "\"",
            "API_KEY=" + "x7Kd9Pq2.LmRt4Vw8",
            "API_KEY=" + "correcthorsebatterystaple",
            "token = " + "settings.deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
            "secret: " + "vault.read(path)",
        ])
    func givenValues(_ text: String) {
        #expect(SecretShapes.hasNamedSecret(text))
        #expect(ClipKindDetector.kind(of: text) == .secret)
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

    @Test("leaves embedded data and package integrity hashes readable")
    func encodedContentAndIntegrityHashes() {
        let payload = Data((0..<64).map(UInt8.init)).base64EncodedString()
        let dataUris = [
            "data:image/png;base64,\(payload)",
            "DATA:image/png;base64,\(payload)",
            "data:text/plain;charset=utf-8;base64,\(payload)",
            "data:;base64,\(payload)",
            "<img src=\"data:image/png;base64,\(payload)\">",
            "<img alt=\"icon\" src='data:image/png;base64,\(payload)'>",
            "body { background: url(data:image/svg+xml;base64,\(payload)); }",
            "background:url(\"data:image/svg+xml;base64,\(payload)\")",
            "background:url('data:image/svg+xml;base64,\(payload)')",
        ]

        for text in dataUris {
            #expect(!SecretShapes.hasHighEntropyTokenByCharacter(text))
            #expect(ClipKindDetector.kind(of: text) != .secret)
        }

        let malformedData = [
            "data:K9x$Qz7Tr2Bn8LmVa",
            "data:image/png;base64,not!base64-K9x$Qz7Tr2Bn8LmVa",
        ]
        for text in malformedData {
            #expect(SecretShapes.hasHighEntropyTokenByCharacter(text))
            #expect(ClipKindDetector.kind(of: text) == .secret)
        }

        let appendedCredential = "src=\"data:image/png;base64,\(payload)\">K9x$Qz7Tr2Bn8LmVa"
        #expect(SecretShapes.hasHighEntropyTokenByCharacter(appendedCredential))
        #expect(ClipKindDetector.kind(of: appendedCredential) == .secret)

        for (bits, byteCount) in [(256, 32), (384, 48), (512, 64)] {
            let digest = Data((0..<byteCount).map(UInt8.init)).base64EncodedString()
            let lockEntry = "\"integrity\": \"sha\(bits)-\(digest)\""
            #expect(!SecretShapes.hasHighEntropyTokenByCharacter(lockEntry))
            #expect(ClipKindDetector.kind(of: lockEntry) != .secret)
        }

        #expect(ClipKindDetector.kind(of: "K9x$Qz7Tr2Bn8LmVa") == .secret)
    }

    @Test("masks standalone generated passwords with symbols from twelve characters")
    func standaloneGeneratedPasswords() {
        for password in ["q7#Vx!2mR$9kLp@4Wz&n", "Tr0ub4dor&3xK!9z", "q7hVxd2mRt9kLpe4Wzbn"] {
            #expect(ClipKindDetector.kind(of: password) == .secret)
        }
    }

    /// The statistical rule is the loosest one, so its gates matter.
    @Test(
        "does not reach for the entropy rule where it has no business",
        arguments: [
            "shortenough123",
            "abcdefghijklmnopqrstuvwxyz",
            "123456789012",
            "123e4567-e89b-12d3-a456-426614174000",
            "com.uttrflow.clipboard.watcher.queue1",
            "/Users/avery/Library/Application1",
            "~/Developer/uttrflow/Sources/Clipboard2",
            "https://example.com/a/verylongpathsegment12345",
            "The quick brown fox jumps over the lazy dog again and again for 24 chars.",
        ])
    func entropyGates(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    @Test(
        "leaves known scheme-only URIs and quoted filesystem paths outside the entropy rule",
        arguments: [
            "mailto:a@example.com?subject=Hi%20there",
            "spotify:track:4iV5W9uYEdYUVa79Axb7Rh",
            "magnet:?xt=urn:btih:4f3c2a1b0e9d8c7b6a594837261504f3c2a1b0e9",
            "urn:example:Q7Vn2mR8xL4pK9cD",
            "tel:+14155552671",
            "\"/Volumes/Backup Drive/photos/2026/a.heic\"",
            "\"/Volumes/Backup Drive/photos/2026/niño.heic\"",
        ])
    func ordinaryURIsAndQuotedPaths(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .secret)
    }

    @Test("still masks a quoted generated token")
    func quotedGeneratedToken() {
        #expect(ClipKindDetector.kind(of: "\"K9x$Qz7Tr2Bn8LmVa\"") == .secret)
    }

    @Test("still masks an exact vendor credential inside a URI")
    func vendorCredentialInsideURI() {
        #expect(ClipKindDetector.kind(of: "spotify:track:sk-ant-abcdefghijklmnop") == .secret)
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
            "fix/796-paste-confirmation-cancel",
            "feature/1234-add-dark-mode-toggle",
            "git checkout -b fix/796-paste-confirmation-cancel",
            "how-to-build-a-2024-garden-shed-in-7-steps",
            "2024-09-18-release-notes-draft-v2",
            "Screenshot-2024-09-18-at-14-30-12",
            "IMG_20240918_143012_HDR_edited",
            "test_parses_utf8_strings_with_bom_2",
            "Q3-2024-marketing-budget-final-v7",
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
