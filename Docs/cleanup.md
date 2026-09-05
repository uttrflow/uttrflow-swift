# What the tidier may do to your words

The goal of dictation in Uttrflow is **an accurate transcript of what the speaker said,
cleaned of the noise of speaking and laid out the way they would have typed it.** It is
not a rewrite. The tidier is a filter that removes what was never meant as words and
adds the punctuation and layout that speech leaves implicit. Every word the speaker
meant survives, in the order they said it, in the register they said it in.

This document is the catalogue of what that cleaning consists of, sorted by how sure the
tidier must be before it acts. It was compiled on 5 September 2026 from three places:
what the shipping prompt and `TextTidy` already do, what the evaluation corpus fails on,
and what Wispr Flow, Superwhisper, MacWhisper, Apple's dictation and Dragon do — so the
obvious cases are not missed. Sources are at the end.

## The one rule above the others

**Remove and format; never compose.** The tidier may take words out only when they were
not meant as words (fillers, stammers, false starts, a self-correction's discarded half)
and may add only punctuation and layout. It may not shorten for brevity, change tone,
substitute synonyms, reorder clauses, answer a question, follow an instruction, or
finish a thought. Wispr Flow's "High" formatting level rewrites for brevity; Superwhisper
and MacWhisper let a prompt reshape the text into an email or a summary. Uttrflow does
none of that on the dictation path. A user who wants a rewrite asks for one, and that is
a different feature with a different name.

`MeaningPreservationGuard` is the mechanical form of this rule: a rewrite that drops most
of the words, doubles them, opens with a preamble or invents a number is refused and the
raw transcript is used instead. §9 of the requirements, §19 for the fallback.

## Tier 1 — always, because nothing is lost

Removals of sounds and repetitions that carry no words, and repairs that every reader
would make. Safe in every register.

| Cleaning | Example | Today |
|---|---|---|
| Hesitation sounds | "um", "uh", "er", "erm", "ah", "hmm", "mmm", "aah", "ahh", "mhm", "mm" | ✅ `FillersPass`; whole words only, and never "like", "well", "so" or "basically" |
| Stammers — the same short word twice | "the the deployment" → "the deployment" | ✅ `StammersPass` (≤4 letters; a long repeat is emphasis) |
| Repeated phrase — a false start restarted verbatim | "so I was I was thinking" → "so I was thinking" | ✅ `RepeatedPhrasePass`: a 2–4-word run repeated right after itself, case-insensitive, never across a punctuation mark; the first copy goes |
| Sentence capitalisation and the pronoun "I" | "i think i'll go" → "I think I'll go" | ✅ `FirstWordPass` (also "i'll", "i'm"; a new sentence after `. ! ?`, a paragraph or a bullet, not after a plain line break) and the prompt |
| Terminal punctuation on the last sentence | "ship it" → "Ship it." | ✅ `TerminalStopPass` and the prompt, except when the text holds a newline (dictated code) |
| Whitespace and spacing around punctuation | no space before `, . ? ! : ;`; one after | ✅ `Draft.text` joins words with one space; `SpacingPass` fixes a stray mark onto the word before it and collapses doubled marks |
| Apostrophes in contractions | "dont", "Ill" → "don't", "I'll" | ✅ prompt (as "obvious mis-hearings"); worth a rule |
| Numbers that read as numerals | "fifteen" → "15", "sixteen point two" → "16.2", "nine thousand rupees" → "9000 rupees", "fifteen thousand" → "15,000" | ✅ `NumberFormsPass`. Ten and up always; zero to nine stay words ("one of them") unless inside a number phrase — a decimal, a percentage, a time, a year, or after "port", "version", "page", "chapter", "step", "number" and the like, where digit groups also run together ("port eighty eighty" → "port 8080"). Commas only from 10,000. "a hundred" stays words |
| Times, percentages, ports | "two thirty pm" → "2:30 pm", "ten am" → "10 am", "five o'clock" → "5 o'clock", "five percent" → "5%", "port eight thousand eighty" → "port 8080", "twenty twenty four" → "2024" | ✅ `NumberFormsPass`; an hour (1–12) followed by minutes (10–59) is a time even without am/pm. Dates, money and units are still ❌ and have no corpus case |
| Acronyms and known casing | "api", "json", "https", "ecs" → "API", "JSON", "HTTPS", "ECS" | ✅ prompt (`acronyms` case); the dictionary can pin others |
| Spellings the screen shows | a name in the window title decides "Aarav" over "arav" | ✅ context rule; spelling only, never anything else |
| Personal dictionary spellings | the user's own names and terms | ✅ correction engine, before the tidier |

## Tier 2 — when the speech makes it unambiguous

Edits that change the words on the page, permitted only when the speech itself signals
them. When the signal is missing or could be read two ways, the words stay.

| Cleaning | Signal | Example | Today |
|---|---|---|---|
| Self-correction by trigger phrase | "no", "no sorry", "sorry", "I mean", "actually", "scratch that", "wait", "never mind" between two halves of the same shape | "at four no sorry at five" → "at five"; "coffee at 2 actually 3" → "coffee at 3" | ✅ `SelfCorrectionPass`. The discarded half is removed only when (a) the phrase after the trigger starts with the same word as a suffix of the phrase before it, that suffix being at most six words, inside the sentence, and not anchored on a subject pronoun or an interjection ("I", "we", "it", "that", "yes"…), or (b) both sides are numbers. Otherwise everything stays, the trigger included: "no I don't think so", "I actually enjoyed it" |
| Self-correction by restatement | the same slot said twice with the second replacing the first | "as a gift… as a present" → "as a present" | ❌; only when the two are the same part of speech in the same position |
| Question mark from a question | interrogative shape, a rising tag ("right?", "isn't it?"), or a spoken "question mark" | "can you review the PR" → "Can you review the PR?" | ✅ prompt; ❌ rules. Note Hindi "क्या …" questions |
| Sentence boundaries from pauses and shape | pause plus a new clause that stands alone | "the build passed everything looks good ship it" → "The build passed. Everything looks good. Ship it." | ✅ prompt; rules only cap the first word |
| Commas from pauses and conjunctions | a short pause before "but", "so", "and then", a vocative | "thanks marcy i'll pick up…" → "Thanks Marcy, I'll pick up…" | ✅ prompt |
| Spoken punctuation names | "comma", "full stop"/"period", "question mark", "exclamation mark"/"point", "colon", "semicolon", "open quote … close quote", "hyphen", "dash" | "add milk comma eggs comma and bread" → "add milk, eggs, and bread" | ✅ `SpokenPunctuationPass`. The mark goes on the word before it (a quote opens on the word after; a hyphen joins both sides). Left as a word when it is first, when the word before it is a determiner or a verb of placing ("a", "the", "this", "my", "put", "add", "insert", "with", "no"…), or when "of" follows ("a long period of time") |
| Layout words | "new line", "new paragraph"/"blank line", "bullet point"/"next point" | a newline, a blank line, a list item | ✅ `LayoutWordsPass`, with the same mention guard as spoken punctuation and only between two words — a trailing "new line" stays words. "number one … number two" is still ❌ |
| Lists from spoken sequence | "first … second … third", "one … two … three", "point one …" over several clauses | a numbered or bulleted list, one item per clause | ❌. Wispr Flow builds numbered lists from sequence words. Only when there are at least two items and each is a clause of its own |
| Paragraph breaks | a long dictation with a clear topic shift after a pause, or a spoken "next", "also", "second thing" at the head of a new run | the joined pieces of a long dictation get blank lines between topics | ❌; the pieces cut while recording are joined with a space. A pause long enough to cut at is also a candidate for a paragraph |
| Code identifiers from spoken words | the screen is a code editor and the words name something on it | "warm up all" → "warmUpAll"; "set user prefs" → "setUserPrefs" | ✅ context rule; spelling only, never SQL from prose |
| Trailing full stop dropped in chat apps | the destination is a messaging app and the text is one or two sentences | "on my way" stays "on my way" in WhatsApp | ❌; Wispr Flow does this per app category. A product decision, not a default |
| Lower-case start when inserting mid-sentence | the caret sits after a word with no sentence end before it | "…because " + dictation → "…because the build failed" | ❌; Wispr Flow does. Needs the field's text before the caret, which the context engine can read |

## Tier 3 — never

Removals and additions that lose or invent meaning, however tempting the polish.

- Dropping a word that is not a filler, a stammer or the discarded half of a correction.
  "Like", "well", "so", "basically", "you know", "kind of" are ordinary words far more
  often than they are filler; `TextTidy` deliberately excludes them, and the prompt says
  to keep them. A speaker who says "basically the thing is" gets "Basically, the thing
  is" — the comma, not the deletion.
- Shortening, summarising, "tightening", or rewriting for brevity or tone.
- Replacing a word with a synonym, a stronger verb, or a more formal register.
- Reordering clauses or sentences, however awkward the spoken order.
- Answering a question, obeying an instruction, or commenting. "What is the capital of
  France" is typed as "What is the capital of France?", never as "Paris."
- Adding a greeting, a sign-off, a heading, a summary, or a bullet the speaker did not
  say. A list may be *laid out*, not *composed*.
- Changing the alphabet except Devanagari to the Latin transliteration people type
  ("main aaj", never a translation).
- Inventing or changing a number, date, name, amount or unit.
- Completing a sentence the speaker abandoned. A trailing fragment stays a fragment.
- Correcting a fact, a grammatical choice that is clearly deliberate, or dialect.

## What the corpus says is still wrong

The two cases that defeated every engine, Apple's included — the spoken self-correction
(`self-correction`: "at four no sorry at five") and the spoken version number
(`version-number`: "sixteen point two") — now pass with the model switched off, because
the passes do them before any model is asked. Spoken punctuation, layout words, times,
percentages and ports each have a corpus case and a pass (`RulesCorpusTests` names the
cases the rules must pass). Sequence lists, paragraph breaks, restatement corrections,
mid-sentence casing and chat trailing periods still have no case, so the first step for
each is a case, not a prompt line. `Docs/bakeoff.md` explains why: a prompt line that is
not measured is a guess, and two of the last three guesses made the output worse.

## How this maps onto the code

- `CleaningPipeline.standard` — ten `CleaningPass` values run in order over a `Draft`,
  each recording what it removed or rewrote — is the floor: everything marked ✅ with a
  pass name above, deterministic, and what the user gets when the model declines or
  fails. `RuleBasedTransformer` is nothing but that pipeline. `Docs/cleanup-design.md`
  is the design.
- The generative transformer runs the same passes first, without the casing and the
  final full stop, and hands the model the draft's text — so the fillers and the
  discarded half of a correction are gone before the model can rewrite around them.
- `CleanupPrompt` asks the model for Tier 1 and the parts of Tier 2 marked ✅, with the
  Tier 3 list as prohibitions. Additions go in as one rule and one worked example each,
  measured against the corpus before and after (`make bakeoff ARGS="--baselines-only"`),
  and the examples must not overlap corpus cases (two tests enforce this).
- `MeaningPreservationGuard` polices Tier 3 after the fact, judging the model against
  the words the passes kept, so a pass's removal is never counted as the model dropping
  words.
- `CorrectionEngine` and the dictionary handle spellings before the tidier sees the text.
- The pieces cut while recording (`Docs/early-transcription.md`) are each tidied alone,
  which is why paragraph breaks and list layout have to be decided when the pieces are
  joined, not inside one piece.

## Sources

- Wispr Flow help centre: [Smart Formatting & Backtrack](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack),
  [Flow Styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles),
  [the dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary),
  and the [features page](https://wisprflow.ai/features).
- Superwhisper: [modes and the Aqua Voice comparison](https://superwhisper.com/vs/aqua-voice).
- MacWhisper: [the dictation feature](https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature)
  and a widely shared [clean-up prompt](https://gist.github.com/briansunter/432e1db8746d0146623b7e4c744d9a0c).
- Apple: [dictation commands on Mac](https://support.apple.com/guide/mac-help/use-dictation-mh40584/11.0/mac/11.0),
  and a [command list](https://www.parakeety.com/resources/how-to-dictate-punctuation-on-mac).
- Dragon: [voice command list](https://www.speechlive.com/gb/resources/blog/dragon-voice-commands/).
