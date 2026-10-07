# The decode session

`DecodeSession` (`Sources/UttrflowSpeech/DecodeSession.swift`) decodes one 30-second window
token by token. It replaces WhisperKit's own `TextDecoder.decodeText` loop on the shipping
path: `LanguageHeldDecoder.decodeText` builds a session and never calls the library loop.

## Why the repository owns the loop

`TextDecoder.decodeText` is `public`, not `open`, so nothing can change what happens inside
one step: the logits filters, the sampler and the cache writes are fixed in one long method.
Every per-step need (a real no-speech probability, a prompt-aware bias, forced scoring,
branching from a copied cache) needs that step. The step itself is built from members the
library does make public: `DecodingInputs`, `predictLogits`, `updateKVCache`,
`updateAlignmentWeights`, the three logits filters and `TextUtilities.compressionRatio`.
No fork of WhisperKit and no new dependency.

## What the session keeps identical

Every rule of the library loop is reproduced as it is, so the segment seeker and the
fallback ladder downstream see the same `DecodingResult`:

- the prompt is forced token by token, except that a timestamp the model chose stands where
  the prompt ends on one;
- an end token sampled while the prompt is still forced is ignored;
- the filters run in the library's order: the decoder's own, then blank suppression, token
  suppression and the timestamp rules, each told the same `sampleBegin`;
- the first-token log-probability threshold, the token-context limit and a progress callback
  answering `false` past the prefill each end the window;
- the result is cut from start of transcript to end of text, with the same average
  log-probability, compression ratio, language and fallback verdict;
- the no-speech probability stays 0, as the library writes it, until it is computed for real.

## The parity gate

`Tests/UttrflowSpeechTests/DecodeSessionParityProbe.swift` installs a decoder that, for every
greedy window, decodes copies of the same inputs through the library loop and through the
session, alternating which runs first, and compares the results byte for byte: tokens,
per-token log-probabilities, text, average log-probability, compression ratio, language,
fallback reason, step count, and the key and alignment caches the word timings are read
from. It also transcribes each clip three times and checks the word timings never vary.

```bash
UTTRFLOW_PROBE_AUDIO=/path/a.wav,/path/b.wav swift test --filter DecodeSessionParityProbe
```

It runs only with the shipping model installed and `UTTRFLOW_PROBE_AUDIO` set.
`DecodeSessionTests` holds the loop's rules without a model, against a scripted decoder.

## Measured

Shipping model (large-v3 turbo), 25 clips: the 6 synthesised English and 12 code-mixed passages
of `uttrflow-eval synthesise`, the 6 Hindi passages read in Devanagari by the system's Hindi
voice, and 5 seconds of digital silence. Each clip transcribed three times.

| Measure | Library loop | Session |
|---|---|---|
| Greedy windows compared | 75 | 75 identical, byte for byte |
| Decoder steps | 7,185 | 7,185 |
| Mean time per step | 22.31 ms | 22.65 ms |
| Word timings across three runs | | 1 distinct result per clip |

The 0.33 ms difference is under the 1 ms bound and within the noise of a machine that was
running other builds at the time (load average above 100); the order of the two loops
alternated window by window. Fallback windows above temperature 0 sample at random and are
not compared.

## Built on it next

The no-speech probability, per-step evidence, prompt-aware biasing, forced scoring and
branching are added to the session, never as a second loop or a wrapper around the library's.
