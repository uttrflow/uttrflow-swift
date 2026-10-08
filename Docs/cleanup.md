# What the tidier may do to your words

The goal of dictation in Uttrflow is **an accurate transcript of what the speaker said,
cleaned of the noise of speaking and laid out the way they would have typed it.** It is
not a rewrite. The tidier is a filter that removes what was never meant as words and
adds the punctuation and layout that speech leaves implicit. Every word the speaker
meant survives, in the order they said it, in the register they said it in.

This page is the catalogue of what that cleaning consists of, sorted by how sure the
tidier must be before it acts. The deterministic passes live in `Sources/UttrflowAI/Passes/`
over the `Draft` and `CleaningPass` types in `Sources/UttrflowCore/Cleaning/`; the model's
prompt is `PromptBuilder`, `PromptContract` and `PromptBlocks` in `Sources/UttrflowAI/`; the
check that holds the model to this page is `MeaningPreservationGuard`; and the pieces of a
long dictation are joined by `PieceJoiner` in `Sources/UttrflowPipeline/`. The design behind
those types is `Docs/cleanup-design.md`.

## Latin letters only

**Uttrflow writes English/Latin script only. Hindi and Hinglish speech is romanised the way
people type it, never written in Devanagari and never translated.** "हाँ ठीक है" becomes
"Haan thik hai." on every path: a model's rewrite, the rules, and words no tidier touched.
`Docs/latin-output.md` has the romaniser, the guard and the measurements.

## The one rule above the others

**Remove and format; never compose.** The tidier may take words out only when they were
not meant as words (fillers, stammers, false starts, a self-correction's discarded half)
and may add only punctuation and layout. It may not shorten for brevity, change tone,
substitute synonyms, reorder clauses, answer a question, follow an instruction, or
finish a thought. Uttrflow does none of that on the dictation path. A user who wants a
rewrite asks for one, and that is a different feature with a different name.

`MeaningPreservationGuard` is the mechanical form of this rule: a rewrite that drops most
of the words, doubles them, opens with a preamble or invents a number is refused and the
rules' answer is used instead. Where a draft is available it also holds the grammar
bound of Tier 2: every content word the passes kept must still be there — the same word,
another form of it (a plural, a past, a progressive, or a form of the same irregular
verb), or the word spelled into an identifier at one of its own word boundaries — **and in
the order it was said in**, which is what carries Tier 3's ban on reordering. The kept
content words are walked along the rewrite, each taking the earliest place still open,
and a word whose only place lies behind one already taken has been moved rather than
tidied. Several spoken words may share one place, because one identifier can spell them
all ("fetch invoices" written as `fetchInvoices`).

The function words a sentence gains and loses are capped at three per sentence of the
rewrite, counted the way `FirstWordPass` counts sentences — a word carrying a stop inside
itself ends none, so "call me at 5 p.m. tomorrow" is one sentence. Negation is counted
separately and may never shrink or grow: "not" and the "n't" forms are function words, so
nothing else would stop "I do not think we should ship" becoming "I think we should ship" —
a churn of two, well inside the cap. "Never", "no" and "nothing" are content words and the
survival check catches those; the count holds them as well. The words `CaretEchoPass`
takes back after the model answers count as present, since the model did write them.

A spoken ampersand is held as a symbol: the model may not spell it out as "and" or write
"and" as an ampersand. A number is read with its thousands separators removed, so "12,000"
and "12000" (and "1,50,000" and "150000") are the same number. The guard's numbers and the
failures behind each check are in `Docs/ai-model-output.md`.

## Tier 1 — always, because nothing is lost

Removals of sounds and repetitions that carry no words, and repairs that every reader
would make. Safe in every register.

| Cleaning | Example | How |
|---|---|---|
| Hesitation sounds | "um", "uh", "er", "erm", "ah", "hmm", "mmm", "aah", "ahh", "mhm" | `FillersPass` (`fillerWords`); whole words only, and never "like", "well", "so" or "basically". Standalone "mhm" and "hmm" are replies, and spaced "uh huh", "uh oh" and "mm hmm" are kept as "Uh-huh", "Uh-oh" and "Mm-hmm". The word is read as every other pass reads one — `WordShape.key`, so "E.R." is not the spelling "er" at all — and a determiner before "er" or "erm" means the noun was meant rather than the sound: "I took her to the ER" keeps its noun, "er, I think so" loses its filler. The lookback is the same `MentionGuard` the spoken marks use |
| Stammers — the same function word twice | "the the deployment" → "the deployment" | `StammersPass`. Only a function word stammers, because a doubled content word is emphasis ("very very", "chop chop", "hear hear"), a name ("Bora Bora"), or a digit of one value rather than a stammer — "extension four four two" is 442, not 42. The function words English doubles on purpose are kept by name (`legitimateDoubles`: "had had", "that that", "so so", "there there"), and a repeat split by punctuation is left alone, the comparison being on the word as it is written. A function word English also emphasises still loses a copy — "this this", "what what" — because the restart reading is the commoner one and the pass has only the word to go on. The same holds for "is": "what it is is a problem" loses its second "is", because a pseudo-cleft and "the build is is red" have the same shape at word level |
| Bare-hyphen cut-off completed by the next word | "th- the" → "the", "w- we" → "we" | `SelfCorrectionPass`; the cut-off is removed only when `WordForms.sameForm` confirms the next word completes it, including inflected restarts such as "go- went". Hyphenated words and spoken "dash" are not cut-offs |
| Repeated phrase — a false start restarted verbatim or in a recognised incomplete clause | "so I was I was thinking" → "so I was thinking"; "I went to the I'll call you later" → "I'll call you later" | `RepeatedPhrasePass`: a 2–4-word run repeated right after itself, case-insensitive, never across punctuation; the first copy goes. It also removes a short incomplete prefix at a clause boundary when a new subject and predicate restart it: an unfinished destination ("I went to the"), "let me", "was going to", a repeated-subject question start ("can we we should"), and the named-topic restart ("the problem is what I wanted to say is"). It keeps complete lookalikes such as "I said I'd go" and "She was going to the store". A run said twice on purpose is left alone on the same terms as the stammer row — one word filling the window ("ha ha ha ha", "no no no no"), or a run of content words and nothing else, which is a name said twice ("New York New York") rather than a restart. A run of function words is removed, so "it is what it is what it is" loses a copy |
| Sentence capitalisation and the pronoun "I" | "i think i'll go" → "I think I'll go" | `FirstWordPass` (also "i'll", "i'm"; a new sentence after `. ! ?`, a paragraph or a bullet, not after a plain line break) and the prompt. A word carrying a stop inside itself — "e.g.", "etc." — does not end a sentence, so "use tools, e.g. a hammer" keeps its "a" in lower case. A meridiem after a clock time in digits is written "am" or "pm" in every form it arrives in ("5 P.M.", "7:30 a m"), by `SpelledInitialismPass`. The first word's case is read from its own place in the text |
| Technical tokens keep their written case | "config.yaml is missing." stays "config.yaml is missing." | `TechnicalToken.classify` in `UttrflowCore` names a token as a URL, path, file name, host, version or identifier, and `WordShape.capitalised` and `WordShape.lowercased` leave it as written. A host or file name needs a known ending, so recogniser glue such as "okay.thanks" and abbreviations such as "e.g." are still capitalised; "and/or" is not a path |
| Spelled initialisms | "a p i" → "API", "i e" → "i.e." | `SpelledInitialismPass` joins adjacent spoken letter names, emits `e.g.` and `i.e.` with stops, and leaves an article "a" alone unless it begins a longer initialism such as "a p i" → "API". A lone "I" stays the pronoun except beside other letter names. Letters then digits spoken as one code are written as one token ("e c one a one b b" → "EC1A1BB", "z 999" → "Z999"), and "v" or "x" before a dotted number takes no space ("v 2.1"); one bare letter beside one number word stays as words ("b seven", "a two hour drive") |
| Terminal punctuation on the last sentence | "ship it" → "Ship it." | `TerminalStopPass` and the prompt, as the destination's formatter says. Under a `paragraphs` layout (document, email, plain, messaging) the last sentence ends whatever line breaks the text holds, and every paragraph of three or more words before a blank line ends with a full stop; a list item never gets one; under `preserveNewlines` (code, SQL) a text holding a newline gets none; under `singleLine` (a cell, a terminal) every line break becomes a space. "Does this already end?" is read off the word's suffix rather than its last character, so a sentence ending in a symbol — `5%`, `20°`, `$5` — is finished like any other, and the stop goes inside a closing quote (`she said "ship it."`). A clause mark, an ellipsis or a bracket the words closed themselves already ends the text, and a quotation opening and closing on one word (`"hello"`) is a quoted term rather than a sentence, so it takes none |
| The mark on a word that goes | "so are we shipping today, uh?" → "So are we shipping today?" | `Draft.remove(at:by:carryingMarks:)`, used by `FillersPass`, `StammersPass`, `RepeatedPhrasePass` and `SelfCorrectionPass`. The recogniser hangs a sentence's mark on whatever word it ended on, so a removed word hands its mark on rather than taking it away. Closing marks move back onto the word before, opening marks forward onto the word after, and two marks meeting are merged by `WordShape.marked`, so a clause mark replaces one already there. A comma is the exception: it is the pause the removed word stood in, so it goes with the word, which leaves "we should, uh, ship it" with no comma at all. The comma before it stays when the sentence owns it — after its first word, or beside a discourse word such as "yes", "well", "okay" or "yeah" — so "Well, um, I think so." becomes "Well, I think so." while "The deadline is, um, Friday." loses both. A currency sign or a percent sign is part of the amount rather than the sentence, so it leaves with the word: "$40, no wait, $50" becomes "$50", not "$$50". No mark crosses a line break |
| Whitespace and spacing around punctuation | no space before `, . ? ! : ;`; one after | `Draft.text` joins words with one space; `SpacingPass` moves a stray mark onto the word before it and collapses doubled marks |
| Apostrophes in contractions | "dont", "Ill" → "don't", "I'll" | `ContractionsPass` and the prompt. Whole words only, and only the ones that are a contraction and nothing else — "dont", "cant", "youre", "thats", "youll", "theyll", "theyve", "youve", "wouldve", "couldve", "shouldve", "mightve", "mustnt", "neednt", "yall", "oclock" and their kind. "Ill" and "Id" are repaired only where the capital says the speaker meant "I", since "ill" and "id" are words of their own. "Its" becomes "it's" before a determiner, a negation or a form such as "been" and "going"; "its own" and "its colour" stay possessives. "whats", "whos", "wheres" and "hows" become contractions only when the next word makes that reading clear ("whats up" → "what's up"); "the whats and whys" stays. A bare plural before a noun is left alone: "dogs bowl" cannot say whether one dog or several own the bowl. A capital past the first letter says the word is an acronym rather than a heard contraction, so "the user ID" and "an IM" are left as they are |
| Numbers that read as numerals | "fifteen" → "15", "sixteen point two" → "16.2", "nine thousand rupees" → "9000 rupees", "fifteen thousand" → "15,000" | `NumberFormsPass`, under the place's `NumberPolicy`. A spreadsheet, a SQL editor, a code editor and a terminal take `.always` — every number is a numeral, "one of them" → "1 of them". A document, an email, a message and plain text take `.fromTen`: ten and up always; zero to nine stay words unless inside a number phrase — a decimal, a percentage, a time, a year, money, or after "port", "version", "page", "chapter", "step", "number" and the like, where digit groups also run together ("port eighty eighty" → "port 8080"). An immediately preceding "negative" or "minus" joins a numeral as its sign ("negative fifteen" → "-15"); a small number that stays words keeps its sign word too. How the numeral is written is a separate decision, the destination's `DigitGrouping`: `.thousands` puts commas in from 10,000; a SQL editor, a code editor and a terminal take `.none`, since "12,000" is a row constructor to Postgres and does not compile in Swift. "a hundred" stays words, and so does the whole of a scale phrase the parser cannot read as one number: "about a hundred and fifty users" keeps every word rather than writing only its tail |
| Times, percentages, ports, dates | "two thirty pm" → "2:30 pm", "ten am" → "10 am", "five o'clock" → "5 o'clock", "five percent" → "5%", "port eight thousand eighty" → "port 8080", "twenty twenty four" → "2024", "twenty fifth of March" → "25th of March", "March twenty fifth" → "March 25", "forty second floor" → "42nd floor" | `NumberFormsPass`; an hour (1–12) followed by minutes (10–59) is a time even without am/pm. A relative clock phrase keeps every word and only takes the number policy: "half past two" stays "half past two" (or "half past 2" where every number is a numeral), "twenty past four" is "20 past four", never "2:30" or "4:20", which would state numbers nobody said. Dates accept spaced or hyphenated ordinals before a month, with optional "of", and bare ordinals after a month, under the destination's number policy. Days must fit the month (February allows 29 without a year). Bare "May" and "March" need the month's capital; after "of", matching is case-insensitive. Ambiguous and invalid date-shaped ordinals stay intact. Outside dates, compound ordinals from 21 onward become suffixed numerals; one-word ordinals stay words. Money in the currencies the pass knows (`currencies`: dollars, euros, rupees) is a numeral at any size, and so is an amount before a noun in `measures`: other currencies and units with no second meaning ("five yen" → "5 yen", "three kilometres" → "3 kilometres"). Words with another meaning, such as "pound", "feet" and "second", are left out, so "give me a second" keeps its words |
| Acronyms and known casing | "api", "json", "https", "ecs" → "API", "JSON", "HTTPS", "ECS" | `PromptContract`: the shared instruction uppercases acronyms while preserving technical terms, illustrated by the `fbi` worked example. The rules do not uppercase acronyms mid-sentence. The dictionary can pin other spellings |
| Place, language and nationality casing | "london", "french", "germans" → "London", "French", "Germans" | `FirstWordPass` cases single-word English language and region names from Foundation's ISO data, plus explicit city, state and nationality names, and "New York" as a phrase. Ambiguous common nouns "china" and "turkey" stay lower-case; code, terminal and spreadsheet destinations keep the case spoken |
| Spellings the screen shows | "arav" → "Aarav" only when the recogniser is unsure and the two spellings open alike | the screen candidate source; spelling only, never anything else — see the doubtful-words row below |
| Personal dictionary spellings | the user's own names and terms | `WordCorrectionEngine`, before the tidier; a run of several words is taken only by an entry that spells it closed up or opens as it does, so a mishearing that loses its opening needs a recorded pronunciation. The same lookup also offers the spelling to the model as a reading of a doubtful word. Thresholds: `Docs/ai-correction-thresholds.md` |

`Homophones` is the hand-kept list of spellings with the same spoken sound, including common
contractions such as "its" and "it's". Two spellings have the same sound when the CMU
Pronouncing Dictionary lists, for each, a pronunciation identical to the other's phoneme for
phoneme, stress marks ignored and no vowel reduced. "then" (`DH EH1 N`) and "than" (`DH AE1 N`,
`DH AH0 N`) fail it; "accept" (`AH0 K S EH1 P T`) and "except" (`IH0 K S EH1 P T`) fail it
too, and would pass only if unstressed vowels were reduced, which the definition does not do.
"affect" (`AH0 F EH1 K T`) and "effect" (third listing `AH0 F EH1 K T`) pass it, but the list
is hand-kept and does not hold them, so no source offers one for the other.

### Sound key against phoneme distance

`uttrflow-eval pronunciation-keys [--lexicon <cmudict.dict>] [--words <frequency list>]` scores
the shipped chain (Double Metaphone key, opening letters, the ordinary-word veto and
`Homophones`) against weighted phoneme edit distance (a vowel for a vowel or a voicing pair
costs 0.5, any other edit 1), with the pronouncing dictionary as the oracle. Distance and
lookup are `PhonemeLexicon`, the one implementation the probe and the candidate sources share;
it reads the bundled [pronunciation lexicon](pronunciation-lexicon.md) when `--lexicon` is
omitted. With no frequency list the pair set is every bundled word (38,151; 19,803 homophone
pairs, 855,101 pairs within distance 1):

| Metric | key alone | shipped chain | phoneme distance <= 1 |
|---|---|---|---|
| Homophone recall | 93.3% | 60.4% | 100% |
| Neighbour recall | 32.4% | 7.0% | 100% |
| Pairs offered | 974,195 | 122,619 | 874,904 |
| Offered pairs within distance 1 | 30.4% | 58.5% | 100% |
| Offered pairs two or more phonemes apart | 45.2% | 18.6% | 0% |

The earlier run on the 9428 of the 10,000 most frequent English words the full dictionary lists
gave the same order: homophone recall 81.8% key, 46.7% chain; neighbour recall 20.4% and 4.8%;
27.0% of the chain's pairs two or more phonemes apart.

Phoneme distance wins on every recall and precision row, so it is the path the candidate sources
move to; the key, `opensAlike`, the veto and `Homophones.groups` are deleted in that change.
Distance 1 offers about 23 neighbours a word, so the sources still rank and cap what they offer.
Lookup goes through a one-edit index: each pronunciation is filed under its phoneme-class
sequence (the classes of `phoneme-classes.txt`: the vowels, each voicing pair) and every sequence one class
shorter. Within distance 1 there is at most one full-cost edit and a half-cost substitution keeps
the class, so two such words always share a key; the probe checks the index against brute force
on 200 words and finds 0 misses. Reading and indexing the bundled file takes 133 ms once; a
lookup takes p50 0.078 ms and p95 0.268 ms over all 38,151 words (release build, Apple M5 Pro,
load average near 70), inside the 5 ms the doubtful-word candidate step is budgeted in
[performance-dictation.md](performance-dictation.md). Precision here is measured against the
pronouncing dictionary, not against what users meant.

## Tier 2 — when the speech makes it unambiguous

Edits that change the words on the page, permitted only when the speech itself signals
them. When the signal is missing or could be read two ways, the words stay.

| Cleaning | Signal | Example | How |
|---|---|---|---|
| Self-correction by trigger phrase | "no", "no sorry", "no wait", "sorry", "wait sorry", "I mean", "actually", "actually make it", "scratch that", "strike that", "or rather", "correction", "never mind" between two halves of the same shape, or a pause-marked single-word correction; the romanised Hindi triggers "nahi nahi", "galat bola" and comma-paused "mera matlab" or "matlab" act only before a repeated number phrase | "at four no sorry at five" → "at five"; "the blue sorry green" → "the green"; "coffee at 2 actually 3" → "coffee at 3"; "chaar baje nahi nahi paanch baje" → "paanch baje" | `SelfCorrectionPass` over `Restatement` (`triggers`). The Hindi triggers act only when a number and its following phrase repeat; ordinary negation and an unpaused "mera matlab" stay. Other triggers remove the discarded half only when (a) the phrase after the trigger starts with the same word as a suffix of the phrase before it, that suffix beginning within twelve words before the trigger (six for a number), inside the sentence and reaching back over a word said twice when the phrase after the trigger opens on that word said twice ("git push dash dash force no wait dash dash force dash with dash lease" takes back "dash dash force no wait"), and not anchored on a subject pronoun or an interjection ("I", "we", "it", "that", "yes"…, and the Hindi ones in both scripts: "main", "hum", "wo", "ye", "मैं", "वो"…, so "main late hoon sorry main abhi aata hoon" keeps its apology), the half taken back holding at least one word the speaker meant rather than function words alone ("we need to wait to finish" keeps its "wait"), and the word before that suffix being neither the trigger over again nor another answer the trigger answers ("yes" against "no", "thanks" against "sorry") — which makes the trigger the head of each item of a list rather than a correction, so "I said no to the offer, no to the meeting", "I said yes to the offer, no to the meeting" and "there's no room, no room at all" keep both halves; or (b) both sides are numbers; or (c) one content word immediately before "sorry" or an explicit correction phrase is replaced by a content word after it; or (d) a bare "actually" or "no" replaces a content word only when a comma marks a pause after that word. So "the weather actually improved overnight", "sales actually grew last quarter", "she gave no reason" and "he said no thanks to the offer" keep their ordinary words. "Wait" alone is not a trigger — it is a verb far more often than a correction, so it counts only in "no wait" and "wait sorry". Otherwise everything stays, the trigger included: "no I don't think so", "I actually enjoyed it". The same rule runs once more at each piece boundary when the pieces are joined, so "let's meet at four" \| "no sorry at five" becomes "Let's meet at five." — there `PieceJoiner` strips the earlier piece's trailing stop before asking `Restatement.discardedStart` and restores it if nothing matched, since that stop is an artefact of cleaning each piece alone |
| Self-correction by restatement | a slot said twice over, each time with a different word after it | "as a gift as a present" → "as a present"; "on tuesday on wednesday" → "on wednesday" | Not done. The rules leave it alone on purpose: a short frame of function words repeated with a different content word after each copy is a list at least as often as a correction ("coffee with milk with sugar", "the meeting is on Monday on Zoom"), and telling them apart is semantic. The model is asked for it, by one line of the contract and one worked example, and does not comply: both examples come back whole, so the words stay |
| Question mark from a question | interrogative shape, a rising tag ("right?", "isn't it?"), or a spoken "question mark" | "can you review the PR" → "Can you review the PR?" | `TerminalStopPass` finishes a prose sentence that asks by its word order with "?" instead of "." (`QuestionShape`): a question word before its verb with no subject between, including a question word followed by an auxiliary before its subject ("what time is it", "how are you"); a verb before a subject or determiner — "do" and "have" only before a pronoun, since they also start commands; an address name before an inverted clause ("papa, are you around"), never a subject pronoun or demonstrative treated as a name ("that is it"); a negative tag such as "isn't it"; a positive tag after a subject and its verb ("the build passed is it", "you sent it did you"), while an agreement ("so did I") or a pronoun complement ("the answer is it") stays a statement; Hindi "kya" before a pronoun or after a verb, and an unembedded Hindi question word in the main clause (including "tum kab aaoge" and "naam kya hai", while embedded or reported content cued by "pata", "ki", "know" or "said" stays a statement); or a subject and predicate followed by "right", where the tag takes a comma while "turn right" and "that's right" stay statements. A subject-first clause such as "what I mean is we should wait" is not a question. It runs after the model too, so a question the model hands back bare is finished as one. A question word straight before a word that takes a determiner reads that word as its verb ("who owns the notification service"); a question-word clause that is the subject of a later verb ("what works for you is fine") stays a statement. Not read: a bare "right" tag and a question run together with a second clause ("are you around yet I should be there"), which keeps its full stop because where the question ends cannot be told. Code, SQL and cells never get one |
| Review label said first | "nit", "minor", "optional", "suggestion" or "question" opens the dictation and heads a clause | "question why is this async" → "Question: why is this async?" | `TerminalStopPass` sets the label off with a colon (`ReviewTag`), and `QuestionShape` judges the clause after a colon on its own. A noun label ("nit", "suggestion", "question") is set off unless the next word continues it ("question for you", "question is whether…"); an adjective label ("minor", "optional") only before a word that opens a clause and never follows an adjective — a pronoun, a determiner, a question word or an auxiliary — so "minor changes only" stays a sentence. Not read: an adjective label before an imperative ("minor rename this") |
| Exclamation mark only on evidence | a spoken "exclamation mark"/"point", or a "!" the recogniser already wrote | "that is a great idea" → "That is a great idea."; "that is amazing exclamation point" → "That is amazing!" | The rules never add one: `SpokenPunctuationPass` writes the spoken name and `TerminalStopPass` finishes with "." or "?" only. The model is told the same, and `MeaningPreservationGuard.textVerdict` refuses a rewrite with more "!" than the kept words (`RefusalKind.inventedExclamation`), because excitement is tone and the transcript carries no tone. No list of exclamatory forms earns one: each is said flat as often as excited |
| Sentence boundaries from pauses and shape | pause plus a new clause that stands alone | "the build passed everything looks good ship it" → "The build passed. Everything looks good. Ship it." | `PauseStopPass` ends a sentence where the recogniser timed a silence of `SpeechWindowing.sentencePause` (0.8 s, the pause that also ends a piece) between two words of one piece, unless `SentenceBoundaryEvidence` shows the sentence carrying on ("finish the … report" keeps going). A stop after "on", "in", "up" or "around" is taken back when the words up to the next stop have no verb by the on-device tagger, read in context, and do not open on a pronoun or interjection — "failed on. Again this morning", "on. A4 paper" — unless an object pronoun precedes it, as in "turn it on", which closes a phrasal verb, and the fragment does not open on a person or place name ("see you in. Boston next week"); a fragment the tagger cannot read keeps its stop. It writes no stop into code, a terminal, SQL or a cell. The word timings travel from the recogniser through `TranscribedWord.start`/`end` to `Draft.Word`, and a dictionary correction keeps the span of the words it replaced. Text with no timing, as typed into `uttrflow-dev clean`, has no pause to read, so a run-on there is the prompt's to split. `SentenceBoundaryPass` takes a full stop back where the boundary evidence shows the sentence running on |
| Commas from pauses and conjunctions | a short pause before "but", "so", "and then", a vocative | "thanks marcy i'll pick up…" → "Thanks Marcy, I'll pick up…" | the prompt |
| Spoken punctuation names | "comma", "full stop"/"period", "question mark", "exclamation mark"/"point", "colon", "semicolon", "open quote … close quote", "quote … unquote"/"end quote", "open single quote … close single quote", "open/close parenthesis" or "parentheses", "open/close bracket", "hyphen", "dash" | "add milk comma eggs comma and bread" → "add milk, eggs, and bread" | `SpokenPunctuationPass`. The mark goes on the word before it (a quote opens on the word after; a hyphen joins both sides), which is what each row's kind records — `.trailing`, `.joining`, `.opening`, `.closing` — and a quotation is an `.opening` row and a `.closing` row. A bare "quote" opens only when "unquote", "end quote" or "close quote" follows it in the sentence with a word between, and "unquote" closes only inside an open quotation, so "can you quote me a price" and "the so called quote unquote expert" keep their words. "bracket" is `[`; "parenthesis" is `(`. A double quote opened inside an open double quote is written single, and every close writes the quote still open, so "she said open quote he told me open quote ship it close quote today close quote" is `she said "he told me 'ship it' today"`; depth is read within one piece. The first word inside a quotation keeps the case it was heard in. Quotes are straight (`"` and `'`) in every destination: code, terminal and SQL need them straight, and no destination asks for curly ones. Each half is still resolved on its own, because a quotation spoken across a pause has its halves in two pieces. A two-word name is read only where both its words sit in one sentence, so "the glass was full. Stop worrying about it" keeps its words. A name stays a word when it is first — except an opening quote, which goes on the word after it — when the word before it is a determiner or a verb of placing ("a", "the", "this", "my", "put", "add", "insert", "with", "no"…), or when "of" follows ("a long period of time"). "Period", "comma" and "dash" are nouns too, and a modifier hides the determiner that says so, so the lookback reaches three words for a determiner proper — "during the trial period", "the 100 metre dash" — stopping at any word that is itself a mark's name and at any word that ends a sentence, which keeps "did you finish the trial period question mark" ending in a question mark. A verb of placing counts only immediately before the word, so "add milk comma eggs" still takes its comma, and a hyphen reads only one word back. "full stop" and "period" are used only where the text closes — as the last word, or before "new line"/"new paragraph"/"bullet point" or "close quote" — so "the trial period ended last week" keeps its word and "ship it period" ends with a stop. "hyphen" and "dash" are the mirror: used only where the text does not close. **"comma", "colon" and "dash" need positive evidence as well**, because each is an everyday noun that modifies the word after it — "colon cancer", "comma separated values", "dash cam" — and no determiner stands in front to refuse them. One of the three is a mark only where it stands at a seam: the text closes after it, including when a corroborated numbered list opens later in that piece, the word before already carries a mark, the word after is one of `FunctionWords`, or the same name is said again in the sentence, which is a list. A final ordinary name with a word before it is read as a mark, because a dictation ending with "period", "comma" or "colon" is a format request. So "if the tests pass comma we ship", "done comma" and "apples comma pears comma plums" take their marks, while "screened for colon cancer" and "sprint dash training" keep their words. Evidence is read inside the piece, never across pieces. What the rule cannot see is a function word after a mention, as in "screened for colon and rectal cancer". A spoken long option marker ("dash dash", "double dash") names no single mark, so a verb of placing before it does not make it a mention; a determiner just before it does when the word after it is one of `FunctionWords`, which can name no option ("make a double dash across the yard"), and does not when that word can ("a dash dash dry dash run flag" → "a --dry-run flag"). Otherwise a command line reads the marker as an option, and prose reads one before a word that can name an option as opening the option and every dash after it in the sentence, as a program's name does ("tag the commit with dash dash sign" → "tag the commit with --sign"), and one before a function word as the clause dash ("we went home dash dash it was late" → "we went home — it was late") |
| Spoken email addresses | a local part, "at", and a domain whose last label is an ending the pass knows | "forward the logs to support at example dot com" → "forward the logs to support@example.com" | `SpokenAddress`, read by `SpokenPunctuationPass`: "at" is a mark said by name like the rest. The domain carries most of the decision — two labels or more, every label letters, digits, hyphens or underscores, and the last one in `SpokenAddress.topLevels`, a hand list because an unknown ending has to be refused rather than guessed at. A spoken "dot" between the parts is written as a dot inside that span and nowhere else, which is why "dot" is not a mark name in its own right. A local part that says for itself that it is an address — more than one label, or a digit, hyphen or underscore inside one — needs nothing further; a plain word needs an announcing word within two content words before it ("email", "send", "forward", "copy", "cc", "write", "contact", "reach", "address"…) or an address already written in the same sentence, which carries the second address of "write to info at example dot com and billing at example dot net". A determiner immediately before the local part refuses it (`MentionGuard.phraseOpeners`), so "please send the report at example.com", "look at example.com" and "we met at the office at five" keep their words. Only the two ends of the address may carry marks, so `TerminalStopPass` finishes "email me at sam at example dot com" as "Email me at sam@example.com." The pass converts rather than deletes, so the words it drops sit inside its own `.conversion` grant. Left as words: a spoken "dash" inside a local part (that is the em dash), an address dictated in another language, and a plain local part whose announcing word stands further back than two content words |
| Chat mentions | a messaging destination, and "at" opens the message or a clause (nothing before the caret, or a stop, comma, colon or semicolon just before) and is followed by a capitalised name of letters alone | "at Sam can you take a look" → "@Sam, can you take a look?" | `AtMentionPass`, a message-wide pass after acronym casing. A possessive ("at Sam's place"), a calendar word ("at Monday"), an "at" inside a clause ("ping me at Sam") and every other destination keep the word. `FirstWordPass` leaves a word holding "@" in the case it was written |
| Layout words | "new line", "new paragraph"/"blank line", "bullet point"/"next point", "number one" … "number two" | a newline, a blank line, a list item, a numbered item | `LayoutWordsPass`, with the same mention guard as spoken punctuation, reading one word back only (a layout phrase heads no noun phrase, so "the update new paragraph" is not a mention), and only between two words — a trailing "new line" stays words. A phrase, and the number after "number", are read only where they sit in one sentence, so "I bought something new. Line up here" keeps its words. A model's answer is read the same way: a line opening with `-`, `•` or `*` and a space is a list item, so each item takes a capital and no stop. The number after "number" is read by `NumberWords`, so "number twenty one" opens item 21 and "number two thirty" is not taken for the time 2:30; nothing is numbered from zero. Inside its sentence a numbered item needs **corroboration**: another item numbered one either side of it said in the same piece, so "we need number one milk number two eggs" is a list and "ring number 5 now", "flight number 447 is delayed" and "room number 5 is free and so is room number 7" keep their words, because a list is never one item long; the mention guard refuses "the number one problem" first. The run must also follow a lead-in rather than a running clause, and a colon before its first item always makes one, so "before you release: number one run it number two ship it" is a list. What it cannot see is two consecutive designators, "room number 5 and room number 6", which reads as a list. A phrase that **opens its sentence** has no lookback to ask, so there it is layout only when the speaker set it off with a mark: "number one is broken" stays words whether or not a sentence comes before it, while "here is the plan. number one, fix the build" is an item. At the head of the text an item's number or bullet is written without the line break in front of it, and "new line" or "new paragraph" stays words. A list cut across pieces is `PieceJoiner`'s |
| Lists from spoken sequence | "first … second … third", "one … two … three", "point one …" over several clauses | a numbered or bulleted list, one item per clause | `PieceJoiner`, over the pieces a long dictation is cut into (`Docs/early-transcription.md`), since only their seams show the sequence. The items run from the piece that opens with "first" or "one" — "number one", "point two", "item three", "step four" too — to the last piece, each carrying the next number of the same kind, ordinals and cardinals never mixed. Two items at least, each a clause: two words or more after the sequence word, not opening on a determiner. A bare cardinal counts what follows it as readily as it announces an item, so it has to carry an announcing word ("number one", "point two") or be set off by a mark — "One, fix the build" opens a list and "One bug is still open" does not. An ordinal never counts, so "First we fix the build" needs neither. The sequence word goes, the item takes a capital, a `- ` and no stop. Everything short of that stays prose — a lone "first", a run that stops before the last piece, a run that does not start at one, an item that only names a thing ("first, the milk"). Where the formatter has no `.lists` — messaging, spreadsheet, code, SQL, terminal — the words stay prose |
| Paragraph breaks | a long dictation with a clear topic shift after a pause, or a spoken "next", "also", "second thing" at the head of a new run | the joined pieces of a long dictation get blank lines between topics | `PieceJoiner`. A piece boundary is a pause the speaker made, so when the next piece opens on a topic — an ordinal ("second thing", "third"), or "also", "next", "okay so", "another thing", "one more thing", "moving on", "finally", "anyway", "additionally", "furthermore", "lastly" — and the formatter's layout has `.paragraphs`, the join is a blank line instead of a space. Never inside a list, never where a restatement swallowed the opening, and never in a cell |
| Code identifiers from spoken words | the screen is a code editor and the words name something on it | "warm up all" → "warmUpAll"; "set user prefs" → "setUserPrefs" | `ScreenCandidates` offers the identifier by name when the recogniser was unsure of the run, so the model chooses between two spellings rather than being asked to notice one; spelling only, never SQL from prose. In a code editor outside a comment, `SpokenCasingPass` writes spoken identifier-casing commands and `CodeEditorCommandsPass` symbol commands |
| Doubtful words — the reading the place decides | the recogniser scored the run below `DoubtPolicy.certaintyThreshold` (0.5) **and** a source offered another reading | "the crash is in payment sheet" → "PaymentSheet" in a code editor, "payment sheet" in a chat; "clear the cash" → "Clear the Cache" over `Cache.swift` | `DoubtfulWords` asks every `CandidateSource` at once: the personal dictionary by sound (`DictionaryCandidates`, the correction engine's own lookup), the screen — the window title, the selection and the text either side of the caret (`ScreenCandidates`) — ordinary words as `GeneralVocabulary` defines them ([ordinary-words.md](ordinary-words.md)) (`PhoneticCandidates`), and a word's partner in `Homophones` (`HomophoneCandidates`). None offers where the heard word is in `FunctionWords` (a there/their or on/one swap changes what was said, not how it is spelt). The sources that read words nobody taught ask `ReadingRestraint`: a reading must **open alike** as well as sound alike (`openingLettersShared`, two letters), because Double Metaphone keeps only a word's first vowel and so files made, mid, mod, mad, mood and mud under one key. Spelling the run with its spaces closed up is the one match exempt from it, since that is what reaches `PaymentSheet` from "payment sheet". The screen, the shipped technical terms and the ordinary-words source all apply one **ordinary-word veto**: an ordinary word is no reading of another ordinary word (`ReadingRestraint.isOrdinaryCollision`), because the screen is evidence of *presence* and an ordinary word is present on every screen — `main` in every Go file says nothing about whether "mean" or "main" was said. The veto is lifted only for pairs in `Homophones`, so `Cache.swift` still offers "Cache" for a spoken "cash" and "here" is still offered for "hear", while "man" and "many" are not offered for "main" and a screen showing `mad` is not offered for "made". A said-alike pair nobody wrote into `Homophones` is one these sources will not offer. The personal dictionary is exempt from the restraint for a single word: a word the user taught is evidence in its own right, and `WordCorrectionEngine` applies one word for one word with no opening rule ("fil" for Phil). A **run of several words** is gated: `WordCorrectionEngine.spells` lets an entry take it only when the entry — its spelling or its recorded pronunciation — spells the run closed up or passes `ReadingRestraint.opensAlike`, because at a length where the blast-radius cap allows two changes, an entry on screen plus several words becoming one clears the evidence margin ("the salt air well enough" would become "the salt URL enough"). The cost is the mishearing that loses its opening across several words: "cooper netties" reaches Kubernetes only through a pronunciation recorded on the entry. `Scripts/loose_match_audit.py` does not see this use, because the prefix comparison lives inside `ReadingRestraint`. Each source caps what it offers (`maximumOffered`: two, one for homophones), and at most `DoubtfulWords.maximumSpans` (five) spans per piece and `maximumCandidatesPerSpan` (three) readings per span go into the prompt's "Doubtful words:" line. The model picks the one that fits the sentence and the place, or keeps the word as heard, and `MeaningPreservationGuard` refuses a rewrite that wrote anything else. Fires only where the recogniser reported real per-word scores (`Draft.confidencesAreReal`) |
| Grammar slips, in places whose formatter repairs them | the destination's `GrammarPolicy` is `.repair` (document, email, plain) and the slip is one speech leaves behind: agreement, a participle, an article or preposition, a tense that drifts | "there is three of them" → "There are three of them"; "we have went" → "we have gone"; "a apple" → "an apple" | the prompt block per destination, bounded: a fix changes only the form of a word the speaker said, or adds or removes an article or a preposition — never which content words are present or their order. A form of "be" changes only within its tense ("we was" → "we were", never "is" → "was"). Dialect and informality are not slips and stay ("gonna", "ain't", "me and him", "didn't do nothing" — a double negative is dialect). A second-language speaker's forms get no separate rule: a slip in this row is repaired within the same bound in a `.repair` destination, and in every other destination it stays as spoken, as `EvaluationCorpus.secondLanguage` pins for messaging. `MeaningPreservationGuard` enforces the bound on the draft's kept words, and the rules never repair, so the floor leaves every slip alone (`rulesLeaveGrammarAlone`) |
| Trailing full stop dropped in chat apps | the destination is a messaging app and the text is one or two sentences | "on my way" stays "on my way" in a chat app | `TerminalStopPass` under `DestinationFormatter` for `.messaging`, `.offForShortMessages(sentences: 2)`; a question or exclamation mark is always kept. Decided by the app's bundle identifier, so Electron apps count. The length is read off the whole message, not a piece of it: a piece is cleaned at `CleaningScope.piece`, which runs neither `FirstWordPass` nor `TerminalStopPass`; `PieceJoiner` ends every seam as a sentence the way the place ends one, and the cleaner's `finishMessage` runs both passes once over the joined message, so the short-message rule counts the sentences the message has. See `Docs/cleanup-design.md` §7 |
| Lower-case start when inserting mid-sentence | the caret sits after a word with no sentence end before it — read off the line the caret is on, so a list marker, a heading marker or an opening quote or bracket the user typed is not mistaken for a word | "…because " + dictation → "…because the build failed" | `FirstWordPass` from `InsertionPoint.sentenceState`, read off the field's text before the caret; "I", its contractions and acronyms keep their capital. A model that repeats the text before the caret at the head of its answer has that echo taken back by `CaretEchoPass` — the whole preceding text of two or more words, or the tail the prompt quoted, case and punctuation aside; never a partial match — and a closing bracket or quote the model added to match an opener before the caret is taken back by `CaretCloserPass`. Electron apps do not report their field, so there the state is `unknown` and the first word stays capital |

Dictionary overrides keep the recogniser’s original word confidence separate from the evidence supporting a replacement. After a dictionary reading is applied, its transcription word is marked settled so downstream correction and meaning guards do not reopen it. Timed words also retain the audio span covered by the corrected reading.

### Correction triggers as data

The trigger phrases are rows of `Sources/UttrflowCore/Resources/Tables/correction-triggers.json`,
each with its `language` and the `evidence` it needs before anything is taken back
(`alignedHalves`, `alignedHalvesPausedSingleWord`, `restatedNumber`,
`pausedRestatedNumber`). `Restatement` reads one table for English and romanised Hindi; a new
phrase is a row, never a Swift literal. Romanised Hindi rows are "nahi nahi", "galat bola"
(a restated number), and comma-paused "mera matlab" and "matlab". "ya phir" is not a trigger:
it offers an alternative more often than it corrects one. A number on either side of a trigger
is read the same way whether it is a digit, an English word or a romanised Hindi word, so
"chai do cup no wait three cup" takes back "do cup". `CorrectionTriggerTableTests` holds 34
Hinglish sentences with a correction and 34 with the same words said plainly, and fails when a
row has no case of either kind. Measured on the table as shipped: 29 of 34 corrections apply
and no plain sentence loses a word; the 5 that do not apply are listed in `owedTriggerCases`
until a fix makes them pass.

## Tier 3 — never

Removals and additions that lose or invent meaning, however tempting the polish.

- Dropping a word that is not a filler, a stammer or the discarded half of a correction.
  "Like", "well", "so", "basically", "you know", "kind of" are ordinary words far more
  often than they are filler; `FillersPass` excludes them, and the prompt says to keep
  them. A speaker who says "basically the thing is" gets "Basically, the thing is" — the
  comma, not the deletion.
- Shortening, summarising, "tightening", or rewriting for brevity or tone.
- Replacing a word with a synonym, a stronger verb, or a more formal register.
- Reordering clauses or sentences, however awkward the spoken order.
- Answering a question, obeying an instruction, or commenting. "What is the capital of
  France" is typed as "What is the capital of France?", never as "Paris."
- Adding a greeting, a sign-off, a heading, a summary, or a bullet the speaker did not
  say. A list may be *laid out*, not *composed* — and the guard enforces that half against
  the destination's own `LayoutPolicy`, so a list the model writes is refused anywhere the
  formatter does not lay lists out, and a break it adds is refused where there are no
  paragraphs to add one to.
- Changing the alphabet, except writing Devanagari in the Latin letters people type ("main
  aaj", never "मैं आज" and never a translation). That one change is not optional: it is made on
  every path, by the rules as well as the model (`Docs/latin-output.md`).
- Inventing or changing a number, date, name, amount or unit.
- Completing a sentence the speaker abandoned. A trailing fragment stays a fragment.
- Correcting a fact, dialect, or a grammatical choice that is clearly deliberate. Only
  the slips in Tier 2's grammar row are repaired, only where the formatter says so, and
  never by changing which words were said.

## Which cases the rules must pass

`RulesCorpusTests` names every corpus case the rules must pass with the model switched off —
the spoken self-correction, the spoken version number, spoken punctuation, layout words,
times, percentages, ports, the paragraph-break cases and the numbered-list matrix among them —
and that list, not this page, is the record of what the floor covers. Spellings the screen has
to decide are the model's alone. A gap gets a corpus case before it gets a prompt line, because
a prompt line that is not measured is a guess (`Docs/bakeoff.md`).

Which layer owns each formatting class — `rules`, `model` or `both` — is
`FormattingClass.ownership`, and `Docs/formatting-matrix.md` prints it beside each class's
cases. Under `both`, the passes after the model have the last word. `FormattingOwnershipTests`
fails a class whose named pass no shipped pipeline runs. `PromptLineTags` tags every bullet
line of the contract and each block with the classes it asks for; `PromptLineTagsTests` fails an
untagged line, and the lines that still ask the model for a `rules` class are a set that never grows.

## Words spelled letter by letter

A speaker spells a name, a code or a file name so that it is written exactly as spelled. The
recogniser already writes a spelled word as upper-case letters joined by hyphens, and that is
the intended output: cleaning leaves it as written.

| Shape spoken | Intended output | Why |
|---|---|---|
| Spelled name or word ("T A V I S H") | left as the recogniser wrote it, `T-A-V-I-S-H` | Joining needs the word's case, which the letters do not carry; the name is usually said beside it |
| Spelled code with digits ("K 7 Q 2 9 X") | upper-case code, `K7Q29X` | The recogniser writes it joined; nothing to do |
| Doubled letters ("double L", "double R") | the letter twice, as the recogniser writes it | Already expanded before cleaning |
| Phonetic alphabet ("M as in Mike", "Bravo Echo") | left as spoken | Not consistent enough to read: "as in" survives, and bare code words come back as separate sentences |
| Spelled file name ("R E A D M E dot t x t") | left as the recogniser wrote it, `readme.txt` | Already joined |

No rule is added: no shape is both left wrong by the recogniser and consistent enough to read.
One cleaning regression was measured: in "A as in Alpha" the spelled letter loses its capital
("a as in Alpha"), because the article "a" and the letter name are one spelling.

Measured on an Apple M5 Pro with `say -v Samantha` clips at 16 kHz, then
`uttrflow-dev transcribe --raw -l en` (the shipping WhisperKit model) and
`uttrflow-dev clean -e rules`:

| # | Spoken | Recogniser | After cleaning |
|---|---|---|---|
| 1 | my name is Tavish, that's T A V I S H | My name is Tavish. That's T-A-V-I-S-H. | unchanged |
| 2 | her surname is spelled M-O-R-L-A-N-D | Her surname is spelled M-O-R-L-N-D. | unchanged |
| 3 | the code is B as in boy, seven four | The code is B as in boy. 7-4. | unchanged |
| 4 | the file is called R E A D M E dot txt | The file is called readme.txt. | unchanged |
| 5 | the booking reference is K 7 Q 2 9 X | Booking references K7Q29X. | unchanged |
| 6 | it's M as in Mike, A as in Alpha, R as in Romeo, A as in Alpha | It's M as in Mike, A as in Alpha, R as in Romeo, A as in Alpha. | It's M as in Mike, a as in Alpha, R as in Romeo, a as in Alpha. |
| 7 | spell it Bravo Echo Lima Tango | Spell it. Bravo. Echo Lima. Tango. | unchanged |
| 8 | that's Callum with a C, C A double L U M | That's Callum with a C, C-A-L-L-U-M. | unchanged |
| 9 | the street is spelled O, double R, I, N | The street is spelled O-R-R-I-N. | unchanged |
| 10 | the ticket is J R A dash four one two | Ticket is JRA-412. | unchanged |
| 11 | my username is Z O R I N 8 8 | My username is Z-O-R-I-N-A-D-A-T. | unchanged |
| 12 | the city is spelled E L D R A V I A | The city is spelled E-L-D-R-A-V-I-A. | unchanged |

The recogniser's own errors (a dropped letter in 2, "8 8" heard as letters in 11) are
recognition, not cleaning, and are out of reach of any rule here. Synthetic voices spell more
evenly than people do, so a recorded human set may still change these shapes.
## Dictation that reads like a request

Dictation that sounds addressed to the model is still dictation, and its expected text is the
tidied words. `RequestCorpus.swift` holds at least eight invented cases for each class in
`RequestClass`: questions (factual, personal, rhetorical), imperatives to an assistant,
"ignore" and "system:" forms, text that names an output format, labels, quotes and fences said
or added, polite requests, Hindi and Hinglish requests in both scripts, one- and two-word
inputs, and text that invites a refusal. Each case carries the output of a model that commits
one `RequestFailure` (obeyed, answered, translated, wrapped, refused), and
`RequestMatrixTests` fails when a guard on the case does not catch that output.

## Where the words are going

Two of the Tier 2 cleanings depend on the place rather than the speech, and
`Docs/cleanup-design.md` gives that place a name. `Situation` is what the screen said when
the key went down, read once per dictation within the context engine's 100 ms budget: the
app, an `InsertionPoint` — up to 300 characters before the caret and 100 after
(`precedingLimit`, `followingLimit`), from the focused field's value and selected range — and
a `Destination` (`document`, `spreadsheet`, `sqlEditor`, `codeEditor`, `terminal`,
`messaging`, `email`, `plain`).

The destination is read off one table, `DestinationRules.standard`, by bundle identifier
prefix, window title or a whole word of the application name; nothing outside
`DestinationClassifier` turns an application into a destination or an `AppKind`, and the only
table read ahead of it is the user's own `DestinationOverrides`. Other modules read a bundle
identifier for their own questions — `SuggestionApplications.offByDefault` in
`UttrflowPredict` names two editors — and none of them decides where the words are going.
`Tests/UttrflowCoreTests/OneAppTableTests.swift` keeps that true: every reverse-DNS literal
anywhere in `Sources` must be one `DestinationClassifier` has an answer for, and its `owed`
list may shrink and may never grow. A row also names the `AppKind` it covers — finer than the
destination, since Notes and a document editor both resolve to `document` but read
differently in the prompt — and that kind is where the "Typed into:" caption comes from, so
the caption and the style block cannot name two different places (`Docs/ai-context-line.md`).

`DestinationFormatter.registry` holds one value per destination:

| Destination | `firstWord` | `terminalStop` | `layout` | `grammar` | `numbers` | `digits` |
|---|---|---|---|---|---|---|
| document | `.fromInsertionPoint` | `.always` | paragraphs, lists | `.repair` | `.fromTen` | `.thousands` |
| spreadsheet | `.asSpoken` | `.never` | singleLine | `.asSpoken` | `.always` | `.thousands` |
| sqlEditor | `.fromInsertionPoint` | `.always` | preserveNewlines | `.asSpoken` | `.always` | `.none` |
| codeEditor | `.fromInsertionPoint` | `.never` (`.always` in a comment) | preserveNewlines | `.asSpoken` | `.always` | `.none` |
| terminal | `.asSpoken` | `.never` | singleLine | `.asSpoken` | `.always` | `.none` |
| messaging | `.fromInsertionPoint` | `.offForShortMessages(sentences: 2)` | paragraphs | `.asSpoken` | `.fromTen` | `.thousands` |
| email | `.fromInsertionPoint` | `.always` | paragraphs, lists | `.repair` | `.fromTen` | `.thousands` |
| plain | `.fromInsertionPoint` | `.always` | paragraphs, lists | `.repair` | `.fromTen` | `.thousands` |

`DestinationFormatter.standard(for: Situation)` adjusts that value for the field: a row of the
table may carry its own `terminalStop`, an `AXSearchField` or a field of a row marked
`field: .search` keeps the heard casing and takes no stop, and an `AXTextField` or any field Accessibility reports as single-line takes
`singleLine`.

A first word lowered mid-sentence keeps its capital when it is "I", an acronym, or looks like
a name: the same word is capitalised off a sentence start elsewhere in the output, or in the
window title, the selection or the text around the caret — a text capitalised throughout, as
a title-cased document name is, says nothing. A name spoken once and absent from the screen
is still lowered; the personal dictionary is where that closes.

The recogniser opens a transcript it closes as a sentence on a capital, and that capital says
nothing about the word. So when the transcript ends on a stop, a question mark or an
exclamation mark, `FirstWordPass` reads its first word as heard in lower case unless the word
keeps its capital by the rule above or is a place, language or calendar name. A place that
keeps the heard case then writes "open the downloads folder" in a launcher, "rent" in a cell
and "git push" in a terminal, and a file name opening a sentence stays "config.yaml". A
transcript with no closing mark keeps the case it was heard in. A paragraph made only of a
literal takes no stop, so `TerminalStopPass` takes back the one the recogniser closed it with:
"localhost:8080", not "localhost:8080.".

Every quoted line of the user prompt — "Typed into:", the text before the caret, the
"Doubtful words:" line with each reading it offers, and the "Spoken:" line itself — has its
double quotes made single first, so a dictionary spelling or screen text holding a `"`
cannot close its quote early and forge a line of its own. Both transformers apply the
first-word and stop policies last, through `FirstWordPass` and `TerminalStopPass`, and the
corpus cases that name a destination (`message-two-sentences-no-stop`,
`mid-sentence-continues-lower-case`, `spreadsheet-cell-no-stop`,
`document-sentence-with-stop`) are scored on the literal beginning and ending of the output,
because the word scorer folds case and punctuation away.

A field the app will not describe — every Electron app — gives an `unknown` insertion point,
which is treated as the start of a sentence. The destination still comes through, because
the bundle identifier costs no permission at all.

## How this maps onto the code

- `CleaningPipeline.piece` is what each piece of a dictation gets: `FillersPass`,
  `RepeatedPhrasePass`, `StammersPass`, `SelfCorrectionPass`, `SpokenPunctuationPass`,
  `LayoutWordsPass`, `NumberFormsPass`, `ContractionsPass`, `SpelledInitialismPass` and
  `SpacingPass`, in that order over a `Draft`, each recording what it removed or rewrote; in a
  code editor outside a comment, `CodeEditorCommandsPass` runs just before `LayoutWordsPass`, and
  `SpokenCasingPass` before it everywhere except a code editor's comments.
  `SpokenPunctuationPass` runs before `LayoutWordsPass` so "question mark new line" becomes
  `?` and then a break. The piece pipeline takes no `FirstWordPolicy` and no
  `TerminalStopPolicy`, so it cannot decide either.
- `CleaningPipeline.message(for:situation:heard:)` — `SentenceBoundaryPass`, `FirstWordPass`,
  `TerminalStopPass` — runs once over the joined message; those two passes carry the
  `DestinationFormatter` policies and are the only place either decision is made.
  `CleaningPipeline.standard(for:situation:steps:)` is the piece's passes then the message's,
  and `RuleBasedTransformer` is that pipeline for the request's formatter and caret: the floor,
  deterministic, and what the user gets when the model declines or fails.
- The generative transformer runs the piece's passes first, built per request from the
  destination's own formatter (`CleaningPipeline.beforeModel`), and hands the model the
  draft's text — so the fillers and the discarded half of a correction are gone before the
  model can rewrite around them, and "one of them" reaches the model already as "1" where
  the place writes numerals. After the model, `CleaningPipeline.afterModel` runs
  `SpokenPunctuationPass`, `CaretEchoPass` and `CaretCloserPass`, then the message's passes.
- `PromptBuilder` gives the model its instructions in three layers, each a separate piece
  of data. The **contract** (`PromptContract`: one string and twelve worked examples) is the
  same everywhere: the goal, Tier 1 and the parts of Tier 2 the model does, the two
  restraints the model still needs spelled out ("never invent or change a name, number,
  date or amount", "when unsure, keep the original wording"), how to read the "Typed into:"
  line (spelling only) and the "Text before the caret:" line (continue the sentence, repeat
  nothing, close nothing) and the "Said just before:" line, the previous piece's last
  sentence (context only, copy none of it), then the examples: a question, a plain sentence, an acronym, an
  injection typed as dictation, a slot the speaker said twice over, three Hindi or Hinglish
  ones, a name off a chat title, an identifier off nearby text, a SQL-editor sentence that
  stays prose, and a continued sentence after a caret. The Tier 3 never-list is not a
  contract sentence: written as one, it made Apple's model passive — it stopped capitalising,
  punctuating and spelling from the screen — so the prohibitions live in the guard and the
  examples. The **formatter block** (`PromptBlocks`, one `PromptBlock` per `PromptBlockID`,
  named by `DestinationFormatter.promptBlock`) is that place's style rules and at most two
  worked examples of its own — a message example teaches "no trailing stop", a code example
  line breaks, a cell example one line, a document example a list, an email example
  paragraphs; the SQL editor's block adds none. The **situation block** is built per request
  by `PromptBuilder.userPrompt(for:spoken:doubtful:preserving:)`: the "Typed into:" line, the
  last `caretLimit` (120) characters before a mid-sentence caret, the "Doubtful words:" line, a
  line naming any clean-up steps the user switched off so the model preserves those words,
  then the spoken words. `PromptBuilderTests.instructionBudget` holds every destination's
  instructions within a fifth over the 2,889-character prompt the layers replaced. Additions
  go in as one rule and one worked example each, measured against the corpus before and
  after (`make bakeoff ARGS="--baselines-only"`, which reports pass rates by destination),
  and no prompt rule or worked example may overlap a corpus case (`ScorerTests`).
- `PromptBuilder.version` is computed, not kept: twelve hex digits of a SHA-256 over every
  destination's instructions, the situation labels and the structured answer's schema with its
  guide text (`PromptContract.answerGuide`), so any wording change gives a new version and two
  different prompts never share one. The contract names each situation label by interpolating
  its constant, so a renamed label reaches the teaching.
- `GenerativeTextTransformer` warms the model for the destination the dictation is going to
  — `DictationPipeline` reads the screen before it warms, and warms for plain text when the
  screen says nothing — because the model keeps one pre-warmed session keyed by the
  instructions it was given.
- `DoubtfulWords` asks the `CandidateSource`s at once for the runs the recogniser
  half-heard, and `GenerativeTextTransformer` puts their readings in the same model call the
  cleaning already makes — never a second call and never a second model.
- `MeaningPreservationGuard` polices Tier 3 after the fact, judging the model against the
  words the passes kept, so a pass's removal is never counted as the model dropping words,
  and against the readings it was offered: a doubtful run must come back as it was heard or
  as one of them.
- **A pass's removal counts as authorised only within its grant.** Each `CleaningPass`
  declares a `RemovalGrant`: `FillersPass` removes a `.sound`, which is never a numeral or a
  word in capitals; `StammersPass` and `RepeatedPhrasePass` remove a `.repetition`, whose
  word is said again within the next four kept words; `SelfCorrectionPass` removes a
  `.retraction`; every other pass only `.conversion`s, so each word it removes sits in a run
  it also wrote a mark, numeral or contraction into. `RemovalAudit` reads the draft's own
  record against those grants, and a retraction that took nothing back — its taken-back
  words said again unchanged straight after, as in "tell the landlord no, the landlord has
  to wait" — has no grant for a one-word negating trigger. A content word or a negation
  removed beyond its grant is still the rewrite's to carry: the guard refuses a rewrite
  without it and accepts one that puts it back, with the words its pass took out beside it
  (`RemovalAudit.restorable`), rather than calling them invented. The refusal
  hands the dictation to the rules, which lose the same word, so what it buys is a named
  refusal in Diagnostics instead of a silent loss. `RemovalGrantCorpusTests` lists every
  corpus case whose passes overreach.
- `WordCorrectionEngine` and the dictionary handle spellings before the tidier sees the text.
- The pieces cut while recording (`Docs/early-transcription.md`) are each tidied alone,
  which is why paragraph breaks and list layout are decided when the pieces are joined.
- **A reply of three words or fewer goes to the rules alone** (`RulesAlone.shortReplies`,
  applied by `TransformerRouter` whenever the rules are on its route), only when every
  character is ASCII — so a Devanagari reply still reaches the model before the rules
  romanise it — and only when the recogniser doubted none of the words, since choosing a
  doubtful word's reading is the model's job. The recogniser already capitalises and
  punctuates a short reply, and the passes do the rest. Measured through `DictationPipeline`
  in one long-lived Release process with the model loaded once, over 17 English dictations of
  one to three words (synthetic speech with noise and gain variants), each run on the shipping
  router and again pinned to the rules: the final text was identical in 17 of 17, and the
  median wait after the key came up was 3.35 s against 0.95 s on a heavily loaded machine.
  Pinned routes, such as the bake-off's per-engine rows, are unaffected.

## What the app shows and lets you change

Three surfaces, so a word that went missing can be accounted for rather than guessed at.

- **Diagnostics names what each step did to the last dictation.** Under "Clean-up steps"
  there is a row per step that changed something — "Filler words: removed 3: um, uh, um",
  "Numbers: rewrote 1: fifteen → 15" — and a grey row for each step that is switched off,
  because a step that is off is why a word the user expected to go is still there. It is
  read off the finished draft's own record of which pass touched which word
  (`CleaningRecord`), so it cannot claim a removal nothing made. An engine whose answer the
  meaning guard refused is named there too ("Answer refused", with the engine and the
  reason), because a refusal is why a dictation comes out plainer than the last one.
  `DictationPipeline` collects one account per piece where it reports the stage timings and
  hands the merged account to `DiagnosticsRecorder`, which keeps the last one only. Nothing
  is written to disk or sent anywhere; the **Copy Diagnostics** report ("Clean-up steps, last
  dictation") counts the words rather than quoting them, and gives a refusal only as its
  `RefusalKind` summary, because that string is pasted somewhere else. Only the steps
  Settings offers are listed, so the section reads the same whether the model answered or
  declined, and a row names the first few words and counts the rest. A reset that clears the
  transcripts clears this too (`DiagnosticsRecorder.forget()`).
- **A step can be switched off.** Settings → Dictation → "Clean-up steps" offers the nine
  steps in `CleaningSteps.offered` — filler words, repeated phrases, stammers,
  self-corrections, spoken punctuation, layout words, numbers, contractions and spacing — all
  on by default, stored as the set that is *off* (`Settings.cleaning`) so a step a later
  build adds is on for everybody who never said otherwise. `CleaningPipeline.piece` builds
  only the ones left on. `FirstWordPass` and `TerminalStopPass` are not offered: they carry
  the formatter's decisions about the place, not a cleaning the user asked for, and
  `CleaningSteps` drops anything else from a stored set rather than trusting it.
- **An app can be treated as somewhere else.** Settings → Dictation → "Where your words go"
  names the app the last dictation went into and offers every kind of place, plus "Work it
  out", which is the table. A choice is stored against the bundle identifier
  (`Settings.destinations`) and `DestinationClassifier` consults the overrides before the
  table; every override made is listed underneath with a button that puts it back. The table
  itself is never edited. The app named is the last one dictated into rather than the
  frontmost, because while the settings window is open the frontmost app is Uttrflow.

All three take effect on the next dictation, not the next launch: `DictationPipeline.adopt`
takes a freshly built cleaner and the overrides as they now stand. A dictation under way
keeps the cleaner and the overrides it began with, so a step switched off while the user is
speaking cannot treat the second half of what they say differently from the first.

## Homophone doubt against the confident-homophone guard

`UncertainSpan` doubts every word of a `Homophones` group whatever its score, so `HomophoneCandidates`
offers its partner; `MeaningPreservationGuard.confidentHomophoneVerdict` refuses a rewrite that swaps a
word scored at or above `certaintyThreshold` for a sound-alike unless that swap was the reading offered
for it. One rule decides both halves: **the guard is the only judge of a swap, and a reading it would
refuse is never offered.** `DoubtfulWords.guardAccepts` runs the guard on the rewrite that writes the
reading over its run and changes nothing else, and drops the reading when the guard refuses it, so a
reading that adds or drops a negation ("no"/"know"), invents a number ("for"/"four", "won"/"one") or
drops an apostrophe ("it's"/"its") never reaches the prompt. Where the same words stand twice and a
different span doubted each mention, each mention is judged by its own span.

`HomophonePolicyProbeTests` runs 40 sentences (20 function-word, 20 sense, the wrong member present)
through `DoubtfulWords.standard` and the guard with the rewrite that takes the offered swap; the model
step is assumed, not run.

| Group | Score of the wrong word | Swap offered | Offered, then refused |
|---|---|---|---|
| function | 0.3 | 15/20 | 0 |
| function | 0.6 | 15/20 | 0 |
| function | 0.95 | 15/20 | 0 |
| sense | 0.3 | 20/20 | 0 |
| sense | 0.6 | 20/20 | 0 |
| sense | 0.95 | 20/20 | 0 |

The five function-word sentences no longer offered are the negation, number and apostrophe swaps above;
they stay as heard.

## How the number grammar chooses between readings

`NumberFormsPass.phrase` tries its readers in a fixed order and the first that matches wins:
a `plus`-led digit run, a numeric date, a cued clock, a 24-hour clock, a dotted number, a spoken digit run, a
decade, a signed number, a month and its day, an ordinal, then a cardinal that may grow into a
decimal, a percentage, a year, a clock time, a colloquial hundred or a context-word digit group.
The semiotic classes it reads are cardinal, ordinal, decimal, percentage, money, measure, date,
time, telephone or code digits, and plain words. Each known ambiguity, and what settles it today:

| Ambiguity | Example | Settled by |
|---|---|---|
| Clock time against a three-digit number | "two thirty" | order: `time` is tried before `colloquialHundred`, which `readsAsOneQuantity` then guards |
| Year against clock time | "nineteen thirty" | order: `year` is tried before `time` |
| Cued clock against digit run | "an alarm for seven oh five" | order: `cuedClock` is tried before `spokenDigitRun` |
| Digit run against one cardinal | "one two three four" | order: `spokenDigitRun` is tried before the cardinal |
| Decade against year | "nineteen nineties" | order: `decade` is tried before `year` |
| Sign against subtraction | "ten minus three" | order: the sign reader runs on any joined `minus`, so it is a sign |
| Price against time against hundred | "two ninety nine" | order, as for "two thirty"; no price reading exists |
| Fraction against ordinal | "two thirds", "a third" | no fraction reading; the ordinal reader decides |
| Ordinal against unit of time | "give me a second" | context: `second` is left out of `measures`; one-word ordinals stay words |
| Pronoun "one" against numeral | "no one", "which one" | not settled: `.always` writes the digit |
| "a hundred" against 100 | "about a hundred users" | context: `finishesAScale` keeps a scale it cannot read whole |
| Product or version number against count | "python three" | context: the closed `contextWords` set |
| Month against verb | "may fifth" | context: `monthIsDated` needs a capital or a dating clause |
| Spoken year shapes | "in twenty oh five" | context: `cuedYear` needs a year cue before it |
| Spoken "dot" between numbers against the word | "one nine two dot one six eight dot one dot one", "two dot five" | context: `dottedNumber` needs three digit groups, or two after a word in `dottedCues` |
| Spoken "double", magnitude letters | "double oh seven", "fifty k" | order: `spokenDigitRun` reads `double`; a spoken letter stays a word |

Every row is a reading the speaker's words already decide, so no output depends on which of two
matching readers runs first except where the table says order, and there the earlier reader is
the one the owner chose: "seven thirty" is 7:30, a calendar time is digits, and am or pm is lower case after it.

**Decided by measurement: ordered readers stay; competing weighted readings are rejected.**
`NumberGrammarStructureTests` scores 19 spoken examples of the rows above with `NumberGrammarScore`:
19 exact, 0 value errors, 0 false conversions (`swift test --filter NumberGrammarStructureTests`,
Apple M5 Pro). Weighted readings choose only among readers that match, so on these rows they can
at best tie, and they would be a second grammar beside this one. A new ambiguity is a missing
reader or a missing context word, added to `phrase` in order with a row here and a case in that test.
Reopen if a row scores inexact because the right reader exists but an earlier one wins.

## Unit words and symbols

A spoken unit word is a word the speaker said, so it stays a word; only its number takes the
numeral policy. A symbol is written only where the speaker said the symbol itself. "Percent"
is the one unit word written as a sign, because "%" is how the word is spelt after a numeral
rather than a shorter word in its place; the guard reads "5%" and "five percent" as one quantity.

| Said | Written | Why |
|---|---|---|
| "ten kilometres" | "10 kilometres" | unit word kept; numeral policy only (`NumberFormsPass`, `measures`) |
| "five percent" | "5%" | spelling of the word after a numeral |
| "minus five degrees" | "-5 degrees" | unit word kept; no degree sign is added |
| "ten k m" | "10 km" | the speaker said the symbol; the case comes from the `symbol` row in `abbreviations.json` |
| "three gigabytes" | "3 gigabytes" | unit word kept |

`MeaningPreservationGuard` holds the model to the same line: a rewrite of "10 kilometres" as
"10 km" loses a kept content word and is refused (`GuardNumberWordsTests`). No table maps a unit
word to a symbol. A spreadsheet or table cell is the one place a symbol may stand for the word;
that needs its own destination rule and is not built.

## Who places commas and stops

One owner per mark, measured with `uttrflow-bakeoff marks --local` over the 726 prose cases of the
corpus (comma F1 against the rules, paired, 95% bootstrap):

| Candidate | Comma F1 | Stop F1 | Question F1 | Declined | Comma F1 vs rules |
|---|---|---|---|---|---|
| Rules | 0.40 | 0.94 | 0.80 | 0 | — |
| Rules with clause commas | 0.44 | 0.94 | 0.80 | 0 | +0.05 [-0.03, +0.14] |
| Apple's model | 0.55 | 0.95 | 0.81 | 126 | +0.12 [+0.00, +0.28] |
| Local tidier | 0.64 | 0.94 | 0.84 | 44 | +0.23 [+0.10, +0.38] |

- **Commas belong to the tidier.** The rules place none: they keep the commas the recogniser wrote
  (precision 1.00, recall 0.25) and move a removed word's comma as the mark table above says.
  Commas placed from clause starts did not beat that, so the rules gain no comma placement.
- **Stops and question marks stay with the rules.** Every candidate scores within 0.01 on stops, so
  `PauseStopPass`, `SentenceBoundaryPass` and `TerminalStopPass` remain the single place a stop is
  decided, and they run after the model too. They are also the floor whenever the model declines
  or is not installed.

## A spoken hashtag

"hashtag" joins the words after it into one lower-case tag (`#springlaunch`) in prose destinations, up to
the first of: a timed pause of at least 300 ms, a spoken or written clause mark, or the end of the piece.
Words alone cannot say where a tag ends, so no word list or word shape decides it. A pause right after
"hashtag" itself does not end the tag. "hashtag" after a determiner or before a form of "be" names a tag and
stays a word ("the hashtag was trending"), as does a "hashtag" with no word after it. A code editor keeps the
word. Measured on 21 invented timed cases plus 3 boundary cases in
`Tests/UttrflowAITests/Passes/HashtagReachTests.swift`: 21 of 21 exact, one to four words.

## Related pages

- `Docs/formatting-matrix.md` — which formatting case classes the corpus covers, generated from its tags.
- `Docs/destination-matrix.md` — how many corpus cases each destination and field kind has, generated from the corpus.
- `Docs/cleanup-design.md` — the types behind this catalogue.
- `Docs/ai-model-output.md` — what the model gets wrong and the guard checks that catch it.
- `Docs/ai-context-line.md` — the "Typed into:" caption.
- `Docs/ai-correction-thresholds.md` — the dictionary correction engine's numbers.
- `Docs/latin-output.md` — romanisation and the script guard.
- `Docs/bakeoff.md` — how a change to the prompt or the rules is measured.
