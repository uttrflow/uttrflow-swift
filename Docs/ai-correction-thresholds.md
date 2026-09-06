# Word correction: the numbers and why they are what they are

`WordCorrectionEngine` replaces a word that does not belong in a sentence and otherwise
does nothing. The default is to do nothing; three conditions must all hold before one word
moves, and each number below is a hard stop rather than a tuning knob.

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

## `improvementMargin = 2`

The single most important number in the engine. One signal is a coincidence: at a margin of
one, "the bear clawed the bark" becomes "the bear Claude the bark" for anyone with a file
called `Claude notes` open. At two it does not, because "clawed" and "Claude" have the same
shape and only one signal separates them. The changes that survive are the ones where the
recogniser visibly came apart (a word split, a word spelt out) and something in the
situation names the word it came apart into. Integers, because the signals are counts of
independent facts.

## `maximumChangedInEvery = 5`, with a floor of one

An engine that wants to change a third of an utterance has misread it, so the whole
utterance is left alone rather than the first few changes applied. The budget counts spoken
words, not proposals. Its floor of one is not a softening: without it every dictation under
five words would be exempt, and short dictations are most of them.

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

## Cost

Ten thousand entries, a forty-word utterance with half the words doubted and a screenful of
selected text: about half a millisecond per dictation on an M-series Mac. The test asserts
under 25 ms, far above the measurement on purpose: a wall clock in a parallel test suite is
noisy, and 25 ms is still a hundredth of the dictation budget and two orders below one
on-device model call, so the test fails only if somebody puts a model call there.

## The restraint corpus

`CorrectionRestraintTests` runs 28 correct sentences with every word doubted, three ways:
with no screen, with the sentence itself on screen, and with the whole fixture dictionary on
screen. The passing score is zero changes. A guard test asserts that at least fifteen of the
sentences tempt the dictionary (seventeen do: "clawed" and "clod" find `Claude`, "sickle"
finds `SQL`, "nickel" finds `Nikhil`, "smell" finds `XML`, "readies" finds `Redis`, "griffin"
finds `Grafana`, "air well" finds `URL`), so silence is restraint rather than coincidence.
