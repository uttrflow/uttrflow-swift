# Conditioning Whisper on the user's own words

`VocabularyPrompt` in `Sources/UttrflowSpeech/VocabularyPrompt.swift` turns the personal
dictionary into the prompt Whisper is conditioned on *before* it decodes anything.

This is where a personal dictionary is worth the most. Rewriting "utter flow" to "Uttrflow"
afterwards is a repair, and one that only fires when the recogniser happened to produce
something close enough to match; putting the word in front of the decoder makes it hear the
word.

## The budget is 111 tokens, not 448 and not 224

Not the model's 448-token context, and not half of it either. WhisperKit trims the prompt to
`(Constants.maxTokenContext / 2) - 1`, and `maxTokenContext` is itself `Int(448 / 2)` — 224 —
so the real ceiling is 111.

> WhisperKit 0.18: `Core/TextDecoder.swift:339` for the expression, `Core/Models.swift:1420`
> for the constant.

Truncating here rather than leaving it to the decoder is the whole point. WhisperKit keeps
the *last* 111 tokens and drops the rest without a word, so a vocabulary ranked best-first
would lose precisely the words worth having. It is not a rare case either: `WorkingSet`
offers up to 96 words and a technical word is seldom one token, so the budget usually binds
long before the word count does.

Packing is word by word rather than a truncation mid-sequence: half of `PaymentSheet` in the
prompt biases the decoder towards something the user has never said. A word too long for what
is left is skipped rather than ending the packing, so one forty-token monster cannot cost the
fifty ordinary words ranked behind it. The separator belongs to the word rather than sitting
between words, because dropping a word that will not fit must not leave its comma behind.

Special tokens are filtered out of every piece. WhisperKit discards them itself, so filtering
here as well is what keeps the count being budgeted equal to the count that survives.

## The sentence around the words is the surprise

The words are offered inside `" The words used here are …"`, and that framing is not
decoration — it is the single most surprising thing measured here.

| Prompt                                 | What the decoder heard |
|----------------------------------------|------------------------|
| `Uttrflow Nikhil PaymentSheet`          | "KidPit"               |
| the same words inside the sentence      | "Uttrflow"             |

The sentence worked with three words in the list and again with fourteen. Whisper's prompt is
trained as the *transcript that came before*, so text shaped like a transcript is what it
knows how to condition on; a glossary is not. It is closed with a full stop for the same
reason it is opened like a sentence.

## The forced prefill, and why a prompt otherwise returns nothing

WhisperKit forces a fixed run of tokens through the decoder before the transcript begins:

```
[<|startofprev|>] + prompt + [<|startoftranscript|>, language, task, timestamps]
```

The language and task tokens are absent when the model only knows English.

> WhisperKit 0.18, `Core/TextDecoder.swift:313-342`.

WhisperKit ends a window the moment the sampler predicts the end token — *including* while it
is still force-feeding the prompt, when whatever the sampler produced is thrown away anyway.
Every conditioning prompt trips this and returns an empty transcript. `PromptPrefillGuard` in
`WhisperKitBackend` holds that token shut until `forcedPrefillLength(promptLength:isMultilingual:)`
tokens have gone through.

## Two decoding options that cost something

**`wordTimestamps: true`** is the only way to get a per-word probability out of WhisperKit,
and correction's first condition is that the recogniser was unsure. Measured on the shipping
turbo model:

| Clip length | Added time | Share of the transcription |
|-------------|-----------|-----------------------------|
| 3.3 s       | +4.1 ms   | 0.9%                        |
| 24.3 s      | +19.1 ms  | 1.4%                        |

Cheap enough that the alternative — a constant confidence, making the condition either
vacuous or unsatisfiable — was never worth considering.

**`promptTokens`** is applied once, ahead of the prefill, and re-forced for every 30-second
window: WhisperKit builds the decoder's initial prompt before its seek loop and never
overwrites it, so a two-minute dictation is biased just as strongly at the end as at the
start. It costs the prefill cache and part of each window's decode budget, which is why the
111 tokens are a ceiling rather than a target.

## Failing open

An empty vocabulary, an absent tokeniser, or one that nothing survives leaves the decoding
options exactly as they would be without any of this. That trade is deliberate: a word missing
from the prompt costs the user a correction, and a dictation refused because a word would not
encode costs them the dictation.

## The `PromptTokenizer` seam

The arithmetic above is checked against a tokeniser a test writes in three lines rather than
against a 646 MB download. Its only real implementation adapts WhisperKit's own and lives
beside the recogniser.
