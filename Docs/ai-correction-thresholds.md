# Word correction: the numbers and why they are what they are

`WordCorrectionEngine` (`Sources/UttrflowAI/CorrectionEngine.swift`, with the scoring in
`CorrectionEvidence.swift`) replaces a word the recogniser half-heard with a personal-dictionary
entry, and otherwise does nothing. The default is to do nothing; three conditions must all hold
before one word moves, and each number below is a hard stop rather than a tuning knob. It runs
before the tidier; the dictionary itself is `Docs/app-dictionary.md`.

## The three conditions

1. **The recogniser was unsure**: every word in the run scored below `certaintyThreshold`, or
   the run is one word that spells no word (see "A heard non-word" below).
2. **A candidate exists**: the phonetic index answers this in constant time.
3. **The sentence improves**: `CorrectionEvidence` scores both readings and the candidate
   must win by `OverridePolicy.requiredMargin`.

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

## `OverridePolicy.baseMargin = 2`

The single most important number in the engine. One signal is a coincidence: at a margin of
one, "the bear clawed the bark" becomes "the bear Claude the bark" for anyone with a file
called `Claude notes` open. At two it does not, because "clawed" and "Claude" have the same
shape and only one signal separates them. The changes that survive are the ones where the
recogniser visibly came apart (a word split, a word spelt out) and something in the
situation names the word it came apart into. Integers, because the signals are counts of
independent facts.
Which margin certifies the false-override target on held-out decisions is chosen with
`uttrflow-eval calibrate-gate` ([dictation-quality.md](dictation-quality.md#choosing-the-override-gates-threshold)).

Recognition confidence does not scale this margin. `certaintyThreshold` already uses that
score to decide whether a word may be changed; once it is below the threshold, the score is
not calibrated across speech engines as a probability that the word is correct. The margin
therefore counts the same independent evidence for every eligible word. A word at 0.49 and
one at 0.05 need the same two-signal advantage to change, while a word at or above 0.5 is
never proposed on counted signals and may corroborate another word. `CorrectionEvidenceTests` pins that boundary.

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

## A heard non-word

A recogniser that has never heard a name often writes it as letters nobody writes ("readees",
"grafna") and scores its own guess above 0.5. Such a word fails condition one and, alone in the
sentence, has none of the four signals, so before this rule no score and no margin could fix it.

`WordCorrectionEngine` therefore weighs one more kind of run, at any score: one word that spells
no word, against an entry the user added themselves (`origin: added`) that passes conditions two
and `spells`. The pair stands for `OverridePolicy.nonWordMargin`, which is the base margin,
because it is two independent facts of the kind the margin asks for: the recogniser visibly came
apart (it wrote no word), and the situation names the word (the user wrote it into the
dictionary). The counted signals then move that margin, so a heard spelling on screen keeps the
word as heard, and a costlier confusion needs more. The change is recorded as `heardAsNonWord`
and spends the same budget, guards and revert counters as every other.

A word spells no word only when every test says so, and each refusal below exists because a
correct word failed the test before it:

| The word is kept when it is | because | example |
|---|---|---|
| an ordinary word (`GeneralVocabulary.isOrdinary`) | the recogniser spells it as one token | "smell" |
| an English word (`LexicalClass.isKnownEnglishWord`) | one-token ordinary misses rarer English | "readies", "griffin", "clawed" |
| listed romanised Hindi (`LoanwordRestoration.isRomanisedHindi`) | the tokenizer splits Hindi | "nikal" |
| in a sentence holding listed romanised Hindi that is not English | Hindi has content words no list holds | "nikaal", "kitaab" |
| written with capitals past its first letter | a form written on purpose | "YOYO" |
| one of two added entries sounding like it | nothing chooses between them | |

An entry the dictionary learned or observed is not enough, since the user never wrote it.

Measured with the fixture dictionary and twenty invented added terms (people, products, tools),
every word of every case of the evaluation corpus (832 cases, 13,499 words, the spoken and the
expected text) heard at 0.95, 0.55 and 0.3, each with no screen, the case's screen and every
entry on screen: the changes that are not a recasing are the same before and after (3, 3 and
131, all from the counted path or a recasing), so 0 correct words change by this rule. Across
the 30 romanised Hindi, Hinglish and code-mixed passages (1,005 words) heard surely it changes
0 words; without the Hindi-sentence refusal it changed "nikaal" to `Nikhil`. Of the measured
misheard strings "sanvi", "saabhan", "grafna" and "readees", each is respelt as its entry;
"aluwaseun" and "thruv" do not open like their entries, so condition two still holds them, and
"trov" is ordinary.

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
- `ConfusionCost` classes a pair: `meaningFlip` when the readings differ in their count of
  negators, `numberFlip` when they differ in a quantity word or numeral, else `cosmetic`.
- Each step of cost (a tier above `cosmetic`, or a destination above `stores`) adds one signal
  to the override margin and lifts the flag line by `FlagPolicy.stepPerTier`:

| cost + destination steps | override margin | flag below | set by |
|---|---|---|---|
| 0 (`cosmetic`, `stores`) | 2 | 0.5 | the margin argument above; `certaintyThreshold` |
| 1 | 3 | 0.6 | provisional: one signal and one tenth per step, pending per-pair error |
| 2 | 4 | 0.7 | provisional |
| 3 or more | 5 or more | 0.8 or more, at most 1 | provisional |

  The cheapest row is today's behaviour unchanged. The costlier rows move only in the safe
  direction for each policy, and the per-pair error measurement replaces the provisional
  steps; a pair is promoted to a costlier class only on measured error.
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
That is far below the recall floor, so the strip stays out of the product.

`DoubtStripFloor` computes the comparison: it flags the lowest-scored words up to 3 per 100 and
reports recall, precision and the unflaggable share with 95% intervals, and
`uttrflow-eval accent-calibration` prints it for every run. The score it ranks is today's word
score; a calibrated doubtful-span detector is ranked the same way when it exists, and the strip is
built only if both floors clear.

## Related pages

- `Docs/app-dictionary.md` — the phonetic index and what the dictionary learns.
- `Docs/speech-vocabulary-prompt.md` — the decode-time biasing that runs before this engine.
- `Docs/cleanup.md` — the doubtful-words line, which offers the same entries to the model.
