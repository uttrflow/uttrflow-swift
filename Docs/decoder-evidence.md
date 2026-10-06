# What WhisperKit can say about a doubtful word

Re-ranking a doubtful word needs more than the one per-word probability the pipeline gets
today. This page records what the pinned WhisperKit (1.1.0) exposes, where, at what cost,
and what it does not expose at all. Upstream paths below are inside the WhisperKit 1.1.0
checkout (Sources/WhisperKit/Core/...).

The harness is `Tests/UttrflowSpeechTests/DecoderEvidenceProbeTests.swift`: an
`EvidenceRecorder` installed as a logits filter, and a probe suite that runs the shipping
model on the clips named in `UTTRFLOW_PROBE_AUDIO` (skipped otherwise).

```bash
UTTRFLOW_PROBE_AUDIO=/path/a.wav,/path/b.wav swift test --filter DecoderEvidence
```

## Summary

| Evidence | Available | Where | Cost |
|---|---|---|---|
| Log-probability of each chosen token | yes, already returned | `TranscriptionSegment.tokenLogProbs`, one `[token: logProb]` per token | none |
| Per-word probability | yes, used today | `WordTiming.probability`, exp of the mean token log-probability | none |
| Top-k alternatives at a position | carried: up to 5 leaders beside the chosen token in `tokenLogProbs` | `EvidenceSampler`, passed in by `LanguageHeldDecoder.decodeText` | 0.31 to 0.39 ms per step, median |
| No-speech probability | **no**: always 0 | TextDecoder.swift:817 writes the constant | n/a |
| No-speech token at the first sampled step | readable, but measured ~0 even on silence | logits filter | as top-k |
| Substituting the sampler | yes: the repository owns the loop ([decode-session.md](decode-session.md)) | `DecodeSession.decode`, called by `LanguageHeldDecoder.decodeText` | none |

## Per-token log-probabilities

- TextDecoder.swift:791-806 builds `tokenLogProbs` as one single-entry dictionary per token,
  the log-probability the sampler gave the token it chose. `SegmentSeeker.swift` slices it per
  segment and averages it per word into `WordTiming.probability` (SegmentSeeker.swift:393-402).
- The value is computed after every logits filter has run (suppression, timestamp rules), so it
  is a probability over the tokens the decoder was still allowed to pick.
- Measured: every segment of every probe clip had exactly one entry per token; no alternative
  is carried beside the chosen one.

## Top-k alternatives

- Neither `SamplingResult` nor `DecodingResult` carries alternatives. `GreedyTokenSampler`
  computes a top-k only when the temperature is above 0, and only to sample from it
  (TokenSampler.swift:57-73 and 140-180); the greedy path takes the argmax and discards the rest.
- Two seams see the full logits at every step:
  1. `TextDecoding.logitsFilters`: custom filters run first, before WhisperKit's own
     (TextDecoder.swift:877-878), every step including the prefill steps. The product already
     sets this array on every call (`WhisperKitBackend`), so a recorder is one more element.
  2. `TokenSampling.update(tokens:logits:logProbs:)` receives the logits after all filters.
     `decodeText` takes the sampler as a parameter (TextDecoder.swift:548-553), but WhisperKit
     builds a fresh `GreedyTokenSampler` per fallback temperature (TranscribeTask.swift:337)
     and offers no option to replace it. `TextDecoder.decodeText` is `public`, not `open`, so it
     cannot be overridden either. The one place a substitute can be passed in is a wrapping
     `TextDecoding`, which `LanguageHeldDecoder.decodeText` already is.
- Positions: the decoder calls filters and sampler once per prompt token before the first
  sampled step, each time with the whole prompt as `tokens`. With the shipping English options
  the prompt is 4 tokens and the first four calls all report 4 tokens; the fourth is the first
  real prediction. A consumer has to key steps by `tokens.count` and keep the last call.
- Cost, measured on an Apple M5 Pro, release build, turbo model, three runs per clip: reading
  the top 5 and a log-sum-exp over the whole vocabulary costs a median of 0.31 to 0.39 ms per
  step against 11 to 15 ms per step of model prediction, about 2.5%. Wall time per clip was
  inside run-to-run noise (English sentence 835 to 1,417 ms without, 800 to 880 ms with).
  The worst single step was 4.1 ms, once.
- What the leaders look like: on clean synthetic speech the lowest-margin steps were almost all
  timestamp tokens and the prefill steps, not words. The lowest word margin seen was 0.66
  ("th" against "tha" inside "Siddharth"). Word-level doubt needs real, noisier speech to
  measure how often a rival is close; this probe establishes only that it can be read.

## No-speech probability

- WhisperKit never computes it: TextDecoder.swift:817 sets `noSpeechProb` to 0 with a TODO, so
  `noSpeechThreshold` in `VocabularyPrompt` compares against a constant and never fires
  (SegmentSeeker.swift:59, Models.swift:368). Measured: 0 in every segment of every clip.
- The no-speech token's own probability, read by the recorder from the raw logits of each of
  the first five calls, was below 0.00001 on every clip, including 3 s of digital silence that
  the model transcribed as "Thank you.". Reading the token at the first step under the
  prefilled prompt does not give the signal Whisper's reference decoder uses, so a no-speech
  estimate cannot be built from this seam as is. See `Docs/silence.md` for how silence is
  caught before the recogniser instead.

## What this means for the work that depends on it

- Re-ranking by alternatives is feasible without forking WhisperKit: a recorder or wrapping
  sampler gives the top-k at every sampled position for under 3% of decode time.
- `EvidenceSampler` now does this: it wraps WhisperKit's sampler, samples exactly as it does,
  and adds each position's leaders to that token's `tokenLogProbs` entry, so they travel through
  WhisperKit's segmenting unchanged. The chosen token keeps the sampler's own value. Leaders are
  log-probabilities over the filtered logits at temperature 0; on a fallback at a higher
  temperature the chosen value is the sampler's and is not on the same scale.
- Wrapping hides the sampler from WhisperKit's `as? GreedyTokenSampler` read of the temperature
  (TextDecoder.swift:812), so `LanguageHeldDecoder` restores it.
- Per-token log-probabilities and leaders are in the results and are dropped at the backend
  mapping, where only the per-word probability survives.
- Entropy has no slot in WhisperKit's result types, so it is kept in a record of the repo's own:
  `EvidenceSampler` computes each step's entropy in nats from the logits it already reads, and
  `LanguageHeldDecoder` appends one `DecodeWindowEvidence` per decode window, fallback retries
  included, to its `DecodeWindowLog`. The log keeps its newest 64 windows until drained.
- A no-speech probability is not available and the first-step token is not a substitute;
  anything gated on it needs another signal.
