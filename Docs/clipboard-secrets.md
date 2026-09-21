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
3. A connection string with a password: `scheme://user:pass@host`, or `scheme://:pass@host` with
   no user, the password-only form some caches use. The colon in the userinfo is what keeps
   `https://example.com:8443/path` and `https://token@github.com/repo` out.
4. Vendor prefixes with a minimum length each (OpenAI, Anthropic, Stripe, GitHub, GitLab,
   Slack, AWS, Google, npm, DigitalOcean, Shopify, SendGrid), so prose about `sk-` keys is not
   itself one.
5. A named secret per line (`API_KEY=…`, `password: …`, `client_secret = …`) whose value is
   quoted, or has a digit, or is at least 12 characters, so `var password: String` does not
   count. The name may carry a prefix: a keyword starts at a word boundary, after `_`, or at a
   lowercase-to-uppercase step, so `DB_PASSWORD`, `GITHUB_TOKEN`, `STRIPE_API_KEY` and
   `dbPassword` are all names. `pass` is a keyword, for `SMTP_PASS`. The keyword's own end
   still needs a word boundary, so `passwordless`, `tokenizer` and `token_count` are not names.
   The cost, paid knowingly: `max_tokens: 4096` is masked, because a digit under a name that
   ends in a keyword is exactly what a short password or PIN looks like.
   A long bare value that only points at a secret is not one: an identifier path or an
   empty call (`request.token`, `process.env.API_KEY;`, `getpass.getpass()`), made of letters,
   `_` and `$` with no digit and no part of 32 or more hex letters, is code that loads a
   credential rather than the credential. A quoted value or one with a digit still counts,
   and so does a single long bare word, which is what a letters-only password looks like.
6. A payment card number (below).
7. The statistical rule below.

## What the named-secret rule leaves alone

A credential inside a one-line command is not a named secret: `curl -u user:pass https://…`,
`mysql -u root -ppass` and `PGPASSWORD=pass psql -h …`. The rule needs the value to end its
line, which is what keeps prose such as `password: now is the time` out, and in a command the
value is followed by more of the command. `-u user:pass` has the same shape as `user:group` and
`host:port`, `-p` is a port, a path or a profile flag in most other tools, and `PGPASSWORD`
fuses the keyword into one uppercase word with no boundary before it. Catching any of these
would mask ordinary commands far more often than it found a password, so they stay text or
code; a long value is still caught by the statistical rule below.

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
on 200,000 random strings and on planted secrets (see "The oracle sweep" below for when the
whole sweep runs). `SecretShapesScalingTests` bounds the
characters read per character of the clip, so the check is a count, not a clock.

The same pass found four classifier patterns with the same flaw, rewritten as patterns that
accept the same language without the backtracking: a link's host (`[^\s/?#]+\S*` is
`[^\s/?#]\S*`), a functional colour (`\(\s*[^()]+\)` is `\([^()]+\)`), a call
(`\w+\((?:\)|[^\s)])` is `\w\(\S`), and every line-start rule in `CodeShapes`, where `^\s*`
could run through a block of blank lines from each of them and `^\h*` cannot.

## Reading a large clip cheaply

Linear was not yet cheap: the vendor-key pattern cost about 0.7 s a megabyte and the card-number
pattern 0.2 s, on every copy up to the 2 MB clip bound. Every byte of a clip is still read for a
credential, and the answer is still exactly the patterns' answer; what changed is how much of the
clip each pattern is handed. `PatternWindows.swift` holds the pieces.

- **A literal in the bytes first.** Every character a pattern matches as ASCII is that ASCII byte,
  so a clip whose bytes lack `-----BEGIN`, `eyJ` or `://` cannot hold a PEM header, a JWT or a
  connection string, and those readers are skipped. The named-secret reader runs only when the
  bytes hold `:` or `=` and a stem of one of its names (`api`, `secret`, `token`, `pass`, `pwd`,
  `credential`, `private`, `access`, `auth`, `client`), with `token`'s `k` also read as U+212A.
- **The vendor-key pattern on windows.** It runs only where one of its literal prefixes starts,
  on the 128 characters from there. Its longest shortest match is 47 characters, so a window
  decides every prefix more than 48 characters before its end, and those are not read again.
  SendGrid's first segment has no longest length, so its window runs to the end of the token.
- **The card-number pattern on runs.** It runs only over runs of digits, spaces and hyphens that
  hold at least thirteen digits, the fewest any grouping has, cut at character boundaries so a
  digit carrying a combining mark stays a non-digit.
- **ASCII clips byte for byte.** The statistical rule and the shell-command rule read an ASCII
  clip's bytes as its characters, which they are.

`ClipKindOracleTests` keeps the whole-clip reading as the oracle and compares it on 50,000 random,
planted and realistic clips in the full sweep; `ClipClassifyScalingTests` bounds the characters handed to the two
patterns by the number of prefixes and runs, not the clip's length. The before and after are in
`Docs/performance.md`.

## The oracle sweep

The two oracle suites are fixed-seed and deterministic, and the full sweep costs over a minute
locally and several on the CI runner, where it starved the rest of the test run. So
`swift test` and `make verify` run a sample: the first two seeds of every generator, each on the
first twenty-fifth of the strings the full sweep gives that seed, plus every planted shape and
hand-written case. The sample is a prefix of the sweep, so anything it finds the sweep finds too.

`UTTRFLOW_ORACLE_SWEEP=1 swift test --filter Oracle` runs every seed in full. The
`oracle-sweep.yml` workflow does that nightly, on demand, and on pull requests that touch
`Sources/UttrflowClipboard`; it is not a required check.

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
Long identifiers with a digit score between 3.7 and 4.1, because English spread over a few words
does, so a run of words joined by `-`, `_` or `/` is exempt (#919): three or more pieces, each a
word in one case (`paste`, `Screenshot`, `HDR`), optionally numbered (`v2`, `utf8`), or a number
with at most a two-letter suffix (`2024`, `2nd`). That lets branch names
(`fix/796-paste-confirmation-cancel`), slugs, dated file names and test names through. A random
piece mixes case and digits, so across three thousand random base64 and base64url tokens at 24,
32 and 40 characters none was exempted and the catch rate did not move. Still masked, paid
knowingly: a long camelCase identifier with a digit, and a deep source path that does not open
like one.

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
