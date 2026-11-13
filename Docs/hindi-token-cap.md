# How often a Hindi piece reaches the decoder's token cap

The decoder stops after about 215 tokens, and Devanagari costs several times the tokens of
English ([speech-engines.md](speech-engines.md)). `CappedDecodeRetry` decodes the tail again when
a piece runs out. This page measures how often a Hindi or Hinglish piece needs that, by length.

## How it was measured

`uttrflow-eval token-cap` has the hi-IN `say` voice Lekha read the corpus's Devanagari passages
joined into growing runs, six per language (`TokenCapPiece.growing`), and decodes each once as a
single piece under the Hindi hint with no prompt. A piece counts as "tail decoded again" when the recogniser
decoded its tail again, after the token cap or after a collapsed window, or found no point to resume from (`TokenCapRow.reachedCap`; the run does not tell the two causes apart); no prompt is
sent, so the unprompted re-decode of an empty result cannot add to the retry time. "Words out per word read"
is a count ratio of the transcript to the text read; it does not say which words came back. Synthetic speech at one voice and one
pace; the seconds are from a virtual machine and say only that a retry happened, not what it costs
on a Mac.

```bash
uttrflow-dev models install
uttrflow-eval token-cap
```

## Result

WhisperKit `openai_whisper-large-v3-v20240930_turbo_632MB`, weights
`0f63a7800b00dd0226abd051b906c246e1907482`, voice Lekha. Apple's speech engine: not measured.

| Piece length | Pieces | Tail decoded again or unresolved | Unresolved | Seconds decoding again | Words out per word read |
|---|---|---|---|---|---|
| under 10 s | 2 | 0 | 0 | 0.0 | 102% |
| 10 to 20 s | 2 | 2 | 0 | 6.0 | 102% |
| 20 to 30 s | 2 | 2 | 0 | 9.4 | 100% |
| over 30 s | 6 | 6 | 0 | 4.1 | 66% |

- A Hindi or Hinglish piece of about 10 s (30 words) decodes in one pass. Every piece of about 19 s
  or more (60 words) needed at least one decode of the tail again, so the tail is decoded again from
  roughly 60 words, not only at the 30 s window; the cap, or a collapsed window, is the cause, and
  the run does not say which.
- Up to 30 s the transcript held as many words as were read (100% to 102%), the extra being words
  split in two.
- Over 30 s it held two thirds as many (66%) even with the retry chain; a piece that long is
  decoded in one call here, which the dictation path may cut differently.
- A cut before about 60 words might avoid the second decode, but no cut was measured here; whether
  it is worth the extra seams needs the tail cost on a Mac and the seam metric, neither of which
  this run has.

## Not measured

Real speech, other voices, pace, the timing of a retry on a Mac, and a cut earlier than the
window: the decision to cut earlier stays open on the evidence above.
