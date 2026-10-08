# Phrase bias at decode time

`PhraseBiasFilter` helps the decoder finish a dictionary word it has already begun. It is built
from the same packed words as the vocabulary prompt, so it is installed, carried and dropped with
the prompt on every decode path.

## Rules

- It never starts a word: only the token after a begun prefix of a word's token path is raised.
- A next token the decoder already gives 0.9 or more is never outvoted.
- The strength is capped at 4 log-odds; 0 turns the filter off.
- Word confidence is the model's own: each window's `EvidenceSampler` undoes the bias on the
  scores it records and reports the chosen token's unbiased log-probability. The window's
  average log-probability, read by the fallback thresholds inside WhisperKit, still sees the
  biased value.

## Measurement

Host: Apple M5 Pro, 48 GB, `openai_whisper-large-v3-v20240930_turbo_632MB`. 16 clips from `say`
(two voices, 175 and 260 words a minute): 8 sentences containing 10 invented names, 8 without
them, all decoded with the five names as vocabulary.

```bash
uttrflow-dev transcribe <clip> --raw --language en --bias "<names>" --phrase-bias <strength>
```

| Strength | Names missed (of 20) | Names inserted where not said (of 16 clips) | Time per clip |
|---|---|---|---|
| 0 | 0 | 2 | 0.8 to 1.7 s |
| 1, 2, 3, 4 | 0 | 2 | 0.8 to 1.9 s |

Transcripts are identical at every strength. The prompt alone already recovers every name, so
the filter has nothing to fix on this audio, and both insertions come from the prompt, not the
filter. It ships off (strength 0) until audio where the prompt misses a begun word shows a gain.
