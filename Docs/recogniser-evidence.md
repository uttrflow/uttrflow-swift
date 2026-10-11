# What each recogniser signal can and cannot say

A flag, a candidate generator or a gate built on the recogniser's own numbers inherits what those
numbers are blind to. This page is the evidence contract: for each signal, what is measured, the
failure it detects, the failure it misses, and the calibration measured so far. A claim with no
measurement is marked **hypothesis** and names the issue that measures it.

Where each signal is read in code: [decoder-evidence.md](decoder-evidence.md) and
[decode-session.md](decode-session.md).

## The signals

| Signal | What is measured | Detects | Misses | Calibration measured |
|---|---|---|---|---|
| Token probability | Softmax of the chosen token over the filtered logits, per step; averaged per word into `WordTiming.probability` | A token the model itself hesitated over | A wrong word the model is sure of; softmax is overconfident in noise ([arXiv 2509.07195](https://arxiv.org/abs/2509.07195)) | WhisperKit turbo, programmer homophones: 3 of 33 errors below the 0.5 gate, the "sed" to "said" error at median 0.97, AUC 0.69 ([eval-methodology.md](eval-methodology.md), #4477). Equal calibration across voices: **hypothesis** (#4527) |
| Margin | Log-probability gap between the chosen token and the next leader (`EvidenceSampler` top 5) | Two near-equal readings at one step | A rival the model never ranked; a word whose error spans tokens each confidently chosen | Clean synthetic speech: lowest word margin 0.66, low margins mostly on timestamp and prefill steps ([decoder-evidence.md](decoder-evidence.md)). On real speech: **hypothesis** (#3595, #3599) |
| Entropy | Entropy in nats of each step's distribution (`DecodeWindowEvidence`) | Probability spread over many tokens | The same confident errors as token probability; a two-way confusion reads as low entropy | Recorded, not calibrated: **hypothesis** (#4496, #3986) |
| Forced score | Log-probability of a candidate spelling decoded under the same model and audio | Which of two given candidates the model prefers | Any candidate not proposed; under the same model it favours the model's own word, so it cannot overrule a confident error alone | **Hypothesis** (#3599) |
| No-speech probability | Whisper's no-speech token probability | A window with no speech | Speech in a language the model does not hear; noise read as speech | WhisperKit 1.1.0 returns a constant 0, so the threshold never fires ([silence.md](silence.md)); the live value is #4498 |
| Language probabilities | Softmax over language tokens at the first step | Which language the window opens in | Code-mixing inside a window; the language is held, not re-detected per word | **Hypothesis** (#3595) |

Every row is WhisperKit's: it is the one speech engine, and the system recogniser it replaced
reported no per-word confidence on most results ([speech-engines.md](speech-engines.md)).

## Confident errors are their own category

A confident error is a wrong word the recogniser scores as sure: an accented word mapped to a
common neighbour, a programmer term heard as an English homophone. No signal above reveals it,
so the measured recall of a doubt detector (#3595) and its oracle ceiling describe only the
flagged errors, never the whole error population.

The mechanisms that handle a confident error do not depend on recogniser doubt:

- a prior: the user's own words biasing the decode ([speech-phrase-bias.md](speech-phrase-bias.md),
  [speech-vocabulary-prompt.md](speech-vocabulary-prompt.md));
- a candidate from the user's lexicon or learnt words ([app-dictionary.md](app-dictionary.md)),
  proposed whatever the probability.

## The rule for a gate

A gate on any signal here is calibrated and reported on two sets: the errors the signal flags,
and confident errors (probability above the gate). A gate whose report omits the confident set
is incomplete. Thresholds and their risk bound are chosen as #3978 states.

## Doubtful words on the outcome

`DoubtfulWordsOutcome.locating` places each doubted heard word on the written text with the same
word-error alignment the dictionary corrections use: a match or a one-for-one rewrite lands, a
word the tidier dropped is counted unplaced. A settled word is `overridden`; a doubted word written
with digits is `numberLike`, capitalised mid-sentence `nameLike`, beside a negator
`negatorAdjacent`, else `soundAlikeClass` or `lowScore` as `DoubtPolicy` says. An engine without
real per-word scores gives `.notAvailable`.

Cost, debug build, load average above 100, 200 runs each: p95 0.25 ms for the 5 s fixture's
12 words and 29 ms for the 30 s fixture's 80 words. The alignment is quadratic in words, so the
release-build reading on an idle machine is the one that answers the 1 ms budget; it is queued
with the idle-machine runs.
