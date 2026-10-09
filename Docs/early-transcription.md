# Working ahead while the key is held

A dictation does most of its work before the key is released. `DictationPipeline`
(`Sources/UttrflowPipeline/DictationPipeline.swift`) cuts the recording into pieces at the
speaker's own pauses, using `SpeechWindowing` (`Sources/UttrflowCore/Support/SpeechWindowing.swift`),
and recognises, corrects and tidies each piece while the key is still held. Releasing the key
leaves only the last piece to do, so a two-minute dictation and a ten-second one wait about the
same. [`pipeline.md`](pipeline.md) covers the stages; [`cleanup-design.md`](cleanup-design.md)
covers how the pieces are joined.

## Why the work can move ahead of the key

Measured on an M5 Pro, the shipping turbo Whisper model already loaded, Apple's on-device model
tidying, synthesised speech cut to exact lengths, median of two runs, with every stage run after
the key came up (`uttrflow-dev transcribe` and `uttrflow-dev clean`; see the last section). The wait
is what happens between the key going up and the words being ready.

| speech | transcription | tidying | wait |
|---|---|---|---|
| 10 s | 0.9 s | 1.05 s | 2.0 s |
| 30 s | 2.3 s | 2.0 s | 4.3 s |
| 60 s | 4.0 s | 3.7 s | 7.7 s |
| 120 s | 7.5 s | 6.7 s | 14.2 s |
| 180 s | 11.2 s | 9.7 s | 20.9 s |
| 240 s | 14.5 s | 13.8 s | 28.3 s |
| 300 s | 18.2 s | 6.0 s, then the raw words | 24.2 s |

Both stages grow with the speech, at about 0.06 s and 0.055 s per spoken second, on top of roughly
0.3 s and 0.5 s that every dictation pays. Done after the key, the wait is about 12% of what was
said plus a second, and the recogniser runs at sixteen times real time: it can keep up with a
speaker with room to spare, and so can the tidier.

**The two stages do not compete.** Run at the same moment, a 120-second transcription took 8.47 s
alone and 8.47 s beside a tidy, and the tidy took 3.79 s alone and 3.90 s beside the transcription.
One is Neural Engine work and the other is not.

**Cutting the tidying into pieces costs nothing.** Four pieces of a five-minute transcript tidied
one after another took 16.6 s; the whole takes about 17 s.

**Two things do not help.** WhisperKit's own voice-activity chunking with four concurrent workers
changes nothing at any length (300 s: 18.5 s against 18.6 s), because the Neural Engine is one
serial resource, so `chunkingStrategy` is left unset. Four tidying sessions started at once take
exactly as long as four in a row (16.1 s against 16.6 s); the model serialises them.

**Past about four minutes the tidier loses words.** Given 943 spoken words Apple's model returned
253; given 755 it returned 747. The meaning guard rejects the short answer, six seconds are spent
finding that out, and the user gets the raw words: the last row of the table. Pieces never get
near that length, a retried recording is cut into pieces the same way, so the ordinary path does
not reach it.

## Where a piece is cut

`DictationPipeline` looks at the audio so far once a second (`earlyPoll`, through
`AudioCaptureEngine.capturedSoFar(from:)`) and asks `SpeechWindowing.nextCut` whether the piece
can end. Quiet is judged with the same threshold as the voice-activity trim,
`VoiceActivity.threshold(forFloor:)` ([`silence.md`](silence.md)).

| `SpeechWindowing` field | Default | Rule |
|---|---|---|
| `minimumLength` | <!-- value:SpeechWindowing.minimumLength -->5 s | audio collected before the window is checked at all |
| `earlyLength` | <!-- value:SpeechWindowing.earlyLength -->2.5 s | no cut falls before this |
| `earlyPause` | <!-- value:SpeechWindowing.earlyPause -->1.0 s | a pause this long may end a piece before `minimumLength` |
| `longPause` | <!-- value:SpeechWindowing.longPause -->1.5 s | a pause that began before `earlyLength` ends a piece there only when it is this long |
| `sentencePause` | <!-- value:SpeechWindowing.sentencePause -->0.8 s | a pause this long ends a piece once the cut falls past `minimumLength` |
| `comfortableLength` | <!-- value:SpeechWindowing.comfortableLength -->15 s | past this, the pause that ends a piece shrinks evenly from `sentencePause` toward `anyPause` |
| `anyPause` | <!-- value:SpeechWindowing.anyPause -->0.4 s | the pause that ends a piece at `maximumLength`, the end of that ramp |
| `maximumLength` | <!-- value:SpeechWindowing.maximumLength -->30 s | no piece holds more, the recogniser's own window |
| `minimumSpeech` | <!-- value:SpeechWindowing.minimumSpeech -->0.8 s | speech a piece must hold before a pause may end it |

**A person who pauses for a long time says so once.** The Languages tab's "Pauses while you
speak" row (`PauseLength`, kept in `UserProfile`) adjusts these fields through
`SpeechWindowing.adjusted(for:)`, and `PauseStopPass` reads the adjusted `sentencePause`, so the
piece cut and the sentence stop still agree. "Usual" is the table above. "Long" multiplies every
pause by 2.5 and lets no cut fall before `minimumLength`. "Very long" lets no pause end a piece or
a sentence; a piece is then cut only at `maximumLength`, and every word waits for the key-up.

**A pause is as long as the speaker made it, wherever the five-second mark falls inside it.**
Every quiet run is measured from where it truly began and the cut goes to its middle, so a 0.9 s
breath from 4.6 s to 5.5 s ends the piece at 5.0 s. Measured only from the five-second mark, that
run would read as 0.5 s, a sentence ending would look like a breath, and the commonest dictation
length would stay one piece.

**With no pause at all, a piece is cut at thirty seconds**, which is what the recogniser would do
to it anyway. The cut falls on the quietest 120 ms stretch after `comfortableLength`, which is
between two words far more often than inside one. A cut at the sample thirty seconds in splits
words: "Terraform" came back as "Tara. Form", and one "seconds" was heard by both pieces.

**A pause ends a piece only once the piece holds 0.8 s of speech.** After a long pause the silence
alone passes five seconds, and one word said between two long pauses would become a piece of its
own; given one function word in seconds of silence, the recogniser writes "the" as "Duh!", "a" as
"Ah." and "and" as nothing. The word stays with the next phrase instead, and a last window at
key-up holding only a word or two joins the one before it. A lone word after a piece already
recognised while recording still goes alone.

**The longer early pause protects a repeated sentence.** The default recogniser returns one copy
from a 6.65 s English clip holding two identical sentences separated by 1.1 s of silence, while it
returns one copy from each half decoded separately. With the early cut, the 13.16 s
English-to-Hindi bench clip returned both English sentences and the Hindi continuation in three
fast runs and one real-time run. On the three fast runs, raw WER was 9.8% against 26.8% without the
early cut, and final WER 16.1% against 38.7%. This is a synthetic-voice measurement, not evidence
that every repetition is recovered.

## What happens to a piece while the key is held

The moment a piece can be ended it is recognised, put through the dictionary, and tidied. The
screen is read once, early in the dictation, and the destination, the vocabulary and the language
policy resolved from that read serve every piece; only the dictionary reads the screen again for
each piece, as evidence for its corrections. The recognition of the next
piece runs beside the tidy of the last; one tidy is ever in flight. The timings of work done while
the key is held are not recorded: the diagnostics page reports what the user waited for, and
nobody waited for these.

A piece the recogniser refuses while recording does not end working ahead. Its span is remembered
as unfinished, the audio cursor moves past it, and the next pause is worked on as usual; the
release pass then does every unfinished span in its own place, so a failure is still reported and
costs only that piece's words.

## What happens at key-up

**A piece still being recognised is finished, not thrown away, and that wait is measured.** It
begins after the user lets go, so it is charged to a stage of its own (`PipelineStage.drain`,
"Finishing the piece already under way"), recorded only when a recognition is in flight, so a
dictation too short to have worked ahead gains no row.

**A piece still being tidied is not waited on at the hand-off.** The audio after it is windowed and
recognised straight away, and the leftover tidy joins the release pass's own pipeline of one
recognition beside one tidy, so the tail's recognition and the earlier piece's tidy overlap instead
of running in series.

The audio after the last cut is windowed the same way and processed in order: the final piece,
usually, or every piece for a retried recording. Each piece is still tidied by exactly one call;
the overlap changes when the model is called, never how many times. Where the release pass has
several pieces to do, its cost is close to the recognition alone rather than the two stages added
together. Stage timings from the release pass are added up per stage into one measurement, so a
dictation done in pieces still reports one figure for transcription and one for tidying.

**A piece that holds speech but decodes to no words** is decoded once more without the vocabulary,
since a short piece set off by pauses (a greeting, a sign-off) decodes blank now and then. If the
second decode is blank too, the release pass leaves that piece out, inserts every other piece, and
counts the gap in the outcome's `missedPieces`. Only when no piece has words, or the whole recording
was one window, does the dictation fail as untranscribed; a kept recording can then be retried. A
window holding genuine silence is skipped.

## How the pieces become one text

`PieceJoiner` joins the pieces under the destination's formatter
([`cleanup-design.md`](cleanup-design.md)). Corrections keep their word ranges by being shifted past
the words of the pieces before them, and a correction that crosses a seam is proposed again over
the joined text. If any piece fell back to the rules, the whole dictation is reported as tidied by
the rules, because "tidied by Apple's model" would be untrue of some of the words.

The tidier is shown the last sentence of the previous piece, as heard, behind a "Said just
before:" line. It is context only: the model copies none of it, and an answer that did adds words
the meaning guard refuses. The words as heard are the one version of the previous piece every path
has: a piece tidied while the key is held, one cut at key-up and one retried all read the same
line. The model uses it for commas and capitals at the piece's start; it still places no stop, so
a sentence that straddles a pause long enough to cut at is still decided at the seam. The joiner ends a piece at a seam as a sentence unless the words either side show
the sentence carried on. That is the trade the pause lengths above are set to make rare, and it is
why the early threshold is a sentence-length pause rather than any pause.

Snippets and the blank check run over the joined text, so a trigger cannot be assembled across a
piece boundary any more than across a sentence.

## Which language each piece is heard in

`ListeningLanguages` follows the Languages setting:

- **English and Hindi ticked, or the default English profile**: every piece detects its own
  language among the product's supported languages. A speaker who ticks both switches between
  sentences, and holding a Hindi sentence to the English of the first piece has Whisper translate
  it or drop it.
- **Hindi alone ticked**: every piece is decoded as Hindi, so a short reply cannot be heard as
  English syllables.

Whatever is ticked, dictation is written in Latin letters: the setting steers what recognition
listens for, never the script ([`latin-output.md`](latin-output.md)).

## What cancelling means

Cancelling leaves no trace: no piece is inserted, and a piece that finishes after the cancel is
dropped, because every piece checks its dictation's generation before it is kept. Nothing reaches
the screen before the key is released.

## Warming the tidier

Apple's model pays for its instructions before it reads the utterance. A session made at the start
of the recording and pre-warmed brings a ten-second utterance's tidying from 1.25 s to 0.92 s, so
the pipeline calls `TranscriptCleaning.warm(for:)` as the dictation's destination is resolved.

A warm session older than a minute (`WarmSupply.staleAfterSeconds`, 60 s) is treated as one made
for other instructions: key-down makes a fresh one, and a stale one is never handed out.

It is a fresh session per utterance, since one sentence's context must not bleed into the next.
`WarmSupply` hands its session out once, and the pipeline warms again after each piece tidied while
the key is still held, so the second and third pieces cost what the first did.

The replacement is made **after** the response returns, not beside it. The model serialises its
work, so prewarming during a rewrite would move the cost into the wait rather than out of it. The
instructions come from the destination and are read once per dictation, so there is one key to make
against and no extra model call: still one call per piece.

Nothing is warmed after the last piece. A session made then would be used only by a dictation
starting within the minute, and key-down warms for that one anyway; for anyone dictating every few
minutes it would be a second prewarm per dictation, thrown away as stale. A one-piece dictation
makes one session, and a dictation of *n* pieces at most *n*.

The warm also counts the tokens of the instructions and of the answer shape (`TokenCountMemo`), the
two parts of the request budget that do not depend on the words. After key-up only the piece itself
is counted: one tokenizer call in place of three. Each call takes about 25 ms, and a call has been
seen to stall for 0.7 to 2.4 s in 3 of 12 tidies, on no one call in particular. The counts are the
same numbers either way, so the request and the inserted text do not change.

### Priming with the situation lines does not help

The "Typed into:" and caret lines are known at key-down, so the warm session could take them as
`prewarm(promptPrefix:)`. It buys nothing measurable, so the warm path keeps the instructions only.
Measured on an Apple M5 Pro under heavy parallel build load, 40 warm runs per configuration,
interleaved, with milliseconds to the first token (p50 / p95):

| Words | No prewarm | Instructions only | Instructions and situation prefix |
|---|---|---|---|
| 10 | 1074 / 1146 | 473 / 488 | 472 / 503 |
| 40 | 1166 / 1907 | 1145 / 1423 | 1256 / 1444 |

After a minute idle (2 runs each, indicative only) the prefix was no faster either. Output text was
identical across all three. Reproduce with
`UTTRFLOW_PREFIX_PROBE=1 swift test --filter SituationPrefixPrewarmProbeTests`.

## What it buys, measured on the real pipeline

`uttrflow-dev dictate` plays the same files into the real pipeline at real time, once working ahead
and once with `--all-at-once`, and reports the wait between the key coming up and the words being
ready. This synthesised speech never pauses for more than 0.4 s, so nothing can be cut before the
thirty-second hard cut: the worst case for the design, and the one where it gains least.

| speech | all at once | working ahead |
|---|---|---|
| 10 s | 2.19 s | 2.21 s |
| 30 s | 4.61 s | 4.66 s |
| 60 s | 7.67 s | 4.52 s |
| 120 s | 14.67 s | 4.55 s |
| 300 s | 24.13 s, raw words | 1.55 s, tidied |

Under thirty seconds with no pause there is nothing to work ahead on, so the wait is the same. From
a minute on it is the last piece's cost, whatever the length; the five-minute row is small because
its last piece happened to be short. All at once, the five-minute file hits the four-minute cliff
and comes back untidied.

The same passage spoken sentence by sentence with 0.8 s between sentences, closer to a person, who
breathes:

| speech | all at once | working ahead | with 0.5 s pauses instead |
|---|---|---|---|
| 10 s | 2.2 s | 2.25 s | |
| 30 s | 4.6 s | 1.55 s | |
| 60 s | 9.04 s | 2.31 s | 1.62 s |
| 120 s | 13.43 s | 3.29 s | 2.94 s |
| 300 s | 24 s, raw words | 1.49 s, tidied | |

A ten-second dictation whose first pause comes before the five-second mark is one piece, which is
why that row does not move; everything longer waits for its last sentence only.

## What a ten-second dictation gains, and what it cannot

Measured with `uttrflow-dev bench` in real-time mode, release build, M5 Pro, 48 GB, macOS 26.5.1,
the shipping router, no dictionary words, five runs a row for the first two and three for the third,
medians with the range in brackets, load average 4 to 42 through the runs. "After key-up" is
recognition that began or was still running when the key came up. Each row compares the clip
decoded as one piece with the clip cut at its pause.

| clip | pieces | recognition after key-up | wait |
|---|---|---|---|
| 9.58 s, no quiet frame anywhere | 1 → 1 | 0.81 s → 0.89 s | 1.58 s (1.40-1.94) → 1.61 s (1.53-1.65) |
| 8.59 s, 1.12 s pause from 4.44 s, a sentence end | 1 → 2 | 0.68 s → 0.49 s | 1.35 s (1.35-1.60) → 0.95 s (0.92-0.96) |
| 9.10 s, 0.90 s breath from 4.60 s, mid-sentence | 1 → 2 | 0.90 s → 0.47 s | 1.57 s (1.36-1.61) → 0.90 s (0.89-0.90) |

Both straddling rows recognise and tidy their first piece about 3 s and 1.7 s before the key comes
up, and the words are the same to the character either way, including the mid-sentence row, whose
wrong full stop after "design review" is the recogniser punctuating the breath and is there whether
or not a piece is cut there. Word error rate over the whole bench corpus is the same in every
category, voice and audio variant; no corpus clip has a pause across the five-second mark, so none
of them changes piece count either.

**Continuous speech cannot be cut at a pause, because there is none.** The first row's loudness has
no quiet run of even 0.25 s, so no threshold reaches it. What a blind cut at a chosen second would
buy is measured with `uttrflow-dev transcribe` on the same clip split at 6.5 s, three runs: the
whole clip is recognised in 0.96 s (0.94-1.09) and the last 3.08 s alone in 0.49 s (0.49-0.66). So
about 0.47 s of the 1.58 s wait is available, and it costs the word the cut lands in. The head
comes back as "fix the flaky test proper", lowercase and unpunctuated, and the tail as "than retry
it three times": "properly" is gone, one word in thirty, the same damage a hard cut does to
"Terraform" above. `MeaningPreservationGuard` cannot see it, because it judges each piece's rewrite
against that piece's own words and never sees the seam. A blind cut is therefore not used.

## Trimming the prompt does not pay

The tidier's fixed cost is mostly its instructions, so a shorter prompt is the obvious candidate.
Measured with `make bakeoff ARGS="--baselines-only"` as the judge:

| prompt | pass | close | typical | slowest |
|---|---|---|---|---|
| shipping | 83% | 91% | 0.78 s | 1.50 s |
| rules compressed to one paragraph, every example kept | 81% | 91% | 0.73 s | 1.36 s |
| the three context examples removed | 75% | 88% | 0.66 s | 1.21 s |
| no examples at all (probe, not the corpus) | fillers survive | | 0.67 s | |

Every trim costs corpus cases, and the largest saving is a tenth of a second on a wait that working
ahead has already taken out of the user's way. The prompt stays as it is.

## Whether the model throttles a burst of pieces

A long dictation sends one tidying request per piece in quick succession, and the app is an agent
application that is rarely in front. Apple's model has a rate-limit failure, which the router records
as `rateLimited` and answers with the rules. `uttrflow-dev burst` sends dictations of several pieces,
one after another or all at once with `--concurrent`, and prints the rate-limited requests per 1,000
sent and the first piece in a burst that was throttled.

From a command-line process on an Apple M5 Pro under heavy load, no request was throttled: 0 of 50
sent five to a dictation one after another (typical 3.39 s, slowest 4.17 s), and 0 of 30 sent five
at once (typical 3.82 s, slowest 5.44 s). Started together, the five wait on one another rather
than fail, so a burst of pieces costs time, not the model's answer.

The menu-bar app with another application in front has not been measured: that needs the app
itself sending the bursts, and it is the condition the limit is most likely to apply to.

## Reproducing the numbers

`uttrflow-dev transcribe <file>` prints transcription and tidying separately for one file,
recognised whole. The sweep above used `say -v Samantha` at 16 kHz cut to exact lengths, and
`uttrflow-dev clean` for the tidying-only measurements.

`uttrflow-dev dictate <file>` plays a file into the real pipeline at real time, as if it were being
spoken, and prints the wait between the key coming up and the words being ready. `--all-at-once`
runs the same file with every stage after the key, so the two can be compared on one Mac.
`uttrflow-dev bench` runs a list of clips through the whole pipeline with the recogniser loaded
once, and `Scripts/dictation_bench.py score` scores its output.
