# Definition of done

**Reconstructed, not quoted.** The original PRD is not in this repository and is no longer
to hand. What follows is assembled from what the code and `PLAN.md` say the requirements
were — every `§` reference below appears in a source comment or in the plan, written at
the time the requirement was being satisfied, and the wording is that comment's rather
than the PRD's.

That is a real limitation and it cuts one way in particular: **this document can only
check promises somebody wrote down. A requirement nobody implemented left no comment, so
it cannot appear here.** Treat it as an audit of the product against its own claims, not
as proof of coverage against the PRD. If the original text resurfaces, the first job is to
diff it against this list.

Verdicts were produced by running the checks in the right-hand column, not by reading.

## The promises

| § | The promise | How it is held | Verdict |
|---|---|---|---|
| 9 | Meaning must not change | `MeaningPreservationGuard` rejects a tidy-up that drops or invents content; English and Hindi number words are equated so "बीस" → "20" does not read as invention | ✅ enforced in code, covered by tests |
| 14 | Never overwrite what the user did not select | Structural, not vigilance: `FocusedTextField` exposes exactly one mutating operation, `replaceSelection(with:)`. No code path exists that could reach the rest of the field | ✅ verified — that is the entire mutating surface of the protocol |
| 15 | The dictation states the interface must draw | `DictationState`: `idle`, `recording`, `transcribing`, `tidying`, `inserted`, plus `failed` as a way of leaving rather than a sixth kind of progress | ✅ matches |
| 16 | The user must never learn which engine ran | Tests scan every string on every pane, page, menu and error for engine, model and vendor names. Six test files enforce it | ✅ enforced; the diagnostics page uses capability descriptions ("Downloaded speech model"), never a product name |
| 19 | Whatever fails, the user's words stay reachable | `FallbackRunner` under insertion; a failed tidy-up inserts the raw transcript; a failed insertion keeps the text and routes the user to Recent | ✅ enforced, with the salvage path now actually writing to history |
| 20 | Report idle memory, the speech model loaded, and the language model | `uttrflow-bakeoff profile` and `footprint` | ✅ measured: 10.9 MB idle, +113 MB for the speech model, 273.6 MB peak mid-dictation. Leak check over 30 dictations: **clean** — footprint falls. `Docs/performance.md` |
| 22 | The numbers are for reading on the machine, never sent | Diagnostics is in-memory and bounded; nothing serialises or uploads it | ✅ — and see `Docs/offline.md` for the network audit |
| 29 | No audio saved | **Deviated, deliberately (2026-09-04).** Each dictation's audio is written beside the live buffer and deleted the moment its words land; it is kept for a day only when the words were lost, so the dictation can be retried. Nothing leaves the Mac. `Docs/recordings.md` | ⚠️ recorded deviation; the privacy copy and `SettingsPrivacyCopyTests` say what is now true |
| 31 | No tiny fallback LLM | **Deviated, deliberately.** A local open-weight model ships, because Apple's Foundation Models have no Hindi | ⚠️ recorded deviation |
| 32 | The requirements' own worked example | Shipped as corpus case `late-to-meeting` | ✅ verified live, below |

## §32, checked against the running product

```bash
uttrflow-dev clean "hey john um i'll probably be about 20 minutes late to the meeting because the deployment is still running"
```

```
raw    hey john um i'll probably be about 20 minutes late to the meeting because the deployment is still running
clean  Hey John, I'll probably be about 20 minutes late to the meeting because the deployment is still running.
by     foundationModels in 2.25s
```

That is the required output exactly: the filler is gone, the comma after the name is
there, nothing else moved.

## Deviations

Recorded in full under *Deviations from the PRD* in `PLAN.md`. In brief:

- **§31** — a local open-weight model ships, for Hindi.
- **§16 recording panel** — the floating button *is* the recorder, so one thing moves on
  screen rather than two.
- **Context does not turn speech into SQL.** The largest deviation, and the one that
  narrows the product most. Seven prompt designs were tried; every one strong enough to
  produce SQL also invented content the speaker never said. Context does spelling only.
- **§29 is no longer a deviation** — the PRD was right and the plan was wrong.

## What this document cannot tell you

- Whether a requirement exists that nobody implemented. No comment, no row.
- Whether the wording above matches the PRD's wording. It is a paraphrase written by
  whoever satisfied the requirement.
- Anything about §1–8, §10–13, §17–18, §21, §23–28, §30 — no source comment cites them.
  They may have been satisfied without comment, or may not have existed.
