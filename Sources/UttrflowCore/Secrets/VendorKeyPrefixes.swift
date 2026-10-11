// The one table of vendor key prefixes that both the vendor-key pattern and its byte windows are built from.

/// A key prefix an issuer gives its keys, with the characters and length that follow it.
struct VendorKeyPrefix: Sendable {
    /// The literal the key starts with, matched case-sensitively.
    let prefix: String
    /// The pattern character class the rest of the key is written in.
    let alphabet: String
    /// The fewest characters after the prefix, so prose that only names the prefix is not a key.
    let minimum: Int
    /// Exactly `minimum` characters are required rather than at least, for keys of fixed length.
    var isExact = false

    /// This row as a pattern alternative.
    var pattern: String {
        VendorKeyPrefixes.escaped(prefix) + alphabet + (isExact ? "{\(minimum)}" : "{\(minimum),}")
    }

    /// The prefix and the shortest body that completes it.
    var shortestMatch: Int { prefix.utf8.count + minimum }
}

/// Every vendor key prefix; a new issuer is one row here and one row in the tests.
enum VendorKeyPrefixes {
    private static let word = "[A-Za-z0-9_\\-]"
    private static let alphanumeric = "[A-Za-z0-9]"
    private static let lowerHex = "[a-f0-9]"

    /// The characters a Slack token runs on in after its `xox` kind letter.
    private static let slack = "[A-Za-z0-9\\-]"

    static let all: [VendorKeyPrefix] =
        [
            VendorKeyPrefix(prefix: "sk-", alphabet: word, minimum: 16),  // OpenAI, Anthropic
            VendorKeyPrefix(prefix: "ghp_", alphabet: alphanumeric, minimum: 16),  // GitHub
            VendorKeyPrefix(prefix: "gho_", alphabet: alphanumeric, minimum: 16),
            VendorKeyPrefix(prefix: "ghu_", alphabet: alphanumeric, minimum: 16),
            VendorKeyPrefix(prefix: "ghs_", alphabet: alphanumeric, minimum: 16),
            VendorKeyPrefix(prefix: "ghr_", alphabet: alphanumeric, minimum: 16),
            VendorKeyPrefix(prefix: "github_pat_", alphabet: "[A-Za-z0-9_]", minimum: 20),
            VendorKeyPrefix(prefix: "glpat-", alphabet: word, minimum: 16),  // GitLab
            VendorKeyPrefix(prefix: "xapp-", alphabet: "[A-Za-z0-9\\-]", minimum: 16),  // Slack app-level
            VendorKeyPrefix(prefix: "xoxc-", alphabet: "[A-Za-z0-9\\-]", minimum: 16),  // Slack browser
            VendorKeyPrefix(prefix: "xoxd-", alphabet: "[A-Za-z0-9%\\-]", minimum: 16),
            VendorKeyPrefix(prefix: "whsec_", alphabet: word, minimum: 16),  // Stripe webhook signing
            VendorKeyPrefix(prefix: "hf_", alphabet: alphanumeric, minimum: 16),  // Hugging Face
            VendorKeyPrefix(prefix: "pypi-", alphabet: word, minimum: 16),  // PyPI
            VendorKeyPrefix(prefix: "dckr_pat_", alphabet: word, minimum: 16),  // Docker Hub
            VendorKeyPrefix(prefix: "lin_api_", alphabet: word, minimum: 16),  // Linear
            VendorKeyPrefix(prefix: "lin_oauth_", alphabet: word, minimum: 16),
            VendorKeyPrefix(prefix: "sbp_", alphabet: word, minimum: 16),  // Supabase
            VendorKeyPrefix(prefix: "hvs.", alphabet: "[A-Za-z0-9._\\-]", minimum: 16),  // HashiCorp Vault
            VendorKeyPrefix(prefix: "AKIA", alphabet: "[0-9A-Z]", minimum: 16, isExact: true),  // AWS key id
            VendorKeyPrefix(prefix: "ASIA", alphabet: "[0-9A-Z]", minimum: 16, isExact: true),
            VendorKeyPrefix(prefix: "AIza", alphabet: word, minimum: 35, isExact: true),  // Google API key
            VendorKeyPrefix(prefix: "GOCSPX-", alphabet: word, minimum: 20),  // Google OAuth client secret
            VendorKeyPrefix(prefix: "ya29.", alphabet: word, minimum: 30),  // Google OAuth access token
            VendorKeyPrefix(prefix: "npm_", alphabet: alphanumeric, minimum: 30),  // npm
            VendorKeyPrefix(prefix: "dop_v1_", alphabet: lowerHex, minimum: 40),  // DigitalOcean
            VendorKeyPrefix(prefix: "doo_v1_", alphabet: lowerHex, minimum: 40),
            VendorKeyPrefix(prefix: "dor_v1_", alphabet: lowerHex, minimum: 40),
            // Shopify
            VendorKeyPrefix(prefix: "shpat_", alphabet: "[a-fA-F0-9]", minimum: 32, isExact: true),
            VendorKeyPrefix(prefix: "gsk_", alphabet: alphanumeric, minimum: 32),  // Groq
            VendorKeyPrefix(prefix: "r8_", alphabet: alphanumeric, minimum: 30),  // Replicate
            VendorKeyPrefix(prefix: "ATATT3", alphabet: "[A-Za-z0-9_\\-=]", minimum: 30),  // Atlassian
            VendorKeyPrefix(prefix: "secret_", alphabet: alphanumeric, minimum: 40),  // Notion
            VendorKeyPrefix(prefix: "ntn_", alphabet: alphanumeric, minimum: 40),
            VendorKeyPrefix(prefix: "sq0atp-", alphabet: word, minimum: 20),  // Square
            VendorKeyPrefix(prefix: "sq0csp-", alphabet: word, minimum: 20),
            VendorKeyPrefix(prefix: "nfp_", alphabet: alphanumeric, minimum: 30),  // Netlify
            VendorKeyPrefix(prefix: "NRAK-", alphabet: "[A-Z0-9]", minimum: 27, isExact: true),  // New Relic
            // RubyGems
            VendorKeyPrefix(prefix: "rubygems_", alphabet: lowerHex, minimum: 48, isExact: true),
            VendorKeyPrefix(prefix: "key-", alphabet: lowerHex, minimum: 32, isExact: true),  // Mailgun
        ]
        + ["sk", "pk", "rk"].flatMap { kind in
            ["live", "test"].map { mode in
                VendorKeyPrefix(prefix: "\(kind)_\(mode)_", alphabet: alphanumeric, minimum: 10)  // Stripe
            }
        }
        + [
            VendorKeyPrefix(prefix: "xoxb-", alphabet: slack, minimum: 10),
            VendorKeyPrefix(prefix: "xoxa-", alphabet: slack, minimum: 10),
            VendorKeyPrefix(prefix: "xoxp-", alphabet: slack, minimum: 10),
            VendorKeyPrefix(prefix: "xoxr-", alphabet: slack, minimum: 10),
            VendorKeyPrefix(prefix: "xoxs-", alphabet: slack, minimum: 10),
            VendorKeyPrefix(prefix: "xoxe-", alphabet: slack, minimum: 10),
        ]

    /// SendGrid's two segments, the one key whose shortest match has no upper bound on its first part.
    static let sendGridPattern = "SG\\.[A-Za-z0-9_\\-]{16,}\\.[A-Za-z0-9_\\-]{16,}"

    /// The pattern source every row and SendGrid's key make, each starting at a word boundary.
    static let patternSource =
        "\\b(?:" + (all.map(\.pattern) + [sendGridPattern]).joined(separator: "|") + ")"

    /// The longest prefix-plus-shortest-body of any row, which a window must hold after its prefix.
    static let longestShortestMatch = all.map(\.shortestMatch).max() ?? 0

    /// Each row's prefix as bytes, grouped by its first byte so a byte opens at most a few comparisons.
    static let byFirstByte: [UInt8: [[UInt8]]] = Dictionary(
        grouping: all.map { Array($0.prefix.utf8) }, by: { $0.first ?? 0 })

    /// Whether one of the rows' prefixes starts at this byte.
    static func opens(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Bool {
        guard let candidates = byFirstByte[bytes[offset]] else { return false }
        return candidates.contains { literal in
            guard offset + literal.count <= bytes.count else { return false }
            for index in 1..<literal.count where bytes[offset + index] != literal[index] { return false }
            return true
        }
    }

    /// A literal with every pattern metacharacter escaped.
    static func escaped(_ literal: String) -> String {
        literal.map { $0.isLetter || $0.isNumber || $0 == "_" ? String($0) : "\\" + String($0) }.joined()
    }
}
