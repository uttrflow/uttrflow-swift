# AI suggestions: accuracy is the product

An AI suggestion (tab-to-complete) that is wrong costs more than one that never appeared. The wrong
one has to be read, judged and rejected, and it spends the belief that what appears is worth
looking at; once a person has learned to ignore the grey text, a better model cannot win them back.
So the feature is judged on how often it is right when it answers, and it answers as rarely as it
must to keep that number high. This page is the set of rules that withhold a line, and what each
measured. The rules live in `FieldReading.scope` (`Sources/UttrflowPredictCapture/FieldReading.swift`),
`Register.answersFromHistoryAlone` (`Sources/UttrflowPredict/Register.swift`), the floors in
`Verification` (`Sources/UttrflowPredict/Verification.swift`), and `CompletionText.finished` and
`Specifics` in `Sources/UttrflowLocalModel`. The loop they sit in is [predict.md](predict.md).

## Precision and coverage

**Precision** is the share of the suggestions actually drawn that were right. **Coverage** is the
share of moments where anything was drawn. `uttrflow-bakeoff complete --fixtures` prints both, with
precision to two decimal places, and the count of wrong lines, per category;
`Scripts/predict_scorecard.py new.json [--compare-run old.json]` reads its `--json` output and
compares two runs.

A fixture whose expectation takes any continuation (`Determinacy.any`, the default for chat, notes
and mail) has nothing to check a hit against, so the report counts its hits as *unjudged*, prints
them apart (`hits judged … unjudged …`), and computes precision over judged fixtures only. An
address or search fixture, where the generator refuses by design, expects `<none>`.

`complete --fixtures` measures the model alone. `complete --sources --json run.json` exercises the
app's choice between remembered, machine and model candidates — shared session ranking,
verification and model fallback — against seeded source cases
(`SourceArbitrationFixtures.swift`), and the scorecard reports precision for each source shown. It
is an arbitration check, not a measurement of a live corpus.

The design target is precision at or above 99%, with coverage whatever that costs: a category that
cannot reach it stays quiet until something can ground it.

`make predict-accuracy` holds that bar on this Mac: it builds `uttrflow-bakeoff` in Release, runs
the full fixture catalogue into `.build/predict/fixtures.json`, and runs `make predict-scorecard`,
which exits non-zero when judged precision falls or the count of wrong shown lines rises against
`Scripts/predict_precision_baseline.json`, overall or in any category. A missing, added, duplicated
or recategorised fixture, or a changed category set, also fails, so a partial `--only`, `--limit`,
`--sources` or `--failed-in` run cannot pass for the full catalogue. Coverage is not compared:
withholding more lines is allowed. A bare `uttrflow-bakeoff complete --fixtures` measures and does
not enforce. The run needs the Metal toolchain and the local model, so CI does not run it;
`make verify` runs `make predict-scorecard-test`, which proves the ratchet on synthetic runs.

The 99% target is reported beside the ratchet: a scope below it prints `TARGET NOT MET`, and an
unchanged run still passes the ratchet, so the gap stays visible without blocking. The baseline is
written only by `Scripts/predict_scorecard.py run.json --record-baseline <path>` from a run whose
JSON says the unfiltered catalogue ran in full; it is refreshed when a reviewed change moves the
fixture set or the model.

## Two causes of a wrong line

**Stale context.** The suggestion was right for a moment that has passed: another conversation,
thread or page. A chat composer publishes the same name in every conversation, so without a
narrower scope one corpus and one set of recent lines would serve every thread. What is on the
screen now outranks anything remembered from before.

**Guessing where nothing grounds the guess.** A host after three letters, a search phrase after
two, a file the machine never listed. In a terminal the machine is asked
([predict-agent.md](predict-agent.md)); elsewhere the rules below hold the model back.

## A field is identified by what it writes to

A field that owns no document is scoped by the window that holds it, so two conversations are two
corpora and two sets of recent lines ([predict.md](predict.md), "What a field's scope is"). Window
counts and edit marks (`Priya (3)`, `Draft •`) are stripped so a thread stays one thread; a title
longer than 120 characters is a document's first line and names nothing; a title equal to the
application's own name names no thread and gives no scope. A field that owns a document keeps its
own scope: a browser by host, a terminal by directory, except a terminal whose title names a remote
or unidentified session ([predict-terminal-paths.md](predict-terminal-paths.md)).

## Refused: what no model can know

`Register.answersFromHistoryAlone` is true where the field writes web addresses or searches, and
there `MLXCandidateScorer` does not generate at all; the corpus still answers, from what this
person entered there before.

- **A web address.** A host exists in this person's history or nowhere. `Register.writesAddresses`
  is true when at least half of this person's lines here are shaped like an address (no whitespace,
  an inner dot followed by a letter), or, with none of their own, when the field's accessibility
  name says it takes one (`namesAddressField`: "url", "website", "web address", "search … address").
- **A search phrase.** `Register.isSearchField` is true when the field's own name contains "search"
  or "find". The test is deliberately narrow: an editor calls its own field a query or a filter, and
  what it holds is grounded by the schema on screen, so those still answer (SQL holds at 97.5%
  precision and full coverage).

Measured with `uttrflow-bakeoff complete --fixtures`, 1,154 fixtures, Release, before judged-only
scoring (unjudged prose hits counted as right):

| | Neither refused | Addresses refused | Searches refused too |
|---|---|---|---|
| Precision | 94.07 % | 95.80 % | **96.74 %** |
| Coverage | 98 % | 92.9 % | 85.1 % |
| Wrong lines drawn | 67 | 45 | **32** |

Refusing addresses alone took the address fixtures from 74.1% to 83.5% precision; what stayed
wrong there was search boxes guessing from two to four characters (`ni` → `ni-ghts`, `blue` →
`blue tooth`, `receipts 20` → `receipts 2023`). Half the wrong lines go for thirteen points of
coverage. Read as a hit rate the same change looks like 112 regressions; a line withheld because
nothing could vouch for it is not a failure of the same kind as a line drawn and wrong. In the
bake-off, which measures the generator alone, the address-and-search category reads as no coverage
at all.

## A generated line says how sure it is

A generated line is scored by the pass that wrote it, and a line below a floor is not drawn. While
the model decodes, `RecordingSampler` keeps the log-probability of every token it chose, and
`GeneratedConfidence` averages the tokens that wrote the line's own words past the typing; a word
the typing still owed and anything the parser cut off the line are left out. When one of those
tokens falls under `Verification.plausibilityFloor`, the line scores as that token instead, so one
invented name or figure among likely words clears neither floor below. A token that
`TokenChoice` or `TokenHealing` held the model to is scored over the model's own logits from before
the mask (`UnmaskedLogits`), so a forced token counts as likely as the model found it, not as
certain. No second model pass is spent. A line no pass scored, such as one whose model has since been released, is never drawn.

| Floor | Value | What clears it |
|---|---|---|
| `Verification.certainFloor` | −0.9 | The one line drawn alone as `.certain` |
| `Verification.choiceFloor` | −1.5 | A line offered as one of several in a `.choice` |

Both are mean log-probability per generated token on gemma-3-4b-it-qat-4bit, a different scale from
`plausibilityFloor` (−6.0), which reads a remembered line with no context.

`certainFloor` is set from the 1,173-fixture catalogue (`uttrflow-bakeoff complete --fixtures
--judge`, which prints this table); coverage is the share of fixtures that drew a line:

| Floor on the pass's own score | Precision | Wrong drawn | Coverage |
|---|---|---|---|
| none | 87.15 % (217/249) | 32 | 77.75 % |
| −1.5 | 87.85 % (217/247) | 30 | 77.15 % |
| −1.0 | 88.57 % (217/245) | 28 | 75.87 % |
| **−0.9** | **90.04 % (217/241)** | **24** | **74.68 %** |
| −0.75 | 90.38 % (216/239) | 23 | 71.44 % |
| −0.6 | 91.77 % (212/231) | 19 | 67.01 % |
| −0.5 | 92.48 % (209/226) | 17 | 61.04 % |

−0.9 is the lowest floor that keeps every judged right line. The eight lines it holds back were all
wrong (`npx esl` → `npx eslinit`, `def subtr` → `def subtrack`, two Hinglish replies, four
shopping-list items), for 3 points of coverage; above it each step loses right lines as fast as
wrong ones. The 24 wrong lines left are ones the model writes with confidence — nine shopping-list
items, five commands (`npx pret` → `npx pretify`), three SQL lines, three replies, two code lines,
one mail line, one robustness case — which the pass's own score cannot see.

**The scorer's second pass is not used for generated lines.** It separates right from wrong about
as well at the same coverage (90.27% at 72.63% with a −8.0 floor, 90.83% at 67.95% with −6.0) but
costs one more pass per line, a median of about 100 ms under load. A −3.0 floor on it reached 97.20%
precision at 40.58% coverage.

`choiceFloor` is not set from the catalogue, which draws one line per fixture. −1.5 refuses only
the two least likely of the 32 wrong lines, and a person chooses from a list on purpose.

`SuggestionScoringTests` (in `Tests/UttrflowPredictTests/SuggestionSessionTests.swift`) pins the
contract: a line under `certainFloor` leaves the turn quiet (`modelUnsure`), a line over it is
drawn, an unscored line is never drawn, an unscored alternative is dropped, and a value the machine
listed needs no score. `GeneratedConfidenceTests` pins which tokens score a line.

## A generated line keeps to this person's shape

Both models' lines pass through `CompletionText.finished`, so these rules hold on either path:

- **Prose ends at its first sentence end** (`Register.endsAtSentence`: not an address, not code or a
  command), since the tail of a run-on line is where a clause goes wrong; a stop inside a number, an
  address, an abbreviation or an ellipsis is read past.
- **Prose that copies the screen is refused**: `CompletionText.copiedRun` (5) or more screen words in
  a row that this person has not written here. The other person's last message is the likeliest
  thing for a small model to echo, and it is never the reply. Commands are exempt, because they
  reuse the paths and names on screen. The `chat/echo` fixtures (`CatalogueChat.swift`) cover a
  reply that opens as the last message does.
- **A sign-off is cut back** (`SignOff`): a closing such as "Kind regards," keeps the name after it
  only where the person wrote that name.
- **Length follows this person.** A continuation is held to `Register.lengthMultiple` (3) times this
  person's typical line here, never under `shortestAllowance` (16) characters; with no history, to
  the register's own limit (`registerContinuationLimit`): 80 for a reply, an address or a search,
  120 for a command, 160 for a document. The token budget follows the typical line too
  (`Register.maxTokens`), so a terse person is not given a paragraph's room.

## A generated line adds no specific nobody gave it

A number, spoken number, time, date, amount, percentage, email or web address can read as right while being wrong; one Tab puts it in a sent message. `Specifics.areGrounded` refuses either model's line when it adds a specific whose same-kind value is absent from typed text, this person's lines, the screen or machine values. Calendar names and day periods count; nearby numbers stay bound to dates (`Inbox (5)` cannot ground `March 5`), and amounts include their unit (`20 dollars` cannot ground `50 dollars` or `20 euros`).
DNS-shaped dotted hosts count, including ambiguous `readme.md` but not paths such as `docs/readme.md`; in code, a key name cannot ground an unprovided credential, and credentials are recognised by the shared `SecretShapes.matches` rules. Tokens compare lowercased with punctuation removed, without prefix or substring matching; digits inside names like `python3` are not numbers. The corpus is unaffected, and refusals log reason only.

Code, queries and commands write a few numbers that carry no value of their own. In those registers
(not prose, an address bar or a search box) a word whose every number is one of these is not a
specific. A number assigned to or compared with a name whose last word is `id`, `ids`, `pid`,
`uid`, `uuid` or `guid` is still an invented id, and one after `<` or `>` is an invented threshold.
So is one passed as the first argument of a call whose name ends in one of those words
(`findById(1)`, `getUserId(1)`), or ends in `user`, `order`, `account`, `record` or `item`, whatever
the verb (`deleteUser(1)`, `cancelOrder(0)`, `lookupAccount(0)`, `updateRecord(0)`,
`archiveItem(1)`). A call whose name starts with `get`, `fetch`, `find` or `load` and names an
entity is also covered (`getBook(1)`, `fetchOrder(0)`), as is a value listed in `IN (…)` or
`NOT IN (…)` after such a column. The exemption holds only where the number is an operand of code:
after an assignment, a bracket, a separator, an operator or a member, or after `return`, `in`,
`case`, `limit` and the like. A number standing as a word after a command's word or after `~` or
`^` is an argument the command acts on (`kill 1`, `HEAD~1`, `tail -n 1`) and is a specific. Each
row has a case in `SpecificsTests`.

| Literal | In code, a query or a command | In prose | Why |
|---|---|---|---|
| `0`, `1`, `-1` | kept | refused | a start, a step, an index, a bound or "not found"; in prose `at 1` is a time |
| `0.0`, `1.0` | kept | refused | the float forms of nothing and one |
| `true`, `false`, `nil`, `null`, `None` | kept | kept | words, never a specific |
| `""`, `''`, `[]`, `{}` | kept | kept | empty values, never a specific |
| `id = 1`, `user_id = 1`, `userId: 0`, `"id": 1` | refused | refused | a record nobody named |
| `findById(1)`, `getUserId(0)`, `deleteUser(1)`, `cancelOrder(0)`, `lookupAccount(0)`, `updateRecord(0)`, `archiveItem(1)`, `getBook(1)`, `id IN (1)`, `id NOT IN (1)` | refused | refused | a record nobody named, passed as an argument |
| `> 0`, `>= 0`, `< 1` | refused | refused | a threshold is a choice the line never showed |
| `kill 1`, `HEAD~1`, `tail -n 1`, `sleep 1` | refused | refused | an argument a command acts on: a process, a commit, a count |
| `2`, `10`, `1042`, `0.5`, `19.99` | refused | refused | a count, an id or an amount |
| `01`, `1e9`, `0x1f`, `1_000`, `1s` | refused | refused | a literal with a form, a base or a unit carries a choice |
| `$0`, `0%` | refused | refused | an amount sign or a percent sign reads as an amount |

## What this trades away

Coverage falls: the address bar is quiet unless the person has been there before, and short
prefixes in a search box do not answer. A feature that speaks less often and is right when it
speaks is one a person keeps switched on.
