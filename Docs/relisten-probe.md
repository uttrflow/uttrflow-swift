# Listening again to one doubtful word

Two ways exist to ask the recogniser about one word it may have misheard:

- **Forced scoring in the window.** Decode the whole clip with the words before the slot, the
  candidate and the next few words of the sentence as `prefixTokens`, and add the log-probability
  of each forced token. Each candidate is scored against the same audio.
- **Cropped re-decode.** Cut the audio to the word's own timing, padded either side, and decode
  it with the words before it as `promptTokens`.

## The probe

`uttrflow-eval relisten` reads every `HomophoneConfidence` pair sentence in synthetic voices
(`say`, three voices at two rates by default). For each clip it runs a free decode with word
timings, then for the slot of the meant word:

| Shape | What it reads |
|---|---|
| forced, whole candidate | forced log-likelihood of the meant word minus the other, over the candidate and the next 3 tokens |
| forced, first-token margin | log-probability of the meant word's first token minus the other's, at the step that chooses it |
| cropped re-decode | whether the cropped decode, prompted with the words before, writes the meant word |

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

Shipping model, Apple M5 Pro under load, debug build; 199 clips (36 pairs, voices Samantha,
Daniel and Karen at 175 and 230 wpm; 17 clips skipped). The free decode wrote the meant word
in 93%.

| Shape | Picks the meant word | Recovers a free-decode error | Overrides a right free decode | Added ms p50 | p95 |
|---|---|---|---|---|---|
| forced, whole candidate | 95% | 23% of 13 | 0% of 186 | 566 | 638 |
| forced, first-token margin | 92% | 23% of 13 | 3% of 186 | 566 | 638 |
| cropped re-decode | 64% | 0% of 13 | 31% of 186 | 385 | 411 |

Forced whole-candidate minus first-token margin, paired share of clips where the meant word wins:
+0.030, 95% bootstrap interval [+0.010, +0.055].

## Decision

The cropped re-decode is not built. Without the sentence's audio around it the word is often
heard as its everyday twin or split ("byte" as "by"), so it overrides 31% of right decodes and
recovers none of the errors. Forced scoring in the window feeds the candidate pipeline as a
feature: it never overrode a right decode here and separates the pair better than the
first-token margin, by an interval that excludes zero.

## Limits

- Synthetic voices only; no recorded speech. Accent and room effects are not measured.
- The forced cost re-encodes and re-prefills per candidate in a debug build on a loaded Mac; it
  is an upper bound, not the cost of a scorer that reuses the window's cache.
- The first-token margin is the log-probability gap between the two candidates' first tokens,
  not the top-2 gap of the greedy step.
- The trie bias is not applied to either shape.
- The full run, with release timings and more voices, is queued.
