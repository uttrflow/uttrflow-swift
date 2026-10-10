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
filter.

### Real speech

Same host and model, shared with other builds (load 50 to 70), so times are noisy. 30 recorded
clips from one speaker (reader-1) reading the evaluation passages of
`Sources/UttrflowEval/TranscriptionCorpus.swift`: the six English passages in a quiet room, read
fast, and in a noisy room (18 clips, 918 reference words), plus the twelve Hindi and Hinglish
passages in a quiet room. The bias words are the names and terms of the English `en-people` and
`en-terms` passages (12 words, 36 occurrences); the Hindi clips use the names and terms of
`hi-people`, `hinglish-people` and `hinglish-terms`. Twelve English clips contain none of the
words. "Prompt" decodes with the words in the prompt, as shipped; "filter only" adds
`--no-prompt-words`.

```bash
uttrflow-dev transcribe <clip> --raw --language <en|hi> [--bias "<words>" --phrase-bias <0-4> [--no-prompt-words]]
```

| Arm | Bias words missed (of 36) | Bias words inserted (word-free clips / anywhere) | Word errors / words | Median time | p95 time |
|---|---|---|---|---|---|
| No bias words | 9 | 0 / 0 | 179 / 918 | 4.5 s | 11.2 s |
| Prompt, strength 0 to 4 | 1 | 0 / 2 | 162 / 918 | 5.0 to 7.1 s | 12.2 to 19.8 s |
| Filter only, strength 1 | 8 | 0 / 0 | 178 / 918 | 4.3 s | 8.2 s |
| Filter only, strength 2 | 8 | 0 / 0 | 176 / 918 | 4.0 s | 9.6 s |
| Filter only, strength 3 | 8 | 0 / 0 | 175 / 918 | 4.7 s | 8.7 s |
| Filter only, strength 4 | 8 | 0 / 0 | 173 / 918 | 3.9 s | 10.3 s |

With the words in the prompt, transcripts are identical at every strength on all 30 clips: the
prompt recovers 8 of the 9 missed words and the filter changes nothing. Both insertions are a
second "JSON" in the `en-terms` passage, which says it once, and come from the prompt. Without
the prompt the filter recovers 1 of the 9 words at every strength and inserts none; its
word-error fall from 179 to 173 is 6 words in 918 from one speaker and one take each, too small
to tell from noise. On the Hindi clips the decoder writes most names in Devanagari, so a Latin
word match cannot score misses there; no arm inserts a bias word in any of them.

It ships off (strength 0): with the prompt on, as shipped, no strength changes a word, and
without the prompt it recovers 1 word where the prompt recovers 8. This is one speaker; a speaker
or vocabulary where the prompt misses a begun word could still show a gain.
