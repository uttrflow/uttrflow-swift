# Recognising a credential

## Per-application exclusions and pause

Settings can exclude applications by bundle identifier and pause capture for one hour.
The exclusion list is empty by default; add an app from the running-app picker or choose
an application bundle. A timed pause can be resumed early and its end time survives an
app restart. Copies observed during a pause are passed over when capture resumes.

macOS exposes the frontmost application when Uttrflow notices a pasteboard change, but
does not identify which process wrote that change. A background writer can therefore be
attributed to the app that is frontmost at detection time. If the bundle identifier is
unavailable, the copy is not filtered by the exclusion list. These controls complement
the concealed pasteboard marker and secret detection; they do not replace either one.

`SecretShapes.matches(_:)` is keener to say yes than no. A false positive masks something
harmless: the row shows dots, Return still pastes it, one keystroke reveals it. A false
negative leaves a production password legible on a panel opened in meetings and on recorded
calls.

The clipboard panel, the main window and the suggestion overlay set `NSWindow.sharingType` to
`.none`. That is the default privacy decision for windows that draw clipboard contents,
transcripts or learned suggestions: a capture client that honours AppKit window sharing must not
receive those windows. This is partial protection, because system screenshots, ScreenCaptureKit
clients and video-call apps have not all honoured AppKit's sharing policy on every macOS release;
the manual checks in `Docs/ui-tests.md` record what each release actually hides.

English BIP-0039 recovery phrases are masked only when their word count, English-list membership
and SHA-256 checksum are valid; the bundled wordlist is from [bitcoin/bips](https://github.com/bitcoin/bips/tree/master/bip-0039)
and is used under its MIT license. This checksum check avoids treating every 12-word sentence as
a wallet credential; other language lists and invalid checksums are not detected by this rule.

## Shapes, cheapest first

1. A PEM header (`-----BEGIN`). Certificates are masked with keys; telling them apart by label
   is one label away from being wrong about the one that matters.
2. A JWT anywhere in the text: three base64url segments beginning `eyJ` (what `{"` encodes
   to). The signature may be empty, because an `alg: none` token is still a token.
3. A connection string with a password: `scheme://user:pass@host`, or `scheme://:pass@host` with
   no user, the password-only form some caches use. The colon in the userinfo is what keeps
   `https://example.com:8443/path` and `https://token@github.com/repo` out.
4. A URL that works for whoever holds it: a Slack, Discord or Teams incoming webhook, or a
   URL whose query or fragment carries `sig`, `signature`, `X-Amz-Signature`,
   `X-Goog-Signature`, `access_token`, `id_token`, `refresh_token` or `token` with a value of
   at least eight characters, which is what a signed (SAS, pre-signed) URL or a magic link is.
   `?token=` with nothing, or with a short placeholder, stays a link. Parameter names are
   percent-decoded first (`access%5Ftoken`), a host's closing dot is ignored
   (`hooks.slack.com.`), and a URL nested after a later `://` in another one's path or query
   (`?next=https://hooks.slack.com/…`) is judged as its own address. Each nested address is read
   only up to the next `://`, so the reading stays linear in the clip.
5. Vendor prefixes with a minimum length each (OpenAI, Anthropic, Stripe, GitHub, GitLab,
   Slack, AWS, Google, npm, DigitalOcean, Shopify, SendGrid), so prose about `sk-` keys is not
   itself one.
6. A named secret per line (`API_KEY=…`, `password: …`, `passphrase: …`, `client_secret = …`) whose value is
   quoted, or has a digit, or is at least 12 characters, so `var password: String` does not
   count. The name may carry a prefix: a keyword starts at a word boundary, after `_`, or at a
   lowercase-to-uppercase step, so `DB_PASSWORD`, `GITHUB_TOKEN`, `STRIPE_API_KEY` and
   `dbPassword` are all names. `pass` is a keyword, for `SMTP_PASS`. The keyword's own end
   still needs a word boundary, so `passwordless`, `tokenizer` and `token_count` are not names.
   The cost, paid knowingly: `max_tokens: 4096` is masked, because a digit under a name that
   ends in a keyword is exactly what a short password or PIN looks like.
   The value ends its line, or is followed by a `#` or `//` comment (after a space, for an
   unquoted value, since `#` can stand inside one). A quoted value may also be followed by `}`,
   `]`, or `, name:`, so a one-line JSON or JavaScript object (`{"apiKey":"…"}`,
   `{ apiKey: "…", region: "us" }`) counts; `"token: " + t` does not, because what follows the
   quote is more of an expression.
   A long bare value that only points at a secret is not one: an identifier path or an
   empty call (`request.token`, `process.env.API_KEY;`, `getpass.getpass()`), made of letters,
   `_` and `$` with no digit and no part of 32 or more hex letters, is code that loads a
   credential rather than the credential. A quoted value or one with a digit still counts,
   and so does a single long bare word, which is what a letters-only password looks like.
7. A payment card number (below).
8. A credential handed to a command or sent in a header (below).
9. The statistical rule below.

## A credential handed to a command

A credential inside a one-line command is not a named secret: the named-secret rule needs the
value to end its line, and in a command the value is followed by more of the command. Terminal
lines are also what the suggestion corpus learns from (`CaptureGate`), so a password typed once
would otherwise be stored and offered back. `CommandCredentialShape` reads each line as shell
words, honouring quotes, ending words at redirects, and splitting commands at `|`, `;` and `&`.
It recognises:

- A short flag, only for the program that reads it as a password: `mysql -pX` (joined only,
  since a bare `-p` asks), `sshpass -p`, `docker`/`podman`/`nerdctl login -p`, `redis-cli -a`,
  `ssh-keygen -N`/`-P`, `curl -u`/`-U user:password`, and the last word after `htpasswd -b`.
  The program may stand anywhere before the flag, so `sudo -u postgres mysqldump -pX` counts;
  `-p` elsewhere is a port, a path or a profile, so `ssh -p 22` and `docker run -p` stay code.
- `openssl … pass:<value>`, whatever the value; `env:` and `file:` only name where it is.
- A long flag whose last `-`/`_` part names a secret (`--password`, `--token`, `--secret`,
  `--db-pass`, `--api-key`), with its value joined by `=` or in the next word. `--no-…`,
  `--password-stdin` and `--token-file` do not pass one.
- An uppercase variable assignment whose name ends in one (`PGPASSWORD=…`, `MYSQL_PWD=…`).
- An `Authorization:` or `Proxy-Authorization:` header in any scheme, or a header whose name
  ends in a secret's name (`X-Api-Key:`), quoted or not, with the value in the same word or
  the next two. A scheme alone (`Authorization: Bearer`) sends nothing.

A value that is an unquoted variable, substitution or placeholder (`$TOKEN`, `${token}`, `{token}`,
`<token>`) is left alone, since it names where the credential is rather than being it. Quoted
shell punctuation is part of the value; a redirect operator outside quotes ends the word first.

A URL whose userinfo is one generated token with no colon (`https://<40 hex>@host/repo`) is
masked too, by the statistical rule below applied to the userinfo; `https://readonly@host`
stays a link.

### Lines learned before the rules widened

The suggestion corpus may already hold a line a newer rule recognises. At launch
`CaptureGate.sweepSecrets` asks `PredictStore.sweep` to delete every stored line, every
retirement pointing at one, and every succession naming one that `SecretShapes.matches` now
recognises. The corpus records the version it was swept with in its `sweep` table, so the pass
runs once per `CaptureGate.secretRulesVersion`; raise that constant whenever a shape is added.

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

`WordBreaks` is where that `\b` lives, and it asks the pattern engine itself rather than a word
index of its own: from a boundary it matches `(?s).(?:\B.)*` over the text from there, which
takes a character and then every further one standing inside the same word, and ends on the next
boundary. Reading from a boundary is what makes the slice safe — a boundary is where the word
rules stop looking back, so the text before it cannot move where the next one falls, and each
character is read once as the scan walks forward. This replaces `String._wordIndex(after:)`, an
underscored standard library entry that carried no source-stability promise, so a toolchain
change could have moved a boundary and altered what the scanner masks without failing a test.
`WordBreaksTests` now compares `WordBreaks` with `\b` over the whole text on combining marks,
emoji, regional indicator pairs, scripts written without spaces, and boundaries next to
punctuation, and the two agree at every character on every case measured. What that costs, and what
is done about it, is the next section.

**Where the two walks differ, and why it does not reach the scanner.** The word index worked in
scalars and could return an index inside a grapheme cluster, usually beside a format character:
in `" \u{70F}:\u{230F}."` it put a boundary partway through the first cluster, which a walk over
whole characters steps past. On 40,000 random strings carrying format characters the two walks
produced a different set of indices on 7,707 of them and differed at a character boundary on none,
and neither ever failed to advance. `NamedSecretScan` walks with `index(after:)` and asks only
about a character boundary, so an index inside a cluster was never asked about and never matched.

The same pass found four classifier patterns with the same flaw, rewritten as patterns that
accept the same language without the backtracking: a link's host (`[^\s/?#]+\S*` is
`[^\s/?#]\S*`), a functional colour (`\(\s*[^()]+\)` is `\([^()]+\)`), a call
(`\w+\((?:\)|[^\s)])` is `\w\(\S`), and every line-start rule in `CodeShapes`, where `^\s*`
could run through a block of blank lines from each of them and `^\h*` cannot.

## Deciding an ASCII boundary without the pattern

Asking the engine for every boundary costs more than twenty times what the word index did, which no
ordinary clip notices and one adversarial clip does — see the measurements below. So `WordBreaks`
takes a boundary from the rules directly where it can, and from the pattern everywhere else.

The rules reach two characters back and one character on: the widest of them holds two words
together across a single joining character, so `a.b` is one word and `a.` is two. Nothing in ASCII
is `Extend`, `Format` or `ZWJ`, which are the characters the rules skip over before applying, so a
position whose four-character window is entirely lone ASCII can be decided from the window alone.
`WordClass` is that decision: eight classes covering the 128 characters — a letter, a digit, an
underscore, a space, the character that joins letters, the one that joins digits, the two that join
either, and everything else, which never joins anything.

`asciiBoundary` walks forward from a boundary deciding each position that way, and gives up the
moment a character it would have to weigh is not lone ASCII — including a `\r\n`, which is one
character in Swift and not a lone scalar. Giving up costs the walk so far and nothing else: the
pattern then runs from the same boundary, exactly as before.

**Why the walk may start with nothing behind it.** At the first position after a boundary there is
only one character of history, not two, and the rules that want two cannot fire there anyway: each
of them needs the pair before the position to have been joined, and a boundary is precisely where
they were not.

**How it is known to be right, rather than argued to be.** Two walks that must agree is the failure
this code cannot have, because a boundary in the wrong place shows a credential instead of masking
it and no test goes red. So `WordBreaksTests` compares the walk with `\b` exhaustively: every ASCII
string of up to three characters; every five-character string over an alphabet holding two members
of each class, which is wider than the rules can see; and every ASCII character in turn in every
four-character context over one member of each class. Together that is 3.0 million strings, and
they agree everywhere. `make verify` reads every twenty-fifth of them and
`UTTRFLOW_ORACLE_SWEEP=1 swift test --filter WordBreaks` reads them all, in 18 seconds.

**What each of the three costs, measured.** Release build, one core, M5 Pro, 21 September 2026,
processor time for one `ClipKindDetector.kind(of:)` call on a 2 MB clip, median of seven, with the
word index, with the pattern alone, and with the ASCII rules in front of it:

| clip | word index | pattern | ASCII rules |
|---|---|---|---|
| code | 0.015 s | 0.014 s | 0.015 s |
| prose | 0.033 s | 0.033 s | 0.034 s |
| CSV | 0.027 s | 0.027 s | 0.027 s |
| logs | 0.069 s | 0.068 s | 0.067 s |
| a secret named on every line and never given | 0.208 s | 0.793 s | 0.213 s |

Only the last clip ever paid for the pattern, and it is the one a user can produce by copying a
`.env` template or a redacted log: 2 MB of
`auth_token=abc pass=x api_key=y secret=z pwd=w credential=v`, where every line starts a keyword the
named-secret reader must measure a boundary around and none of them gives a value it accepts. The
walk over that clip finds 838,872 boundaries whichever way it is read, and costs 0.705 s from the
pattern against 0.105 s from the ASCII rules; against the whole call, the pattern adds 0.70 µs a
boundary and the ASCII rules add 0.006 µs. The budget table in `Docs/performance.md` is written for
an M1, where these figures roughly double, so that clip sits at about 0.42 processor-seconds there
and over the 0.2 budget for a copy — as it did before any of this, and for a reason that has nothing
to do with word breaking.

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
- **The card-number pattern on runs.** It runs only over runs of digits (ASCII or fullwidth),
  horizontal spaces, hyphens and full stops (ASCII or fullwidth) that hold at least thirteen digits, the fewest any grouping has, cut at character boundaries so a
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
The word must be at least 12 characters (shorter values are too common in identifiers), contain
only ASCII letters, digits or the printable ASCII symbols the scanner allows, and contain both a
letter and a digit. The byte and character readers use the same alphabet. Hex of 32 or more
characters is a digest outright, because a sixteen-symbol alphabet can never reach the general
floor. Anything that opens like a path is left to the general rules.

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
in (4-4-4-4, 4-4-4-4-3, 4-6-5, 4-6-4, 4-3-3-3) with one separator, a space, dash or full stop,
used throughout. Checkout pages, statements and some password managers group with a no-break,
thin or other Unicode horizontal space, and some input methods type fullwidth digits and
separators. Line breaks split runs rather than joining groups, so a column of four-digit
numbers stays text even if the combined digits pass Luhn. The number is read in its printed
form first: fullwidth forms as ASCII, line breaks as `\n` and other
`Character.isWhitespace` spaces as U+0020. The digits must then carry a prefix some network issues under at that length (Visa, Mastercard,
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
| `org.nspasteboard.ConcealedType` | a password or similar | records text as `.secret`; does not record pictures |
| `org.nspasteboard.TransientType` | a copy made to move data, not for history | does not record it |
| `org.nspasteboard.AutoGeneratedType` | written by software, not by a person | does not record it |

Secrets detected by shape follow the same storage rule as concealed clips: the row can appear in
the running panel, masked until deliberately revealed, but the JSON history and saved-clips files
omit it. A launch after copying a secret therefore cannot show that secret again; keeping,
pinning or filing a secret only lasts until this process exits.

This is the only way an ordinary password is recognised. `hunter2` and `Tr0ub4dor&3` have no
shape that separates them from a word or a product code, and the frontmost application is not
necessarily the one that wrote the clipboard, so neither length and character classes nor the
application's identity is a sound signal. A password typed out and copied from a note is text.
That is why the home page promises passwords from password managers, not passwords.

## Pictures

Pictures are not scanned for credentials, card numbers or words. A picture copied with
`org.nspasteboard.ConcealedType` is skipped, because the app has no text to classify and no
masked picture row to show safely. Other copied pictures are kept in `Images/` beside the
clipboard file and follow the picture retention window from `Docs/clipboard-budget.md`.
