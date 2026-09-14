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
6. A payment card number (below).
7. The statistical rule below.

## Reading in linear time

Every copy is read for a credential inside the pasteboard watcher's loop, before the next copy
can be noticed, so the reading has to cost time in proportion to the clip. Three of the shapes
above were once backtracking patterns that reread the rest of a run from every place a match
could start: the JWT (`eyJ` in a long base64url run), the connection string (every letter in a
run of scheme characters) and the named secret (every keyword in `pwd=pwd=…`). A 16 KB line of
hex took seconds, and each doubling of its length cost four times as long.

They are now single-pass readers in `SecretScanners.swift` that accept exactly what the patterns
did, character for character: ASCII classes match only a lone ASCII scalar, `\s` is
`Character.isWhitespace`, `$` stands before any `Character.isNewline`, a case-insensitive `k`
also matches U+212A KELVIN SIGN, and `\b` is the Unicode word boundary the pattern engine uses.
`SecretShapesOracleTests` keeps the old patterns as the oracle and compares them with the readers
on 200,000 random strings and on planted secrets. `SecretShapesScalingTests` bounds the
characters read per character of the clip, so the check is a count, not a clock.

The same pass found four classifier patterns with the same flaw, rewritten as patterns that
accept the same language without the backtracking: a link's host (`[^\s/?#]+\S*` is
`[^\s/?#]\S*`), a functional colour (`\(\s*[^()]+\)` is `\([^()]+\)`), a call
(`\w+\((?:\)|[^\s)])` is `\w\(\S`), and every line-start rule in `CodeShapes`, where `^\s*`
could run through a block of blank lines from each of them and `^\h*` cannot.

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

## Card numbers

`CardNumberShape` accepts 13 to 19 digits, written unbroken or in the groups cards are printed
in (4-4-4-4, 4-4-4-4-3, 4-6-5, 4-6-4, 4-3-3-3) with one separator, space or dash, used throughout. The
digits must then carry a prefix some network issues under at that length (Visa, Mastercard,
American Express, Diners Club, JCB, Discover, UnionPay, RuPay, Mir, Maestro) and pass the Luhn
check.

Luhn alone passes one number in ten, which is too many for order numbers and timestamps; a
network prefix at the right length is what rules out `1700000000000000` (a timestamp in
microseconds), `9780306406157` (an ISBN) and `1234567812345670`. A number joined to more digits
by a dash, full stop, slash, colon or underscore is part of something longer (a date, a
decimal, an id) and is left alone, as is one behind a `+`, which is a phone number. A space is
not a joiner, so a card number after a line number or a date is still caught.

`CardNumberDetectionTests` holds the false-positive table: phone numbers, ISBNs, UUIDs, order
numbers and timestamps.

## What a password manager marks

Password managers commonly mark what they copy with the nspasteboard.org types, and
`PasteboardMarkers` reads them:

| Type | Meaning | What the watcher does |
|---|---|---|
| `org.nspasteboard.ConcealedType` | a password or similar | records the clip as `.secret`, whatever its shape |
| `org.nspasteboard.TransientType` | a copy made to move data, not for history | does not record it |
| `org.nspasteboard.AutoGeneratedType` | written by software, not by a person | does not record it |

This is the only way an ordinary password is recognised. `hunter2` and `Tr0ub4dor&3` have no
shape that separates them from a word or a product code, and the frontmost application is not
necessarily the one that wrote the clipboard, so neither length and character classes nor the
application's identity is a sound signal. A password typed out and copied from a note is text.
That is why the home page promises passwords from password managers, not passwords.
