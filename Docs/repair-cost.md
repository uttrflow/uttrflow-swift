# What a mistake costs to repair

Counting errors says how often the words are wrong; it does not say how long the person spends
putting them right. This page prices each recovery route for each class of error, so a route is
argued from its cost rather than on its own, and so a more accurate setting can be judged once
repair is counted.

## How the table is made

`python3 Scripts/repair_cost.py` prints it. Each route is written as the actions a person takes,
priced with the published keystroke-level operator times: a key press 0.28 s, pointing 1.10 s, a
button press or release 0.10 s, moving a hand between keyboard and pointer 0.40 s, and 1.35 s of
preparation before each unit of action. Speech runs at 2.5 words a second. Waits are the measured
ones in [performance-dictation.md](performance-dictation.md#word-error-rate): 1.07 s after a short
utterance, 2.75 s after a 100-word dictation in real time, and 8.41 s to decode a recording again
all at once. The writes into the field are the measured ones under [Machine waits](#machine-waits).
Finding the mistake costs the same on every route, so it is left out.

The error classes are one wrong word (6 characters), a sound-alike (5), a dropped negator (nothing
to select, 4 to type), a wrong number (3), a wrong name (7), and a lost piece of 8 words
(45 characters). Routes that remove the dictation say all 100 words again.

## The table

N = 1 scripted user per cell; the model is deterministic, so a cell has no spread.

| route | wrong word | sound-alike | dropped negator | wrong number | wrong name | lost piece |
|---|---|---|---|---|---|---|
| retype by hand | 5.6 s | 5.3 s | 4.9 s | 4.8 s | 5.9 s | 16.3 s |
| app undo, redictate (IN.11) | 46.3 s | 46.3 s | 46.3 s | 46.3 s | 46.3 s | 46.3 s |
| undo last, redictate (UX.10) | 46.6 s | 46.6 s | 46.6 s | 46.6 s | 46.6 s | 46.6 s |
| History Undo, redictate | 50.4 s | 50.4 s | 50.4 s | 50.4 s | 50.4 s | 50.4 s |
| Retry (UX.6) | 15.8 s | 15.8 s | 15.8 s | 15.8 s | 15.8 s | 15.8 s |
| replace X with Y (CM.9) | 4.7 s | 4.7 s | 4.7 s | 4.7 s | 4.7 s | 9.2 s |
| History fix (LN.26) | 10.6 s | 10.3 s | 9.8 s | 9.7 s | 10.9 s | 21.3 s |
Faster (N=3), repaired by retype by hand: 102.6 net words a minute (95% 75.7-140.2)
Faster (N=3), repaired by replace X with Y (CM.9): 109.5 net words a minute (95% 85.0-140.2)
Most accurate (N=6), repaired by retype by hand: 95.1 net words a minute (95% 71.6-126.6)
Most accurate (N=6), repaired by replace X with Y (CM.9): 101.0 net words a minute (95% 79.8-126.6)

`Scripts/repair_cost_test.py` holds the orderings below, so a change to an operator or a route
that reverses a decision fails there.

## Machine waits

What each route asks of the machine, timed on the insertion fixture's multi-line view
([insertion.md](insertion.md#the-insertion-fixture)). **Only the machine is timed: reading,
pointing, typing and speaking are excluded**, and stay the keystroke-level estimates above. Each step
is timed from the call to the field reading back as the route left it.

| Route | What the machine does | N | median | p95 | mean, 95% |
|---|---|---|---|---|---|
| every dictation | write 100 words through Accessibility and confirm the caret after them | 600 | 1.22 ms | 4.73 ms | 1.71-2.00 ms |
| app undo (IN.11) | the field's own Undo, until the field reads back as before the dictation | 200 | 0.70 ms | 1.87 ms | 0.79-1.13 ms |
| undo last (UX.10) | take the last dictation out by its recorded range (`RecordedEditor`, "undo that") | 200 | 1.15 ms | 5.51 ms | 1.81-2.97 ms |
| replace X with Y (CM.9) | rewrite one word inside the last dictation (`RecordedEditor.rewrite`) | 200 | 1.17 ms | 4.86 ms | 1.71-2.32 ms |
| Retry (UX.6) | decode the kept recording whole and put the words on the clipboard | the `dur30` clips of [Net speed](#net-speed) | 7.41 s | | |
| retype by hand | nothing of Uttrflow's; the field echoes the keys | | | | |
| History Undo | not built: no History row takes a dictation out of a field | | | | |

```bash
swift build --product uttrflow-insertion-fixture
UTTRFLOW_INSERTION_FIXTURE=$PWD/.build/debug/uttrflow-insertion-fixture UTTRFLOW_REPAIR_TIMING_RUNS=200 \
  swift test --filter RepairRouteTimingProbeTests
```

One machine under heavy load (load average 230 to 245), debug build, 200 runs after 3 discarded
warm-ups; each run writes three dictations, so the write has three times the samples. The probe
launches the fixture itself and reaches it only through the fixture process's own Accessibility
elements, so no key is posted and no other window can receive a write; it needs Accessibility
granted to the shell.

- **The machine is not where repair time goes.** Every field-side median is under a thousandth
  of the cheapest cell in the table (4.7 s), so adding them leaves every cell unchanged at its
  printed precision. The routes are decided by the person's actions and
  the decode waits.
- **Retry's wait is the decode, not the fixture.** Retry writes the clipboard, not the field, so
  its machine time is the whole-recording decode: the Most accurate wait on the `dur30` clips
  under [Net speed](#net-speed), the same pass at key-up. The table keeps 8.41 s from
  [performance-dictation.md](performance-dictation.md#word-error-rate) for 100 words.
- **The fixture is one native text view.** Other applications are not timed here;
  [compatibility.md](compatibility.md) records per application whether its undo takes the
  dictation back in one step.

## What it decides

| Route | Decision | Why |
|---|---|---|
| retype by hand | keep | the floor every other route is measured against |
| app undo, then redictate | keep, never the default for one wrong word | 8 to 10 times retyping; it is the right route only when most of the dictation is wrong, and it is the platform's own |
| undo last, then redictate | delete unless the accessibility review needs a keyboard route | the same cost as the app's undo, a second implementation of it |
| History Undo, then redictate | keep only for apps where one Command-Z does not remove the dictation | the slowest route on every class |
| Retry | keep only for the lost piece and for a whole dictation heard wrong | 3 times retyping a word even when one Retry fixes it, which the model assumes |
| replace X with Y | default spoken route | the only route at or under retyping for every class, and half the cost for a lost piece |
| History fix | keep for the dictionary fix it saves, not as a repair | twice retyping a word; its value is that the same mistake does not recur |

Insert as spoken and read-back are not priced: the first repairs only formatting, and the second
finds a mistake rather than repairing it.

## Net speed

The same script prices a 100-word dictation with its expected errors repaired, with a 95% band from
a Poisson count of the errors. The two settings are the two decode paths the pipeline has:
**Faster** works ahead while the key is held and joins the pieces; **Most accurate** decodes the
whole recording at key-up, which is also what Retry does.

Reduced run, one machine under heavy load (load average 110 to 250), shipping recogniser and
cleaner, clean audio, the `dur30`, `dur60` and `tc-everyday` clips of `Scripts/dictation_bench.py`:

| | clips | final WER, 30 s | final WER, 60 s | final WER, everyday | wait p50, 30 s |
|---|---|---|---|---|---|
| Faster (`--mode rt`) | 13 | 2.2% | 0.4% | 0.6% | 2.80 s |
| Most accurate (`--mode fast`, run twice) | 26 | 2.2% | 0.4% | 0.6% | 7.41 s |

```bash
python3 Scripts/dictation_bench.py corpus
for m in rt fast; do python3 Scripts/dictation_bench.py jobs --mode $m --clean-only \
  --categories dur30,dur60,tc-everyday --repeat $([ $m = fast ] && echo 2 || echo 1); done > jobs.tsv
.build/release/uttrflow-dev bench jobs.tsv > run.txt
python3 Scripts/dictation_bench.py score run.txt
```

- **Decoding the whole recording bought no words** on synthetic speech: the same final word error
  rate in every category, for a wait 2.6 times as long. Net speed is lower for Most accurate on
  both repair routes; the bands overlap.
- **One Retry fixed no error class.** Every clip decoded twice answered identically, so a Retry
  of a mistake on this corpus returns the same mistake; the model's best case for Retry is not
  met here. Real speech varies more between decodes, so this is a floor for Retry, not a verdict.
- **Not measured yet:** the full corpus on an idle machine.
