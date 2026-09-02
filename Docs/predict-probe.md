# Phase 0 — what tab-to-complete can rely on

Measurements taken before any of the feature was built, so the design rests on numbers
from this machine rather than on estimates. Re-run everything here with
`uttrflow-dev probe`.

Apple M5 Pro, release build, SQLite 3.53.2. Every timing is a median of 100 runs after
20 warm-up runs.

## Retrieval — settled

`uttrflow-dev probe retrieval`, 50,000 synthetic entries of commands, URLs and phrases.

| Query | Median |
|---|--:|
| SQLite range scan, `text >= 'git c' AND text < 'git d'` | **4.7 µs** |
| Same rows through `LIKE 'git c%'` | 19.8 µs |
| Fuzzy scan, no prefilter | 7,128 µs |
| Fuzzy scan, 6-byte character mask | **478 µs** |
| Fuzzy scan, 12-byte character mask | 1,764 µs |

Three things follow, and the third was not expected.

**Write the range scan, not `LIKE`.** Four times slower here for a bare `LIMIT 8`. An
earlier measurement of the same comparison *with* `ORDER BY count DESC` put the penalty
near seventeen times, because the sort has to see every match before it can rank them.
The real store ranks, so expect the larger figure and measure it again in phase 2.

**Fuzzy stays a fallback, never a parallel path.** `git p` matches 925 entries exactly
and 2,776 within one edit — and the extra matches are other commands, `git commit` among
them. Running fuzzy beside exact would answer "did you mean `git commit`?" to somebody
typing `git push`. It runs only when the exact scan returns nothing with support behind
it.

**The character-mask prefilter's strength is its window width.** A mask over the first
*n+k* bytes of an entry, matched to the query, gives **14.9×**. A fixed 12-byte window
gives 4.0× — sound, because a wider window can only make the filter weaker and never
rejects a true match, but most of the gain is lost. Phase 2 must therefore hold masks at
a width the query can choose from rather than one width for everything.

Damerau, not Levenshtein: `gti c` is one edit from `git commit` only when transposition
costs one. Under plain Levenshtein it is two, and the query the user actually mistypes
would be missed.

## The placement ladder — implemented and tested

`SurfaceCapability.placement` decides where a suggestion can be drawn for one field:

| The field reports | Placement |
|---|---|
| Its text, its caret rectangle and its styling | Inline ghost |
| Its text and its caret rectangle | Caret chip |
| Its text only | Window strip |
| Nothing, or it is a secure field | Nothing is drawn |

`CapabilitySweep` aggregates readings and answers the one question phase 0 exists to
settle: whether the inline ghost reaches enough fields to lead with. Below 30% it does
not, and the window strip is the product.

## The application sweep — pending the operator

`uttrflow-dev probe surface --seconds 120 --output Docs/predict-sweep.md`

**Not yet run.** Accessibility is granted per binary, and `uttrflow-dev` does not have
it. Granting it needs a password, and the sweep needs somebody to click into a text
field in each application while it runs. Until then the capability table below is empty
and the ladder decision is unmade.

To run it: grant `.build/release/uttrflow-dev` Accessibility in System Settings ›
Privacy & Security › Accessibility, then run the command above and click into a text
field in each of Terminal, Chrome, Safari, Slack, Mail, Notes, Word, Cursor, VS Code,
Xcode, Messages, Finder, Music, Preview, Numbers, Pages, Linear, Notion, Figma and
System Settings.

The probe prints each new field as it sees it, so the run can be watched. It asks
system-wide first and the application second, in that order, because apps answer one or
the other and not reliably both — the same ordering `Docs/insertion.md` records for the
dictation path. Fields are told apart by application, role and whichever of identifier,
placeholder or description the field publishes, so Chrome's address bar and a search box
on a page do not collapse into one row.

## The event tap — pending the operator

`uttrflow-dev probe tap --seconds 20`, and `--stall` to force the system to disable it.

**Not yet run**, for the same reason: an event tap cannot be created without
Accessibility. What it will answer:

- Tab is swallowed while the tap is armed, and other keys pass through untouched.
- `--stall` sleeps two seconds inside the callback, which is past the system's patience,
  so the tap is disabled and the recovery path runs. The summary counts both.

## Open, and not answered by this probe

**Detecting a composing input method.** Nothing in the Accessibility API reports that a
Hindi, Chinese or Japanese IME is mid-composition in another application. Suppressing
suggestions during composition — which the design requires, because marked text and a
ghost overlay in the same place are unreadable — needs a different mechanism, most
likely watching for the marked-text range the field itself exposes while composing. This
is phase 5's problem and it is not solved.

**Single-undo grouping.** Whether `⌘Z` reverts an accepted completion as one step is a
property of each target application, not of the insertion. It needs the sweep to have
run first, so it is deferred to the same session.
