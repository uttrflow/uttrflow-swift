# Code quality

Readability, maintainability and design quality outrank speed of delivery. The principles below
are non-negotiable on every change, without exception: **single source of truth (DRY), SOLID,
KISS, YAGNI, design patterns where they remove duplication or branching, and modular low-level
design.** A rule whose check is a command is a gate; a rule whose check is reading the diff is a review
rule, and the measure shown is what the reviewer counts.

## Gated limits

| Rule | Measure | Limit | Check |
|---|---|---|---|
| Comments | lines in a new `//` or `///` block; multi-line blocks per file | 1; never above `Scripts/comment_baseline.json` | `make comment-audit` |
| Line coverage per module | percent | at least 95 | `make coverage` |
| User-facing claims | privacy, accuracy or speed sentences in `Sources/UttrflowUX`, `Sources/Uttrflow` and `README.md` not in `Docs/claims.json` with live, unexpired evidence | 0 | `make claims-audit` |
| Coverage exclusion size | lines per excluded file | at most 400, unless listed in `OVERSIZED_EXCLUSIONS` | `make exclusion-audit` |
| Spelling matches decided by shape, per file | count | never above `Scripts/loose_match_baseline.json` | `make match-audit` |
| Closed word lists: literal collections of 4 or more words, per file | count | never above `Scripts/closed_list_baseline.json` | `make closed-list-audit` |
| Text split by a hand-written separator (`split(whereSeparator:` or `split {`) in `UttrflowAI`, `UttrflowPipeline`, `UttrflowCore/Cleaning`, `UttrflowEval`, per file | count | never above `Scripts/word_split_baseline.json` | `make word-split-audit` |
| Fixed English literals handed to `Text`, `Button`, `Label`, `.help`, `.accessibilityLabel`, per file | count | never above `Scripts/string_baseline.json`; see [localisation.md](../localisation.md) | `make string-audit` |
| Line length and indentation | characters, spaces | 110, 4 | `make lint` |
| Force unwraps, `try!`, implicitly unwrapped optionals, leading underscores, non-`///` doc comments | count | 0 | `make lint` |
| Compiler warnings | count | 0 | `make build` |
| Swift language mode | version | 6, strict concurrency | `make build` |
| Real email or postal addresses in fixtures | count | 0 | `make pii-audit` |
| Audio files outside `Tests/Fixtures/SyntheticAudio/`, by extension or header | count | 0 | `make audio-audit` |
| Connections opened on the dictation path | count | 0 | `make offline-audit` |
| Pasteboard access outside the clipboard adapters | count | 0 | `make pasteboard-audit` |
| Local-store writes outside `PrivateFile` | count | 0 | `make store-permissions` |
| Typed text in log messages | count | 0 | `make log-audit` |
| `swiftlint:disable` and `swift-format-ignore` markers | count | 0 | `grep -rE 'swiftlint:disable\|swift-format-ignore' Sources Tests` prints nothing |
| Remote scripts piped into a shell | count | 0 | `grep -rE 'curl[^\|]*\|[[:space:]]*(ba)?sh' Scripts .github Makefile` prints nothing |
| `@testable import` in `Sources/` | count | 0 | `grep -rE '@testable import' Sources` prints nothing |
| XCTest in the test suite | count | 0; tests use Swift Testing (`import Testing`) | `grep -rlE 'import XCTest' Tests` prints nothing |
| Test functions named after an issue number | count | 0 | `grep -rE 'func test[A-Za-z_]*(Issue\|issue)[0-9]+' Tests` prints nothing |
| Files named `*_v2`, `*_new`, `*_old` or `* copy` | count | 0 | `git ls-files \| grep -c -E '_v2\|_new\.\|_old\.\| copy'` prints 0 |

## Design limits for code you add or touch

Checked in review with the measure shown. A function or file that is already over a limit does not
grow when you touch it: extract first, then add. The limits bind the code being written; existing
code meets them when it is next changed.

| Rule | Limit | Measure |
|---|---|---|
| Function length | at most 40 lines | read the diff; `git diff -U0 origin/main` hunks inside one `func` |
| File length | at most 400 lines; a file over 1,000 lines gets 0 new members | `git diff --name-only origin/main -- '*.swift' \| xargs wc -l \| sort -n \| tail` |
| Nesting depth | at most 3 levels; use early returns | read the diff |
| Parameters per function | at most 5; more means a value type | read the signature |
| Primary types per file | 1, plus its extensions and private helpers | read the file |
| New `default:` arm in a `switch` over our own enum | 0, so a new case forces every switch to handle it | `git diff origin/main \| grep -E '^\+\s*default:'` lists none for our own types |
| Boolean parameters that select behaviour | 0; use an enum or an option type | read the signature |
| Requirements per protocol | at most 5 | read the protocol |
| Access level | `internal` by default; `public` only for a cross-module API | `grep -n '^public\|^    public' <file>` |
| Duplicated code | 0 blocks of 3 or more identical lines; 0 literal collections with the same members in 2 places | search before adding (below) |
| URLs to chat, tracker or pull-request pages in comments, new | 0; link to a `Docs/` page | `git diff origin/main \| grep -E '^\+\s*//.*https?://'` prints nothing |
| Commented-out code, new | 0 | `git diff origin/main \| grep -E '^\+\s*//\s*(let\|var\|func\|if\|for\|return\|guard)\b'` prints nothing |
| UI frameworks in logic modules | 0 imports of `AppKit`, `ApplicationServices`, `SwiftUI` or `Cocoa` outside the platform modules | see "Modules" |
| Modules a behaviour change edits | at most 3; more means the seam is wrong, so say why in the PR | `git diff --stat origin/main` |
| New `@unchecked Sendable`, `nonisolated(unsafe)` or `Unsafe*Pointer` | 0 in logic modules; in a platform module 1 only with a one-line reason | `git diff origin/main \| grep -E '^\+.*(@unchecked Sendable\|nonisolated\(unsafe\)\|Unsafe[A-Za-z]*Pointer)'` |
| New singletons (`static let shared`) | 0; inject the dependency | `git diff origin/main \| grep -E '^\+.*static (let\|var) shared'` prints nothing |
| Unused declarations added | 0; delete code in the commit that stops using it | search for the name |

## Single source of truth (DRY) — non-negotiable

Every fact, rule, threshold, table, string, path and key has exactly one home. Everything else
reads it from there; nothing copies it.

1. **Search before you write.** Run `git grep` and, for work in progress, `git grep --untracked`
   for the concept name and for the literal values. A match means reuse it. A near-match means
   extract the shared seam in the same pull request, then use it.
2. **The decision question.** If one of two things changes, must the other? Yes means one owner
   and one reader. No means two different facts that happen to look alike; leave them apart.
3. **A caller asks the owner; it never re-derives.** Derived values, caches and projections come
   from the owner with an explicit invalidation point.
4. **Numbers and thresholds live in one named constant or configuration type**, never inline in
   two places, and their reasons live on the `Docs/` page that measured them.
5. **Settings.** A setting is one stored value. A second flag for the same question is a bug.

Use these owners; do not reimplement them.

| Question | Single owner | Held by |
|---|---|---|
| Are two spellings one word? | `WordForms.sameForm` | `make match-audit` |
| Is a word written out at its own boundaries? | `spelledInto`, `isWritten` | `make match-audit` |
| Is a word still there, in the order spoken? | `WordErrorRate.measure` | `make match-audit` |
| Is a scalar in the Latin range? | `UttrflowCore.LatinScript.isInLatinRange` | tests, `Docs/latin-output.md` |
| Does text write only Latin? | `LatinScript.writesOnlyLatin` in `UttrflowCore`, built on the row above | tests, `Docs/latin-output.md` |
| What is the current line? | `FocusedFieldSnapshot.currentLine` | tests, `Docs/predict.md` |
| Which application is a terminal? | `TerminalApplications` | tests, `Docs/predict.md` |
| How much memory may the clipboard use? | `ClipboardBudget.standard` | `Docs/clipboard-budget.md` |
| Who touches the pasteboard? | the clipboard adapters | `make pasteboard-audit` |
| Who writes a local store's files? | `PrivateFile` | `make store-permissions` |
| Who may use the network? | `UttrflowAccount`, plus the listed exceptions | `make offline-audit` |
| Is suggestions mode on? | `suggestions.isEnabled` in the settings blob | `Docs/predict.md` |

## SOLID, each with a test you can run

1. **Single responsibility.** A type has one reason to change. Its doc comment is one sentence
   with no "and". A file with 2 or more unrelated primary types is split.
2. **Open for extension, closed for modification.** The next case of the same kind is a data
   entry, a configuration row or a new conformance, plus one test. If adding it edits an existing
   `switch` or `if` chain in 2 or more files, replace the chain with one exhaustive `switch` in
   one place, or with a protocol.
3. **Liskov substitution.** Every conformer passes the same protocol-level test suite. A new
   `as?` downcast on a protocol value in production code is 0; add the missing requirement
   instead.
4. **Interface segregation.** A protocol has at most 5 requirements and names one capability
   (`WordCorrecting`, `SnippetExpanding`). A client depends on the requirements it calls and no
   more; split a protocol when two clients use disjoint halves.
5. **Dependency inversion.** Logic depends on a protocol declared in its own pure module; the
   system API (Accessibility, the pasteboard, the Keychain, the network, the clock, the file
   system) sits behind an adapter and is injected. The engine is tested against values in an
   array, not a database.

## KISS and YAGNI

1. Build the smallest design that passes the check you wrote first (`AGENTS.md`, "Working
   agreement"). A simpler design that passes is the one you ship.
2. A protocol, generic, option, parameter or configuration key has at least 2 uses, or 1 use plus
   a test double that needs the seam. Otherwise delete it.
3. 0 compatibility shims, aliases or re-exports for code you removed; the app is not a library.
   The only compatibility code is a migration of persisted data, and it names the stored version
   it reads.
4. Do not build for a case no caller has. Make the next case cheap (an extension point) only
   when 2 cases of the same kind already exist.
5. Make invalid states unrepresentable. A closed set is an enum with one exhaustive `switch`, an
   identifier is its own type, and a runtime check is added only where the type system cannot say
   it. A test is not written for what a type or the compiler already guarantees.
6. Prefer a value type and a pure function to a class with state. Shared mutable state lives in
   an actor, or behind one owner.

## Design patterns

Choose a pattern only when it removes a measured duplication or a branch chain of 3 or more
cases on the same discriminator in 2 or more places. Do not name a pattern in the code; the type
and its doc comment say what it does.

| Need | Pattern | Where it already exists |
|---|---|---|
| Keep logic independent of a system API | port and adapter | `PredictionStore`, `ClipboardSource`, `KeyValueStore` |
| Swap an engine without touching callers | strategy | `TransformerKind`, `CandidateScoring`, `CandidateGenerating` |
| Several ordered, independently testable steps | pipeline of passes | the cleanup passes in `Docs/cleanup-design.md` |
| Never lose the user's words when a step fails | fallback chain | `FallbackRunner` |
| Sequence several collaborators once per event | coordinator and session | `SuggestionCoordinator`, `SuggestionSession` |
| A closed set of situations with different behaviour | enum with one exhaustive `switch` | `DictationState` |
| Local persistence behind one seam | store actor | `ClipboardStore`, `SnippetStore` |
| Keep presentation out of the view | presentation model in a value type | `UttrflowUX` |

Do not add: global mutable state, a god object (a type
that other types need to know the internals of), inheritance to share code (compose), or a
wrapper that only renames.

## Modules (low-level design)

The module graph has one direction: pure logic, then platform adapters, then the app shell.
Dependencies are declared in `Package.swift`; a cycle fails the build.

| Layer | Modules | UI-framework imports |
|---|---|---|
| App shell and platform adapters | `Uttrflow`, `UttrflowClipboard`, `UttrflowContext`, `UttrflowInput`, `UttrflowPermissions`, `uttrflow-dev` | allowed |
| Everything else | logic, stores, models, presentation, evaluation | 0 |

```bash
make layering-audit
```

fails on a UI-framework import in any module of the second row, and on a `Package.swift` target
dependency from one of those modules to a module of the first row. The count is baselined in
`Scripts/layering_baseline.json` and may fall and never rise; `python3 Scripts/layering_audit.py
--report` lists what is left.

A change that adds a module states, in the pull request: the module's one-sentence
responsibility, the modules it depends on and why none points the wrong way, its public surface in
at most 10 declarations, its test target, and its page in `Docs/README.md`. The module meets the
95% coverage floor from its first commit.

A non-trivial change (3 or more files, or 2 or more modules) writes its design in the pull request
before the diff: the responsibilities
of each type in one sentence each, the direction of every new dependency, the test seams.

## Readability and maintainability

1. **Names state intent.** Full words; no abbreviations except established ones (`URL`, `ID`).
   Types are nouns, functions are verbs, booleans read as assertions (`isEmpty`, `hasFocus`).
   A name that needs a comment to explain it is renamed.
2. **A literal that carries meaning is a named constant at its single owner.**
3. **Errors are explicit, and a fallback needs a promise behind it.** A silent substitute for a
   failure hides the defect, so a failure propagates unless a product promise requires a
   fallback (the user's words stay reachable, `Docs/definition-of-done.md`). Input from the
   user, the screen, a model or the disk never reaches `fatalError`, `precondition` or `try!`. A
   failure is typed and handled or propagated; a new `try?` carries a one-line reason for
   discarding the error and leaves the user-visible state unchanged.
4. **Concurrency is declared.** Shared mutable state is an actor or has one owner; strict
   concurrency stays on. 0 blocking I/O inside a lock or critical section; work that must follow
   it is handed off after the lock is released.
5. **The next case of the same kind** edits 1 data or configuration location and adds 1 test. If
   it edits more, the design has a branch where it needs a table.
6. **Docs move with behaviour.** A measurement, platform trap or rejected approach goes on a
   `Docs/` page in the same pull request. A page is evidence, not authority: when code and a page
   disagree, the code and a run decide, and the page is corrected in the same pull request.

## Fixing a defect

Answer in the pull request, in this order, before the diff is read:

1. **Why does the defect exist?** Name the code that is wrong, not the symptom, and the evidence
   that proves it: a failing test, a log line or a measurement. 0 unproven hypotheses.
2. **Why was it not caught?** Name the missing test, audit or measurement, and add it. The new
   test fails on the original code and passes on the fix; show both runs.
3. **What class of input does the fix cover?** If the answer is one phrase, one app, one fixture
   or one reported sentence, the fix is a special case and is rejected.
4. **Why can it not recur?** Name the test or audit that now fails if it does.

A rule that cannot be stated for the whole class of input means the design is wrong: reshape the
code into a clean seam first, then fix.

## Comments

A comment is one line and says what the code does now.

```swift
/// Judges the audio before it is decoded. See `Docs/silence.md`.
```

1. One line per block. A trailing comment on a line of code is exempt from the length limit.
2. Present tense, about the present code: what it does, what the value means.
3. A reason is allowed only if it changes what a reader would do. "Kept under the lock because
   `deinit` can run on any thread" qualifies; a story about what was tried does not.
4. Document a parameter only where one line covers it. `swift-format` rejects a singular
   `- Parameter` on a function with several, and a plural block is multi-line, so a function with
   several parameters documents all of them or none; say what is surprising in the summary line.
5. A measurement, platform trap or rejected approach goes on a `Docs/` page under a heading, and
   the comment links to it.

```bash
python3 Scripts/comment_audit.py --report                 # what is left, worst first
python3 Scripts/comment_audit.py --update                 # record a fall after improving a file
python3 Scripts/comment_audit.py --update --after-merge   # only when main moved under you
```

`--update` refuses a rise. `--after-merge` records the rises that rebasing onto `main` brings in
from files the rule has not reached; it prints each one into the baseline diff for review. Never
use it for your own comments.

## Spelling and meaning

A key proposes; it never disposes. A phonetic code or other hash finds candidates, and the owners
below decide; a helper that compares letters is a shape match even inside another function.

Never decide that two spellings are one word by shape: not a prefix of *n* characters, not "one
contains the other". Ask the owners in the table above. A shape match fails in one direction: it
says "same" too easily, on paths whose failure is acceptance, so no test goes red. A
three-character stem equates "confirm" with "confuse" and "Aarav" with "Aaron".

```bash
make match-report                                            # what is left, with the line
python3 Scripts/loose_match_audit.py --update                # record a fall
python3 Scripts/loose_match_audit.py --update --after-merge  # only when main moved under you
```

A baselined match is legitimate when the shape is the question rather than a stand-in for one;
`CaretEchoPass` asks which completion targets begin with what the user typed. The author says why
a given match is right.

## Closed word lists

A literal collection of four or more words in code is a rule keyed to the words someone said, and
each one makes the next defect a patch. Decide by the property the words share, or move the list
into a data file; the count per file never rises.

```bash
make closed-list-report                                      # every list left, with the line
python3 Scripts/closed_list_audit.py --update                # record a fall
python3 Scripts/closed_list_audit.py --update --after-merge  # only when main moved under you
```

## Word splits

Each hand-written split decides where a word ends, so two call sites count different words for one
text and an index, a range or a verdict moves by a word. Word boundaries belong to one seam,
`WordTokens.swift`; the count of splits elsewhere per file never rises.
`Tests/UttrflowEvalTests/WordTokeniserCharacterisationTests.swift` pins what each tokeniser does today.

```bash
python3 Scripts/word_split_audit.py --report                 # every split left, with the line
python3 Scripts/word_split_audit.py --update                 # record a fall
```

## Measurements and thresholds

1. **Show the measured value; missing evidence is its own value.** An unknown is never defaulted
   to the strongest value, and a sentinel is never shown to the user or written into a prompt.
2. **A threshold needs a live signal**, proved by a test that varies the signal across the
   threshold. A threshold compared against a constant input is a defect.
3. **A claim about speed or accuracy names its measurement** and where its clock starts and stops,
   in a document and in the interface. A threshold is cited by its constant's name, not its value.
4. **Behaviour that depends on its neighbours is proved by a property over every cut of the
   corpus**, not by the one failing example.
5. **The instrument does not move with the patch.** A pull request that changes cleaning code may
   add corpus cases, but does not change an existing case's expectation unless it names the
   decision that changed it.
6. **A gate fails when it cannot run.** A check whose tool is missing exits non-zero instead of
   passing, and a count quoted in a document is re-measured by the command in the same commit.
7. **A latency claim states where its clock starts and stops**, both as named events (key down,
   last audio frame, words ready, text inserted), and records each sub-stage on its own. A total
   without its stages cannot say which stage moved.
8. **Read the artefact before writing the premise.** A claim about a third-party model's
   internals cites the symbol and its access level, or the run that showed it.
9. **A derived constant names its source**: the corpus, language and command it was fitted on.
   A constant fitted on one language is not a default for the others.
10. **One current table per measurement.** A new run replaces the table on its page; an older run
    is history and goes in the pull request, not beside the current one.

Evidence for rules 7 to 10: [measurement-claims.md](../measurement-claims.md).

## Tests and coverage

1. Tests are load-bearing. Deleting, skipping or weakening an existing assertion is agreed in the
   pull request first; list each one the diff removes:
   `git diff origin/main -- Tests | grep -E '^-.*(#expect|#require|@Test)'`. A test that is
   genuinely broken is surfaced in the PR, not edited until it passes.
2. Prefer a real object, then a hand-written fake, and a mock last. A test asserts behaviour a user
   or caller depends on, never code structure, and its name is a
   sentence. It fails only when our code changes.
3. A test asserts exact values and counts, never a bound ("more than 0") or the mere absence of
   an error. It never asserts a value the test itself just set and stored.
4. A test that executes lines without asserting behaviour is worse than the exclusion it hides.
   A new test is run by name (`swift test --filter`), and the run shows it executed: a test that
   is not discovered covers 0 lines.
5. An exclusion lives in `Scripts/coverage_report.py` with a stated reason, printed on every
   run. Adding tests until the exclusion can go is the way out.
6. A test leaves 0 side effects: every temporary file, `UserDefaults` suite and Keychain item it
   creates is removed (`Docs/preferences-suites.md`).
7. A test injects a fake for the Keychain, the pasteboard and `UserDefaults`; `make test` shows 0
   macOS permission prompts. A new `sleep` to fix a race is 0: wait on the event, and a `sleep` that
   must stay carries a one-line reason.

## Protected files

Change one only when the task is about it, and say so in the PR.

| File | Rule |
|---|---|
| `Package.swift`, `Package.resolved`, `.github/workflows/`, `.githooks/` | see "Dependencies" |
| `Scripts/*_baseline.json` | written only by the script's `--update`; never by hand |
| `Scripts/disclosure_audit.py` | never loosened |
| `Resources/Uttrflow-Info.plist` version fields | changed only by a release |
| Bundle identifier and signing identity | unchanged across builds; Keychain items are tied to the signature (`Docs/account-keychain.md`) |
| `Design/*.dc.html` artboards | regenerated from `Design/_gen_*.py`; edit the generator |
| `Scripts/design_*.py`, the `design-audit` target and its place in `verify`, `ALLOWED` and `SCENERY` | never loosened; an exception is added with its reason ([design.md](design.md#exceptions)) |

## Dependencies

1. A new package dependency, workflow or hook change is agreed in an issue before the pull
   request.
2. The pull request states the dependency's purpose, a licence compatible with `LICENSE`, whether
   the project is maintained, and the count of transitive dependencies it adds. A dependency
   that duplicates an existing one is refused.
3. Dependencies are updated one at a time, `swift package update <name>`; 0 whole-lockfile
   updates.
