// What must not be masked and what still must, on invented values shaped like real ones.

import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("Masking is for credentials, not for things that look random")
struct SecretFalsePositiveTests {
    private static let hash40 = "3f9a1c07be52d846a0c1f7e39d2b58c46e17fa03"
    private static let hash64 = hash40 + "6c0de1b7a4935f28c7d1e06b"

    @Test(
        "an ordinary URL is not masked",
        arguments: [
            "https://example.com/search?q=swift+concurrency&page=2&ref=nav_4f2a9c",
            "https://shop.example.com/products/9F3kLm2QxT7pV8n?variant=41235566778&utm_source=mail&utm_campaign=Spr24",
            "https://docs.example.com/d/1aB3xY9kLmQ2rT7pV8nZ4wS6uC0eH5jD/edit#gid=1948220",
            "https://www.example.com/watch?v=dQ4w9XgZx1c&list=PL9xK2mQ7vT3nB8zR4yL1",
            "https://login.example.com/authorize?client_id=7f3a9c12&redirect_uri=https%3A%2F%2Fapp.example.com%2Fcb&state=Zx9kLmQ2rT7p",
            "https://example.com/reset-password/done?session_id=4f2a91bc77",
            "https://example.com/access/keys/aB3xY9kLm2",
            "https://example.com/account/password=help2",
            "https://sheets.example.com/view?key=1aB3xY9kLmQ2rT7p",
            "https://app.example.com/callback?code=Zx9kLmQ2rT7pQ3vB",
            "https://example.com/oauth?auth=Zx9kLmQ2rT7pQ3vB",
            "https://example.com:8443/api/v2/items/9F3kLm2QxT7pV8n",
            "https://readonly@example.com/repo.git",
            "https://example.com/org/repo/commit/\(hash40)",
            "www.example.com/a/9F3kLm2QxT7pV8nZ4wS6u",
            "example.com/files/9F3kLm2QxT7pV8n?dl=1",
            "See https://example.com/x?id=9F3kLm2QxT7pV8n for details",
            "https://example.com/a?id=9F3kLm2QxT7pV8n\nhttps://example.com/b?id=Zx9kLmQ2rT7pQ3vB",
            "[the report](https://example.com/r/9F3kLm2QxT7pV8n?v=2)",
            "git@example.com:org/repo.git",
        ] as [String])
    func ordinaryURL(_ url: String) {
        #expect(!SecretShapes.matches(url), "\(url)")
    }

    @Test(
        "a URL carrying a credential is masked",
        arguments: [
            "https://deploy:Vb4nM7xQ2p@example.com/",
            "postgres://app:Vb4nM7xQ2p@db.example.com:5432/app",
            "https://example.com/x?token=Zx9kLmQ2rT7pQ3vB8n",
            "https://example.com/x?a=1&access_token=Zx9kLmQ2rT7pQ3vB8n",
            "https://example.com/x?api_key=Zx9kLmQ2rT7pQ3vB8n",
            "https://example.com/x?client_secret=Zx9kLmQ2rT7pQ3vB8n",
            "https://bucket.example.com/f?X-Amz-Signature=\(hash64)",
            "https://example.com/x?sig=Zx9kLmQ2rT7pQ3vB8n",
            "https://example.com/x?password=Vb4nM7xQ2p",
            "https://example.com/x/ghp_Zx9kLmQ2rT7pQ3vB8nW4sY6uC0eH5jD1aF3g",
            "https://\(hash40)@example.com/org/repo.git",
            "curl -u deploy:Vb4nM7xQ2p https://example.com/x",
            "curl -H 'Authorization: Bearer Zx9kLmQ2rT7pQ3vB8n' https://example.com/x",
        ] as [String])
    func credentialURL(_ url: String) {
        #expect(SecretShapes.matches(url), "\(url)")
    }

    @Test(
        "public material is not masked",
        arguments: [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9xZ2mQ7vT3nB8zR4yL1aF6sD0gH5jC2eU8wP3kN7 dev@example.com",
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC9xZ2mQ7vT3nB8zR4yL1aF6sD0gH5jC2eU8wP3kN7",
            "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTY dev@example.com",
            "-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE9xZ2mQ7vT3nB8zR4yL1aF6sD0gH5\n-----END PUBLIC KEY-----",
            "-----BEGIN CERTIFICATE-----\nMIIB9xZ2mQ7vT3nB8zR4yL1aF6sD0gH5jC2eU8wP3kN7\n-----END CERTIFICATE-----",
            "121QsRpnveZ4bCtDGM4pTK8r3Fqcs93MKu",
            "34XbMt85YvALRtz2PZBwu1Uk5YVykR3b2B",
            "bc1q9y4zktpd9chnqvfjxv6r2d3h8qun5weul6mx7d",
            "bc1p85lr7szpgfp5g32xgayyjjjtf3x5un6s29f9x4z42et4sk26tdwqm68na0",
            "0x9f8E7d6C5b4A39281706f5E4d3C2b1A098765432",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
            "The docs use eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c as an example",
            hash40,
            hash64,
            "sha256:\(hash64)",
            "\(hash40) Fix the panel layout",
            "pwd: /Users/dev/Desktop",
        ] as [String])
    func publicMaterial(_ text: String) {
        #expect(!SecretShapes.matches(text), "\(text)")
    }

    @Test(
        "lookalikes of public material are still masked",
        arguments: [
            "-----BEGIN PRIVATE KEY-----\nMIIB9xZ2\n-----END PRIVATE KEY-----",
            "-----BEGIN OPENSSH PRIVATE KEY-----\nb3Blbn\n-----END OPENSSH PRIVATE KEY-----",
            "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----",
            "ssh-ed25519 AAAAC3Nza\npassword=Vb4nM7xQ2p",
            "121QsRpnveZ4bCtDGM4pTK8r3Fqcs93MKv",
            "bc1q9y4zktpd9chnqvfjxv6r2d3h8qun5weul6mx7e",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiJ9.Zx9kLmQ2rT7pQ3vB8nW4sY6uC0eH5jD1",
            "API_KEY=\(hash64)",
            "token: \(hash40)",
            "0123456789abcdef0123456789abcdef",
            "pwd: Zx9kLmQ2rT7p",
        ] as [String])
    func stillSecret(_ text: String) {
        #expect(SecretShapes.matches(text), "\(text)")
    }
}
