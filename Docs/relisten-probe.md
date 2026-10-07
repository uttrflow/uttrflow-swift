# Listening again to one doubtful word

Two ways exist to ask the recogniser about one word it may have misheard:

- **Forced scoring in the window.** Decode the whole clip with the words before the slot, the
  candidate and the next few words of the sentence as `prefixTokens`, and add the log-probability
  of each forced token. Each candidate is scored against the same audio.
- **Cropped re-decode.** Cut the audio to the word's own timing, padded either side, and decode
  it with the words before it as `promptTokens`.

## The probe

`uttrflow-eval relisten` reads every `HomophoneConfidence` pair sentence in synthetic voices
(`say`, four voices at two rates by default). For each clip it runs a free decode with word
timings, then for the slot of the meant word:

| Shape | What it reads |
|---|---|
| forced, whole candidate | forced log-likelihood of the meant word minus the other, over the candidate and the next 3 tokens |
| forced, first-token margin | log-probability of the meant word's first token minus the other's, at the step that chooses it |
| cropped re-decode | whether the cropped decode, prompted with the words before, writes the meant word |
| greedy-step margin | at the step that chooses the first token where the two candidates differ, with the words before forced: top-1 minus top-2 log-probability when the candidate's token leads, otherwise its log-probability minus the leader's |

A wrapper `TextDecoding` records each step's log-probabilities of the prompt tokens; only the
first window of each decode is recorded. The flags are an oracle: every slot is scored, so
"recovers" is over the slots the free decode got wrong and "overrides" is over the slots it got
right. A clip whose free decode has a different word count is skipped, because its slot cannot
be timed.

```bash
swift run uttrflow-eval relisten --list            # every clip's scores, then the table
swift run uttrflow-eval relisten --limit 4 --voices Samantha --rates 175   # a reduced run
```

## Measured

Shipping model, Apple M5 Pro under load, debug build; 266 clips (34 pairs, voices Samantha,
Daniel, Karen and Rishi at 175 and 230 wpm; 6 clips skipped). The free decode wrote the meant
word in 93%.

| Shape | Picks the meant word | Recovers a free-decode error | Overrides a right free decode | Added ms p50 | p95 |
|---|---|---|---|---|---|
| forced, whole candidate | 95% | 39% of 18 | 0% of 248 | 675 | 1518 |
| forced, first-token margin | 92% | 39% of 18 | 4% of 248 | 675 | 1518 |
| cropped re-decode | 65% | 6% of 18 | 31% of 248 | 405 | 957 |

Forced whole-candidate minus first-token margin, paired share of clips where the meant word wins:
+0.030, 95% bootstrap interval [+0.011, +0.053]. The forced cost is per candidate.

### Separation: forced score against the greedy-step margin

Each slot gives two candidates, the meant word (right) and its pair (wrong). The forced score of
a candidate is its forced log-likelihood minus its rival's. The greedy-step margin is the feature
the reranker and gate already receive for free. "Both" adds the two after dividing each by its
standard deviation. The AUROC is right against wrong candidates over all slots. Its 95% interval
comes from 1000 resamples of whole sentences, so the voices and rates of one sentence move
together. The forced-minus-margin difference is read on the same resamples.

The bar was set before the run: the forced score separates better only if the lower bound of
the forced-minus-margin interval is above 0.

| Feature | AUROC | 95% interval |
|---|---|---|
| forced score | 0.996 | [0.980, 1.000] |
| greedy-step margin | 0.990 | [0.968, 0.999] |
| both | 0.995 | [0.979, 1.000] |

Forced minus greedy-step margin: +0.006, 95% interval [−0.000, +0.016], over 266 slots in 34
sentences. The lower bound is just below 0, so the bar is not met.

Confident errors, where the forced score prefers the rival and the greedy step chose it too:
8 of 266 (4 "sed" heard as "said", 2 "kernel" as "colonel", 1 "sync" as "sink", 1 "byte" as
"bite"). Neither feature can repair these, because both agree with the misreading.

## Decision

The greedy-step margin suffices; the fast forced scorer is not built. On these clips both
features separate the pair almost perfectly, and the forced score's gain over the margin has an
interval that does not exclude 0. The cropped re-decode is not built either. Without the
sentence's audio around it the word is often heard as its everyday twin or split ("byte" as
"by"), so it overrides 31% of right decodes and recovers 1 of the 18 errors. The forced score still picks the meant word more often than the
pairwise first-token gap does, but that gap is not the feature the pipeline uses. Against the
greedy-step margin it adds nothing the interval can tell apart from 0.

## Limits

- Synthetic voices only; no recorded speech. Accent and room effects are not measured.
- The forced cost re-encodes and re-prefills per candidate in a debug build on a loaded Mac; it
  is an upper bound, not the cost of a scorer that reuses the window's cache.
- The first-token margin is the log-probability gap between the two candidates' first tokens.
  The greedy-step margin is the top-2 gap. Both are read with the reference words before the
  slot forced, which equals the free decode's step only where the free decode wrote those words.
- Both AUROCs are near 1 on synthetic voices, so the comparison has little room. A clip whose free
  decode changes the word count is skipped for both features.
- The trie bias is not applied to either shape.
- Release-build timings are not measured.
