# How `uttrflow-eval transcribe` measures a recogniser

`uttrflow-eval` (`Sources/uttrflow-eval/`) runs the recorded corpus through a speech engine and
reports word error rate, latency and failures; the decisions it relies on live in `UttrflowEval`
(`Sources/UttrflowEval/`): `TranscriptionCorpus`, `TextNormaliser`, `TranscriptionScorer`,
`AccuracyBaseline` and `PairedBootstrap`. This page holds those measurement decisions, so the
one-line comments in the source can stay short. The targets these measurements are judged
against are in [accuracy-targets.md](accuracy-targets.md). How to run it is in
[`measuring-accuracy.md`](measuring-accuracy.md); the edit distance is in
[`core-word-error-rate.md`](core-word-error-rate.md).

## Capitalisation by class

`CaseScore.caseAccuracy` is the share of aligned words whose case matches the reference. Most
reference words are lower case, so that share starts high for an output that changes nothing. The
bake-off therefore also counts each aligned word under one `CapitalisationClass`, read from the
reference by the rule in `CapitalisationScore.swift` (the pronoun "I", acronym, inner capital,
sentence start, capitalised inside a sentence, lower case, uncased), and prints each class beside
two floors: the reference written all lower case, and the recogniser's own text. `caseAccuracy` is
the total of that tally, so its meaning is unchanged for stored results.

Floors over the clean-up corpus, from `swift test --filter CapitalisationScoreTests`:

| Class | Words | All lower case | Recogniser |
|---|---|---|---|
| I | 87 | 0% | 52% |
| acronym | 67 | 0% | 11% |
| inner capital | 17 | 0% | 100% |
| sentence start | 826 | 9% | 13% |
| capitalised | 129 | 0% | 18% |
| lower case | 4198 | 100% | 100% |
| uncased | 222 | 100% | 100% |
| all | 5546 | 81% | 83% |

An all-lower-case output already scores 81% on the old mean, so a mean is read against this floor
and the class that moved, never alone.

## The baseline gate

- A run is compared against a stored baseline, and the gate says *better* or *worse*. "The
  numbers looked fine" is not evidence: a change to the model, the prompt, the normalisation or
  the dictionary moves some samples up and some down, and only a diff against a point somebody
  was prepared to defend tells a fix from a trade.
- The baseline is written only with `--save-baseline`. Writing it at the end of every run would
  make the gate compare a change with itself, so it could never fail.
- The samples that moved are printed capped, as evidence for the verdict, not as the verdict.
  At a thousand samples dozens move every run.
- The normalisation rules are printed before the numbers, every time. The same transcripts
  score differently under a different rule set, and a rate quoted without them cannot be
  compared with anything.
- Matching a shared case ID is not enough: `recordingIdentity` (a WAV digest locally, a
  catalogue sample's own key from the backend) has to match too, or the gate reports it as
  unverifiable instead of comparing rates that may belong to two different takes.

## What is scored and what is only timed

- The recogniser's output is scored. Clean-up (`--shipping`) is timed but never scored:
  its job is to change the words (strip false starts, punctuate, romanise), so a word error
  rate against a verbatim reference would charge it for working. How well it rewrites is
  `uttrflow-bakeoff`'s measurement, over a corpus built for it.
- Model loading is reported once, on its own, never folded into a per-passage latency. It is
  paid once at launch, so a per-passage number that included it would describe a wait no user
  has.
- Reading a WAV off disk is not timed as capture. The capture row is what the microphone costs.
- A stage nothing timed is printed with its reason, never as a zero. A zero in a latency table
  reads as "instant".

## Where results live

- Each passage's score is written to disk as it finishes, so a run that dies on the fifteenth
  passage still reports the first fourteen, and `--summarise` prints what is already measured
  without loading a model.
- Results are kept per configuration (engine, hinted or detected language), so a hinted run
  cannot overwrite a detected one and two engines can be compared without measuring either
  twice.
- Stored results come back in file-system order and are put back into corpus order before
  printing. A report whose rows move between runs is one nobody can compare with the last.
- Language is detected by default, as the product does it. `--hint-language` exists to measure
  whether telling the engine helps, not as an assumption built in.
- A decode's per-word evidence (log-probability, margin, entropy, alternatives, timing and the
  fallback rung kept) is a `DecodeDump` in `decode-dumps/` inside the local corpus, keyed by the
  audio digest and the engine identity, with no audio. A re-decode writes a second file, never
  over the first, because fallback retries make two decodes of one clip differ. A fit reads
  dumps only and refuses one made under another engine identity, naming the field that differs.
  `transcribe` writes one per recording it decodes and prints their total size;
  `word-doubt --from-dumps <corpus>` scores every doubt feature from them with no model loaded.

## Local recordings and the catalogue

- The local corpus is the passages somebody read on this Mac; the catalogue is the backend's
  bucket. Both are a `(passages, audio directory)` pair to the
  runner, which is what lets them be compared at all.
- `transcribe --from-catalogue` refuses to download missing audio. A measurement run that also
  fetches gigabytes reports a latency that includes somebody's broadband, and an interrupted
  one leaves a half-measured corpus behind. `pull` is the command that fetches.
- A catalogue sample carries no recording date, so its `recordedAt` is the moment of the run.
  Nothing scores on it.

## Recording a corpus (`record`)

- The recordings are the only half a machine cannot do: about fifteen minutes of somebody's
  reading, after which every transcription measurement runs unattended off the same audio.
- Each take reaches disk before the corpus service is told anything. Upload is layered on top
  of that, and `--sync` sends whatever has no receipt beside it. [`recordings.md`](recordings.md)
  has the same rule inside the app.
- A cohort name is validated before a word is spoken, because a name the catalogue refuses is
  otherwise discovered after the whole sitting.
- A take is warned about immediately when it is silent (peak under 0.001, which is what no
  microphone access produces), very quiet (under 0.05), clipping (over 0.99), or too short: under
  60% of the passage's length at two and a half words a second means it stopped early.

## The corpus connection

- `URLSessionHTTPTransport` is the only code in the repository that opens a network connection
  for the corpus, and it lives in an executable that `Uttrflow.app` does not link. No build of
  the product can be made to fetch corpus audio. The file is excluded from the coverage floor,
  so it is kept small enough that reading it is a sufficient review; every decision, from the
  URL to the meaning of a 404, is made in `UttrflowEval`.
- The session uses its own configuration rather than `.shared`, so a thousand multi-megabyte
  objects are not cached in memory beside the copy being written to disk.
- The backend URL has no default. A measurement tool that quietly pointed at production would
  produce numbers nobody could place. The token is read from the environment by default,
  because a token on an argument list is a token in the shell history and in every `ps`.

## Scoring across scripts

- Each transcript is scored against the reference written in the script it came back in. Scoring
  a Devanagari transcript against a romanised reference (or the reverse) measures transliteration
  rather than recognition and invents errors the recogniser never made.
- When only one form of the passage exists the transcript is transliterated first and the score is
  flagged as an upper bound: ICU romanises letter by letter and charges for spellings no person
  writes ("karana" where a Hinglish speaker types "karna").
- A recogniser answering in Devanagari is itself a finding. Uttrflow's Hindi output is romanised
  Hinglish, so such a transcript hands clean-up a transliteration job on top of everything else.
  The rate says how well it heard; the count of Devanagari answers says how much work it left.
- A Devanagari answer is also scored as the user receives it: `LatinScript.enforced` against the
  romanised reference. The regression gate judges that output rate wherever it exists, so a
  romaniser break fails the gate; a baseline entry records which text it counted, and a run that
  counts the other text for a shared passage is refused, not compared.
- `mustKeep` terms are only ever words spelled the same in either script. Demanding a romanised
  spelling of a Hindi name would fail every Hindi passage every time.
- A passage's `stresses` is a list, because a real recording stresses several things at once
  (a noisy room *and* proper nouns). Rows built from it overlap and do not sum to the corpus.
  A stress the typed enum has no word for reports as "other", never as "everyday": an accented or
  noisy sample is not an easy one, and filing it under the floor category would flatter the floor.

## Regression verdicts

- Two runs of the same model over the same audio can differ by a word, and a slice of a few
  utterances swings by points on one misheard name. A fixed tolerance treats a 300-word slice and a
  3,000-word slice alike, so it either fires on noise or misses real change. `PairedBootstrap`
  (`Sources/UttrflowEval/PairedBootstrap.swift`) judges each slice from its own sample instead:

  | field | default | meaning |
  |---|---|---|
  | `confidence` | 0.95 | the share of resampled changes the printed interval holds |
  | `power` | 0.8 | the chance of detecting a change as large as the printed minimum detectable change |
  | `resamples` | 2,000 | bootstrap draws per slice |
  | `seed` | fixed | the same two runs always give the same interval and verdict |

- The comparison is paired: each utterance scored in both runs is one draw, so the resample keeps
  the baseline and the new run on the same audio. Each draw recomputes both pooled rates over the
  drawn utterances, and the change is their difference.
- A slice is `worsened` when the whole interval is above zero, `improved` when it is all below, and
  otherwise "no change detectable". Every row
  prints the interval and the minimum detectable change, (z for the confidence plus z for the
  power) times the bootstrap standard deviation, so a reader sees what the sample could not have
  caught.
- A slice with fewer than two shared utterances has no spread to resample. It is printed as too
  few utterances to judge, never as a verdict.
- Utterance resampling measures how much the corpus could have come out differently, not how much
  the decoder varies between runs on one clip. That second source is measured separately below and
  is the floor an interval has to clear.
- Slices are never pooled. An engine that gets better at English and worse at Hinglish has not
  got better, so any judged slice going backwards is a regression even when the headline improved.
- A comparison is computed over the samples both runs share; added and removed samples are
  reported, not folded in. Samples that stopped being scorable are counted on their own, because
  forty samples going unscorable is a regression even if every remaining rate improved.
- Only two things make two runs incomparable: a different label (engine, model, hinting) or a
  different normalisation rule set. Both mean the numbers are not about the same thing.
- Baseline entries store error and reference-word counts, never a rate. A stored rate cannot be
  re-aggregated, and storing both is how the two come to disagree.
- Layout is judged the same way. `StructureComparison`
  (`Sources/UttrflowEval/StructureComparison.swift`) pairs two `StructureScore` runs by case and,
  per destination and over all cases, bootstraps missed breaks (one less recall), wrong breaks (one
  less precision), missed list items and output breaks per 100 words. The last has no better
  direction, since over-segmentation is best at zero, so it prints its interval without a verdict.
  Breaks inside a sentence are a count that must stay at zero and take no interval.

### Run-to-run and machine-to-machine spread

- Decoder run-to-run spread is not yet measured. A recogniser running through CoreML can give
  different words on different chip generations and OS builds, and hosted CI runners have no
  Neural Engine, so a baseline from one machine and a gate run on another can disagree for
  reasons that are not the code.
- `RunToRunSpread` (`Sources/UttrflowEval/RunToRunSpread.swift`) turns repeated runs of one
  configuration over the same audio into the numbers a verdict must sit above: per passage,
  the identical-text rate (transcripts compared character for character) and the rate spread; over
  the corpus, the share of passages every run agreed on and the headline spread between runs.
  `uttrflow-eval transcribe --repeat 8` runs the corpus eight times with one model load and prints
  the differing passages and this table's row, with the chip and OS build read from the machine.
  `--repeat` refuses `--baseline` and `--summarise`: spread is the gate's floor, not its subject.
- A verdict counts only when its interval clears the measured spread, and the baseline records chip and OS
  build. Until a second machine reproduces the table, the gate runs only on the machine that
  recorded the baseline.

  | chip | OS build | runs | identical passages | headline spread (points) | differing passages |
  |---|---|---|---|---|---|
  | not yet measured | | 8 | | | |

## The upload outbox

- There is no queue file. The outbox is derived state: every recording on disk with no settled
  receipt. A queue would be a second copy of the truth, and the process dying between writing the
  audio and writing the queue entry is exactly the failure it would introduce.
- A settled receipt names the take it was for, by when that take was recorded, so a passage
  re-recorded with `--redo` after its upload is pending again, and a take replaced while its
  upload was in flight is not settled by that upload's success. A receipt written before receipts
  named their take settles only a take recorded before the upload was tried.
- Rejected takes stay in the pending list on purpose. They fail again, and they should: an upload
  the backend refuses is a corpus quietly smaller than the operator believes.
- `flush` stops at the first held-back upload rather than timing out nine hundred more times
  against a backend that is down. A rejection is about one sample and does not stop the run.
- A receipt that cannot be written is not worth failing an upload over: the backend upserts by
  slug, so the worst case is one repeated transfer.
- Hinglish has no BCP-47 tag, so it files under `hi-IN` and the outbox adds the `code-switching`
  stress, which is what the catalogue reads it back as Hinglish by. Deleting a recording's receipt
  under `uploads/` and flushing again re-sends it, and the backend's upsert by slug rewrites its
  stresses.
- Catalogue rows are a faithful mirror of the database. Several tools read that database, and a
  client that renamed or dropped fields would be the reason two of them disagree.

## Normalisation

Normalisation *is* the word error rate: the same transcript scores 4% or 19% depending on what
is folded away first, so every rule is named and the report prints the list next to the score.
What is deliberately not done matters as much as what is:

- **Fillers stay.** The corpus has passages written with false starts, read as written.
  Stripping "um" would hide the failure those passages exist to measure; clean-up removes them
  and is measured separately.
- **Spelling variants stay.** "Colour" and "color" count as a substitution. Folding them needs a
  dictionary that grows into an accuracy fudge factor.
- **Hindi number words stay words.** Only the Devanagari spellings map to digits, because "do"
  and "teen" are also English words. "एक" and "दो" are left out even so: one is the everyday word
  for "a", the other for "give". Nothing above ninety-nine is mapped; the corpus keeps large
  numbers as digits the operator reads aloud.
- `TextNormaliser` keeps its own number table (`NumberWords` in `TextNormaliser.swift`) rather
  than reading `UttrflowCore`'s: it must not compose scales, and sharing the table would move every
  stored baseline.
- "3 point 11" joins to "3.11" only when both neighbours are entirely digits.
- ICU transliteration is a last resort. It romanises akshara by akshara, so "करना" becomes
  "karana" where a person writes "karna", and every score computed through it is an upper bound.

## The recorded corpus

- Six passages in each of the product's three ways of speaking, with five stressors spread across
  them so no language is measured only on its easy cases. Each passage has to survive being
  spoken: no bracketed asides, no punctuation nobody voices, short enough for one breath-group.
- The Hindi passages carry no English loanwords, because a recogniser writing Hindi leaves
  borrowed words in Latin script and a mixed passage is a Hinglish passage whatever its label.
  The Devanagari form of each Hinglish passage keeps its borrowed words in Latin script for the
  same reason; writing "मीटिंग" for "meeting" would score a correct transcript as a substitution.
- Reading time is estimated at 120 words a minute (dictation is slower than silent reading, and a
  passage rattled through is not the speech the product copes with) plus half a minute a passage.
- A recording carries the whole `TranscriptionCase`, not only its id, so a reworded passage never
  silently scores old audio against new words; `drifted(from:)` names the recordings whose text
  has changed, as a prompt to re-record rather than an error.
- Digits are read aloud as the reader says them. `en-versions` says "production is on 443", read
  as "four four three"; a recogniser that writes `4 4 3` scores three errors there, which is the
  digits stressor working, not a defect in the normaliser.
- Three files per passage share one id: `<id>.json` for the harness, `<id>.wav`, and `<id>.txt`
  for whoever opens the folder in six months. Audio is written before the record, so a crash
  between the two leaves a passage that reads as not yet recorded rather than a record pointing
  at nothing.
- Cohorts are the third reporting axis and only matter once the corpus is large. A speaker is a
  label, never a name. Slugs are `cohort-passage`, so the bucket sorts by sitting; unattributed
  recordings keep the bare passage id rather than an `unattributed-` prefix that would become
  part of the key. Slug sanitising never truncates to the domain's 64 characters: two long names
  agreeing in their first 64 would upsert over each other in the bucket.

## The audio cache

- A thousand recordings is a few gigabytes; a sample is fetched once and read from disk after.
- The cache is one file per slug with the catalogue's byte count as the only validity check,
  because the failure it has to survive is a download cut off half way. A size mismatch counts
  as absent and is fetched again; a short read never reaches disk.
- It lives beside the recorded corpus rather than in the system caches directory, so a tool that
  cleans caches cannot make a week of results irreproducible.
- `fetchAll` does not stop on one failure: a domestic connection loses a few, they are named at
  the end, and the next run picks them up because everything already here is skipped.

## The leak check

- One dictation's footprint says nothing (a model allocates scratch space, an allocator holds
  pages back), but a figure that climbs at every repetition and never comes down ends with a
  swapping Mac after an afternoon's work. Readings are taken after the same point in each cycle,
  never including the first dictation of the process, which pays for buffers the rest reuse.
- The allowance is 32 MiB (`LeakCheck.defaultAllowanceBytes`) over the default ten dictations: a little over 3 MB each, which for a
  hundred dictations in a working day is roughly a third of a gigabyte. Anything looser would
  call that noise. Growth that wobbles is "suspect" and needs a longer run; two readings are
  "undetermined", which is not a pass. Readings are in [`performance-leaks.md`](performance-leaks.md).

## How far the corpus is from spontaneous speech

- `uttrflow-bakeoff speech-shape` prints, per 100 words, the words the standard passes remove by
  grant (sound, repetition, retraction), marks by kind, mean words per sentence and the share of
  lines with a repetition or retraction. With no option it reads the English cases' `spoken`;
  `--reference <file>` reads a local file of one utterance per line. The passes are the
  instrument on both sides, so a gap is a difference in the text, not in two definitions.
- The margin, fixed before any reference is measured: a figure differs when the two columns are
  more than 25% of the reference value apart, or more than 0.5 per 100 words where the reference
  is under 2. A class outside the margin gets cases added to the matrix, or a filed gap with case
  counts.
- A reference is a public spontaneous-speech transcript set whose licence permits use of its
  transcripts. Only the printed numbers and the set's name, version and licence are committed,
  never its text. Until one is measured the reference column is empty.

| Figure | Corpus (English `spoken`) | Reference |
|---|---|---|
| Words removed as sounds /100w | 0.90 | not measured |
| Words removed as repetitions /100w | 0.83 | not measured |
| Words removed as retractions /100w | 1.99 | not measured |
| `.` /100w | 2.13 | not measured |
| `,` /100w | 0.63 | not measured |
| `?` /100w | 0.07 | not measured |
| `!` /100w | 0.07 | not measured |
| Other marks /100w | 1.46 | not measured |
| Words per sentence | 6.81 | not measured |
| Lines with a restart | 7.07% | not measured |

The corpus column is 410 English cases, 3,011 words.

## The contamination audit

- `ContaminationAudit` is the one check that no tuned-on text carries a corpus passage. It reads
  every clean-up case's spoken and expected text and every transcription passage in each form it
  is written in, and reports the case id, the asset and the shared words.
- An asset fails on a run of 8 or more consecutive words shared with a passage
  (`ContaminationAudit.sharedRunWords`), or on a phrase of 4 or more words that sits whole inside
  one (`ContaminationAudit.wholePhraseWords`). Function words are exempt by these lengths, not by
  a word list: any two English texts share runs of two or three of them.
- The prompt check passes 3 as the shortest phrase, because rules quote slips that short.
- Measured on Apple M5 Pro: 0 findings across the prompt contract, rules and worked examples, and
  across every `.txt` and `.json` asset in the data manifest, so 0 false positives today
  (`swift test --filter ContaminationAuditTests`).
- The string literals in `Sources/UttrflowAI/Passes`, `Sources/UttrflowCore/Cleaning` and
  `Sources/UttrflowPipeline` are audited the same way (`SourceLiteralContaminationTests`). The copies
  already there are listed in that test and the list only falls; a new copy fails it.
- The assets audited are the ones [`Resources/DataManifest.json`](data-manifest.md) lists, so a
  new lexicon, vocabulary pack or n-gram text is audited as soon as it is bundled.

## The transcription split

- `TranscriptionSplit.assignment` puts each transcription passage on one side: `fit` (a fitted
  layer may learn from it), `calibration` (a threshold is chosen on it) or `test` (read only to
  judge a release). The unit is the passage, never the recording, because every recording of a
  passage carries the same words and names. The table is written by hand, so a new passage never
  moves an old one.
- Each language has 2 passages per side: 6 fit, 6 calibration and 6 test across the 18. Test holds
  the proper-noun and digit passages of each language, the two stressors a fitted layer is most
  likely to memorise.
- `SplitLeakAudit` fails when a passage has no side, when the table names a passage the corpus
  lacks, when a passage outside `test` shares a run of 8 words with a test passage in any form
  (the contamination audit's run length), or when a language has fewer than 2 test passages.
  It reports passage counts per side and language (`swift test --filter TranscriptionSplitTests`).
- The corpus has one reader, so passage and speaker group coincide today; a second reader of a
  passage takes the passage's side.

## Recogniser confidence on homophones (`homophone-confidence`)

`uttrflow-eval homophone-confidence` reads each pair in `HomophoneConfidence` (14 programmer terms whose spoken form
matches an everyday word, 20 everyday pairs as a control) in an invented sentence. It finds the meant word's slot
by alignment and records the per-word score of whatever was written there. The correction engine doubts a word
under `CorrectionEngine.certaintyThreshold` (0.5). Each pair is decoded 24 times: 3 voices × 2 rates × with or
without a spoken developer prefix × with or without the term in the vocabulary prompt.

Measured on Apple M5 Pro, 48 GB; whisperKit `openai_whisper-large-v3-v20240930_turbo_632MB`, language detected;
`say` voices Samantha, Daniel and Karen at 175 and 230 words a minute.

| Group | Prefix | Term in prompt | Decodes | Error rate | Median score when wrong | Wrong below 0.5 | Right below 0.5 | AUC |
|---|---|---|---|---|---|---|---|---|
| programmer | no | no | 84 | 17% | 0.77 | 21% | 1% | 0.59 |
| programmer | no | yes | 84 | 6% | 0.77 | 0% | 0% | 0.93 |
| programmer | yes | no | 84 | 10% | 0.97 | 0% | 3% | 0.44 |
| programmer | yes | yes | 84 | 8% | 0.96 | 0% | 0% | 0.83 |
| programmer | all | all | 336 | 10% | 0.92 | 9% | 1% | 0.69 |
| ordinary | all | all | 480 | 1% | 0.63 | 0% | 0% | 1.00 |

Pairs with errors (of 24 decodes each): sed written as "said" 23 times, median score 0.97; kernel as "colonel" 6;
sync as "async" 4; rode as "wrote" 2; hertz as "herds" 1; tail as "tale" 1. The other 28 pairs had no errors.

**Result.** The 0.5 gate cannot detect these errors: 3 of 33 programmer misreadings (9%) score under it, and the
most frequent one, sed heard as "said", is written at a median of 0.97. The score still ranks wrong words below
right ones (AUC 0.69 for programmer pairs, 1.00 for everyday pairs), so a misreading is low relative to its
sentence, not low in absolute terms. Putting the term in the vocabulary prompt cut programmer errors from 17% to
6% without a prefix, which a fixed threshold never could.

## Generated homophone repair cases (`HomophoneCaseSet`)

`HomophoneCaseSet.cases(classes:)` builds repair cases from `HomophoneCarriers.all`: two
invented carrier sentences for every spelling in `HomophoneCarriers.classes`, each holding a slot `_`.
For every carrier and every other member of its class, the input has the other member at the
slot and the expected output has the meant spelling. A new class or carrier needs no case written
by hand.

Each carrier is tagged by what decides the spelling: `role` (the grammar around the slot),
`sense` (the meaning of the other words), `domain` (the app or field) or `none` (nothing in the
sentence decides, so a repair is a guess and the case measures harm).

| Classes | Spellings | Carriers | Cases | role | sense | domain | none |
|---|---|---|---|---|---|---|---|
| 59 | 125 | 250 | 292 | 137 | 138 | 14 | 3 |

`HomophoneCaseSetTests` holds the counts' shape: two carriers per spelling, one slot, no class
member in the carrier, and one changed word per case. Per-tag bakeoff rates are #6257, and
replacing AC.21's hand-built set #6258.

`HomophoneLexiconClasses.all` adds 56 classes of common words, exact homophones and pairs one
sound apart ("accept"/"except", "then"/"than"), with two invented carriers per spelling in
`HomophoneCarriers.lexicon`. Both sets are for evaluation only: the repair path reads the
pronunciation lexicon, and none of the added spellings is in `HomophoneCarriers.classes`. Whether the recogniser ever
writes one for the other is measured from its output on synthetic speech, never assumed from
these lists.

| Classes | Spellings | Carriers | Cases | role | sense | domain | none |
|---|---|---|---|---|---|---|---|
| 115 | 237 | 474 | 516 | 233 | 249 | 28 | 6 |

### Repair and harm per decider (`uttrflow-bakeoff homophones`)

`uttrflow-bakeoff homophones` runs every clean-up engine (rules, Apple on-device, the shipping
router, and any `--models`) twice per case: on the input, where writing the meant spelling at
the slot is a **repair**, and on the expected sentence, where changing it is **harm**
(`HomophoneRepairRates`). Words are compared without case or edge punctuation; when an engine
changes the word count the whole sentence must match. One row per engine per decider tag.

Measured on all 292 cases, without a local model (the local models' rows need the Metal build
from `make bakeoff`):

| Engine | Decider | Cases | Repair | Harm |
|---|---|---|---|---|
| rules | role / sense / domain / none | 137 / 138 / 14 / 3 | 0% / 0% / 0% / 0% | 0% / 0% / 0% / 0% |
| Apple on-device | role / sense / domain / none | 137 / 138 / 14 / 3 | 1.5% / 2.2% / 0% / 0% | 0% / 0% / 0% / 0% |
| shipping router | role / sense / domain / none | 137 / 138 / 14 / 3 | 1.5% / 2.2% / 0% / 0% | 0% / 0% / 0% / 0% |

Apple on-device declined or failed 26 of 584 runs; those count as unchanged. No engine harms a
right spelling, and none repairs more than about one wrong spelling in fifty: the clean-up
engines do not fix homophones from sentence context today.

### Class-by-class error table (AC.21)

AC.21's table reads only these generated cases; there is no hand-built sentence set for it.
`uttrflow-eval homophone-table` prints one row per class: cases, the error rate as heard (`raw`,
100% by construction, since every input holds the wrong member) and after the standard cleaning
rules (`rules`). Words are compared lower-cased with marks dropped but apostrophes kept, so a
capitalised first word or an added stop is not an error and "its" stays apart from "it's".

| Classes | Cases | raw errors | rules errors |
|---|---|---|---|
| 59 | 292 | 292 (100%) | 292 (100%) |

The rules repair no case in any class: no class is owned by the rules, so ownership lies between
the model and the guard, and that column needs the on-device model (measured in `make bakeoff`
per #6257). A raw rate from the recogniser itself needs audio of the carriers.

## Confusable pairs by cost of the error (`confusable-pairs`)

Some confusions turn the meaning: "can" for "can't", "fifteen" for "fifty", "accept" for
"except", a dropped "not". `ConfusablePairs` (`Sources/UttrflowEval/ConfusablePairs.swift`) holds
them as data, each an invented carrier sentence with one slot and two readings, in five groups:

| Group | Pairs | Examples |
|---|---|---|
| negation | 8 | can / can't, will / won't, now / not, not / (dropped) |
| hindiNegation | 4 | nahi, mat, na, each present or dropped; one Hinglish carrier |
| teenTen | 7 | thirteen / thirty through nineteen / ninety |
| nearQuantity | 8 | hundred / thousand, million / billion, a / one, an / a, on / one, two / to, four / for, ate / eight |
| meaningSwap | 3 | accept / except, affect / effect, lose / loose |

The cost class of each pair is `ConfusionCost.of` on its two readings, the same call
`DoubtPolicy`'s `OverridePolicy` and `FlagPolicy` read (see
[ai-correction-thresholds.md](ai-correction-thresholds.md#two-directions-of-doubt-override-less-flag-more));
the inventory holds no tier of its own. `ConfusablePairsTests` pins the class each group lands in:
every negation pair is `meaningFlip`, every teen/ten pair and every amount word `numberFlip`, and
"a", "an", "on" and the meaning swaps `cosmetic`. A pair moves to a costlier class only when its
measured flip rate below says so, by changing `ConfusionCost`, never by a list here.

```bash
uttrflow-eval confusable-pairs
```

Each pair is read both ways, by `say` voices Samantha (en_US) and Rishi (en_IN) at 150, 190 and
240 words a minute, clean and with seeded white noise at 20 and 10 dB: 36 decodes per pair. Both
sides are normalised (`TextNormaliser.standard`, so "fifteen" and "15" are one word). A decode is
**right** when it equals the spoken reading, **flipped** when it is fewer word edits from the other
reading than from the spoken one, and otherwise an **other error**. `--compute gpu` keeps the
Neural Engine free when another process holds its compiler.

**Not yet measured.** The per-pair flip and error table, and the table by cost class, rate and
noise, are recorded here from a full run (1,080 decodes). Until they are, every pair keeps the
class `ConfusionCost` gives it, and the steps in `DoubtPolicy` stay provisional.

## Accent classes and the correction gates (`accent`)

`uttrflow-eval accent` has `say` read 400 invented carrier sentences (`AccentProbeCorpus`): 30
target words for each of 10 accent classes, and 50 technical terms in an English carrier and
in a Hindi one. Each clip is transcribed by the shipping recogniser; the words between the
carrier's own words are what was heard. For every miss, `SoundAlikeReach` asks whether the word
meant, were it in the dictionary, is reached by (a) the sound key alone, (b) the key plus
`ReadingRestraint.soundsNear` (the column was the opening-letters gate when the table below was
measured), and (c) `WordCorrectionEngine.spells` for an entry spelt that way.
Each share is of the misses in that row.

Measured on an Apple M5 Pro with 48 GB. Engine: whisperKit
`openai_whisper-large-v3-v20240930_turbo_632MB`, weights `0f63a7800b00dd0226abd051b906c246e1907482`.
Voices: Rishi (en_IN), Thomas (fr_FR), Tessa (en_ZA), Moira (en_IE), Samantha (en_US), with an
English hint; Rishi alone also with a Hindi hint. One voice takes about 70 minutes on a loaded
machine. Aman and Tara (en_IN), the other fr_FR voices, Karen (en_AU) and Daniel (en_GB) were not
run; Tara is listed by `say -v ?` but `say` refuses it by name.

| Class | Hint | Clips | Too short | Misses | (a) key | (b) key + opening | (c) entry spells | (a) - (b) |
|---|---|---|---|---|---|---|---|---|
| v/w | en | 150 | 16 | 37 | 56.8% | 32.4% | 40.5% | 24.3 |
| th as t/d/s/f | en | 150 | 9 | 55 | 45.5% | 5.5% | 14.5% | 40.0 |
| l/r | en | 150 | 13 | 24 | 41.7% | 33.3% | 58.3% | 8.3 |
| s/z | en | 150 | 16 | 36 | 47.2% | 22.2% | 30.6% | 25.0 |
| sh/s | en | 150 | 7 | 47 | 29.8% | 23.4% | 51.1% | 6.4 |
| h-dropping | en | 150 | 14 | 61 | 50.8% | 27.9% | 32.8% | 23.0 |
| prothetic vowel | en | 150 | 4 | 23 | 34.8% | 34.8% | 60.9% | 0.0 |
| vowel length | en | 150 | 12 | 38 | 44.7% | 28.9% | 60.5% | 15.8 |
| final consonant | en | 150 | 12 | 25 | 28.0% | 24.0% | 56.0% | 4.0 |
| retroflex t/d | en | 150 | 19 | 34 | 29.4% | 20.6% | 38.2% | 8.8 |
| term in English | en | 250 | 25 | 77 | 49.4% | 33.8% | 46.8% | 15.6 |
| term in Hindi | en | 250 | 50 | 167 | 9.0% | 4.8% | 12.6% | 4.2 |
| v/w | hi | 30 | 14 | 13 | 15.4% | 7.7% | 7.7% | 7.7 |
| th as t/d/s/f | hi | 30 | 8 | 18 | 11.1% | 11.1% | 11.1% | 0.0 |
| l/r | hi | 30 | 7 | 15 | 0.0% | 0.0% | 13.3% | 0.0 |
| s/z | hi | 30 | 4 | 17 | 0.0% | 0.0% | 0.0% | 0.0 |
| sh/s | hi | 30 | 10 | 18 | 0.0% | 0.0% | 0.0% | 0.0 |
| h-dropping | hi | 30 | 8 | 17 | 5.9% | 5.9% | 5.9% | 0.0 |
| prothetic vowel | hi | 30 | 8 | 15 | 0.0% | 0.0% | 0.0% | 0.0 |
| vowel length | hi | 30 | 10 | 14 | 0.0% | 0.0% | 0.0% | 0.0 |
| final consonant | hi | 30 | 8 | 15 | 6.7% | 6.7% | 6.7% | 0.0 |
| retroflex t/d | hi | 30 | 11 | 13 | 15.4% | 7.7% | 7.7% | 7.7 |
| term in English | hi | 50 | 9 | 34 | 11.8% | 8.8% | 11.8% | 2.9 |
| term in Hindi | hi | 50 | 0 | 49 | 26.5% | 26.5% | 22.4% | 0.0 |

Classes where the opening-letters gate removes more than 5 points of what the key reaches, under
the English hint: th as t/d/s/f (40.0), s/z (25.0), v/w (24.3), h-dropping (23.0), vowel length
(15.8), technical terms in English (15.6), retroflex t/d (8.8), l/r (8.3) and sh/s (6.4). Under
the Hindi hint most misses are Devanagari or translated output, which no gate reaches.

How far to trust it:
- The voices are synthetic; a row decides only whether a class is worth recording real speakers for.
- "Too short" counts transcripts with no words between the carrier's; the target is taken by word
  count, so a carrier word the recogniser fuses or drops shifts the run. "Term in Hindi" under the
  English hint is the worst case: the recogniser fuses `mujhe` with the term, so most of its 167
  misses are extraction failures, not mishearings.
- (c) asks without the doubt and evidence conditions the engine also checks, so it is a ceiling.

## Proper names by origin and frequency band (`names`)

`uttrflow-eval names` has `say` read every name in `NameClassCorpus`
(`Sources/UttrflowEval/Resources/Corpus/Names/names.json`): 159 names, each tagged with an origin
(english, southAsian, eastAsian, african, slavic, irishScottish, arabic), a band (common, uncommon,
rare) and a kind. Every origin holds, per band, three given names, two surnames and two places;
twelve English given names that are also ordinary words ("Will", "Grace", "Hope") form the
`wordAlike` kind, four per band. Each kind is read in one fixed carrier (`NameClassItem.Kind.carrier`),
and the words between the carrier's own are what was heard.

- Every clip is transcribed twice under an English hint: plain, and with the name as the
  dictation's vocabulary, which is the path a personal-dictionary entry takes into the prompt.
- *Exact* keeps case and drops apostrophes, so a word-alike name heard in lower case is a miss;
  *spelled* also folds case. Both are printed per origin and band, per band over every origin and
  per kind, with the confusion list (meant against heard, clips per condition) by band and origin.
  The rows file keeps every transcript for comparison with a later run.
- The band is the author's judgement of how often the name is written in English text, not a
  measured frequency; a row compares origins and bands, it does not rank single names.
- The file holds given names and surnames on their own and public place names only, never a full
  name, so no entry identifies a person.
- `--compute gpu` keeps the Neural Engine free when other loads hold it; the plan is printed with
  the engine.

Measured on Apple M5 Pro, 48 GB; whisperKit `openai_whisper-large-v3-v20240930_turbo_632MB`,
`--compute gpu`, English hint; `say` voices Samantha and Rishi, so each name is two plain clips and two
dictionary clips. Exact and spelled agree in every row of this run, so only exact is shown.

| Origin | Common, plain | Common, dictionary | Uncommon, plain | Uncommon, dictionary | Rare, plain | Rare, dictionary |
|---|---|---|---|---|---|---|
| english | 95.5% | 100.0% | 86.4% | 100.0% | 50.0% | 90.9% |
| southAsian | 100.0% | 100.0% | 64.3% | 100.0% | 21.4% | 92.9% |
| eastAsian | 100.0% | 100.0% | 71.4% | 92.9% | 21.4% | 85.7% |
| african | 78.6% | 100.0% | 57.1% | 100.0% | 21.4% | 100.0% |
| slavic | 92.9% | 100.0% | 50.0% | 100.0% | 7.1% | 100.0% |
| irishScottish | 100.0% | 100.0% | 42.9% | 100.0% | 21.4% | 78.6% |
| arabic | 92.9% | 92.9% | 71.4% | 100.0% | 21.4% | 92.9% |
| all | 94.3% | 99.1% | 65.1% | 99.1% | 25.5% | 91.5% |

| Kind | Clips per condition | Exact, plain | Exact, dictionary |
|---|---|---|---|
| given | 126 | 57.1% | 97.6% |
| surname | 84 | 60.7% | 95.2% |
| place | 84 | 60.7% | 95.2% |
| wordAlike | 24 | 91.7% | 100.0% |

- **The weakest band is `rare`**: 25.5% exact plain, against 65.1% uncommon and 94.3% common. Within
  it, slavic is lowest plain (7.1%) and irishScottish lowest with the dictionary (78.6%).
- A rare name is spelled by sound ("Szczecin" heard as "success in", "Kumbakonam" as "come back in
  them"); the dictionary lifts the rare band to 91.5%, so the entry, not the recogniser, carries it.
- Misses left with the dictionary include the name heard as another real word or name
  ("Xiong" as "Zhang", "Colquhoun" as "Cahoon", "Cairo" as "Kahira").
- Two synthetic voices only; readers are later work, and a band row of 14 clips moves 7 points per
  clip.

## Dropped words and the coverage signal (`omission-coverage`)

A dropped "not", "no" or "a" carries no score, so no doubt mechanism sees it. The probe asks
whether voiced audio that no recognised word covers predicts a deletion. `uttrflow-eval
omission-coverage` has `say` read 16 invented sentences dense in negators, articles,
auxiliaries and numbers, aligns each decode against its reference (`OmissionCoverage`), places
every deleted reference word between the recognised words either side of it, classes it by the
on-device tagger in its sentence, and finds the voiced runs (inside
`VoiceActivity.speechRange`) that no word's time range covers. A run of at least d ms within
120 ms of a deletion's window counts as a hit.

Run with whisperKit large-v3 turbo, voices Samantha, Daniel, Karen and Rishi at 175, 260 and
340 wpm: 192 clips, 1,680 reference words, 5.2 words per voiced second.

| Class | Deletions |
|---|---|
| negator | 0 |
| article | 0 |
| auxiliary | 2 |
| number | 0 |
| other | 12 |

| d (ms) | Uncovered runs | Precision | Recall | False alarms per 100 words |
|---|---|---|---|---|
| 150 | 100 | 0% | 0% | 6.0 |
| 300 | 21 | 0% | 0% | 1.2 |
| 500 | 0 | – | 0% | 0.0 |

**No-go** for feeding the signal to the review strip: precision stays under the 50% floor
(`OmissionCoverage.precisionFloor`) at every swept length. On synthetic speech the recogniser
drops no meaning-bearing word, and the deletions it does make (mostly "can not" read as one
word) leave no uncovered voiced run, while ordinary pauses leave runs with nothing missing.

How far to trust it:
- The voices are synthetic and read cleanly; a real speaker's swallowed "not" is the case this
  cannot show. `--manifest <file>` (tab-separated audio path and reference) runs the same scoring
  on recorded clips; the run on the recorded transcription corpus decides whether the no-go
  holds for real speech.
- Only the shipping whisperKit model is installed on the measuring Mac; the faster path is
  measured by passing `--model <variant>` once it is installed.
- The tolerance is fixed at 120 ms until LT.9's word-timing accuracy result sets it.
## Per-speaker confusion learning curve

`ConfusionLearningCurve` (`Sources/UttrflowEval/ConfusionLearningCurve.swift`) is the model and
scorer for the question "after how many corrections does learning one speaker's confusions rank
the meant word better than the global key, without overturning more right answers". Nothing in
it ships. It fits two levels from a speaker's first k corrections, in time order: sound-class
counts with add-one (Dirichlet) smoothing toward uniform, and word-pair counts; `backOff` uses the
pair when it was seen and the class otherwise. Each level's log-ratio is added to the global
key's score on the candidate lists the existing sources produce, and reported as top-1 recall of
the meant word and the false-override rate (trials the key had right that the model overturned).
`poisoned` replaces a stated share of the fit events with random pairs, for the 10% and 30%
poisoning rows; `storedBytes` is the size of the fitted model.

`uttrflow-eval learning-curve --manifest <tsv>` runs it. It reads the manifest
`harvest-confusions` reads (audio path, reference, first-language group, speaker), decodes each
clip with the shipping path, aligns with `WordErrorRate.measure`, and holds each speaker out in
turn: the global key is the smoothed share of each heard-to-meant pair over the other speakers,
and the candidates are the heard word, the meant word and every word the others' pairs offer. It
prints, per level, k (0, 5, 10, 20, 50) and poisoning (0, 10%, 30%), the trials, top-1 recall with a
95% interval from resampling whole speakers, the false-override rate and the mean stored bytes.

**Reduced run, synthetic speech only.** Eight system voices (en_AU, en_GB, en_IE, two en_IN, en_ZA,
two en_US), each reading 63 carrier sentences from `HomophoneCarriers`: 504 clips, 63 substitutions,
shipping model, debug build on a loaded machine.

| level | k=0 | k=5 | k=10 | k=20 | false override |
|---|---|---|---|---|---|
| global key | 60.3% (63) | 60.6% (33) | 59.1% (22) | 41.7% (12) | - |
| soundClass, backOff | 60.3% | 90.9% (50.0-100.0) | 95.5% | 91.7% | 0.0% at 0, 10%, 30% poisoning |
| wordPair | 60.3% | 60.6% | 59.1% | 41.7% | 0.0% |

Trials in brackets after the global key. Stored size is 200 bytes at k=5 and 590 at k=20; no
speaker had 50 errors. The sound-class level beats the global key from k=5 with no false
overrides, and the word-pair level adds nothing, because a synthetic voice repeats its sound
contrast but rarely the same word. This does not decide the question: a system voice is not a
speaker, the substitutions are few, and from k=10 only one or two voices are left to test, so the
interval collapses. Until the full run on public accented read speech is recorded here, no channel
work may assume that per-speaker learning helps, at any k.
## Real-speaker accent slices: what a group row may claim

The synthetic table above decides which classes are worth recording real speakers for; a
real-speaker slice decides whether a group is served worse. This is the specification any
per-group report (word error rate, false override or seam rate by speaker group) follows.

**Datasets and labels, stated exactly.**

| dataset | licence | access | accent label |
|---|---|---|---|
| Common Voice (English) | CC0 | open download | self-described by the contributor; reported as "self-described" |
| Svarah (Indian-accented English) | CC BY 4.0 | gated: request access, accept terms | first language and region from collected speaker metadata; reported as "verified" |

- Neither is committed or redistributed: the user downloads the slice, the run reads a local
  path, and no audio or transcript enters the repository. Only the dataset name, version,
  licence, sample seed and the printed counts are committed.
- A group label comes from verified metadata where the dataset has it, and every row says which
  kind of label it carries. Self-described and verified groups are never pooled into one row.

**Every group row carries its sample, not only its rate.** Speaker count, reference-word count,
and for a decision rate (false override) the number of decisions. A rate without these is not
printed.

**Intervals resample speakers, not clips.** Clips from one speaker share a voice, a microphone and
a room, so they are correlated; resampling clips understates the interval. The bootstrap draws
speakers with replacement and keeps every clip of a drawn speaker, using the same confidence,
power, resample count and fixed seed as `PairedBootstrap` above.

**The minimum detectable difference is computed, not assumed.** At about 400 reference words and
an 8% word error rate, the binomial standard error is sqrt(0.08 x 0.92 / 400), about 1.4 points,
so the 95% interval is about plus or minus 2.7 points before speaker correlation widens it.
40 clips per group therefore cannot resolve a 5-point spread reliably; each row prints its own
minimum detectable difference.

**Decision-rate bounds need their own sample size.** With zero false overrides in n decisions the
95% upper bound is about 3/n, so a bound of 1 in 1,000 needs about 3,000 decisions in that
group. A group whose decision count cannot support the stated bound prints "insufficient
evidence", never a rate.

**What files an issue.** A difference between two groups is reported when its speaker-resampled
interval excludes zero, not when the point spread passes a fixed number of points. A difference
inside the interval is "no difference detectable at this sample", with the minimum detectable
difference beside it.

**The report.** `uttrflow-eval accent-groups --rows <counts.tsv>` implements this specification
(`Sources/UttrflowEval/SpeakerGroupReport.swift`). It reads a local table of per-clip counts
(speaker, group, label kind, errors, words, decisions, false overrides), never audio, and prints
one row per group and label kind and one line per same-label pair. A group under two speakers, or
whose decisions fall short of the 3/n count for `--decision-bound` (default 1 in 1,000), prints
"insufficient evidence". `SpeakerGroupReportTests` fixes these rows over an invented slice.

With `--manifest` in place of `--rows`, the command reads the `harvest-confusions` manifest
(audio path, reference text, accent group, speaker) of a slice already downloaded, decodes a
seeded sample of each group with the shipping recogniser (`ManifestDecoder`), and scores each clip
with the standard normaliser and `WordErrorRate`; only those counts reach the report. The sample
(`AccentSlice.sample`) takes `--clips-per-group` clips (200 by default: about 2,000 reference words
on ten-word clips, a binomial interval of about plus or minus 1.2 points at 8%, before speaker
correlation widens it), one clip per speaker per round in seeded order, so the budget reaches every
speaker the group has. The first printed line names the dataset, version, label kind, seed, clip
budget and engine, and is pasted above the table. Nothing is fetched and no audio is written.

```bash
uttrflow-eval accent-groups --manifest <slice>/manifest.tsv --label self-described \
  --dataset "Common Voice English" --dataset-version <release> --seed 1
```

Not yet measured: no real-speaker slice has been run through it. The per-accent table belongs here
once a slice is downloaded; each difference whose interval excludes zero is filed as its own issue.

## Word-score calibration by accent group (`accent-calibration`)

`uttrflow-eval accent-calibration` has each voice read the `accent` corpus (reusing its clips),
aligns every reference word against the decode with `HomophoneConfidence.outcome`, and reports per
accent group (`GroupCalibration`): reliability (the share right in each score bin), and, at
`DoubtPolicy.certaintyThreshold`, the share of errors written below it (**seen**, a candidate
source is asked), at or above it (**confident**, never asked), and the share of right words below it
(**falsely doubted**, put at risk of replacement), each with a 95% Wilson interval. A dropped word
counts as an error that is neither seen nor confident. A group whose seen share and the best
group's lie outside each other's intervals is listed as standing apart, and is filed as its own
issue. No threshold is changed from this table. Per-person calibration reads the confident share
per group from here.

Not yet measured: the run takes several hours of recogniser time per voice on an otherwise idle Mac.
Run it with `swift run -c release uttrflow-eval accent-calibration` and paste both tables here.

Real accented read speech goes through the same report with `--manifest`, which reads the
`harvest-confusions` manifest (audio path, reference text, first-language group, speaker) in place
of the voices, so both reports share one alignment and one table. Run it over the same local slice
the harvest reads and paste the per-group table here beside the synthetic one. Until that slice is
downloaded, synthetic voices are the only stand-in for accent groups: they share one synthesiser's
prosody, so a gap between them understates the gap between real speakers.

Both runs end with one line measuring the score against the doubtful-word strip's floor
([ai-correction-thresholds.md](ai-correction-thresholds.md#showing-doubtful-words-after-insertion-not-built)):
the lowest-scored words flagged at 3 per 100, with recall, precision and the unflaggable share.

## What one guided read measures (`guided-read`)

`uttrflow-eval guided-read` decodes one reading of `GuidedRead.passage` per speaker, from `say`
voices (`--voices`) or recordings of a person reading it (`--recordings`), and prints one row each
(`GuidedRead.measure`). The passage is invented English; its targets are its words written as one
technical-lexicon term, so a term added to the lexicon is tracked without a code change.

| Column | Measured as |
|---|---|
| Words a minute | words heard over the span from the first timed word's start to the last one's end |
| Median pause, 90th pause | gaps between two timed words of one sentence; the gap after a word ending `.`, `?` or `!` is left out |
| Median confidence | the recogniser's confidence over every word heard |
| Pause setting | the first `PauseLength` whose `sentencePause` the 90th pause stays under |
| Missed | targets `HomophoneConfidence.outcome` finds wrong or dropped |

Nothing here changes a setting or a threshold, and no audio or row is kept by the app: this measures
whether a reading at setup separates speakers enough to tune anything. Synthetic voices share one
synthesiser's prosody, so their pause columns say little; recordings of people are the evidence
that counts. Still to measure before any of it reaches setup: first-week word error rate on corpus
speakers with the pause setting a reading picks against the default.

## Confusions on accented read speech (`harvest-confusions`)

`uttrflow-eval harvest-confusions` decodes a locally downloaded slice of public accented read
speech and writes a table of `(reference word, recognised word, first-language group, count)`
and confusion-class counts per group (`ConfusionHarvest`). Nothing else leaves the run: no
sentence, no audio, no speaker identifier. A group read by fewer than `--minimum-speakers`
speakers (10 by default) is merged into `other`.

The input is a tab-separated manifest the maintainer builds from the downloaded slice, one clip
per line: audio path, reference text, first-language group, speaker. Speakers are split by a
seeded hash: one half builds the table, the other half measures coverage, the share of its
substitutions whose word pair the table holds. Two runs over the same slice and engine give the
same digest, which the command prints.

```bash
uttrflow-eval harvest-confusions --manifest <slice>/manifest.tsv \
  --dataset Svarah --dataset-version <release> --licence CC-BY-4.0 --seed 1 \
  --output .uttrflow-eval/confusions-svarah.json
```

Sources and their terms:

| Dataset | Publisher | Licence | Access |
|---|---|---|---|
| Svarah | AI4Bharat | CC BY 4.0, attribution required | gated download from its Hugging Face page |
| Common Voice English, accent field | Mozilla | CC0 | public download |

A committed table names its dataset, release, licence and engine in its `provenance` block and
carries the CC BY attribution "Svarah, AI4Bharat, CC BY 4.0" wherever it is shipped. The classes
are read from the two spellings, so `other` holds every pair whose contrast the spelling does not
show. The class rules are deliberately the probe's, not the engine's: the harvest reads no
lexicon, phonetic index or candidate source, and `ConfusionHarvestTests` checks that.

### System voices as a second source (`synthesise-harvest`)

Recognition errors of real users never leave the Mac, so system voices reading invented text are
the other source of rows. `uttrflow-eval synthesise-harvest` has each `--voice Name:class` read
each sentence at each `--rate`, and writes the clips and a manifest in the same four-field form:
the voice class is the group, `Name@rate` the speaker. The harvest that follows is the same
`harvest-confusions` decode and `ConfusionHarvest` table, not a second one, and the source
(`SyntheticHarvestSource`) reads no lexicon, phonetic index or candidate source either. Without
`--text`, the English fit-split passages are read, so coverage on the calibration split is never
measured on text the table was built from.

With `--calibration-results` naming a `transcribe` results folder, every clip builds the table and
coverage is the share of real substitutions on calibration-split recordings whose pair the table
holds. A voice class has only as many speakers as rates, so pass `--minimum-speakers 1`.

```bash
uttrflow-eval synthesise-harvest --output-directory <dir> \
  --voice Samantha:en_US --voice Daniel:en_GB --voice Rishi:en_IN --rate 160 --rate 220
uttrflow-eval harvest-confusions --manifest <dir>/manifest.tsv \
  --dataset synthetic --dataset-version <text set> --licence none --minimum-speakers 1 \
  --calibration-results .uttrflow-eval/whisperKit-<model> --output .uttrflow-eval/confusions-synthetic.json
```

The table's `provenance.engine` names the model that decoded it; a table from another engine is
rebuilt, not reused.

## Wrong forms from synthetic voices as bias paths (`path-coverage`)

The question is whether the wrong forms the recogniser writes for a rare term, spoken by system
voices when the term is added, predict the wrong form a further speaker gets. If they do, those
forms can be added as extra paths to the one bias trie and the one candidate generator. The decode
is `harvest-confusions`'s (`ManifestDecoder`), not a second harvest. `SyntheticPathCoverage`
(`Sources/UttrflowEval/SyntheticPathCoverage.swift`) holds each speaker out in turn and counts a
misheard clip as covered when another speaker produced the same wrong form for that term, with a
95% Wilson interval.

```bash
uttrflow-eval path-coverage --manifest <dir>/manifest.tsv
```

Each manifest line is one term read alone: audio path, term, group, speaker.

**Reduced run, synthetic speech only.** 50 invented terms, each read alone by six system voices
(en_GB, en_IN, en_AU, en_IE, en_US, en_ZA): 300 clips, shipping model, debug build.

| misheard clips | covered by the other five voices | wrong forms per misheard term | terms always right |
|---|---|---|---|
| 232 of 300 | 100 (43.1%, 95% 36.9-49.5%) | 3.4 | 1 |

Synthetic voices cover about two in five of another synthetic voice's wrong forms, at a cost of
about three paths per term. This does not decide the question: a system voice is not a speaker,
and the clips are terms read alone, not in sentences. The decision needs two runs that are not
done yet: the same coverage with a consenting contributor's recorded clips as the held-out
speaker (the audio stays local), and biased-word error and false insertions with and without
the paths, which needs the decode-time trie. Until both are recorded here, the harvested paths
are not added to the trie or the candidate generator.

## Accuracy in noise (`noise`)

Every recorded passage is a clean read, so the corpus alone cannot say where accuracy falls off
in a noisy room. `uttrflow-eval noise` replays each recording clean and then with one noise added
at 20, 10, 5 and 0 dB signal-to-noise ratio, and pools the word errors per condition and language.

```bash
uttrflow-eval noise
```

- The noises are generated, never recorded or committed (`Sources/UttrflowEval/Degradation.swift`):
  white and pink hiss, a 100 Hz hum with harmonics to 500 Hz, babble summed from six synthetic
  voices, and a synthetic chord sequence.
- The noise is scaled so speech power over noise power is the stated ratio across the whole clip.
  A mix that would leave full scale is scaled down whole, so the ratio holds and nothing clips.
- The run is reproducible byte for byte: each recording's noise comes from the run's `--seed`
  and the recording's identifier alone, through FNV-1a rather than Swift's salted hashing.
- Each condition is its own row beside clean, never pooled with it, with the paired 95% interval
  on the change in word error rate (`ConditionTable`, the pooling `input-level` uses too).
- Per language and noise, the report names the first step, mildest first, where word error rate
  passes clean by more than 5 points (`NoiseBreakpoint`).
- The insertions column counts inserted words over reference words in speech. Text invented from
  sound with no speech in it is `nonspeech`'s rate.
- `--baseline <path>` gates the run like `transcribe` does, with `--save-baseline` and
  `--fail-on-regression`. Each degraded replay is its own `BaselineEntry` with a `condition`; the
  overall, language, stress and cohort slices hold clean reads only, and each condition gets its
  own `byCondition` slice, so a regression under one noise fails the gate without moving the
  headline.
