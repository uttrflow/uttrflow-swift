# Changelog

Notable changes to Uttrflow. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are calendar dates,
`YEAR.MONTH.DAY` with no leading zeros, for the day a release is cut; a second release on
the same day adds a fourth number, `2026.9.14.1`. Releases up to 0.5.0 used semantic
versioning.

Each released version is a git tag and a build at
[uttrflow/releases](https://github.com/uttrflow/releases).

## [Unreleased]

### Changed
- **Suggestions is now called AI suggestions.** The Settings tab and its heading, the menu
  bar switch, the notes on that screen and what VoiceOver reads for a suggestion all use the
  new name. Nothing you chose there changes: every setting is kept as it was.

## [2026.9.14] — 2026-09-14

The first release named by its date. Nothing about updating changes: an installed copy of
0.5.0 is offered this release like any other.

### Fixed
- **Hiding an AI suggestion that is already hidden no longer redraws the panel.** Each keystroke
  with nothing drawn used to rebuild the view and look up the screens two or three times on the
  main thread (#889).
- **Dictating into a slow field while AI suggestions are on no longer times out after 100 ms.**
  Each Accessibility caller now sets its timeout on its own elements, so a suggestion read can no
  longer shorten an insertion write to 0.1 s, and the context read keeps its budget (#887).
- **Typing at a clipboard confirmation no longer filters the list behind it.** Letters and arrow
  keys under "Delete this clip?", a collection delete or a formatter diff are held, so the clip
  being asked about stays listed (#946).
- **Branch names, slugs and dated file names are no longer hidden as credentials.** Words joined
  by `-`, `_` or `/` such as `fix/796-paste-confirmation-cancel` stay readable in the clipboard
  panel (#919).
- **Uttrflow crashed after a few thousand key presses.** Every keystroke the app passed on
  left the stack a little deeper, so after about 2,500 presses — and again when the
  keyboard monitor stopped — it ran out. A keystroke now costs the same at the five
  hundredth press as at the first, and the microphone's change handler, which had the same
  shape, is fixed with it.
- **A selection reported by another app could crash Uttrflow.** Accessibility hands over
  whatever range an app reports, and one near the "not found" marker overflowed when its
  end was worked out. Every place that reads such a range now treats an impossible one as
  unknown: no text either side of the caret, rather than a crash.
- **One damaged file in the shared model cache crashed Suggestions every time it
  started.** A weights file whose header claimed a size near the largest number there is
  overflowed the check that measured it. A header that does not add up now counts as an
  incomplete download, and the model is fetched again instead.
- **An unreadable clipboard file deleted the pictures of your pinned and saved clips.** If
  either of the clipboard's two index files could not be read at launch, the tidy-up that
  removes orphaned pictures ran against a list missing half its entries, and the next save
  wrote over the damaged file. A file that cannot be read is now set aside beside the
  original rather than overwritten, and no picture is removed while one is. Dictation
  history, the dictionary and snippets set an unreadable file aside the same way.
- **The microphone could stay open after a dictation.** Stopping the shortcut monitor at
  the instant a key went down could deliver the release before the press, and the
  recording then waited for a release that had already gone. The two now always arrive in
  the order they happened. Switching between hold-to-talk and press-to-toggle in the middle
  of a dictation had the same result; the dictation now finishes, and keeps its words, when
  the mode changes.
- **The arrow keys started dictation.** macOS marks the arrow and navigation keys with the
  same flag as Fn, and the Fn shortcut read that flag from any key. It is now read only
  when a modifier key itself changes, so moving the cursor no longer opens the microphone.
- **A shortcut made only of modifiers dictated during other shortcuts.** With `⌃⌥⌘` as the
  dictation shortcut, pressing `⌃⌥⇧⌘K` started a dictation on the way. A press of modifiers
  alone now waits a fifth of a second, and a key typed or another modifier added in that
  time withdraws it. Settings also draws such a shortcut with all of its keys rather than
  one, and refuses `⌘`, `⌥`, `⌃` or `⇧` held on its own, which is part of too many other
  shortcuts to be one; a saved one returns to the default.
- **The clipboard shortcut could stop working after a shortcut change.** When the old
  registration was removed off the main thread, the new one could be refused and the old
  one then removed anyway, leaving the keys to the app in front. That path is closed; other
  reports of `⇧⌘V` pasting are still being looked into.
- **Dictation stopped until relaunch when macOS switched off the keyboard tap.** The tap is
  switched back on when that happens. The menu bar also shows the shortcut you set rather
  than `⌥Space`.
- **An interrupted speech model download left a model that never loaded and could not be
  repaired.** A download that ended early — a quit, a crash, the Mac sleeping — left some
  weights behind and counted as installed, and Try Again loaded the same broken files. The
  weights now download to a separate folder and are moved in only when every file is
  there, and a model that fails to load offers to download it again.
- **Hindi and Hinglish sometimes came out in Urdu script, or translated into English.** A
  confident Hindi decode looked repetitive by a measure tuned to English, so it was retried
  with sampling, and the retry could pick another language. Detection is now held to
  English and Hindi, and a Hindi decode is judged by its own measure.
- **A dictation with dictionary words could lose whole sentences.** The words from your
  dictionary are handed to the recogniser as a prompt, and its word timings were then
  lined up against the prompt instead of the speech, so sentences at the start, middle or
  end were dropped. The timings are now read from where the speech begins.
- **Two recognitions could run on the model at once.** A dictation started while a
  cancelled or timed-out one was still being recognised shared the model with it, and one
  could be decoded with the other's dictionary words. The recogniser now takes one job at a time.
- **The last moment of every recording was thrown away.** Releasing the key discarded the
  audio the microphone was still holding, up to about 85 milliseconds. It is kept now.
- **A microphone that disconnected mid-dictation joined the words either side of the gap
  into one sentence.** The microphone is retried when a device changes; a recording with a
  hole in it is refused rather than inserted as if nothing were missing, and the level
  meter falls to silence instead of freezing on its last reading.
- **The stop sound was recorded.** It played while the microphone was still open, so its
  start landed at the end of every recording. It now plays once the microphone has closed.
- **History filed a dictation under the app it started in**, not the one the words landed
  in when you switched windows while speaking.
- **Tab could apply a suggestion meant for an earlier line.** A key typed just before Tab
  left Tab applying the edit worked out before it, so the letter just typed came out twice. An
  out-of-date suggestion is now refused, and the text being replaced is checked before it
  is taken back.
- **A line you typed in a chat and never sent could become a suggestion later.** In a chat
  app only a sent line is learned from.
- **Suggestions interrupted you with a dialog** asking whether to learn from an app that
  the Suggestions screen had already allowed. The switch there is the only question now.
- **Check Now in Settings did not check for updates.** It does, as the menu bar did.
- **Turning Suggestions on showed nothing while about 3 GB downloaded.** The download's
  size and progress are shown, and so is a failure.
- **Copying a transcript sent it to your other devices.** The panel's Copy and the menu
  bar's Copy cleared the clipboard in the ordinary way, so Universal Clipboard offered the
  words to every device on the same account. Every copy Uttrflow makes now stays on this
  Mac.
- **Spoken dates and small amounts of money stayed as words.** "the twenty fifth of March"
  is written "25 March", and "five dollars" is "5 dollars" in any place.

### Changed
- **A reply of three words or fewer lands in well under a second.** "Ship it.", "Are you
  free?" — the rules already write these exactly as the model would, but the model was
  still asked, which cost about half a second on a quiet Mac and several on a busy one. A
  short reply the recogniser was sure of, in English, now skips it.
- **Suggestions cost a fifth of the processor they did.** Each pass re-read the whole
  prompt to add one typed character; the fixed part is now read once and each line once,
  which took a hundred keystrokes from about 170 processor-seconds to about 30. The page
  around the field is held to a budget rather than a length, so a busy web page no longer
  fills the prompt, and a pass over one takes about half as long. And a page is read as a
  conversation only when people are visibly taking turns on it, so a comment box or an
  email is no longer suggested to as if it were a chat.
- **Uttrflow no longer works while you are not using it.** The Home page's clipboard
  demonstration used a third of a core whenever any part of its window was on screen; it
  now moves only in the window you are using, with the card in view, and at 30 frames a
  second. Tab-to-complete's once-a-second check stops shortly after you stop typing, and the
  clipboard is checked twice a second rather than five times, catching up the moment the
  panel opens.
- **Reduce Motion, Low Power Mode and a hot Mac are honoured.** Animations hold still under
  any of the three, the meter draws at the rate its data arrives in Low Power Mode, and
  Suggestions pause in Low Power Mode and when the Mac is under thermal pressure. Their
  work runs at a lower priority than what you are doing at all times.
- **The suggestion model gives its memory back.** It holds about 2.5 GB while loaded. It is
  now released when Suggestions is turned off, when macOS reports memory pressure — and
  loaded again once the pressure has passed — and after an idle spell whose length depends
  on how much memory the Mac has, loading again on the next keystroke that needs it. While
  it is loaded, its working memory no longer grows with every pass: it reached 10 GB after
  forty passes and now stays at the weights. Reloading it no longer leaks a little more each
  time, and neither does opening sign-in.
- **Copying something large no longer stalls the clipboard.** Looking for a password in a
  long run without spaces could take minutes, and comparing a large block of code when
  formatting it took 10 seconds and 4 GB. Both now grow with the text rather than its
  square, and working out what a 2 MB copy is takes hundredths of a second instead of
  seconds. A very long terminal line, which Suggestions took 15 seconds to read at 100 KB,
  is read in under a millisecond.

### Added
- **Uttrflow says when the speech model is still loading.** The first load after a restart
  can take two or three minutes, and until now pressing the shortcut in that time opened
  the microphone and waited. The floating button, Home and the clipboard panel now say the
  model is loading and roughly how long, a dictation tried during the load is told why
  nothing is happening, and a failed load says so with a way to try again.
- **A broken speech model can be downloaded again** from the message that says it did not
  load.
- **Opening Uttrflow a second time brings up the copy already running**, rather than
  starting another with its own speech model and keyboard monitor.
- **Card numbers, and passwords copied from a password manager, are hidden in clipboard
  history.** A card number is recognised by its length, its grouping, the prefix its
  network issues and its check digit, so a phone number or an order number is left alone. A
  copy a password manager marks as concealed is hidden whatever it looks like, and one it
  marks as temporary is not kept at all.

### Security
- **What you type no longer reaches the system log.** The suggestion loop wrote the line
  being typed, in any app, into the unified log in plain text. The text
  is gone from every log line, and `make verify` now refuses a log message that carries
  text a person typed, read or said.
- **The suggestion model loads without going online when it is already on this Mac.** Every
  load asked the model host for a file list before using the copy on disk. A complete copy
  is now used directly, and the offline audit checks that it stays that way.

## [0.5.0] — 2026-09-06

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
- **Every shortcut can be changed, and there are four of them.** Settings lists each one
  with its own keys: the dictation shortcut, the clipboard panel — which could be stored
  but never changed until now — and two new ones, `⌃⌘V` to put the last thing you
  dictated back at the caret and `⌃⌘C` to put it on the clipboard. Pasting takes the same
  route a dictation takes, so putting a transcript back does not cost you what was on
  your clipboard; copying is the one place the clipboard is written on purpose. Binding
  a shortcut to keys another one already holds is refused, and says which one holds them.
- **Double-tap the dictation key to keep talking without holding it.** Two quick taps
  leave the microphone open; two more close it. It is the same key you already dictate
  with rather than a second shortcut to learn, and a single stray tap does nothing.
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
- **Contractions are repaired without a model.** "dont", "cant", "youre", "thats" and
  their kind get their apostrophe back deterministically, so a dictation the model
  declines — Hindi, a refusal, a timeout — no longer keeps them broken. Only the words
  that are a contraction and nothing else: "Ill" and "Id" are repaired where the capital
  says the speaker meant "I", and "its", "wed" and "were" are left as they were said.
- **Numbers follow the place they are going.** A spreadsheet, a SQL editor and a code
  editor now write every number as a numeral, "one of them" → "1 of them"; a document, an
  email, a message and plain text keep ten and up, as before.

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
- **A phrase said twice over lost half of itself.** "I'll pay for lunch for everyone"
  came out as "I'll pay for everyone", "coffee with milk with sugar" as "Coffee with
  sugar", and "the meeting is on Monday on Zoom" as "The meeting is on Zoom". The rule
  that did it read a repeated frame of small words as a correction the speaker made
  without saying so — but that shape is a list at least as often, and which of the two
  halves was meant to stand is a question about meaning, not about shape. The rule is
  gone from the deterministic floor, inside a piece and across a pause both; a correction
  the speaker announced — "no sorry", "I mean", "actually" — is still taken back, and the
  model is now told to drop the earlier of two goes at the same slot.
- **A repeated number word was read as a stammer.** "extension four four two" became
  "Extension 42" and "port eight zero zero zero" became "Port 80". A number word is never
  a stammer now, because each copy of it is a digit of one value.
- **"mm" was removed as a hesitation sound.** It is millimetres, and "MM" is millions, so
  "the gap is three mm" lost its unit. "mmm" is still a hesitation.
- **The nouns "period", "comma" and "dash" turned into punctuation.** "During the trial
  period" became "During the trial", "I love the Victorian period" lost its noun, and
  "the 100 metre dash was close" became "the 100 metre — was close". The check for a word
  being talked about rather than dictated looked only one word back, so any modifier hid
  the determiner in front of it; it now reaches three words, stopping at a mark's own
  name so "did you finish the trial period question mark" still ends in a question mark.
- **An acronym was read as a contraction.** "Reset the user ID" became "Reset the user
  I'd", and "an IM" became "an I'm". A capital past the first letter now says the word is
  an acronym.
- **Part of a number phrase was written as a numeral.** "About a hundred and fifty users"
  became "About a hundred and 50 users" — and when the model wrote the sentence correctly
  the guard threw the good answer away, so the mangled floor text was what the user got.
  A phrase whose scale the parser cannot read whole is now left whole.
- **A sentence started after "p.m."** "Call me at five p.m. tomorrow" became "Call me at
  5 p.m. Tomorrow." A word carrying a stop inside itself — "p.m.", "a.m.", "e.g." — no
  longer ends a sentence.
- **A rewrite could drop a negation and be accepted.** "not" and the "n't" forms count as
  small words, so "I do not think we should ship" becoming "I think we should ship"
  passed every check the guard made — the worst edit it could let through. Negation is
  now counted on both sides, and a rewrite holding less of it is refused.
- **A good rewrite was thrown away over a word the caret echo had taken back.** The pass
  that removes the model's repetition of the text before the caret runs before the guard,
  so a word inside that repetition looked to the guard like a word the model had lost.
  The echo now counts as written.
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
- **A shortcut recorded with two keys could end up watching for a third.** Letting go of
  one modifier while another was still held stored the key code of the one that left
  beside the modifiers that stayed, so a shortcut set to `⌥` fired on `⌘`, and `fn` — set
  deliberately — did nothing at all. The keyboard now reads whether a key went down or up
  rather than inferring it, a binding whose keys and modifiers disagree cannot be stored,
  and one already saved repairs itself when the app opens. Caps Lock is refused with it:
  it sets no modifier at all, so nothing could ever see it held.
- **A dictation interrupted by changing the shortcut could leave the microphone open.**
  The release owed for a hold in progress was thrown away a moment before it was sent.
- **Removing a filler left the comma that bracketed it** — "we should, uh, ship" came out
  as "we should, ship".
- **Changing the clipboard shortcut took effect only after a relaunch.**

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

[Unreleased]: https://github.com/uttrflow/uttrflow-swift/commits/main
[0.5.0]: https://github.com/uttrflow/releases/releases/tag/v0.5.0
[0.4.0]: https://github.com/uttrflow/releases/releases/tag/v0.4.0-test.90a5262
[0.3.0]: https://github.com/uttrflow/releases/releases/tag/v0.3.0-test.0f0a7ad
[0.2.2]: https://github.com/uttrflow/releases/releases/tag/v0.2.2-test.346aad1
