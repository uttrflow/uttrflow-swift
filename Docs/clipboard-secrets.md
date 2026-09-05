# Recognising a credential

`SecretShapes.matches(_:)` is keener to say yes than no. A false positive masks something
harmless: the row shows dots, Return still pastes it, one keystroke reveals it. A false
negative leaves a production password legible on a panel opened in meetings and on recorded
calls.

## Shapes, cheapest first

1. A PEM header (`-----BEGIN`). Certificates are masked with keys; telling them apart by label
   is one label away from being wrong about the one that matters.
2. A JWT anywhere in the text: three base64url segments beginning `eyJ` (what `{"` encodes
   to). The signature may be empty, because an `alg: none` token is still a token.
3. A connection string with a password: `scheme://user:pass@host`. The colon in the userinfo
   is what keeps `https://example.com:8443/path` and `https://token@github.com/repo` out.
4. Vendor prefixes with a minimum length each (OpenAI, Anthropic, Stripe, GitHub, GitLab,
   Slack, AWS, Google, npm, DigitalOcean, Shopify, SendGrid), so prose about `sk-` keys is not
   itself one.
5. A named secret per line (`API_KEY=…`, `password: …`, `client_secret = …`) whose value is
   quoted, or has a digit, or is at least 12 characters, so `var password: String` does not
   count.
6. The statistical rule below.

## The entropy floor: 3.8 bits per character

Applies to single words on one-line clips only (a multi-line clip is a document and
legitimately carries digests; the shapes above already catch `.env` lines and PEM blocks).
The word must be at least 24 characters (below that a token and
`applicationDidFinishLaunching` score alike), drawn entirely from the base64/base64url/hex
alphabet, and contain both a letter and a digit. Hex of 32 or more characters is a digest
outright, because a sixteen-symbol alphabet can never reach the general floor. Anything that
opens like a path is left to the general rules.

Measured over three thousand random base64 strings at each length: a floor of 4.0 catches 96%
of 24-character tokens and everything longer; 3.8 catches 99.8%. The difference is the
shortest, unluckiest, most repetitive keys, and a key is no less live for a repeated character.
The cost, paid knowingly: long identifiers with a digit score between 3.7 and 4.1, so
`invoice_2024_q3_final_v2_signed` and a deep source path are masked.
