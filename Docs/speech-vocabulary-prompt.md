# Conditioning Whisper on the user's own words

`VocabularyPrompt` in `Sources/UttrflowSpeech/VocabularyPrompt.swift` turns the personal
dictionary into the prompt Whisper is conditioned on *before* it decodes anything, and builds
every `DecodingOptions` the WhisperKit backend decodes with. `WorkingSet`
(`Sources/UttrflowDictionary/WorkingSet.swift`) chooses the words and `DictionaryVocabulary`
(`Sources/UttrflowSpeech/VocabularySource.swift`) bridges the two. The pipeline ranks the words
once per dictation, against the screen it began on, and gives the same list to every piece.
[`speech-engines.md`](speech-engines.md) covers what the prompt costs the decoder's own rules.

This is where a personal dictionary is worth the most. Rewriting "utter flow" to "Uttrflow"
afterwards is a repair, and one that only fires when the recogniser happened to produce
something close enough to match; putting the word in front of the decoder makes it hear the
word.

## The budget is 111 tokens, not 448 and not 224

Not the model's 448-token context, and not half of it either. WhisperKit trims the prompt to
`(Constants.maxTokenContext / 2) - 1`, and `maxTokenContext` is itself `Int(448 / 2)` — 224 —
so the real ceiling is 111.

> WhisperKit 1.1.0: `Core/TextDecoder.swift:199` for the expression, `Core/Models.swift:1340`
> for the constant. Both numbers are asserted against the linked package by
> `WhisperKitContractTests`, so a bump that moves them fails the build rather than this page.

Truncating here rather than leaving it to the decoder is the whole point. WhisperKit keeps
the *last* 111 tokens and drops the rest without a word, so a vocabulary ranked best-first
would lose precisely the words worth having.

| Constant | Value | Meaning |
|---|---|---|
| `VocabularyPrompt.maximumTokens` | 111 | the prompt budget |
| `WorkingSet.defaultLimit` | 28 words | how many dictionary words usually fit beside the rest |
| `WorkingSet.newAdditionPriorityDays` | 7 days | a word added by hand ranks ahead of older entries for this long |
| `WorkingSet.recencyHalfLifeInDays` | 30 days | the age at which a word's value halves |
| `WorkingSet.unusedInferredLifetimeDays` | 30 days | an unused inferred word stops taking a slot after this |

Long technical words can make the token budget bind before the word limit. Words added by hand
in the last seven days rank ahead of older entries, newest first, which keeps a just-corrected
name in front of entries that have accumulated a few uses. Otherwise words are scored on
frequency, recency and whether the frontmost app agrees with the entry. The Diagnostics page
shows the dictionary words kept by the latest prompt ("Words in recogniser prompt"); that personal
list stays on screen and is left out of Copy Diagnostics.

Packing is word by word rather than a truncation mid-sequence: half of `PaymentSheet` in the
prompt biases the decoder towards something the user has never said. A word too long for what
is left is skipped rather than ending the packing, so one forty-token monster cannot cost the
fifty ordinary words ranked behind it. The separator belongs to the word rather than sitting
between words, because dropping a word that will not fit must not leave its separator behind.

Special tokens are filtered out of every piece. WhisperKit discards them itself, so filtering
here as well is what keeps the count being budgeted equal to the count that survives.

## The sentence around the words is the surprise

The words are offered inside `" The words used here are …"` (`VocabularyPrompt.opening`), closed
with `"."` (`closing`), and that framing is not decoration: it is the single most surprising thing
measured here.

| Prompt                                 | What the decoder heard |
|----------------------------------------|------------------------|
| `Uttrflow Nikhil PaymentSheet`          | "KidPit"               |
| the same words inside the sentence      | "Uttrflow"             |

The sentence worked with three words in the list and again with fourteen. Whisper's prompt is
trained as the *transcript that came before*, so text shaped like a transcript is what it
knows how to condition on; a glossary is not. It is closed with a full stop for the same
reason it is opened like a sentence.

## The words are spaced, not punctuated

The words are separated by a space alone. A comma between them is copied into the transcript:
Whisper's prompt is read as the transcript that came before, so the mark between two listed
words is the style the decoder continues when the audio says those two words next to each
other — which a first and last name does.

Measured with `uttrflow-dev bench` and `Scripts/dictation_bench.py` on the bench's
`nouns-vocabulary` clips, `nouns0` and `nouns1` in all three English voices, against the shipping
turbo model:

| Separator | Clips with an adjacent pair that gained a comma | `nouns-vocabulary` raw WER |
|---|---|---|
| `", "`    | 6 of 6 — "Zorvane, Kelthmar", "Ask Mirvella, Ostrander," | 0.0% |
| `" "`     | 0 of 6 | 0.0% |

Every dictionary word is heard either way: the sentence around the words is what conditions the
decoder, not the punctuation inside it. The word error rate cannot show the difference, since it
drops punctuation.

A space also costs less than a comma: no token in the model's vocabulary begins with a comma
followed by a space or a letter, so `", " + word` encodes the comma on its own, and every word
past the first costs one token more with commas than with spaces.

## The forced prefill, and why a prompt otherwise returns nothing

WhisperKit forces a fixed run of tokens through the decoder before the transcript begins:

```
[<|startofprev|>] + prompt + [<|startoftranscript|>, language, task, timestamps]
```

The language and task tokens are absent when the model only knows English.

> WhisperKit 1.1.0, `Core/TextDecoder.swift:163-223`.

WhisperKit 1.1.0 ignores an end token sampled while it is still forcing the prompt, when whatever
the sampler produces is thrown away anyway (`Core/TextDecoder.swift:679-686`), and honours one
sampled at the last prefill token, which is the first real prediction.

`DecoderPrefill` counts that run once, and it is the only place the count is written. A prompt
that survives trimming brings a `<|startofprev|>` token with it; a prompt that does not is
dropped whole and takes that token with it.

## The prompt shares the 223-position decode budget with the transcript

The prefill tokens occupy the left end of the decoder's context, and the transcript's words and
timestamps occupy the rest. WhisperKit sizes the context at `Constants.maxTokenContext = 224`
and lets the decode loop run up to `initialPromptIndex - 1 + sampleLength` steps, where the
`sampleLength` here is also `maxTokenContext`. That is **223 positions shared between the forced
prompt and the transcript** — not added on top of one another.

A full prompt leaves about 108 positions for the words, and Hindi writes roughly 4.7 tokens per
Devanagari word, so a Hindi piece over ~23 words on a full prompt, or ~44 words on a one-word
prompt, runs out of room mid-word. `CappedDecodeRetry` recovers the audio past the cap by
re-decoding the tail ([`speech-engines.md`](speech-engines.md)); the budget itself is fixed by
WhisperKit.

Each retry is a fresh decode with the same prompt, so it advances by the same ~23 or ~44 Hindi
words, and `CappedDecodeRetry.maxRetries` is 10: one dictation recovers at most roughly 230 to
440 Hindi words past the cap. A dictation that is still capped when the retries run out is
marked `DecodeEffort.capUnresolved` rather than returned as if it were complete.

## Two decoding options that cost something

**`wordTimestamps: true`** is the only way to get a per-word probability out of WhisperKit,
and correction's first condition is that the recogniser was unsure. Measured on the shipping
turbo model:

| Clip length | Added time | Share of the transcription |
|-------------|-----------|-----------------------------|
| 3.3 s       | +4.1 ms   | 0.9%                        |
| 24.3 s      | +19.1 ms  | 1.4%                        |

A constant confidence is not used instead, because it makes the condition either vacuous or
unsatisfiable, and the measured cost is small.

**`promptTokens`** is applied once, ahead of the prefill, and re-forced for every 30-second
window: WhisperKit builds the decoder's initial prompt before its seek loop and never
overwrites it, so a two-minute dictation is biased just as strongly at the end as at the
start. It costs the prefill cache and part of each window's decode budget, which is why the
111 tokens are a ceiling rather than a target.

## A saved prompt cache belongs to the audio it was computed on

Each decoder block runs self-attention and then cross-attention over the encoder output, so
from the second block on, the keys and values of the forced prompt already depend on the
audio. A cache prefilled on one clip is therefore not the cache for another clip, and reuse
is exact only inside one window (a retry or a fork over the same audio).

`Scripts/prefix_cache_probe.py` measures it on the shipping turbo model (4 decoder layers):
20 synthetic clips, greedy decoding without timestamps, each clip decoded with its own
prefill and again with the prefix cache transplanted from the next clip. "Whole prefix" is
every forced token but the last; "prompt only" is `<|startofprev|>` and the prompt, with the
start, language and task tokens recomputed on the clip's own audio; "library prefill" is
WhisperKit's `TextDecoderContextPrefill` model, a lookup table indexed by language and task
that sees no audio. WhisperKit 1.1.0 ships that model but never loads it.

| Prompt tokens | Cache | Max logit difference | Top-1 same | Transcripts same | Largest key or value difference, layers 0 / 1 / 2 / 3 |
|---|---|---|---|---|---|
| 0 | same clip, run twice | 0.00 | 20/20 | 20/20 | |
| 0 | whole prefix from another clip | 1.77 | 20/20 | 19/20 | 0.00 / 0.32 / 0.74 / 1.43 |
| 0 | library prefill | 2.14 | 20/20 | 19/20 | 0.04 / 0.86 / 1.01 / 1.23 |
| 20 | whole prefix from another clip | 3.33 | 20/20 | 20/20 | 0.00 / 0.32 / 2.53 / 2.13 |
| 20 | prompt only from another clip | 3.22 | 20/20 | 20/20 | |
| 111 | whole prefix from another clip | 1.98 | 20/20 | 20/20 | 0.00 / 0.37 / 2.53 / 2.13 |
| 111 | prompt only from another clip | 1.89 | 20/20 | 20/20 | |

Layer 0 is identical across clips and layers 1 to 3 are not. The changed transcript is the
same in both rows: a final full stop the clip's own prefill does not produce. So a transplanted
cache is an approximation that changes logits by up to 3.3 and changed 2 of 120 transcripts
here, not the identical output a cross-audio cache would need. The per-window prefill cost is
reduced by shortening the prompt instead.

> Apple M5 Pro, 48 GB, decoder and encoder on the Neural Engine, load average 170 to 240
> during the 182-second run. Clips are `say` voices reading short sentences; real speech and
> longer windows are not measured.

## Failing open

An empty vocabulary, an absent tokeniser, or one that nothing survives leaves the decoding
options exactly as they would be without any of this. That trade is deliberate: a word missing
from the prompt costs the user a correction, and a dictation refused because a word would not
encode costs them the dictation.

## The `PromptTokenizer` seam

The arithmetic above is checked against a tokeniser a test writes in three lines rather than
against a 646 MB download. Its only real implementation adapts WhisperKit's own and lives in
`WhisperKitBackend.swift`. `firstSpecialToken` is what the special-token filter compares against.

## The prompt is not played back from non-speech

A conditioned decoder given no evidence could continue its prompt, typing the listed words or
the opening sentence from audio that said neither. `uttrflow-eval nonspeech --vocabulary <words>`
conditions every clip of the non-speech corpus on those words and counts a clip as an echo when
the words after the last spoken one are prompt words in prompt order, the opening sentence
included; `--max-echo-rate` gates it.

Measured on Apple M5 Pro with the shipping turbo model, 66 clips (six non-speech kinds, three
seeds each, plus eight `say` sentences in one voice followed by each kind), with 20 invented
names and five words the sentences really say ("bakery", "kettle", "printer", "folder",
"plants"):

| Prompt | Echoed | Inserted | Spoken dictionary words dropped |
|---|---|---|---|
| none | 0 of 66 | 1 of 66 | 0 |
| 20 words | 0 of 66 | 1 of 66 | 0 |

The one insertion is a breath clip in both runs ("The End" with the prompt), so the prompt adds
none. With no echo found, no echo check runs at transcript assembly; the empty-result
retry without the prompt in `CappedDecodeRetry` stays the only prompt-specific recovery.
