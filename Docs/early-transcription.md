# Working ahead while the key is held

A dictation used to begin its work the moment the key was released: transcribe all of
it, tidy all of it, insert. Now the recording is cut into pieces at the speaker's own
pauses, each piece is recognised and tidied while the key is still held, and releasing
the key leaves only the last piece to do. This is why a two-minute dictation and a
ten-second one now wait about the same.

## What was measured, and why this is the fix

Taken on 5 September 2026, M5 Pro, the shipping turbo Whisper model already loaded,
Apple's on-device model tidying, synthesised speech cut to exact lengths, median of two
runs. The wait is what happened between the key going up and the words being ready.

| speech | transcription | tidying | wait |
|---|---|---|---|
| 10 s | 0.9 s | 1.05 s | 2.0 s |
| 30 s | 2.3 s | 2.0 s | 4.3 s |
| 60 s | 4.0 s | 3.7 s | 7.7 s |
| 120 s | 7.5 s | 6.7 s | 14.2 s |
| 180 s | 11.2 s | 9.7 s | 20.9 s |
| 240 s | 14.5 s | 13.8 s | 28.3 s |
| 300 s | 18.2 s | 6.0 s, then the raw words | 24.2 s |

Both stages grow with the speech, at about 0.06 s and 0.055 s per spoken second, on
top of roughly 0.3 s and 0.5 s that every dictation pays. The wait is therefore about
12% of what was said plus a second, and the recogniser runs at sixteen times real time
— which is the whole opportunity: it can keep up with a speaker with room to spare, and
so can the tidier.

**The two stages do not compete.** Run at the same moment, a 120-second transcription
took 8.47 s alone and 8.47 s beside a tidy, and the tidy took 3.79 s alone and 3.90 s
beside the transcription. One is Neural Engine work and the other is not.

**Cutting the tidying into pieces costs nothing.** Four pieces of a five-minute
transcript tidied one after another took 16.6 s; the whole would have taken about 17 s.

**Two things do not help, and were measured so nobody tries them again.** WhisperKit's
own voice-activity chunking with four concurrent workers changed nothing at any length
(300 s: 18.5 s against 18.6 s), because the Neural Engine is one serial resource. Four
tidying sessions started at once took exactly as long as four in a row (16.1 s against
16.6 s); the model serialises them.

**Past about four minutes the tidier loses words.** Given 943 spoken words Apple's
model returned 253; given 755 it returned 747. The meaning guard rejects the short
answer, six seconds are spent finding that out, and the user gets the raw words. Pieces
never get near that length, so this cannot happen any more — but the last row of the
table is what a retry of a kept five-minute recording used to produce.

## What it bought, measured on the real pipeline

`uttrflow-dev dictate` plays the same files into the real pipeline at real time, once
the new way and once with `--all-at-once`, and reports the wait between the key coming
up and the words being ready. This synthesised speech never pauses for more than 0.4 s,
so nothing could be cut before the thirty-second hard cut — the worst case for the
design, and the one where it gains least.

| speech | wait before | wait now |
|---|---|---|
| 10 s | 2.19 s | 2.21 s |
| 30 s | 4.61 s | 4.66 s |
| 60 s | 7.67 s | 4.52 s |
| 120 s | 14.67 s | 4.55 s |
| 300 s | 24.13 s, raw words | 1.55 s, tidied |

Under thirty seconds with no pause there is nothing to work ahead on, so the wait is
what it was. From a minute on it is the last piece's cost, whatever the length; the
five-minute row is small because its last piece happened to be short. The same run
reproduced the four-minute cliff on the old path: after 24 seconds the words came back
untidied.

The same passage spoken sentence by sentence with 0.8 s between sentences — closer
to a person, who breathes — is where the design was aimed:

| speech | wait before | wait now | with 0.5 s pauses instead |
|---|---|---|---|
| 10 s | 2.2 s | 2.25 s | |
| 30 s | 4.6 s | 1.55 s | |
| 60 s | 9.04 s | 2.31 s | 1.62 s |
| 120 s | 13.43 s | 3.29 s | 2.94 s |
| 300 s | 24 s, raw words | 1.49 s, tidied | |

A ten-second dictation whose first pause comes before the five-second minimum is still
one piece, which is why that row does not move; everything longer waits for its last
sentence only. The five-minute recording came back tidied in full, so the cliff is gone
from the ordinary path as well as the retry.

The first run of the pause-less file also showed why a hard cut must not fall on a
sample chosen for being thirty seconds in: "Terraform" came back as "Tara. Form" and one
"seconds" was heard by both pieces. A hard cut now falls on the quietest frame after the
comfortable length, which is between two words far more often than inside one.

## How it works

already computes. A cut may not fall before 2.5 s; where it may, a pause of 1.0 s can end
an early phrase, a pause of 0.8 s ends the piece once the cut falls past five seconds,
which is a sentence ending rather than a breath, and past fifteen seconds a pause of 0.4 s
will do.

**A pause is as long as the speaker made it, wherever the five-second mark falls inside
it.** Every quiet run is measured from where it truly began and the cut goes to its
middle, so a 0.9 s breath from 4.6 s to 5.5 s ends the piece at 5.0 s. Measuring the run
only from five seconds instead saw 0.5 s of it, read a sentence ending as a breath, and
left the commonest dictation length one piece — which is what #917 was. A piece never holds more than thirty seconds, the
recogniser's own window, and with no pause at all it is cut there — which is exactly
what the recogniser would have done to it anyway.

The longer early pause protects a repeated-sentence case. The default recogniser returned
one copy from a 6.65 s English clip containing two identical sentences separated by 1.1 s
of silence, while it returned one copy from each half decoded separately. With the early
cut, the 13.16 s English-to-Hindi benchmark clip returned both English sentences and the
Hindi continuation in three fast runs and one real-time run. On the three fast runs, raw
WER fell from 26.8% to 9.8%, and final WER from 38.7% to 16.1%. This is a synthetic-voice
measurement, not evidence that every repetition is recovered.

While recording, `DictationPipeline` looks at the audio so far once a second
(`AudioCaptureEngine.capturedSoFar()`, a copy of the buffer at the canonical rate). The
moment a piece can be ended it is recognised, put through the dictionary, and tidied,
against the screen as it was when the piece was cut. Its timings are not recorded: the
diagnostics page reports what the user waited for, and nobody waited for these.

**The drain is the exception, and it is measured.** A piece still being recognised when the key
comes up is finished rather than thrown away, and the user waits through that — it begins after
they let go. It is charged to a stage of its own (`.drain`, "Finishing the piece already under
way"), recorded only when a recognition is in flight, so a dictation too short to have worked
ahead gains no row. What is still not charged to anyone is the work that finished before the key
came up, which is the decision this paragraph records.

A piece still being *tidied* when the key comes up is not waited on at the hand-off: the audio
after it is windowed and recognised straight away, the same as any other piece the release pass
picks up, and the leftover tidy is joined into that pass's own pipeline of one recognition beside
one tidy — so the tail's recognition and the earlier piece's tidy run beside each other instead of
in series. Only the two stages that would otherwise sit idle end up overlapped; the tidies
themselves still run one at a time.

When the key comes up, a piece under way is finished rather than thrown away, and the
audio after the last cut is windowed the same way and processed in order — the final
piece, usually, or every piece for a retried recording. Those timings are added up per
stage into one measurement, so a dictation done in pieces still reports one figure for
transcription and one for tidying.

That final pass overlaps the two stages rather than alternating them: the tidy of one
piece is started and left running while the next piece is recognised, and it is collected
before the piece after that begins. One tidy is ever in flight, which is what the two
measurements above ask for — the stages do not compete, and four tidies at once are no
faster than four in a row. It changes when the model is called, never how many times: a
piece is still tidied by exactly one call. Where the release pass has several pieces to
do — a retry, or a dictation whose working ahead stopped early — this is close to the
cost of the recognition alone, rather than the two stages added together.

A piece the recogniser refuses while recording is not the end of working ahead. Its span
is remembered as unfinished, the audio cursor moves past it, and the next pause is worked
on as usual; the release pass then does every unfinished span in its own place, so a
failure still gets reported and still costs only that piece's words rather than the whole
recording's wait.

If that release pass still gets no words for audio `VoiceActivity` judges speech-bearing,
the dictation fails instead of inserting only the other pieces. A kept recording can be
retried; a window holding genuine silence is still skipped.

The pieces are then joined with a space. Corrections keep their word ranges by being
shifted past the words of the pieces before them. If any piece fell back to the rules,
the whole dictation is reported as tidied by the rules, because "tidied by Apple's
model" would be untrue of some of the words.

### What a piece boundary costs

The tidier sees each piece alone. A sentence that straddles a pause long enough to cut
at is tidied as two sentences, and each piece is given a terminal full stop, so a
speaker who pauses 0.8 s mid-sentence in the first fifteen seconds gets a full stop
there. That is the trade the pause lengths above are set to make rare, and it is the
whole reason the early threshold is a sentence-length pause rather than any pause.

Snippets and the blank check run over the joined text, as before, so a trigger cannot
be assembled across a piece boundary any more than across a sentence.

How each piece gets its language follows the Languages setting, `ListeningLanguages`:

- **Hindi alone ticked**: every piece is decoded as Hindi, so a short reply cannot be heard as
  English syllables.
- **English and Hindi ticked**: every piece detects its own language among the two. A speaker
  who ticks both switches between sentences, and holding a Hindi sentence to the English of
  the first piece has Whisper translate it or drop it (issue 698).
- **Hindi not ticked**, which is also the default: the first piece that reports a language
  sets it for the dictation and every later piece is given it as a hint, and the next
  dictation detects afresh. A piece that is short, quiet or heavy with proper nouns can
  otherwise be detected as the other language. English alone cannot pin English, because it
  is everybody's default, and pinning it would end Hindi dictation for anyone who never opened
  Settings.

Whatever is ticked, dictation is written in Latin letters: the setting steers what
recognition listens for, never the script.

### What cancelling means

Cancelling still leaves no trace: no piece is inserted, and a piece that finishes after
the cancel is dropped, because every piece checks its dictation's generation before it
is kept. Nothing reaches the screen before the key is released.

### Warming the tidier

Apple's model pays for its instructions before it reads the utterance. Made at the
start of the recording and pre-warmed, a session brought a ten-second utterance's
tidying from 1.25 s to 0.92 s, so `TranscriptCleaning.warm()` is called as recording
begins.

A session kept from the last dictation is not warm any more, so the supply records when it made
one and treats anything older than a minute as it would a session made for other instructions:
key-down makes a fresh one, and a stale one is never handed out (#876).

It is still a fresh session per utterance — one sentence's context must not bleed into the
next — but no longer only one per *dictation*. `WarmSupply` hands its session out once and
then makes another for the same instructions, so the second and third pieces cost what the
first did. Warming once while the unit of work was the piece meant every piece after the
first built its own session, and the piece that paid for it was the last one, which is the
only one the user is waiting on.

The replacement is made **after** the response returns, not beside it. This model serialises
its work — four tidying sessions started at once took exactly as long as four in a row, as
measured above — so prewarming during a rewrite would move the cost into the wait rather than
out of it. The instructions come from the destination and are read once per dictation, so
there is one key to make against and no extra model call: still one call per piece.

## What a ten-second dictation gains, and what it cannot

Taken on 21 September 2026, `uttrflow-dev bench` in real-time mode, release build, M5 Pro,
48 GB, macOS 26.5.1, shipping router, no dictionary words, five runs a row for the first two
and three for the third, medians with the range in brackets. **Load average 4-42 through the
runs**, so these are quieter-machine figures than #918's. "After key-up" is recognition that
began or was still running when the key came up.

| clip | pieces | recognition after key-up | wait |
|---|---|---|---|
| 9.58 s, no quiet frame anywhere | 1 → 1 | 0.81 s → 0.89 s | 1.58 s (1.40-1.94) → 1.61 s (1.53-1.65) |
| 8.59 s, 1.12 s pause from 4.44 s, a sentence end | 1 → 2 | 0.68 s → 0.49 s | 1.35 s (1.35-1.60) → 0.95 s (0.92-0.96) |
| 9.10 s, 0.90 s breath from 4.60 s, mid-sentence | 1 → 2 | 0.90 s → 0.47 s | 1.57 s (1.36-1.61) → 0.90 s (0.89-0.90) |

Both straddling rows recognise and tidy their first piece about 3 s and 1.7 s before the key
comes up, and the words are the same as before to the character — including the mid-sentence
row, whose wrong full stop after "design review" is the recogniser punctuating the breath and
is there whether or not a piece is cut there. Word error rate over the whole bench corpus is
unchanged in every category, voice and audio variant; no corpus clip has a pause across the
five-second mark, so none of them changed piece count either.

**The first row cannot be fixed by finding a pause, because there is none.** Its loudness has
no quiet run of even 0.25 s, so no threshold reaches it. The ceiling for continuous speech is
what a blind cut at a chosen second would buy, measured with `uttrflow-dev transcribe` on the
same clip split at 6.5 s, three runs: the whole clip is recognised in 0.96 s (0.94-1.09) and
the last 3.08 s alone in 0.49 s (0.49-0.66). So about 0.47 s of the 1.58 s wait is available —
and it costs the word the cut lands in. The head came back as "fix the flaky test proper",
lowercase and unpunctuated, and the tail as "than retry it three times": "properly" is gone,
one word in thirty, which is the same damage a hard cut did to "Terraform" above.
`MeaningPreservationGuard` cannot see it, because it judges each piece's rewrite against that
piece's own words and never sees the seam. Buying that 0.47 s therefore needs the seam to
carry evidence of what it is (#474) and the tail's recognition not to queue behind the head's
tidy (#853), rather than a blinder cut.

## Trimming the prompt does not pay

The tidier's fixed cost is mostly its instructions, so a shorter prompt was the obvious
fourth idea. Measured with `make bakeoff ARGS="--baselines-only"` as the judge, on the
same day:

| prompt | pass | close | typical | slowest |
|---|---|---|---|---|
| shipping | 83% | 91% | 0.78 s | 1.50 s |
| rules compressed to one paragraph, every example kept | 81% | 91% | 0.73 s | 1.36 s |
| the three context examples removed | 75% | 88% | 0.66 s | 1.21 s |
| no examples at all (probe, not the corpus) | fillers survive | | 0.67 s | |

Every trim costs corpus cases, and the largest saving is a tenth of a second on a wait
that working ahead has already taken out of the user's way. The prompt stays as it is.

## Reproducing the numbers

`uttrflow-dev transcribe <file>` prints transcription and tidying separately for one
file, recognised whole. The sweep above used `say -v Samantha` at 16 kHz cut to exact
lengths, and `uttrflow-dev clean` for the tidying-only measurements.

`uttrflow-dev dictate <file>` plays a file into the real pipeline at real time, as if it
were being spoken, and prints the wait between the key coming up and the words being
ready — which is the figure this whole document is about. `--all-at-once` runs the same
file the old way, so the two can be compared on one Mac.
