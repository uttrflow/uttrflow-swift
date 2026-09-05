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
| Hesitation sounds | "um", "uh", "er", "erm", "ah", "hmm", "mmm", "aah", "mm-hmm" as a hesitation | ✅ `TextTidy.fillerWords`; extend with "aah", "ahh", "mhm", "huh" (when not a question) |
| Stammers — the same short word twice | "the the deployment" → "the deployment" | ✅ `TextTidy.removeFillers` (≤4 letters) |
| Repeated phrase — a false start restarted verbatim | "so I was I was thinking" → "so I was thinking" | ✅ prompt; ❌ rules (only single words). Extend to 2–4-word repeats |
| Sentence capitalisation and the pronoun "I" | "i think i'll go" → "I think I'll go" | ✅ both |
| Terminal punctuation on the last sentence | "ship it" → "Ship it." | ✅ both, except when the text holds a newline (dictated code) |
| Whitespace and spacing around punctuation | no space before `, . ? ! : ;`; one after | ✅ rules; make the punctuation spacing explicit |
| Apostrophes in contractions | "dont", "Ill" → "don't", "I'll" | ✅ prompt (as "obvious mis-hearings"); worth a rule |
| Numbers that read as numerals | "fifteen" → "15", "sixteen point two" → "16.2", "nine thousand rupees" → "9,000 rupees" | 🟡 prompt does numerals; **version numbers still fail** (`version-number` corpus case) |
| Times, dates, money, units in their written form | "two thirty pm" → "2:30 pm", "five percent" → "5%", "eight thousand eighty" (a port) → "8080" | 🟡 partly; needs cases in the corpus |
| Acronyms and known casing | "api", "json", "https", "ecs" → "API", "JSON", "HTTPS", "ECS" | ✅ prompt (`acronyms` case); the dictionary can pin others |
| Spellings the screen shows | a name in the window title decides "Aarav" over "arav" | ✅ context rule; spelling only, never anything else |
| Personal dictionary spellings | the user's own names and terms | ✅ correction engine, before the tidier |

## Tier 2 — when the speech makes it unambiguous

Edits that change the words on the page, permitted only when the speech itself signals
them. When the signal is missing or could be read two ways, the words stay.

| Cleaning | Signal | Example | Today |
|---|---|---|---|
| Self-correction by trigger phrase | "no", "no sorry", "sorry", "I mean", "actually", "scratch that", "wait", "never mind" between two candidates | "at four no sorry at five" → "at five"; "coffee at 2 actually 3" → "coffee at 3" | ❌ **the corpus case every engine fails.** Wispr Flow: trigger phrases *and* natural restatement, and "actually" is kept when context does not read as a correction |
| Self-correction by restatement | the same slot said twice with the second replacing the first | "as a gift… as a present" → "as a present" | ❌; only when the two are the same part of speech in the same position |
| Question mark from a question | interrogative shape, a rising tag ("right?", "isn't it?"), or a spoken "question mark" | "can you review the PR" → "Can you review the PR?" | ✅ prompt; ❌ rules. Note Hindi "क्या …" questions |
| Sentence boundaries from pauses and shape | pause plus a new clause that stands alone | "the build passed everything looks good ship it" → "The build passed. Everything looks good. Ship it." | ✅ prompt; rules only cap the first word |
| Commas from pauses and conjunctions | a short pause before "but", "so", "and then", a vocative | "thanks marcy i'll pick up…" → "Thanks Marcy, I'll pick up…" | ✅ prompt |
| Spoken punctuation names | "comma", "full stop"/"period", "question mark", "new line", "new paragraph", "open quote … close quote", "hyphen" | "add milk comma eggs comma and bread" → "add milk, eggs, and bread" | ❌. Apple and Dragon do this always; Wispr Flow does. Only when the word is used *as* punctuation, never when mentioned ("put a comma there") |
| Layout words | "new line", "new paragraph", "bullet point", "next point", "number one … number two" | a newline, a blank line, a list item | ❌; MacWhisper's prompt treats these as commands only when clearly instructional |
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

Two cases defeat every engine, Apple's included, and both are Tier 2: the spoken
self-correction (`self-correction`: "at four no sorry at five") and the spoken version
number (`version-number`: "sixteen point two"). Nothing in Tier 2's ❌ column has a corpus
case yet — spoken punctuation, layout words, sequence lists, paragraph breaks,
restatement corrections, mid-sentence casing, chat trailing periods — so the first step
for each is a case, not a prompt line. `Docs/bakeoff.md` explains why: a prompt line
that is not measured is a guess, and two of the last three guesses made the output
worse.

## How this maps onto the code

- `TextTidy` and `RuleBasedTransformer` are the floor: Tier 1 only, deterministic, and
  what the user gets when the model declines or fails.
- `CleanupPrompt` asks the model for Tier 1 and the parts of Tier 2 marked ✅, with the
  Tier 3 list as prohibitions. Additions go in as one rule and one worked example each,
  measured against the corpus before and after (`make bakeoff ARGS="--baselines-only"`),
  and the examples must not overlap corpus cases (two tests enforce this).
- `MeaningPreservationGuard` polices Tier 3 after the fact.
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
