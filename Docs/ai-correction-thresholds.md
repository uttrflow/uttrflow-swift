# Word correction: the numbers and why they are what they are

`WordCorrectionEngine` (`Sources/UttrflowAI/CorrectionEngine.swift`, with the scoring in
`CorrectionEvidence.swift`) replaces a word the recogniser half-heard with a personal-dictionary
entry, and otherwise does nothing. The default is to do nothing; three conditions must all hold
before one word moves, and each number below is a hard stop rather than a tuning knob. It runs
before the tidier; the dictionary itself is `Docs/app-dictionary.md`.

## The three conditions

1. **The recogniser was unsure**: every word in the run scored below `certaintyThreshold`.
2. **A candidate exists**: the phonetic index answers this in constant time.
3. **The sentence improves**: `CorrectionEvidence` scores both readings and the candidate
   must win by `improvementMargin`.

Each alone is a different failure. Condition one alone rewrites constantly, because
recognisers are unsure all the time. Condition two alone destroys correct-but-rare words:
"clawed" and "Claude" sound identical. Condition three alone is a model guessing at words it
has never seen.

## `certaintyThreshold = 0.5`

One number doing two jobs on purpose: the line under which a word may be replaced and the
line at or above which a word may corroborate a replacement. Because the two sets are exact
complements, a mis-heard word cannot vouch for itself. A half rather than a tuned value
because speech engines disagree about what their scores mean; a half is where any
recogniser claims to be more right than wrong.

Condition one rarely holds for the case this engine is built for. A recogniser that has
never heard a name is not unsure; it is sure it heard two ordinary words, and scores them
above the threshold. Raising the threshold does not target names: it makes every word under
the new line eligible. Decode-time biasing (`Docs/speech-vocabulary-prompt.md`) fixes that
class before there is anything to correct; this engine's job is the narrower one of a word
the biasing missed and the situation names.

## `improvementMargin = 2`

The single most important number in the engine. One signal is a coincidence: at a margin of
one, "the bear clawed the bark" becomes "the bear Claude the bark" for anyone with a file
called `Claude notes` open. At two it does not, because "clawed" and "Claude" have the same
shape and only one signal separates them. The changes that survive are the ones where the
recogniser visibly came apart (a word split, a word spelt out) and something in the
situation names the word it came apart into. Integers, because the signals are counts of
independent facts.

Recognition confidence does not scale this margin. `certaintyThreshold` already uses that
score to decide whether a word may be changed; once it is below the threshold, the score is
not calibrated across speech engines as a probability that the word is correct. The margin
therefore counts the same independent evidence for every eligible word. A word at 0.49 and
one at 0.05 need the same two-signal advantage to change, while a word at or above 0.5 is
never proposed and may corroborate another word. `CorrectionEvidenceTests` pins that boundary.

**The margin alone does not hold a run of several words.** In a sentence short enough that
`budget(for:)` is one, a two-word proposal is discarded by the blast-radius cap anyway; padded
to twelve words, where the cap allows two changes, the restraint corpus produces "the salt
**URL** enough for the coast" and "read **Aditi** nobody" on the margin alone: the entry is on
screen and the run is several words becoming one, which is two signals, which clears a margin
of two. The longer sentences in `CorrectionRestraintTests` exist to keep that case measured.

So a run of several words has a condition of its own before the evidence is counted at all
(`WordCorrectionEngine.spells`): the entry must spell the run closed up, or the run closed up
must have the entry's Double Metaphone code. An all-capitals entry is said letter by letter, so
only its pronunciation is read that way. "payment sheet" to `PaymentSheet`, "utter flow" to
`Uttrflow` and "cube lit" to `Kubelet` pass it; "air well" to `URL` does not. An entry's pronunciation counts as well as its spelling, so
a user who writes "cube cuttle" against `Kubectl` gets that run back.

## `maximumChangedInEvery = 5`, with a floor of one

An engine that wants to change a third of an utterance has misread it, so the whole
utterance is left alone rather than the first few changes applied. The budget counts spoken
words, not proposals. Its floor of one is not a softening: without it every dictation under
five words would be exempt, and short dictations are most of them.

The budget belongs to the dictation, not to one engine call. A dictation's pieces and its seam
pass share one `CorrectionBudget`: each piece adds its words, the seam pass adds none, and a call
that would take the dictation past one change in five is abandoned. Ten four-word pieces may
change at most eight words, as the same forty words in one piece may.

## `maximumWordsOnScreen = 512`

A selection can be a whole document and this runs inside a dictation. Five hundred words
covers a visible page, and the scan is not measurable at that size. Past the cap the screen
stops corroborating, which is the safe direction to fail in.

## Why condition three is not a language model

Every word the engine can propose is, by construction, one a general model has never seen;
that is why it is in a personal dictionary. Asking Apple's on-device model whether
"Uttrflow" belongs in a sentence buys an opinion formed from no evidence, at one model call
per uncertain word on a path that already spends two seconds. Word embeddings return nothing
for out-of-vocabulary words, which is every word here. So the question is answered from
evidence already in hand: four independent signals of equal weight, read from the utterance
and from what the frontmost app shows, scored for both readings so a rare word heard
correctly usually has the evidence on its side.

## Two directions of doubt: override less, flag more

Doubt has two consumers that need opposite movement when an error would cost more. The override
gate decides whether a pass may replace a heard word; a review flag decides whether the user is
shown that a word may be wrong. For a number, a negator or a name, a costlier error must make the
override **harder** to pass and the flag **easier** to raise. One "stricter" scalar moves one of
them the wrong way, so cost is never expressed as a single threshold.

The decided shape, inside `DoubtPolicy` (the one seam every consumer of doubt already asks):

| policy | reads | as cost rises | invariant |
|---|---|---|---|
| `OverridePolicy` | evidence, the pair's cost class, the destination's `Consequence` | needs more evidence | never raises the override rate |
| `FlagPolicy` | the same three | needs less doubt | never lowers the flag rate |

- Both are functions of the same three inputs; no consumer holds a threshold constant of its own.
- A property test fixes monotonicity over the corpus and generated sentences: raising the cost
  class or the destination consequence (`stores` to `sends` to `executes`) never raises the
  override rate and never lowers the flag rate.
- Today `certaintyThreshold = 0.5` is the only threshold and both directions read it; each tier's
  thresholds are set by measurement when the cost classes exist, and recorded in a table here.
- Abstention cost depends on the destination as well as the pair: the same swap is cheaper to
  leave doubted in a note than in a field that runs or sends what it receives.

## Cost

The cost is held by counting rather than timing, because a wall clock in a parallel suite on
a loaded machine fails with nothing wrong. Over a forty-word utterance with half the words
doubted and a screenful of selected text, the dictionary entries the lookups read are the same
over ten thousand entries as over fifty, and the screen is read once per utterance however
many runs are doubted. A lookup that scanned the dictionary, or evidence rebuilt per run, fails it.

## The restraint corpus

`CorrectionRestraintTests` runs 28 correct sentences with every word doubted, three ways:
with no screen, with the sentence itself on screen, and with the whole fixture dictionary on
screen. The passing score is zero changes. A guard test asserts that at least fifteen of the
sentences tempt the dictionary (sixteen do: "clawed" and "clod" find `Claude`, "sickle"
finds `SQL`, "nickel" finds `Nikhil`, "smell" finds `XML`, "readies" finds `Redis`, "griffin"
finds `Grafana`, "air well" finds `URL`), so silence is restraint rather than coincidence.
That exact count is pinned by `corpusIsTempting`, so it cannot drift from this page unnoticed.

## Showing doubtful words after insertion: not built

A strip that lists the words the app doubted and left alone, shown after a confirmed insertion,
is built only when the doubt signal clears a floor. Below it the strip would flag mostly right
words and miss most wrong ones, and a visible list of flags implies the rest were checked.

The floor, at a budget of at most 3 flags per 100 words:

| Measure | Floor |
|---|---|
| Recall: wrong words that are flagged | at least 50% |
| Precision: flags that are wrong words | at least 50% |
| Unflaggable fraction: wrong words with no doubt signal at all (omissions, insertions) | stated beside the result |

Measured so far: the per-word score flags 3 of 33 programmer misreadings (9%) under the 0.5
gate, and the most frequent misreading is written at a median score of 0.97
([eval-methodology.md](eval-methodology.md#recogniser-confidence-on-homophones-homophone-confidence)).
That is far below the recall floor, so the strip stays out of the product. No calibrated
doubtful-span detector with a measured precision and recall exists yet; when one does, its
table at the 3-per-100 budget is compared with this floor, and the strip is built only if both
floors clear.

## Related pages

- `Docs/app-dictionary.md` — the phonetic index and what the dictionary learns.
- `Docs/speech-vocabulary-prompt.md` — the decode-time biasing that runs before this engine.
- `Docs/cleanup.md` — the doubtful-words line, which offers the same entries to the model.
