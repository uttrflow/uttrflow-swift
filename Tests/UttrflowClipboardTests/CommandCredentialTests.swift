// Tests that a password passed to a command, or an authorization header, is recognised as a credential.

import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

/// Every password and token below is invented.
@Suite("A credential handed to a command or a header")
struct CommandCredentialTests {
    @Test(
        "A password passed as a flag, a header value or a URL's userinfo token is a secret",
        arguments: [
            "curl -u admin:Hunter2x https://api.example.com",
            "curl --user admin:Hunter2x https://api.example.com",
            "curl -uadmin:Hunter2x https://api.example.com",
            "mysql -u root -pS3cretPass appdb",
            "mysql -p'Pa$sw0rd'",
            "mysql -p'{Pa}sw0rd'",
            "mysqldump -psecret>dump.sql",
            "sudo -u postgres mysqldump -pS3cretPass appdb",
            "sshpass -p 'S3cret!' ssh deploy@db.example.com",
            "docker login -u ci -p S3cr3tValue registry.example.com",
            "docker login --password S3cr3t",
            "podman login --password=S3cr3t registry.example.com",
            "htpasswd -b .htpasswd alice Mead0wlark",
            "htpasswd -nb alice Mead0wlark",
            "ssh-keygen -t ed25519 -N 'correct horse'",
            "ssh-keygen -p -P oldphrase -N newphrase -f key",
            "openssl pkcs12 -export -passout pass:sunshine",
            "redis-cli -a sunshine ping",
            "vault login --token s.sunshine",
            "deploy --api-key sunshine",
            "PGPASSWORD=sunshine psql -h db.example.com",
            "MYSQL_PWD=sunshine mysql -u root",
            "curl -H \"Authorization: Basic YWxpY2U6czNjcjN0\" https://api.example.com",
            "curl -H \"Authorization: Bearer 8fK2pQ7xLm4Rt9vW3nB6cY1zH5jD0sAe\"",
            "curl -H\"Authorization: Bearer sunshine\" https://api.example.com",
            "curl -H'Authorization: Bearer sunshine' https://api.example.com",
            "curl -H 'Proxy-Authorization: Digest sunshine' https://api.example.com",
            "curl -H 'X-Api-Key: sunshine' https://api.example.com",
            "Authorization: token sunshine",
            "Authorization: CustomScheme sunshine",
            "\"Authorization\": \"Bearer sunshine\",",
            "git clone https://0123456789abcdef0123456789abcdef01234567@git.example.com/org/repo.git",
        ])
    func recognised(_ text: String) {
        #expect(SecretShapes.matches(text))
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test(
        "A flag, header or URL that hands over no credential is not a secret",
        arguments: [
            "use -p to pick a port",
            "the Authorization header",
            "ssh -p 22 deploy@db.example.com",
            "docker run -p 8080:80 nginx",
            "mysql -u root -p appdb",
            "curl -u admin https://api.example.com",
            "ssh-keygen -t ed25519 -N ''",
            "docker login --password-stdin registry.example.com",
            "docker login -u ci -p \"$REGISTRY_PASSWORD\"",
            "curl -H \"Authorization: Bearer $TOKEN\" https://api.example.com",
            "headers: { Authorization: `Bearer ${token}` }",
            "\"Authorization\": f\"Bearer {token}\",",
            "Authorization: Bearer",
            "openssl enc -pass env:SECRET_PASSWORD",
            "pg_dump --no-password appdb",
            "htpasswd -c .htpasswd alice",
            "https://readonly@git.example.com/org/repo.git",
            "PGPASSWORD=$DB_PASSWORD psql -h db.example.com",
        ])
    func notRecognised(_ text: String) {
        #expect(!SecretShapes.hasCommandCredential(text))
        #expect(!SecretShapes.hasTokenUserinfoURL(text))
    }

    @Test("A credential on one line of several is found, and quotes do not carry past a line's end")
    func lineByLine() {
        #expect(SecretShapes.hasCommandCredential("cd app\nmysql -u root -pS3cretPass appdb\nls"))
        #expect(!SecretShapes.hasCommandCredential("echo 'unclosed\nmysql -u root -p appdb"))
        #expect(SecretShapes.hasCommandCredential("ls | sshpass -p sunshine ssh host"))
    }

    @Test(
        "A netrc password is read inside its machine or default block",
        arguments: [
            "machine example.com\nlogin u\npassword hunter2x9",
            "default\nlogin u\npassword hunter2x9",
            "machine example.com login u password hunter2x9",
            "machine example.com\nlogin u\naccount acct\npassword hunter2x9",
            "machine example.com\nmacdef init\npassword ordinary\n\nmachine next.example\nlogin u\npassword hunter2x9",
        ])
    func multilineNetrc(_ text: String) {
        #expect(SecretShapes.matches(text))
        #expect(ClipKindDetector.kind(of: text) == .secret)
    }

    @Test("A netrc macro body is not a password directive")
    func netrcMacroBody() {
        let text = "machine example.com\nmacdef init\npassword ordinary\n\n"
        #expect(!SecretShapes.hasCommandCredential(text))
        #expect(!SecretShapes.matches(text))
    }

    @Test("Password in ordinary prose is not a netrc credential")
    func prosePassword() {
        #expect(!SecretShapes.hasCommandCredential("Please enter your password on the next line."))
        #expect(!SecretShapes.matches("Please enter your password on the next line."))
    }
}
