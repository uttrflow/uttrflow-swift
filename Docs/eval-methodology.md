# How `uttrflow-eval transcribe` measures a recogniser

`uttrflow-eval` (`Sources/uttrflow-eval/`) runs the recorded corpus through a speech engine and
reports word error rate, latency and failures; the decisions it relies on live in `UttrflowEval`
(`Sources/UttrflowEval/`): `TranscriptionCorpus`, `TextNormaliser`, `TranscriptionScorer`,
`AccuracyBaseline` and `RegressionTolerance`. This page holds those measurement decisions, so the
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
- `mustKeep` terms are only ever words spelled the same in either script. Demanding a romanised
  spelling of a Hindi name would fail every Hindi passage every time.
- A passage's `stresses` is a list, because a real recording stresses several things at once
  (a noisy room *and* proper nouns). Rows built from it overlap and do not sum to the corpus.
  A stress the typed enum has no word for reports as "other", never as "everyday": an accented or
  noisy sample is not an easy one, and filing it under the floor category would flatter the floor.

## Regression tolerance

- Two runs of the same model over the same audio can differ by a word. A gate that called that a
  regression would be switched off within a week, which is the real failure mode of an accuracy
  gate. `RegressionTolerance` says how much movement counts:

  | field | default | meaning |
  |---|---|---|
  | `percentagePoints` | 0.5 | how far a slice's rate may rise before it is a regression (`--tolerance`) |
  | `minimumReferenceWords` | 200 | the fewest reference words a slice needs to be judged |

- A slice under `minimumReferenceWords` is still printed, as "too small to judge", never as a
  verdict: a cohort of two short samples swings by ten points on one misheard name.
- Slices are never pooled. An engine that gets better at English and worse at Hinglish has not
  got better, so any judged slice going backwards is a regression even when the headline improved.
- A comparison is computed over the samples both runs share; added and removed samples are
  reported, not folded in. Samples that stopped being scorable are counted on their own, because
  forty samples going unscorable is a regression even if every remaining rate improved.
- Only two things make two runs incomparable: a different label (engine, model, hinting) or a
  different normalisation rule set. Both mean the numbers are not about the same thing.
- Baseline entries store error and reference-word counts, never a rate. A stored rate cannot be
  re-aggregated, and storing both is how the two come to disagree.

### Run-to-run and machine-to-machine spread

- The 0.5-point default is not yet measured. A recogniser running through CoreML can give
  different words on different chip generations and OS builds, and hosted CI runners have no
  Neural Engine, so a baseline from one machine and a gate run on another can disagree for
  reasons that are not the code.
- `RunToRunSpread` (`Sources/UttrflowEval/RunToRunSpread.swift`) turns repeated runs of one
  configuration over the same audio into the numbers the tolerance must sit above: per passage,
  the identical-text rate (transcripts compared character for character) and the rate spread; over
  the corpus, the share of passages every run agreed on and the headline spread between runs.
- The tolerance is set at or above the measured spread, and the baseline records chip and OS
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
  across every `.txt` and `.json` file under `Sources/*/Resources`, so 0 false positives today
  (`swift test --filter ContaminationAuditTests`).
- Bundled assets are found by walking `Sources/*/Resources` until the data manifest lists them.

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
