# Changelog

Notable changes to Uttrflow. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org).

Each released version is a git tag and a build at
[uttrflow/releases](https://github.com/uttrflow/releases).

## [Unreleased]

### Changed
- **Dictation is ready almost as soon as the key comes up, however long you spoke.** The
  recording is cut at your own pauses and each piece is recognised and tidied while you
  are still talking, so releasing the key leaves only the last piece to do. A two-minute
  dictation used to wait fourteen seconds; the tidier is also warmed as recording starts.
  A retried recording is processed in the same pieces, which is what stops the tidier
  losing words past about four minutes. A speaker who never pauses for half a minute is
  cut at their quietest moment rather than mid-word. `Docs/early-transcription.md` has
  the numbers, measured before and after on the real pipeline.

### Added
- **A word the recogniser half-heard is offered the readings it could be, and the model
  picks the one that fits.** Three sources answer at once, in under two milliseconds for
  a whole dictation: your own dictionary, the words on screen — the window title, the
  selection and the text either side of the caret — and ordinary words that sound alike.
  So "the crash is in payment sheet" comes out as "PaymentSheet" over a window called
  `PaymentSheet.swift` and stays two words in a chat, and "clear the cash" becomes
  "clear the cache" over `Cache.swift`. The readings go into the same model call the
  tidying already makes, never a second one, and the guard refuses a rewrite that wrote
  a word nobody offered. Nothing fires unless the recogniser actually reported how sure
  it was, word by word. `Docs/cleanup.md` has the rule.
- **You can see what the clean-up did, and switch parts of it off.** Diagnostics now lists
  what each clean-up step changed in the last dictation, by word — "Filler words: removed
  3: um, uh, um" — so a word that went missing can be accounted for rather than guessed
  at; a step that is switched off is named as off, because that is why a word you expected
  to go is still there. It stays on this Mac, and the Copy Diagnostics report counts the
  words rather than quoting them. Settings → Dictation offers the nine deterministic
  steps with a switch each, all on to begin with, and lets you tell Uttrflow what kind of
  place an app really is when the built-in table has it wrong — every override you make is
  listed there with a button that puts it back. All three take effect on your next
  dictation rather than at the next launch.
- **Grammar slips are repaired where the place calls for it.** "there is three", "he
  don't", "we have went", "a apple", a tense that drifts mid-sentence — the model may
  fix these in a document, an email or plain text, and leaves them alone in a message,
  a cell, code or SQL. The bound keeps it a cleaning rather than a rewrite: a fix
  changes only the form of a word the speaker said, or adds or removes an article or a
  preposition, never which words. Dialect is not a slip — "gonna", "ain't", "me and
  him" and a double negative go out as spoken. The guard enforces the bound
  mechanically (every content word of the draft must survive; at most three small
  words may change per sentence), the deterministic floor never repairs grammar, and a
  new `grammar` corpus category measures repair against overreach per destination.
- **The tidier knows where the words are going.** The context read now takes the text
  either side of the caret from the focused field, and the app is classified as a
  document, spreadsheet, SQL editor, code editor, messaging app, email client or plain
  text from one table of bundle identifiers and window titles. Two decisions follow
  from that: dictation into the middle of a sentence starts lower-case ("…because " +
  "the build failed") unless the first word is a name the screen or the rest of the
  dictation shows capitalised, and a message of one or two sentences in Slack, WhatsApp,
  Telegram, Discord, Messages or Teams ends without a full stop, as does a spreadsheet
  cell or a line in a code editor. Apps that do not report their field, Electron ones
  among them, keep today's capital. `Docs/cleanup.md` has the rules.
- **The tidier's rules now do every cleaning that needs no model, before any model is
  asked.** Ten small passes run in order over the words — fillers, stammers, a phrase
  said twice, a spoken self-correction ("at four no sorry at five" → "at five"), spoken
  punctuation ("milk comma eggs" → "milk, eggs", but "put a comma there" stays, and
  "period" is a full stop only at the end, so "the trial period ended" keeps its word), "new
  line" and "new paragraph", numbers ("sixteen point two" → "16.2", "two thirty pm" →
  "2:30 pm", "five percent" → "5%", "port eight thousand eighty" → "port 8080"), spacing,
  capitals and the final full stop — and each records what it did to every word. The
  language model is handed the result, so it cannot rewrite around a filler it no longer
  sees, and its answer is judged against the words the rules kept. `Docs/cleanup.md` has
  the rules; ten corpus cases were added to measure them.
- **The tidier's model is told about the place, not just the words.** Its instructions
  are now three layers: a contract that is the same everywhere (the goal, what may be
  removed, what may never be changed, and that a window title is only ever a spelling),
  a short block of style rules and worked examples for the kind of place the words are
  going — a chat message ends without a full stop but a question keeps its mark, a
  spreadsheet cell is one line with numerals, a code editor keeps line breaks and takes
  identifiers from the screen, a SQL editor keeps prose as prose, an email is sentences
  and paragraphs — and, when the caret sits mid-sentence, the text just before it, so the
  dictation continues the sentence rather than starting a new one. Every place is shown
  the same nine worked examples — the bake-off showed that taking them away made the
  model passive — and its own only where its layout or final stop differs, so the
  instructions for any place are at most a tenth longer than the single prompt they
  replace. The model is warmed for the place the moment the key goes down, and the
  bake-off now scores each place on its own. Fifteen corpus cases were added so every
  place has at least three. Where the model repeats the text before the caret at the
  head of its answer, that echo is taken back; a list it writes with dashes is laid out
  with a capital on each item and no stop; in a document, an email, a message or plain
  text every paragraph and the last sentence end with a full stop whatever line breaks
  the text holds, while code and SQL keep theirs and a cell is one line; and a number the
  model writes without its thousands separator is no longer refused as invented.
- **A dictation that fails can be retried from its audio.** Every recording is written to
  this Mac while the key is held, beside the buffer the recogniser reads, and deleted the
  moment the words land. When the words are lost — the recogniser fails, or the app dies
  mid-dictation — the recording stays for a day and sits at the top of the Dictation page
  with a Retry, which runs it through the same stages and copies the result. The floating
  button's failure state gains a Retry that opens that page. Nothing leaves the Mac; the
  privacy wording in Settings, onboarding and History now says exactly this.
- **A long dictation is laid out where its pieces meet.** Each piece of a long dictation
  is cleaned on its own, so three things can only be decided at the seams, and a new
  `PieceJoiner` decides them. A spoken sequence over consecutive pieces — "first… second…
  third", "one… two…", "number one…" — becomes a list where the place takes one (a
  document, an email): two items at least, each of them a clause, the sequence unbroken
  to the end of the dictation, the sequence word dropped and the item given a bullet. A
  chat, a cell, code and SQL keep the prose. A piece that opens on a new topic — "also",
  "next", "okay so", "another thing", "moving on", an ordinal — starts a new paragraph
  where the place has paragraphs, and never inside a list or in a spreadsheet cell. And a
  correction the speaker made across the pause — "let's meet at four" | "no sorry at
  five" — now drops the half they replaced, by the same rule the self-correction pass
  uses inside one piece.

### Fixed
- **The tidier deleted words the speaker said.** A sentence holding the word "wait"
  opened a search for a correction, and the search would settle on an ordinary small word
  as the point the two halves met — so "grab a coffee and wait a moment" came out as
  "Grab a moment." and "we need to wait to finish the review" lost its "wait". "Wait" is
  now heard as a correction only in "no wait" and "wait sorry", and a half taken back has
  to hold a word the speaker meant rather than small words alone.
- **The verb "dash" became an em-dash.** "We should dash off a quick note" is punctuation
  nobody asked for; "dash" and "hyphen" now stay words when a particle follows them — off,
  out, over, up, down, back, away, through, in, to, into, across.
- **English doubles lost a word.** "I had had enough", "the thing that that person said"
  and "bye bye for now" were read as stammers. The doubles the language itself makes —
  "had had", "that that", "bye bye", "no no", "so so" — are kept; "we we" and "the the"
  still go.
- **Reset left the last dictation's words on the Diagnostics page.** "Reset everything"
  emptied the dictionary, the transcripts, the clipboard and every preference, and the
  clean-up section went on naming the words of the dictation before it. It is cleared with
  the transcripts now.
- **Switching a clean-up step off stopped your own spellings informing a half-heard word**
  until the next launch. The tidier is rebuilt in one place now, and that place hands it
  the dictionary.
- **An app you told Uttrflow to treat as somewhere else was treated that way only for a
  short dictation.** A long one, cut into pieces at your pauses, was laid out for the app
  the built-in table names instead.
- **Pressing the key, giving up and pressing it again could send the second dictation to
  the first one's app.** The screen read for a dictation you abandoned is now dropped with
  it.
- **A setting changed while you were speaking changed that dictation halfway through.**
  Clean-up steps and per-app places now take effect on the next dictation, as they say.
- **One correction from your dictionary silenced the half-heard-word readings for the rest
  of the sentence.** Every other word keeps the score the recogniser gave it, so "clear the
  cash in payment sheet" can have both its dictionary spelling and its doubtful word.
- **One unreadable entry threw away every app you had told Uttrflow about.** An entry this
  build has no word for now costs only itself.
- **Diagnostics named clean-up steps by their internal names**, listed a different set of
  them depending on how the dictation had been tidied, and ran a long row off the edge of
  the page. It lists the steps you are offered, the same ones either way, and quotes the
  first few words with a count of the rest.
- **A step's work vanished from Diagnostics when a later step touched the same word.**
  "dont" → "don't" → "Don't" was credited only to the last of them; both are named now.
- **An app you dictate into was listed twice** under "Where your words go" once you had
  given it a place of its own.
- **An email whose subject mentioned Google Docs was written as a document.** What an app
  is now beats what its window happens to be called.

### Added
- **A correction the speaker made without saying so is taken back.** "I wanted to buy a
  record as a gift as a present" becomes "…as a present", and "let's meet on tuesday on
  wednesday" becomes "…on wednesday", from the shape alone: a short frame of small words
  said twice over, each time with a different word after it. A frame that opens a clause
  is not a correction, so "I like tea I like coffee both are fine" survives whole. It runs
  inside a piece and across the pause between two.
- **Contractions are repaired without a model.** "dont", "cant", "youre", "thats" and
  their kind get their apostrophe back deterministically, so a dictation the model
  declines — Hindi, a refusal, a timeout — no longer keeps them broken. Only the words
  that are a contraction and nothing else: "Ill" and "Id" are repaired where the capital
  says the speaker meant "I", and "its", "wed" and "were" are left as they were said.
- **Numbers follow the place they are going.** A spreadsheet, a SQL editor and a code
  editor now write every number as a numeral, "one of them" → "1 of them"; a document, an
  email, a message and plain text keep ten and up, as before.

## [0.4.0] — 2026-09-01

### Changed
- **The floating button's meter is the microphone now.** It was seventeen bars running a
  canned loop with staggered durations — the same animation whether you shouted, whispered
  or said nothing at all. It is a real level: root mean square, mapped in decibels because
  speech sits near −30 dBFS and a linear meter spends nine tenths of its travel on the
  loudest tenth.
- **The meter is a recording rather than a decoration.** Capsules, mirrored about a centre
  line, one per arrival, walking from the edge where sound comes in toward the mark — so
  the horizontal axis is time and every bar on screen is a moment that was actually said.
  Bars past half scale take the accent teal.
- **Listening went from 286 × 52 points to 136 × 32**, and working is identical to it so
  the panel cannot change shape at the instant the key is released. The old width was what
  a sixty-character transcript preview and a recovery button need, paid on every dictation
  for a state listening never enters.
- **A success needs no words.** Inserted, copied and nothing-heard were a 286-point panel
  each; they are a 26-point disc, an expanding ⌘V keycap and a struck level. When the text
  has landed in the document, a panel repeating it narrates something you are already
  looking at. Only a blocked microphone stays wide, because it is the one with something to
  do about it.
- **Inserted is the mark opening into a checkmark.** Both are one round-capped stroke — a
  short arm, a turn, a long arm — so confirming an insertion needs no second glyph.
- The resting grip is three dots rather than five, and 34 points tall rather than 46.

### Fixed
- **The resting grip had a box drawn round it, and in fact two.** Every form was built on
  the same translucent slab, whose hairline and 34%-black shadow read as depth around a
  pill and as an outline nobody meant to draw around nine points of dots — and the panel
  was drawing a second ring outside the first. Both are gone; the dots keep a half-point
  shadow so they hold on a pale wallpaper, and the hit target is unchanged because it never
  came from the slab.
- Working no longer loops. A loop says *indefinite*, which is the animation of a download
  with no progress bar; tidying up a sentence takes about a second and always ends, so it
  now plays once and resolves into the tick.

## [0.3.0] — 2026-08-30

### Added
- **Any modifier combination can be the dictation shortcut** — ⌃⌥, ⌘⌥, or a single
  modifier on its own. Only Fn was allowed before, on an argument about ⌘ that had been
  applied to every modifier-only binding.
- **Updates in Settings**: the version, a Check Now button, and a switch for whether an
  update installs itself or asks first. Updating was reachable only from the menu bar.
- **The menu bar says when an update is happening.** Downloading, waiting for a quiet
  moment, and installing each say so. Before this the app replaced itself and relaunched
  in silence, which reads as a crash.
- Continuous integration on every pull request, and a tag-driven release workflow.
- `CONTRIBUTING.md`, `RELEASING.md`, `SECURITY.md` and a code of conduct.
- `Docs/measuring-accuracy.md` — what it would actually take to measure a speech-engine
  change, which turns out to be fifteen minutes rather than the sixteen hours assumed.

### Fixed
- The "install updates automatically" preference is now read at launch. It was hardcoded
  on, so any change to it was forgotten the next time the app started.
- The shortcut field's refusal no longer says "Try a letter, a number or Space" to
  somebody who pressed a perfectly ordinary modifier combination.

## [0.2.2] — 2026-08-29

First public release of the source. The app itself has been shipping since 0.1.0; this is
where its code became readable.

### Added
- Work on this Mac without an Uttrflow account, using the name macOS already knows you by.
  Sign-in was the one screen that could not work offline; it now has a way through that
  needs nothing.
- Automatic updates through Sparkle, checked against a key compiled into each build.
- A Position Monitoring view, and version reporting at the foot of the sidebar.

### Fixed
- The sidebar no longer claims a session nobody has.
- One retention window now governs both copies of a transcript, rather than two that could
  disagree.

[Unreleased]: https://github.com/uttrflow/uttrflow-swift/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/uttrflow/uttrflow-swift/releases/tag/v0.4.0
[0.3.0]: https://github.com/uttrflow/uttrflow-swift/releases/tag/v0.3.0
[0.2.2]: https://github.com/uttrflow/uttrflow-swift/releases/tag/v0.2.2
