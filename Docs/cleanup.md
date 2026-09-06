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
raw transcript is used instead. Where a draft is available it also holds the grammar
bound of Tier 2: every content word the passes kept must still be there — the same word,
a word grown from the same stem, or another form of the same irregular verb — and the
function words a sentence gains and loses are capped at three. Negation is counted
separately and may never shrink: "not" and the "n't" forms are function words, so
nothing else would have stopped "I do not think we should ship" becoming "I think we
should ship" — a churn of two, well inside the cap. "Never", "no" and "nothing" are
content words and the check above catches those; the count holds them as well. The
words the caret-echo pass takes back after the model answers count as present, since
the model did write them — otherwise a good rewrite is thrown away for a word that is
only missing from the finished text.
A number is read with its thousands separators removed, so "12,000" and "12000" (and
"1,50,000" and "150000") are the same number and a model that drops or adds the comma
is not refused. §9 of the requirements, §19 for the fallback.

## Tier 1 — always, because nothing is lost

Removals of sounds and repetitions that carry no words, and repairs that every reader
would make. Safe in every register.

| Cleaning | Example | Today |
|---|---|---|
| Hesitation sounds | "um", "uh", "er", "erm", "ah", "hmm", "mmm", "aah", "ahh", "mhm" | ✅ `FillersPass`; whole words only, and never "like", "well", "so" or "basically". "mm" is not on the list either: it is millimetres, and "MM" is millions |
| Stammers — the same short word twice | "the the deployment" → "the deployment" | ✅ `StammersPass` (≤4 letters; a long repeat is emphasis). A double the language itself makes is kept — "had had", "that that", "bye bye", "no no", "so so" — and so is a repeated number word, which spells a digit of one value rather than stammering: "extension four four two" is 442, not 42 |
| Repeated phrase — a false start restarted verbatim | "so I was I was thinking" → "so I was thinking" | ✅ `RepeatedPhrasePass`: a 2–4-word run repeated right after itself, case-insensitive, never across a punctuation mark; the first copy goes |
| Sentence capitalisation and the pronoun "I" | "i think i'll go" → "I think I'll go" | ✅ `FirstWordPass` (also "i'll", "i'm"; a new sentence after `. ! ?`, a paragraph or a bullet, not after a plain line break) and the prompt. A word carrying a stop inside itself — "p.m.", "a.m.", "e.g." — does not end a sentence, so "call me at 5 p.m. tomorrow" keeps its "tomorrow" in lower case |
| Terminal punctuation on the last sentence | "ship it" → "Ship it." | ✅ `TerminalStopPass` and the prompt, as the destination's formatter says. Under a `paragraphs` layout (document, email, plain, messaging) the last sentence ends whatever line breaks the text holds, and every paragraph of three or more words before a blank line ends with a full stop; a list item never gets one; under `preserveNewlines` (code, SQL) a text holding a newline gets none; under `singleLine` (a cell) every line break becomes a space |
| Whitespace and spacing around punctuation | no space before `, . ? ! : ;`; one after | ✅ `Draft.text` joins words with one space; `SpacingPass` fixes a stray mark onto the word before it and collapses doubled marks |
| Apostrophes in contractions | "dont", "Ill" → "don't", "I'll" | ✅ `ContractionsPass` and the prompt. Whole words only, and only the ones that are a contraction and nothing else — "dont", "cant", "youre", "thats" and their kind. "Ill" and "Id" are repaired only where the capital says the speaker meant "I", since "ill" and "id" are words of their own; "its", "wed", "were" and "hell" are left alone for the same reason, "it's" being the one the model is trusted with. A capital past the first letter says the word is an acronym rather than a heard contraction, so "the user ID" and "an IM" are left as they are |
| Numbers that read as numerals | "fifteen" → "15", "sixteen point two" → "16.2", "nine thousand rupees" → "9000 rupees", "fifteen thousand" → "15,000" | ✅ `NumberFormsPass`, under the place's `NumberPolicy`. A spreadsheet, a SQL editor and a code editor take `.always` — every number is a numeral, "one of them" → "1 of them". A document, an email, a message and plain text take `.fromTen`: ten and up always; zero to nine stay words ("one of them") unless inside a number phrase — a decimal, a percentage, a time, a year, or after "port", "version", "page", "chapter", "step", "number" and the like, where digit groups also run together ("port eighty eighty" → "port 8080"). Commas only from 10,000. "a hundred" stays words, and so does the whole of a scale phrase the parser cannot read as one number: "about a hundred and fifty users" keeps every word rather than writing only its tail |
| Times, percentages, ports | "two thirty pm" → "2:30 pm", "ten am" → "10 am", "five o'clock" → "5 o'clock", "five percent" → "5%", "port eight thousand eighty" → "port 8080", "twenty twenty four" → "2024" | ✅ `NumberFormsPass`; an hour (1–12) followed by minutes (10–59) is a time even without am/pm. Dates, money and units are still ❌ and have no corpus case |
| Acronyms and known casing | "api", "json", "https", "ecs" → "API", "JSON", "HTTPS", "ECS" | ✅ prompt (`acronyms` case); the dictionary can pin others |
| Spellings the screen shows | a name in the window title decides "Aarav" over "arav" | ✅ context rule; spelling only, never anything else. A word the recogniser was unsure of is also offered the screen's spelling by name — see the doubtful-words row below |
| Personal dictionary spellings | the user's own names and terms | ✅ correction engine, before the tidier; the same lookup also offers the spelling to the model as a reading of a doubtful word |

## Tier 2 — when the speech makes it unambiguous

Edits that change the words on the page, permitted only when the speech itself signals
them. When the signal is missing or could be read two ways, the words stay.

| Cleaning | Signal | Example | Today |
|---|---|---|---|
| Self-correction by trigger phrase | "no", "no sorry", "no wait", "sorry", "wait sorry", "I mean", "actually", "scratch that", "never mind" between two halves of the same shape | "at four no sorry at five" → "at five"; "coffee at 2 actually 3" → "coffee at 3" | ✅ `SelfCorrectionPass`. The discarded half is removed only when (a) the phrase after the trigger starts with the same word as a suffix of the phrase before it, that suffix being at most six words, inside the sentence, and not anchored on a subject pronoun or an interjection ("I", "we", "it", "that", "yes"…), and the half taken back holding at least one word the speaker meant rather than function words alone ("we need to wait to finish" keeps its "wait"), or (b) both sides are numbers. "Wait" alone is not a trigger — it is a verb far more often than a correction, so it is heard as one only in "no wait" and "wait sorry". Otherwise everything stays, the trigger included: "no I don't think so", "I actually enjoyed it". The same rule (`Restatement`, shared, not copied) runs once more at each piece boundary when the pieces are joined, so "let's meet at four" | "no sorry at five" becomes "Let's meet at five." — there the full stop the piece before was given is read through, being an artefact of cleaning each piece alone rather than a sentence the speaker ended |
| Self-correction by restatement | a slot said twice over, each time with a different word after it | "as a gift as a present" → "as a present"; "on tuesday on wednesday" → "on wednesday" | ❌ asked of the model, which does not do it; ❌ rules, and deliberately so. A deterministic rule reads only the shape — a short frame of function words repeated with a different content word after each copy — and that shape is a list at least as often as it is a correction: "I'll pay for lunch for everyone", "coffee with milk with sugar", "the meeting is on Monday on Zoom" all match it, and the floor was deleting the first half of each. What separates "as a gift, as a present" from those is which of the two the speaker meant to stand, and that is semantic. So the floor now acts only on a trigger phrase (the row above) and the model is asked for the rest: one line of the contract and one worked example. **Measured 2026-09-06: the model does not comply.** "I wanted to buy a record as a gift as a present" and "let's meet on tuesday on wednesday afternoon" both come back whole. So this cleaning is asked for and delivered by nothing; the words stay, which is the side of the line this product errs on, but nothing here works yet |
| Question mark from a question | interrogative shape, a rising tag ("right?", "isn't it?"), or a spoken "question mark" | "can you review the PR" → "Can you review the PR?" | ✅ prompt; ❌ rules. Note Hindi "क्या …" questions |
| Sentence boundaries from pauses and shape | pause plus a new clause that stands alone | "the build passed everything looks good ship it" → "The build passed. Everything looks good. Ship it." | ✅ prompt; rules only cap the first word |
| Commas from pauses and conjunctions | a short pause before "but", "so", "and then", a vocative | "thanks marcy i'll pick up…" → "Thanks Marcy, I'll pick up…" | ✅ prompt |
| Spoken punctuation names | "comma", "full stop"/"period", "question mark", "exclamation mark"/"point", "colon", "semicolon", "open quote … close quote", "hyphen", "dash" | "add milk comma eggs comma and bread" → "add milk, eggs, and bread" | ✅ `SpokenPunctuationPass`. The mark goes on the word before it (a quote opens on the word after; a hyphen joins both sides). Left as a word when it is first, when the word before it is a determiner or a verb of placing ("a", "the", "this", "my", "put", "add", "insert", "with", "no"…), or when "of" follows ("a long period of time"). "Period", "comma" and "dash" are nouns too, and a modifier hides the determiner that says so, so the lookback reaches three words for a determiner proper — "during the trial period", "the 100 metre dash" — stopping at any word that is itself a mark's name, which is what keeps "did you finish the trial period question mark" ending in a question mark. A verb of placing counts only immediately before the word, so "add milk comma eggs" still takes its comma, and a hyphen, which joins the two words around it rather than heading a phrase, reads only one word back. "full stop" and "period" are used only where the text closes — as the last word, or before "new line"/"new paragraph"/"bullet point" or "close quote" — so "the trial period ended last week" keeps its word and "ship it period" ends with a stop; a mid-sentence "period" stays a word and the model places the stop from the pause. "hyphen" and "dash" are the mirror: used only where the text does not close, since both need a word to follow |
| Layout words | "new line", "new paragraph"/"blank line", "bullet point"/"next point", "number one" … "number two" | a newline, a blank line, a list item, a numbered item | ✅ `LayoutWordsPass`, with the same mention guard as spoken punctuation, reading one word back only (a layout phrase heads no noun phrase, so "the update new paragraph" is not a mention), and only between two words — a trailing "new line" stays words. A model's answer is read the same way: a line opening with `-`, `•` or `*` and a space is a list item, so each item takes a capital and no stop. "number one … number two" is ✅ too, and is the one phrase whose mark the word after it decides rather than the table: the number is read by `NumberWords`, the same table `NumberFormsPass` sits on, so "number twenty one" opens item 21 and "number two thirty" is not taken for the time 2:30. Nothing is numbered from zero, so "number zero" stays words. A numbered item is a list item on the same terms as a bulleted one — a capital and no stop. The mention guard carries the whole weight of telling an item from a designator, and one word of lookback is not always enough for it: "the number one problem" and "my number one priority" are left alone, but "flight number 447 is delayed" is not, and a lead-in is what separates them. |
| Lists from spoken sequence | "first … second … third", "one … two … three", "point one …" over several clauses | a numbered or bulleted list, one item per clause | ✅ `PieceJoiner`, over the pieces a long dictation is cut into (`Docs/early-transcription.md`), since only their seams show the sequence. The items run from the piece that opens with "first" or "one" — "number one", "point two", "item three", "step four" too — to the last piece, each carrying the next number of the same kind, ordinals and cardinals never mixed. Two items at least, and each of them a clause: two words or more after the sequence word, not opening on a determiner. The sequence word goes, the item takes a capital, a `- ` and no stop. Everything short of that stays prose — a lone "first", a run that stops before the last piece ("first… second… and then the other thing"), a run that does not start at one, an item that only names a thing ("first, the milk"). Where the formatter has no `.lists` — messaging, spreadsheet, code, SQL — the words stay prose whatever they count |
| Paragraph breaks | a long dictation with a clear topic shift after a pause, or a spoken "next", "also", "second thing" at the head of a new run | the joined pieces of a long dictation get blank lines between topics | ✅ `PieceJoiner`. A piece boundary is a pause the speaker made, so when the next piece opens on a topic — an ordinal ("second thing", "third"), or "also", "next", "okay so", "another thing", "one more thing", "moving on", "finally", "anyway", "additionally", "furthermore", "lastly" — and the formatter's layout has `.paragraphs`, the join is a blank line instead of a space. Otherwise a space. Never inside a list, never where a restatement swallowed the opening, and never in a cell, whose `.singleLine` keeps the whole dictation on one line |
| Code identifiers from spoken words | the screen is a code editor and the words name something on it | "warm up all" → "warmUpAll"; "set user prefs" → "setUserPrefs" | ✅ `ScreenCandidates` offers the identifier by name when the recogniser was unsure of the run, so the model is choosing between two spellings rather than being asked to notice one; spelling only, never SQL from prose |
| Doubtful words — the reading the place decides | the recogniser scored the run below `WordCorrectionEngine.certaintyThreshold` (0.5) **and** a source offered another reading | "the crash is in payment sheet" → "PaymentSheet" in Xcode, "payment sheet" in Slack; "clear the cash" → "clear the cache" over `Cache.swift` | ✅ three `CandidateSource`s, asked at once, under 2 ms for a whole dictation: the personal dictionary by sound (the correction engine's own lookup), the screen — the window title, the selection and the text either side of the caret, matched by Double Metaphone or by the same letters with the spaces closed up — and ordinary words that sound alike **and open alike** over `GeneralVocabulary`. At most five spans per piece and three readings per span go into the prompt's "Doubtful words:" line; the model picks the one that fits the sentence and the place, or keeps the word as heard, and `MeaningPreservationGuard` refuses a rewrite that wrote anything else. Fires only where the recogniser reported real per-word scores (`Draft.confidencesAreReal`) |
| Grammar slips, in places whose formatter repairs them | the destination's `GrammarPolicy` is `.repair` (document, email, plain) and the slip is one speech leaves behind: agreement, a participle, an article or preposition, a tense that drifts | "there is three of them" → "There are three of them"; "we have went" → "we have gone"; "a apple" → "an apple" | ✅ prompt block per destination, bounded: a fix changes only the form of a word the speaker said, or adds or removes an article or a preposition — never which content words are present or their order. Dialect and informality are not slips and stay ("gonna", "ain't", "me and him", "didn't do nothing" — a double negative is dialect). `MeaningPreservationGuard` enforces the bound on the draft's kept words, and the rules never repair, so the floor leaves every slip alone (`rulesLeaveGrammarAlone`) |
| Trailing full stop dropped in chat apps | the destination is a messaging app and the text is one or two sentences | "on my way" stays "on my way" in WhatsApp | ✅ `TerminalStopPass` under `DestinationFormatter` for `.messaging`, `.offForShortMessages(2)`; a question or exclamation mark is always kept. Decided by the app's bundle identifier, so Electron apps count |
| Lower-case start when inserting mid-sentence | the caret sits after a word with no sentence end before it | "…because " + dictation → "…because the build failed" | ✅ `FirstWordPass` from `InsertionPoint.sentenceState`, read off the field's text before the caret; "I", its contractions and acronyms keep their capital. A model that repeats the text before the caret at the head of its answer has that echo taken back by `CaretEchoPass` — the whole preceding text of two or more words, or the tail the prompt quoted, case and punctuation aside; never a partial match. Electron apps (Slack, Discord, VS Code) do not report their field, so there the state is `unknown` and the first word stays capital |

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
- Correcting a fact, dialect, or a grammatical choice that is clearly deliberate. Only
  the slips in Tier 2's grammar row are repaired, only where the formatter says so, and
  never by changing which words were said — a double negative is dialect, not a slip.

## What the corpus says is still wrong

The two cases that defeated every engine, Apple's included — the spoken self-correction
(`self-correction`: "at four no sorry at five") and the spoken version number
(`version-number`: "sixteen point two") — now pass with the model switched off, because
the passes do them before any model is asked. Spoken punctuation, layout words, times,
percentages and ports each have a corpus case and a pass, and the four cases that name
a destination pass through the same passes under that destination's formatter
(`RulesCorpusTests` names every case the rules must pass). The cases where the screen has to decide a
spelling are the model's alone and are now handed the identifier by name rather than
being left to notice it — which fixed `editor-identifier-casing` and
`code-editor-identifier-from-screen`, and did not fix the rest. Sequence lists and
paragraph breaks still have no case, so the first step for each is a case, not a prompt
line. `Docs/bakeoff.md` explains why: a prompt line that is not
measured is a guess, and two of the last three guesses made the output worse.

**Seven cases fail on the shipping configuration, measured 2026-09-06 and left failing
rather than papered over.** `sql-editor-identifier-from-screen`,
`editor-selected-identifier` and `slack-name-spelling` — spellings the screen shows and
the model still will not take. `spreadsheet-number-in-cell` — the model writes `12000`
where the passes wrote `12,000`. `message-question-keeps-its-mark` and `plural-slip` —
the model drops a question mark and will not pluralise "two more developer", and no
prompt wording tried has moved either. `sql-editor-totals`. Each is a case that failed
honestly; none is a rule waiting to be written.

## Where the words are going

Two of the Tier 2 cleanings depend on the place rather than the speech, and the design
in `Docs/cleanup-design.md` gives that place a name. `Situation` is what the screen said
when the key went down, read once per dictation within the context engine's 100 ms
budget: the app, an `InsertionPoint` — up to 300 characters before the caret and 100
after, from the focused field's value and selected range — and a `Destination`
(`document`, `spreadsheet`, `sqlEditor`, `codeEditor`, `messaging`, `email`, `plain`).
The destination is read off one table, `DestinationRules.standard`, by bundle
identifier prefix or window title; no code branches on a bundle identifier anywhere
else. `DestinationFormatter.registry` holds one value per destination and, so far, four decisions:
how the first word is cased, whether the last sentence gets a full stop, whether grammar
slips are repaired (`.repair` for a document, an email and plain text; `.asSpoken`
everywhere else), and the layout
(`paragraphs` and `lists` for a document or an email, `paragraphs` alone for a message
or plain text, `preserveNewlines` for code and SQL, `singleLine` for a cell). A first
word lowered mid-sentence keeps its capital when it is "I", an acronym, or looks like a
name: the same word is capitalised off a sentence start elsewhere in the output, or in
the window title, the selection or the text around the caret — a text capitalised
throughout, as a title-cased document name is, says nothing. A name spoken once and
absent from the screen is still lowered; the personal dictionary is where that closes.
Both transformers apply those two policies last, through `FirstWordPass` and
`TerminalStopPass`, and the corpus cases that name a
destination (`message-two-sentences-no-stop`, `mid-sentence-continues-lower-case`,
`spreadsheet-cell-no-stop`, `document-sentence-with-stop`) are scored on the literal
beginning and ending of the output, because the word scorer folds case and punctuation
away.

A field the app will not describe — every Electron app, in the probe — gives an
`unknown` insertion point, which is treated as the start of a sentence: today's
behaviour. The destination still comes through, because the bundle identifier costs no
permission at all.

## How this maps onto the code

The design that generalises all of it — `Situation`, `Formatter`, `CleaningPass`, `Draft`,
one model call per piece — is `Docs/cleanup-design.md`. Below is where things are today.

### Today

- `CleaningPipeline.standard(for:situation:)` — ten `CleaningPass` values run in order
  over a `Draft`, each recording what it removed or rewrote — is the floor: everything
  marked ✅ with a pass name above, deterministic, and what the user gets when the model
  declines or fails. `RuleBasedTransformer` is nothing but that pipeline for the
  request's formatter and caret.
- `SituationResolver` turns the context read into a `Situation`; `FirstWordPass` and
  `TerminalStopPass` carry the `DestinationFormatter` policies, and are the only place
  either decision is made — last in the rules pipeline, and again after the model as
  `CleaningPipeline.afterModel(for:situation:heard:)`, where `CaretEchoPass` first takes
  back a repeated "Text before the caret".
- The generative transformer runs the same passes first, without the casing and the
  final full stop, and hands the model the draft's text — so the fillers and the
  discarded half of a correction are gone before the model can rewrite around them.
- `PromptBuilder` gives the model its instructions in three layers, each a separate
  piece of data. The **contract** (`PromptContract`, one string and ten worked examples)
  is the same everywhere: the goal, Tier 1 and the parts of Tier 2 marked ✅, the two
  restraints the model still needs spelled out ("never invent or change a name, number,
  date or amount", "when unsure, keep the original wording"), how to read the "Typed
  into:" line (spelling only) and the "Text before the caret:" line (continue the
  sentence, repeat nothing, close nothing), then the examples the bake-off showed were
  load-bearing: a question, a plain sentence, an injection typed as dictation, a slot the
  speaker said twice over, the two Hindi ones, a name off a chat title, an identifier off
  nearby text, a SQL-editor sentence that stays prose, and a continued sentence after a
  caret. The Tier 3
  never-list was tried as a contract sentence and made Apple's model passive — it
  stopped capitalising, punctuating and spelling from the screen — so the prohibitions
  live in the guard and the examples, not the wording. The **formatter block**
  (`PromptBlocks`, one `PromptBlock` per `PromptBlockID`, named by
  `DestinationFormatter.promptBlock`) is that place's two to four style rules and at
  most two worked examples of its own, only where its layout or final stop differs from
  the contract's examples — a message example teaches "no trailing stop", a code example
  teaches line breaks, a cell example teaches one line, a document example a list, an
  email example paragraphs; plain text and the SQL editor add none. The **situation
  block** is built per request by `PromptBuilder.userPrompt(for:spoken:doubtful:)`: the
  "Typed into:" line, the last 120 characters before a mid-sentence caret, the
  "Doubtful words:" line, then the spoken words. No destination's instructions exceed
  the size of the single prompt they replaced by more than a tenth (a test holds the
  number; the tenth paid for the shared examples), and the contract sentence teaching
  the model what to do with a doubtful-words line was paid for by trimming contract
  prose rather than by raising it.
  Additions go in as one rule and one worked example each, measured against the corpus
  before and after (`make bakeoff ARGS="--baselines-only"`, which now reports pass rates
  by destination), and no block's examples may overlap a corpus case (two tests enforce
  this over every block).
- `GenerativeTextTransformer` warms the model for the destination the dictation is going
  to — `DictationPipeline` reads the screen before it warms, and warms for plain text when
  the screen says nothing — because the model keeps one pre-warmed session keyed by the
  instructions it was given.
- `DoubtfulWords` asks the three `CandidateSource`s at once for the runs the recogniser
  half-heard, and `GenerativeTextTransformer` puts their readings in the same model call
  the cleaning already makes — never a second call and never a second model.
- `MeaningPreservationGuard` polices Tier 3 after the fact, judging the model against
  the words the passes kept, so a pass's removal is never counted as the model dropping
  words, and against the readings it was offered: a doubtful run must come back as it
  was heard or as one of them.
- `CorrectionEngine` and the dictionary handle spellings before the tidier sees the text.
- The pieces cut while recording (`Docs/early-transcription.md`) are each tidied alone,
  which is why paragraph breaks and list layout have to be decided when the pieces are
  joined, not inside one piece.

## What the app shows and lets you change

Three surfaces, so a word that went missing can be accounted for rather than guessed at.

- **Diagnostics names what each step did to the last dictation.** Under "Clean-up steps,
  last dictation" there is a row per step that changed something — "Filler words: removed
  3: um, uh, um", "Numbers: rewrote 1: fifteen → 15" — and a grey row for each step that
  is switched off, because a step that is off is why a word the user expected to go is
  still there. It is read off the finished draft's own record of which pass touched which
  word (`CleaningRecord`), so it cannot claim a removal nothing made. `DictationPipeline`
  collects one account per piece where it already reports the stage timings and hands the
  merged account to `DiagnosticsRecorder`, which keeps the last one and only the last.
  Nothing is written to disk or sent anywhere; the **Copy Diagnostics** report counts the
  words rather than quoting them, because that string is pasted somewhere else. Only the
  steps Settings offers are listed, so the section reads the same whether the model
  answered or declined and cannot be read backwards into which engine ran, and a row names
  the first four words and counts the rest. A reset that clears the transcripts clears this
  too (`DiagnosticsRecorder.forget()`): the page must not still be holding the words the
  user asked the app to forget.
- **A step can be switched off.** Settings → Dictation → "Clean-up steps" offers the nine
  deterministic steps, all on by default, stored as the set that is *off*
  (`Settings.cleaning`) so a step a later build adds is on for everybody who never said
  otherwise. `CleaningPipeline.standard(for:situation:steps:)` builds only the ones left
  on. `FirstWordPass` and `TerminalStopPass` are not offered: they carry the formatter's
  decisions about the place, not a cleaning the user asked for, and `CleaningSteps` drops
  them from a stored set rather than trusting it.
- **An app can be treated as somewhere else.** Settings → Dictation → "Where your words
  go" names the app the last dictation went into and offers every kind of place, plus
  "Work it out", which is the table. A choice is stored against the bundle identifier
  (`Settings.destinations`) and `DestinationClassifier` consults the overrides before the
  table; every override made is listed underneath with a button that puts it back. The
  table itself is never edited — an override is one app the user disagreed with Uttrflow
  about. The app named is the last one dictated into rather than the frontmost, because
  while the settings window is open the frontmost app is Uttrflow.

All three take effect on the next dictation, not the next launch: `DictationPipeline.adopt`
takes a freshly built cleaner and the overrides as they now stand. The next dictation
literally: a dictation under way keeps the cleaner and the overrides it began with, so a
step switched off while the user is speaking cannot treat the second half of what they say
differently from the first.

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
