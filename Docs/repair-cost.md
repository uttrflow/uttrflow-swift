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
all at once. Finding the mistake costs the same on every route, so it is left out.

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
Faster, repaired by retype by hand: 94.6 net words a minute (95% 68.8-140.4)
Faster, repaired by replace X with Y (CM.9): 102.5 net words a minute (95% 78.2-140.4)

`Scripts/repair_cost_test.py` holds the orderings below, so a change to an operator or a route
that reverses a decision fails there.

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
a Poisson count of the errors. At the Faster setting's measured 2.9% final word error rate it is
about 95 net words a minute repaired by hand and about 103 with the spoken fix. The Most accurate
setting's word error rate and wait on the same corpus, and timed runs of the built routes on the
insertion fixture application, are tracked in #6287.
