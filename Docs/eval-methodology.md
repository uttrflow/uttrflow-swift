# How `uttrflow-eval transcribe` measures a recogniser

`uttrflow-eval` (`Sources/uttrflow-eval`) runs the recorded corpus through a speech engine and
reports word error rate, latency and failures. This page holds the measurement decisions the
code relies on, so the one-line comments in the source can stay short.

## The baseline gate

- A run is compared against a stored baseline, and the gate says *better* or *worse*. "The
  numbers looked fine" is not evidence: a change to the model, the prompt, the normalisation or
  the dictionary moves some samples up and some down, and only a diff against a point somebody
  was prepared to defend tells a fix from a trade.
- The baseline is written only with `--write-baseline`. Writing it at the end of every run would
  make the gate compare a change with itself, so it could never fail.
- The samples that moved are printed capped, as evidence for the verdict, not as the verdict.
  At a thousand samples dozens move every run.
- The normalisation rules are printed before the numbers, every time. The same transcripts
  score differently under a different rule set, and a rate quoted without them cannot be
  compared with anything.

## What is scored and what is only timed

- The recogniser's output is scored. Clean-up (`--with-cleanup`) is timed but never scored:
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
  bucket (around a thousand samples). Both are a `(passages, audio directory)` pair to the
  runner, which is what lets them be compared at all.
- `transcribe --from-corpus` refuses to download missing audio. A measurement run that also
  fetches gigabytes reports a latency that includes somebody's broadband, and an interrupted
  one leaves a half-measured corpus behind. `pull` is the command that fetches.
- A catalogue sample carries no recording date, so its `recordedAt` is the moment of the run.
  Nothing scores on it.

## Recording a corpus (`record`)

- The recordings are the only half a machine cannot do: roughly twenty minutes of somebody's
  afternoon, after which every transcription measurement runs unattended off the same audio.
- Each take reaches disk before the corpus service is told anything. Upload is layered on top
  of that, and `--sync` sends whatever has no receipt beside it. See `Docs/recordings.md` for
  the same rule inside the app.
- A cohort name is validated before a word is spoken, because a name the catalogue refuses is
  otherwise discovered after forty passages.
- A take is warned about immediately when it is silent (no microphone access produces silence)
  or too short: fewer than two and a half words a second means the recording stopped before the
  passage ended.

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
  gate. `RegressionTolerance` says how much movement counts.
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

## The upload outbox

- There is no queue file. The outbox is derived state: every recording on disk with no settled
  receipt. A queue would be a second copy of the truth, and the process dying between writing the
  audio and writing the queue entry is exactly the failure it would introduce.
- Rejected takes stay in the pending list on purpose. They fail again, and they should: an upload
  the backend refuses is a corpus quietly smaller than the operator believes.
- `flush` stops at the first held-back upload rather than timing out nine hundred more times
  against a backend that is down. A rejection is about one sample and does not stop the run.
- A receipt that cannot be written is not worth failing an upload over: the backend upserts by
  slug, so the worst case is one repeated transfer.
- Catalogue rows are a faithful mirror of the database. Several tools read that database, and a
  client that renamed or dropped fields would be the reason two of them disagree.
