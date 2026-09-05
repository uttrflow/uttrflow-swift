# Word error rate: how `WordErrorRate` measures and why it lives in Core

## What it measures

A genuine edit distance over words, not the word overlap the clean-up scorer uses. The
two measure different things: a rewrite may say the same thing in other words and still
be right, so clean-up is scored on similarity; a transcript that says other words is wrong
by definition, so a recogniser is scored on the number of edits it takes to repair it.

`WER = (substitutions + deletions + insertions) / reference words`. It can exceed 1: a
recogniser that hallucinates a paragraph over a two-word utterance is more than 100%
wrong, and clamping to 1 would hide it. An empty reference has no rate at all; reporting
`nil` rather than 0% keeps the harness from lying in the flattering direction.

## Why the alignment is kept

A rate says a passage went badly; only the alignment says which words. The fix is nearly
always in the corpus or the normalisation rather than the recogniser, and that cannot be
found from counts alone.

## The tie-break

Ordinary Levenshtein over words with unit costs, then a backtrace that prefers a diagonal
step, then a deletion, then an insertion. The tie-break cannot change the total, since
every optimal path has the same number of edits, but it decides how a tie is split between
the three kinds, and a split that varied run to run would make the report unreadable.

"Send it to Priya" heard as "send to preeya now" is three edits either way: a deletion,
a substitution and an insertion, or three substitutions. The backtrace reports the
second. The rate is the same; only the breakdown differs, so the breakdown is read as
"three words wrong here", never as evidence about which kind of mistake the recogniser is
prone to.

## Combining passages

Errors and reference words are summed before dividing, the standard corpus WER, rather
than averaging per-passage rates. Averaging would give a six-word passage the same weight
as a sixty-word one, so a single stumble over a short sentence could swing the headline
figure by more than a whole bad passage.

## Why it is in `UttrflowCore`

The evaluation harness must never be linked into the shipped app: it knows how to reach a
private bucket of real people's recordings, and `Scripts/bundle.sh` refuses a build whose
binary carries its symbols. Onboarding's microphone check scores a read passage with the
same edit distance. Keeping the algorithm in Core lets both have it without the app
importing the harness, and without two implementations of a measurement two parts of the
product must agree on.
