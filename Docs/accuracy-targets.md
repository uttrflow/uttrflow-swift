# Accuracy targets, the error taxonomy and the release gate

This page is the single source for what "accurate" means in dictation: which errors count, how
each one is measured, the number each one has to meet, and which numbers stop a release. Work
that claims to improve accuracy cites a metric by its ID from the table below and reports it
before and after; a change that cites none has not said what it improved.

The mechanics live elsewhere and are not repeated here:
[eval-methodology.md](eval-methodology.md) (the baseline gate, normalisation, what is scored and
what is only timed), [measuring-accuracy.md](measuring-accuracy.md) (the recorded corpus and why
one voice is enough for a regression check), [core-word-error-rate.md](core-word-error-rate.md)
(the edit distance and how passages are combined) and [bakeoff-method.md](bakeoff-method.md)
(how clean-up is scored).

## Why there is no single whole-system rate

A target such as "one error in ten thousand words" cannot be the gate, for two reasons.

- **It cannot be certified.** With zero errors observed in *n* trials, the one-sided 95% upper
  bound on the true rate is `1 − 0.05^(1/n)`, roughly `3/n`. Certifying 1 in 10,000 needs about
  30,000 clean words per release; a recorded corpus of seven hundred words certifies, at best,
  about 1 in 230, however well the system does.
- **It pools what has to be kept apart.** A dropped "not" and a missing comma are one edit each
  in a word error rate. The product promise is about the first kind, and a single rate lets
  a gain in the second hide a loss in the first. Rates are also never pooled across language,
  stressor or cohort; `AccuracyBaseline` refuses to average those away.

So every target below names its sample size and its bound, and where the corpus cannot supply
the sample, the gate is a regression check against the last release rather than an absolute
number.

## The error taxonomy

Every error a dictation can contain belongs to exactly one class. A formatting or cosmetic
error that changes what the text means is a meaning-changing error, never a formatting one.

| Class | What counts | Severity |
|---|---|---|
| **Meaning-changing** | a wrong word; a dropped or added negation; a dropped content word; an invented content word; a lost name, number or term the passage insists on; a rewrite (a synonym, a reorder, a summary, an answer); Devanagari or a translation reaching the screen; a number written with the wrong value; punctuation or layout that changes what is asserted | 1 — blocks |
| **Formatting** | a missing or wrong sentence stop, comma or question mark; wrong capitalisation; a number left as words where a numeral is wanted, or the reverse, at the same value; a line, paragraph or list break missing or misplaced; a filler, stammer or discarded false start left in | 2 — must not regress |
| **Cosmetic** | spacing: a doubled space, a space before a mark, a missing space after one, trailing whitespace | 3 — reported |

What the tidier may and may not do is catalogued in [cleanup.md](cleanup.md); that page decides
whether a given change is wanted, this one decides how its absence or its excess is counted.

## The metrics

Each metric has one owner in the code. "Not measured" is a state, printed as such, never as a
zero.

| ID | Metric | Definition | Owner today |
|---|---|---|---|
| `wer` | word error rate | `(substitutions + deletions + insertions) / reference words`, summed over passages, per language, stressor and cohort | `WordErrorRate.measure`, reported by `uttrflow-eval transcribe` |
| `wer-biased` | biased-word WER | `wer` over the reference words that were in the vocabulary handed to recognition | not measured: the corpus does not yet mark which words were biased |
| `wer-unbiased` | unbiased-word WER | `wer` over every other reference word; a bias list that helps its own words and hurts the rest shows here | not measured, for the same reason |
| `entity-loss` | entity error rate | required terms (`mustKeep`) absent from the output as a consecutive run, divided by required terms | counted per passage as `PassageScore.lost` and per case as `CaseScore.lost`; not yet reported as a rate |
| `override-error` | false-override rate | of the words a correction stage replaced, the fraction where the recogniser's word was right and the replacement is wrong | not measured |
| `meaning-change` | annotated meaning-preservation failures in the clean-up corpus | required phrases missing from output (`mustKeep`) or forbidden phrases added (`mustNotAdd`); these are sentinels, not a comprehensive count of every class-1 change | `CaseScore.lost` and `CaseScore.invented` in the shipping-router row of `make bakeoff` |
| `formatting` | formatting accuracy | marks and capitalisation matched against the reference, averaged over attempted cases | `CaseScore.markAccuracy` and `CaseScore.caseAccuracy` |
| `cosmetic` | cosmetic errors | class-3 errors per case | not measured |
| `seam-artefact` | seam-artefact rate | errors at the joins between separately recognised pieces (a duplicated, dropped or re-cased word, a stray stop) per join | not measured as a rate; `PieceJoiner` is tested by example |
| `silence-insertion` | silence-insertion rate | inputs with no speech that produce any inserted text, divided by such inputs | `uttrflow-eval nonspeech`, with the repetition-loop rate; see [silence.md](silence.md#measuring-what-still-gets-through) |
| `latin-output` | non-Latin output | outputs containing Devanagari or a translation, divided by outputs | the last check before insertion, see [latin-output.md](latin-output.md) |
| `tail-latency` | tail latency | the slowest dictations, from key release to words on screen | named here only; its stages, clocks and limits are set where latency is measured ([performance.md](performance.md)), not on this page |

## The targets

The bound is the one-sided 95% upper bound (`1 − 0.05^(1/n)` with zero failures; the
Clopper–Pearson bound otherwise). "Sample" is the smallest *n* that can certify the target with
zero failures observed.

| ID | Target | Sample | Until the sample exists |
|---|---|---|---|
| `meaning-change` | 0 annotated sentinel failures on the clean-up corpus | every case, every run | — exact count of the `mustKeep` and `mustNotAdd` checks, not a comprehensive class-1 error rate |
| `latin-output` | 0 on both corpora | every case, every run | — |
| `override-error` | fewer than 1 in 1,000 overrides wrong | 2,995 override decisions | report the bound the corpus does support, and require it not to rise from the last release; never state the target as met |
| `entity-loss` | never rises from the last release, per language | every required term | — |
| `wer` | no slice whose `PairedBootstrap.standard` interval against the last release lies wholly above zero | slices under two shared utterances report as too few to judge | — |
| `wer-biased`, `wer-unbiased` | neither worse than the last release; a bias change that lowers one by raising the other is a trade, and the pull request says so | as `wer` | not gated |
| `formatting` | neither the `marks` nor the `case` figure worse than the last release | every case | — |
| `seam-artefact` | 0 over every cut of the corpus, proved by a property over all cuts rather than by sampling | every cut | not gated |
| `silence-insertion` | 0 on the silent inputs | 2,995 silent inputs to certify 1 in 1,000 | report the count and the bound |
| `cosmetic` | 0 | — | reported, never blocks |
| `tail-latency` | the limits set where latency is measured | — | — |

The `override-error` bound is the false-override target that correction work cites.

## The release gate

A release is tagged by hand, and only when every step below passes, in this order:

1. **`make verify` exits 0.** The release workflow runs it again on the tagged commit
   (`RELEASING.md`).
2. **The recogniser has not regressed.** `uttrflow-eval transcribe` against the last release's
   baseline exits 0:

   ```bash
   uttrflow-eval transcribe --corpus-path ./corpus \
                            --baseline ./baseline-last-release.json --fail-on-regression
   ```

   This gates `wer` only. `entity-loss` is read from the `lost` terms the same report prints per
   passage, and a count above the last release's blocks. A run with no verdict (a different label, no shared
   samples, a re-read recording, unrecorded normalisation) exits non-zero and blocks: "no
   verdict" is not "no regression".
3. **Clean-up has not regressed.** `make bakeoff ARGS="--against <last release's result>"`
   reports no regression for the shipping-router row (no passing case now failing, no case
   losing more required words), and `--verbose` lists no case in that row with `lost` or
   `invented` words. This gates `meaning-change`; `formatting` is read from the same row's
   `marks` and `case` columns. The comparison reports a regression with a message, not an exit
   status, so the line `Regressions against` in its output is read, not the exit code.
4. **Non-speech has not inserted text or looped.** `uttrflow-eval nonspeech` with its defaults
   reports no inserted text and no repetition loop:

   ```bash
   uttrflow-eval nonspeech
   ```

   Its ceilings all default to 0, so it exits non-zero on any insertion or loop. This gates the
   repetition-loop rate and, as a regression check, the `silence-insertion` count; it does not
   certify the `silence-insertion` target, whose sample this corpus does not have. The count is
   reported with its bound ([silence.md](silence.md#measuring-what-still-gets-through)).
5. **Every target above that is an exact count is met.** The measured `meaning-change` sentinel
   checks and `latin-output` checks are zero. A zero sentinel count does not establish that
   unannotated meaning-changing errors are absent.

A metric that fails is reported by name, with its before and after, its sample size and its
bound, and the tag is not made. A metric marked "not measured" is listed as not measured in the
release notes, never omitted and never shown as zero. A metric that is neither met nor measured
does not block a release; it blocks a claim about it.
