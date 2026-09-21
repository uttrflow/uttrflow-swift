// Tests that the single-pass secret readers and the rewritten classifier patterns agree with the patterns they replace, on a fixed sample unless `UTTRFLOW_ORACLE_SWEEP=1` asks for every seed in full.

import Foundation
import Testing

@testable import UttrflowClipboard

/// Every credential below is invented or a network's published test number, and assembled from pieces so no secret scanner matches the source.
@Suite("The linear readers answer exactly as the backtracking patterns did", .serialized)
struct SecretShapesOracleTests {
    /// Pieces that sit on every edge the patterns draw: separators, quotes, line ends, keywords, case folds and combining marks.
    static let pieces: [String] = [
        "sk" + "-", "sk" + "-ant-", "sk" + "_live_", "gh" + "p_", "AK" + "IA", "eyJ",
        "eyJhbGciOiJIUzI1NiJ9", "://", "http", "https://", "postgres", ":", "/", "@", "=", ";", ",",
        "\"", "'", " ", "\t", "\n", "\r\n", "\r", "\u{2028}", "\u{85}", "\u{A0}", "\u{0B}", ".", "-",
        "_", "+", "()", "request.token", "password", "PASSWORD", "Password", "pwd", "passwd",
        "token", "tokens", "api_key",
        "API-KEY", "apikey", "api_keys", "secret", "Secrets", "credential", "credentials",
        "private_key", "access-key", "auth_token", "client_secret", "clientsecret", "\u{212A}",
        "api_\u{212A}ey", "\u{301}", "é", "e\u{301}", "\"\u{301}", "'\u{301}", ";\u{301}", "\u{37E}",
        "x", "a", "Z", "J", "y", "e", "0", "1", "9", "٣", "½", "4111", "1111 ", "abc123", "hunter2",
        "Qv7RkT2mXeL9pAz4", "\u{0}", "\u{FEFF}", "😀", "🇺🇸", "\u{200D}", "'s", "x.", "rgb(", "(", ")",
        "func ", "import ", "//", "select ", "  ", "#", "?", "{", "}", "return", "if(",
        "AAAAAAAAAAAAAAAAAAAAAAAA", "user", "pass", ":x@", "a1", "-----BEGIN", "\\", "$", "*", "-- ",
        "# ", "* ", "/*", "from ", "else", "oklab(", "OKLCH(", "o\u{212A}lab(", "Https://",
        "DB_", "db", "Pass", "PASS", "_pass", "Token", "SMTP_", "max_", "_count", "less", "izer",
    ]

    /// Secrets and near-misses of every detected shape, to be planted, cut and spliced.
    static let planted: [String] = [
        "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAABG5vbmU\n-----END OPENSSH PRIVATE KEY-----",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.SflKxwRJSMeKKF2QT4fw",
        "eyJhbGciOiJub25lIn0.eyJzdWIiOiIxIn0.", "eyJa.b.", "xeyJab.cd.e", "eyJ.a.b", "eyJa..b",
        "Bearer eyJhb.eyJz.", "postgres://admin:s3cr3t@db.example.com/app", "a://b:c@d", "1a://b:c@d",
        "+://u:p@h", "x-y.z://u:p@ h", "s://u:p@", "https://example.com:8443/health",
        "sk" + "-proj-Qv7RkT2mXeL9pAz4NbHc8FwJ", "gh" + "p_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8",
        "AKIAIOSFODNN7EXAMPLE", "API_KEY" + "=9f2b7c4e1a8d3f6b", "password = \"hunter2\"", "token: true",
        "client_secret" + ": 'Qv7RkT2mXeL9pAz4'", "export GITHUB_TOKEN" + "=abc123def456ghi789",
        "pwd" + "=abcdefghijkl ;", "secret\"=x1,", "api-keys :\n  v4lue\n", "password: now",
        "var password: String", "pwd=\"\"", "token='a\nb'", "x.password=abc123",
        "\"privateKey\": \"MIIE\",", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6", "Qv7RkT2mXeL9pAz4NbHc8FwJdY3gS6uH", "4111 1111 1111 1111",
        "4111111111111111", "5555-5555-5555-4444", "378282246310005", "6011 1111 1111 1117",
        "3530 1113 3330 0000", "4222 222 222 222", "4111 1111 1111 1112", "https://example.com/a b",
        "http://x", "rgb(1, 2, 3)", "hsla( 0 )", "oklch()", "color(display-p3 1 0 0)",
        "func greet() {}", "  // note", "\n\n  select * from t", "if (x) return", "import Foundation",
        "let x = 1", "DB_PASSWORD" + "=Kq7v2mX", "dbPassword" + ": 'x'", "SMTP_PASS" + "=a1",
        "redis://:" + "pw1@h", "max_tokens: 4096", "token_count: 128000", "passwordless=x1",
        "APP_ENV=prod\nGITHUB_TOKEN" + "=a1b2\nPORT=1", "aPwd=1", "a_b_pwd=1", "tokenizer: 12345",
        "let token = request.token", "secret = settings.SECRET_KEY;",
        "password = getpass.getpass()", "token=a.b.c,", "pwd=f();", "token=a..bcdefghijkl",
        "token=" + "x.deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", "token=abcdef.ghijkl()x",
        "pwd=getpass.getpass()\u{37E}", "pwd=getpass.getpass.\u{301}x",
    ]

    static func randomText(_ random: inout Seeded) -> String {
        var text = ""
        for _ in 0..<Int.random(in: 0...24, using: &random) {
            if random.chance(1.0 / 12),
                let scalar = Unicode.Scalar(UInt32.random(in: 0...0x2FFF, using: &random))
            {
                text.unicodeScalars.append(scalar)
            } else {
                text += random.pick(pieces)
            }
        }
        return text
    }

    /// A planted shape, cut or spliced up to three times, between random text on either side.
    static func plantedText(_ random: inout Seeded) -> String {
        var characters = Array(random.pick(planted))
        for _ in 0..<Int.random(in: 0...3, using: &random) {
            let at = Int.random(in: 0...characters.count, using: &random)
            let piece = Array(random.pick(pieces))
            switch Int.random(in: 0..<3, using: &random) {
            case 0: characters.insert(contentsOf: piece, at: at)
            case 1 where at < characters.count: characters.remove(at: at)
            case 2 where at < characters.count: characters.replaceSubrange(at..<at + 1, with: piece)
            default: break
            }
        }
        let before = random.chance(0.5) ? randomText(&random) : ""
        let after = random.chance(0.5) ? randomText(&random) : ""
        return before + String(characters) + after
    }

    /// Where each reader disagrees with its oracle on this text, named.
    private static func disagreements(_ text: String) -> [String] {
        var found: [String] = []
        if SecretShapes.hasJSONWebToken(text) != BacktrackingPatterns.hasJSONWebToken(text) {
            found.append("jwt")
        }
        if SecretShapes.hasCredentialledURL(text) != BacktrackingPatterns.hasCredentialledURL(text) {
            found.append("url")
        }
        if SecretShapes.hasNamedSecret(text) != BacktrackingPatterns.hasNamedSecret(text) {
            found.append("named")
        }
        if SecretShapes.matches(text) != BacktrackingPatterns.matches(text) { found.append("matches") }
        return found
    }

    @Test("Random text: 200,000 strings over eight seeds in the full sweep", arguments: OracleSweep.seeds(8))
    func randomStrings(seed: Int) async {
        let failures = await offTheTestPool {
            var random = Seeded(seed: 443_000 + seed)
            var failures: [String] = []
            for _ in 0..<OracleSweep.strings(25_000) {
                let text = Self.randomText(&random)
                let found = Self.disagreements(text)
                if !found.isEmpty, failures.count < 20 {
                    failures.append("\(found) on \(text.debugDescription)")
                }
            }
            return failures
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test(
        "Planted secrets and near-misses, cut and spliced into random text", arguments: OracleSweep.seeds(4))
    func plantedSecrets(seed: Int) async {
        let count = OracleSweep.strings(10_000)
        let (failures, detected) = await offTheTestPool {
            var random = Seeded(seed: 397_000 + seed)
            var failures: [String] = []
            var detected = 0
            for _ in 0..<count {
                let text = Self.plantedText(&random)
                let found = Self.disagreements(text)
                if !found.isEmpty, failures.count < 20 {
                    failures.append("\(found) on \(text.debugDescription)")
                }
                if SecretShapes.matches(text) { detected += 1 }
            }
            return (failures, detected)
        }
        #expect(failures.isEmpty, "\(failures)")
        // Most planted texts still carry a secret, so agreement is measured on positives as well as negatives.
        #expect(detected > count / 4)
    }

    @Test("Every planted shape, untouched, reads the same")
    func plantedAsWritten() {
        for text in Self.planted {
            #expect(Self.disagreements(text).isEmpty, "\(text.debugDescription)")
        }
    }

    @Test(
        "The rewritten classifier patterns accept exactly what the backtracking ones did",
        arguments: OracleSweep.seeds(4))
    func classifierPatterns(seed: Int) async {
        let failures = await offTheTestPool {
            var random = Seeded(seed: 405_000 + seed)
            var failures: [String] = []
            for _ in 0..<OracleSweep.strings(10_000) {
                let text = random.chance(0.5) ? Self.plantedText(&random) : Self.randomText(&random)
                for name in Self.classifierDisagreements(text) where failures.count < 20 {
                    failures.append("\(name) on \(text.debugDescription)")
                }
            }
            return failures
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    /// Which rewritten classifier patterns answer differently from their backtracking forms on this text.
    private static func classifierDisagreements(_ text: String) -> [String] {
        let pairs: [(String, Regex<Substring>, Regex<Substring>, whole: Bool)] = [
            ("link", LinkShape.address, BacktrackingPatterns.address, true),
            ("colour", ColourShape.functional, BacktrackingPatterns.functional, true),
            ("declaration", CodeShapes.declaration, BacktrackingPatterns.declaration, false),
            ("controlFlow", CodeShapes.controlFlow, BacktrackingPatterns.controlFlow, false),
            ("invocation", CodeShapes.invocation, BacktrackingPatterns.invocation, false),
            ("commentLine", CodeShapes.commentLine, BacktrackingPatterns.commentLine, false),
            ("query", CodeShapes.query, BacktrackingPatterns.query, false),
        ]
        return pairs.compactMap { name, new, old, whole in
            let agree =
                whole
                ? (text.wholeMatch(of: new) != nil) == (text.wholeMatch(of: old) != nil)
                : (text.firstMatch(of: new) != nil) == (text.firstMatch(of: old) != nil)
            return agree ? nil : name
        }
    }

    @Test("A case-folded keyword, a quote with a mark on it, and a line break inside quotes read as before")
    func edges() {
        let cases = [
            "api_\u{212A}ey=abc123", "pwd=\"\u{301}abc", "password=\"a\r\nb\"", "token= 'x'\u{2028}",
            "secret=abc;\u{85}",
            "client-secret" + "=abcdefghijklm", "x.password=abc123", "password.x=abc123", "PWD\t:\t1",
            // The first assignment's value holds the second keyword, which the pattern's next search starts after.
            "credential://token\r\n:x@clientsecret4111", "pwd=a;\n\n token=b1", "secret=x ,\n\npwd: 'y'",
            // A name may start after an underscore or at a lowercase-to-uppercase step, never after an uppercase letter.
            "DB_PASSWORD=a1", "dbPassword=a1", "PGPASSWORD=a1", "_\u{301}password=a1", "b\u{301}Password=a1",
            "aPWD=1", "a_pass=1;\n", "x_secret_token=1", "pwd_pwd=1", "tPassword=1",
        ]
        for text in cases {
            #expect(
                SecretShapes.hasNamedSecret(text) == BacktrackingPatterns.hasNamedSecret(text),
                "\(text.debugDescription)")
        }
    }
}

/// How much of each randomised oracle comparison runs: the first seeds' prefix by default, all of it under `UTTRFLOW_ORACLE_SWEEP=1`.
enum OracleSweep {
    /// Whether the full sweep was asked for; see the nightly `oracle-sweep.yml` workflow.
    static let isFull =
        ProcessInfo.processInfo.environment["UTTRFLOW_ORACLE_SWEEP"].map { !["", "0"].contains($0) } ?? false

    /// The seeds to run: every one of `full` in the sweep, the first two by default.
    static func seeds(_ full: Int) -> Range<Int> { 0..<(isFull ? full : min(full, 2)) }

    /// The strings per seed: `full` in the sweep, a fixed sample by default drawn from the start of the same stream.
    static func strings(_ full: Int) -> Int { isFull ? full : max(1, full / sampleDivisor) }

    /// How much smaller each seed's default run is than its full one.
    static let sampleDivisor = 25
}

/// Runs CPU-bound work on its own thread, so a long loop does not hold a thread other suites' async tests are waiting for.
func offTheTestPool<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        Thread { continuation.resume(returning: work()) }.start()
    }
}

/// The patterns the readers replace, kept here as the oracle and never shipped.
enum BacktrackingPatterns {
    nonisolated(unsafe) static let jsonWebToken = #/eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*/#

    nonisolated(unsafe) static let credentialledURL = #/[a-zA-Z][a-zA-Z0-9+.\-]*://[^\s:/@]*:[^\s:/@]+@\S/#

    nonisolated(unsafe) static let namedSecret =
        #/
        (?i)
        (?: \b | _ | (?-i:[a-z])(?=(?-i:[A-Z])) )
        (?: api[_\-]?keys? | secrets? | tokens? | passwords? | passwd | pwd | pass
            | credentials? | private[_\-]?key | access[_\-]?key | auth[_\-]?token
            | client[_\-]?secret )
        \b["']? \s* [:=] \s*
        (?<value> "[^"\n]+" | '[^'\n]+' | [^\s"'\n]+ )
        \s*[,;]?\s*$
        /#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let address = #/(?i)https?://[^\s/?#]+\S*/#

    nonisolated(unsafe) static let functional =
        #/(?i)(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(\s*[^()]+\)/#

    nonisolated(unsafe) static let declaration =
        #/
        \b(?: func | function | def | fn | sub )\s+\w+\s*\(
        | \b(?: class | struct | enum | interface | trait | protocol | actor )\s+\w+
        | \b(?: let | var | const | val )\s+\w+\s*[:=]
        | \b(?: public | private | internal | fileprivate | static | async | await )\s+\w
        | ^\s*(?: import | from | package | using | require | \#include | \#import )\s+\S
        /#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let controlFlow =
        #/
        \b(?: if | for | while | switch | catch | foreach )\s*\(
        | ^\s*(?: return | throw | break | continue | yield | else | elif | endif )\b
        /#
        .anchorsMatchLineEndings()

    nonisolated(unsafe) static let invocation = #/\w+\((?:\)|[^\s)])/#

    nonisolated(unsafe) static let commentLine = #/^\s*(?://|/\*|\*\s|\#\s|--\s)/#.anchorsMatchLineEndings()

    nonisolated(unsafe) static let query =
        #/(?i)^\s*(?:select|insert\s+into|update|delete\s+from|create\s+table|alter\s+table|drop\s+table)\s+/#
        .anchorsMatchLineEndings()

    static func hasJSONWebToken(_ text: String) -> Bool { text.firstMatch(of: jsonWebToken) != nil }

    static func hasCredentialledURL(_ text: String) -> Bool { text.firstMatch(of: credentialledURL) != nil }

    static func hasNamedSecret(_ text: String) -> Bool {
        text.matches(of: namedSecret).contains { match in
            let raw = String(match.value)
            let isQuoted = raw.count >= 2 && (raw.hasPrefix("\"") || raw.hasPrefix("'"))
            let value = isQuoted ? String(raw.dropFirst().dropLast()) : raw
            let hasDigit = value.contains { $0.isASCII && $0.isNumber }
            let isLatin = value.allSatisfy(\.isLatinScript)
            return isQuoted || hasDigit
                || (value.count >= 12 && isLatin && !isReference(value))
        }
    }

    /// An identifier path or an empty call, optionally closed by `,` or `;`, read scalar by scalar so `;` means only U+003B.
    static func isReference(_ value: String) -> Bool {
        var scalars = Array(value.unicodeScalars.map(\.value))
        if let last = scalars.last, last == 0x2C || last == 0x3B { scalars.removeLast() }
        let isCall = scalars.count >= 2 && scalars.suffix(2) == [0x28, 0x29]
        if isCall { scalars.removeLast(2) }
        func isName(_ scalar: UInt32) -> Bool {
            (0x41...0x5A).contains(scalar) || (0x61...0x7A).contains(scalar) || scalar == 0x5F
                || scalar == 0x24
        }
        let parts = scalars.split(separator: 0x2E, omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isName) }), parts.count > 1 || isCall
        else { return false }
        return !parts.contains { part in
            part.count >= 32
                && part.allSatisfy {
                    (0x30...0x39).contains($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0)
                }
        }
    }

    /// `CardNumberShape.matches` as it read before the runs: the pattern over the whole clip.
    static func hasCardNumber(_ text: String) -> Bool {
        text.matches(of: CardNumberShape.candidate).contains { match in
            CardNumberShape.standsAlone(match.range, in: text)
                && CardNumberShape.isCardNumber(match.output.0.filter(\.isNumber))
        }
    }

    /// `SecretShapes.matches` as it read before the readers, with the unchanged rules borrowed from it.
    static func matches(_ text: String) -> Bool {
        text.contains("-----BEGIN") || hasJSONWebToken(text) || hasCredentialledURL(text)
            || text.firstMatch(of: SecretShapes.vendorKey) != nil || hasNamedSecret(text)
            || hasCardNumber(text)
            || SecretShapes.hasHighEntropyToken(text)
    }
}
