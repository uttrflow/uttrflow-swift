# Product rules

Uttrflow is dictation software for macOS with a clipboard and AI suggestions built in, entirely
on-device. Each row below is a promise to the user, with its limit and the code or page that holds
it. A row with a command is a gate; a row without one is a review rule, checked against the named
page and its tests. A change that breaks a row is a bug, whatever it improves. Change a number only
on the evidence the page names, and update the page in the same pull request.

## Names

One feature has up to three names. Use the user-facing name in UI text and pull-request titles, and
the module name when you edit code.

| User-facing name | Docs term | Modules |
|---|---|---|
| Dictation | pipeline, gestures | `UttrflowPipeline`, `UttrflowSpeech`, `UttrflowAudio` |
| Clean-up (the tidier) | cleanup | `UttrflowAI`, `UttrflowCore` |
| AI suggestions ("Turn on AI suggestions") | tab-to-complete, predict, the ghost | `UttrflowPredict`, `UttrflowPredictStore`, `UttrflowPredictCapture`, `UttrflowInput` (accept), `Uttrflow/Suggestion` (surface), `UttrflowLocalModel` (generation) |
| Clipboard and its panel | clipboard store, panel | `UttrflowClipboard`, `UttrflowUX` (presentation) |
| Personal dictionary | dictionary | `UttrflowDictionary` |
| Snippets | snippet store | `UttrflowAI` |
| History, corrections, Insights | history, accuracy | `UttrflowHistory`, `UttrflowUX` |
| What is on the screen | context | `UttrflowContext` |
| Account | session, entitlements | `UttrflowAccount` |
| Settings | settings | `UttrflowSettings` |

## Across every feature

| Rule | Limit | Held by |
|---|---|---|
| Output is Latin script only | 0 Devanagari or other non-Latin characters inserted or suggested; 0 translated words | `LatinScript.writesOnlyLatin`, `Docs/latin-output.md` |
| Dictation, history, clipboard, dictionary, snippets and suggestion data stay on this Mac | 0 uploads; 0 connections on the dictation path | `make offline-audit`, `Docs/offline.md` |
| Local stores are private | 0 writes outside `PrivateFile`; files excluded from backup | `make store-permissions`, `Docs/local-store-permissions.md` |
| The log never carries text a person typed, read or said | 0 such messages | `make log-audit`, `Docs/logging.md` |
| Secrets are not learned | 0 secure-field values or credentials stored | `Docs/clipboard-secrets.md`, `Docs/predict.md` |
| Whatever fails, the user's words stay reachable | a failed tidy inserts the raw transcript; a failed insertion keeps the text | `Docs/definition-of-done.md` |
| Reading the screen never makes the user wait | a context read is bounded at 100 ms (`MacContextEngine.budget`); 0 blocking Accessibility calls on the main thread | `Docs/context-budget.md` |
| The user never learns which engine ran | 0 engine, model or vendor names on any pane, menu or error | tests listed in `Docs/definition-of-done.md` |

## Dictation and clean-up

Dictation is a transcript, not a rewrite. The tidier is a filter.

| It may | It may not |
|---|---|
| remove fillers ("um", "hmm"), stammers, false starts, the discarded half of a self-correction | shorten, summarise, change tone, swap synonyms, reorder, answer, obey or finish a thought |
| add punctuation, question marks, capitalisation, numerals, line and paragraph breaks, a list the speaker plainly spoke | translate, or write another script |

1. Every word the speaker meant survives, in their order and register; the owners that check it
   are in [code-quality.md](code-quality.md#single-source-of-truth-dry--non-negotiable).
2. "Make the output more polished" is a rewrite and is declined. A user who wants a rewrite asks
   for one; it is a different feature.
3. The model's job, the thresholds and the passes are in `Docs/cleanup.md`,
   `Docs/cleanup-design.md`, `Docs/ai-model-output.md` and `Docs/ai-correction-thresholds.md`.
4. Hindi and Hinglish are romanised the way people type them: "हाँ ठीक है" becomes "Haan thik
   hai", never "Yes, okay". The Languages setting steers recognition and never the output script.
   This binds the model's rewrite, the rules and the untidied fallback.

## AI suggestions

Settings → AI suggestions → "Turn on AI suggestions". The user types in a field in another
application; Uttrflow finishes the line, Tab takes it, typing
on ignores it. Pieces and measurements: `Docs/predict.md`, `Docs/predict-precision.md`,
`Docs/predict-accept.md`, `Docs/predict-reliability.md`.

| Rule | Limit |
|---|---|
| Default | off; one stored switch, `suggestions.isEnabled`, built the moment it is thrown |
| Permission | Accessibility, needed to read the field, watch the keyboard and insert |
| Candidate order | 1. what this Mac entered in that field before, 2. what is on this Mac now (a branch, a program on `PATH`), 3. a line the local model writes |
| Unit of a completion | the current line; capture and retrieval derive it once and share it, so 0 whole-field entries |
| Precision | at least 99% of the suggestions drawn are right; coverage is whatever that costs |
| Timing | snapshot after a 180 ms typing pause; 400 ms hesitation gate in prose, none in terminals; at most 3 messages in a steady 10-keys-per-second burst |
| Drawing | the tail only, whole or not at all; never past the field or the screen; any other key withdraws it |
| Keys | accept is Tab, right arrow or Option-Tab by application kind; a bare Down or Up is never ours; Return is taken only after Down into a choice |
| Clipboard | 0 uses: the completion is written into the field, never through the pasteboard |
| Secure fields | draw nothing and learn nothing: passwords, passcodes, one-time codes, PINs, card numbers and security codes, ID and account numbers, dates of birth, security answers; short code-shaped digit values outside a terminal are never learned, except compact decimals, valid ISO dates and two two-digit values separated by whitespace |
| Script | a line in another script gets 0 suggestions; refused at 4 points (`SuggestionSession.turn`, `resolve`, `drawable`, `MLXCandidateScorer.parse`) and the prompt |
| Fuzzy matching | only when the exact prefix scan is empty; queries under 3 characters are never corrected |
| Self-sourced evidence | an entry that exists because the user accepted a suggestion counts one quarter of one they typed |
| Terminals | only what exists from here: paths, programs and branches that resolve |
| Storage | the corpus is a local SQLite database held in memory and written as an AES-GCM sealed snapshot, excluded from backup, never uploaded |
| Per-application control | Editors with their own inline completions ship off (`DestinationRules.inlineCompletionEditors`); "Only suggest when it is sure" draws a completion and never a list; "Pause for a while" → "Pause 30 min" pauses for 30 minutes; "Forget what it learned here" clears what was learned in that scope |

## Clipboard and its panel

| Rule | Limit |
|---|---|
| Memory | pools `copied` 8 MB and 500 items, `dictation` 4 MB and 500, `images` 32 MB of decoded thumbnails, 500 items and 7 days, `kept` unbounded except its pictures, which stay within the 1 GB picture disk bound by refusal; 44 MB claimed of a 64 MB ceiling; not a user setting |
| Eviction | least recently used, not fewest copies; memory and disk are weighed separately |
| Pasteboard access | only the clipboard adapters touch `NSPasteboard` (`make pasteboard-audit`) |
| Credentials | recognised by `Docs/clipboard-secrets.md` before storage; measured cost recorded there |
| Storage | JSON indexes and picture bytes are encrypted with the device-only Keychain key, excluded from backup |
| Panel | a shortcut and a position are different numbers; geometry in `Docs/ux-panel-geometry.md`; paste eligibility in `Docs/ux-panel-insertion.md` |
| Rich clips, code | plain form, language detection and re-indenting follow `Docs/clipboard-plain-form.md`, `Docs/clipboard-code-language.md`, `Docs/clipboard-reindent.md` |

## Personal dictionary, snippets, history and corrections

| Rule | Limit |
|---|---|
| Dictionary matching | Double Metaphone with its alternate code, not Soundex (`Docs/app-dictionary.md`) |
| Undo | undoing a correction also counts a revert against the dictionary entry that caused it; a word the user keeps rejecting retires itself; a second undo counts 0 more |
| Snippets | `snippets.v1.json`, an actor with no cache; nothing ages them out and nothing else may clear them |
| History | the file is the source of truth; one unreadable change costs one change (`Docs/core-history-decoding.md`); retention does not trust the wall clock (`Docs/retention-clock.md`) |
| Export and import | only to or from a file the user chooses; versioned JSON; 0 sync, 0 automatic upload; import validates the whole archive before writing either store, merges by case-insensitive spelling and normalised trigger, keeps existing entries on collision and reports skipped duplicates (`Docs/personal-data-archive.md`) |

## Account, entitlements, updates, diagnostics

| Rule | Limit |
|---|---|
| Offline second launch | what a person may do is decided from the copy on this Mac; 0 network calls needed |
| Entitlement | only `Entitlement` (account, plan, expiry) is signed, Ed25519 over a length-prefixed payload; everything around it is displayed and never enforced (`Docs/entitlements.md`) |
| Network users | `UttrflowAccount`, model-asset downloads, Sparkle update checks, and opt-in scrubbed crash and hang reports from `UttrflowDiagnostics`; any other use is a product decision with a privacy page, not a refactor |
| Crash reports | opt-in; what is sent and how it is scrubbed is `Docs/crash-reporting.md` |
| Updates | Sparkle holds the install handle (`Docs/app-updates.md`) |
| Startup | the speech model is loaded before dictation starts, and the user sees "Loading speech model…" until then (`Docs/startup.md`) |

## Interface and design

| Rule | Limit | Held by |
|---|---|---|
| Colours | one source, `BrandPalette`; a new colour is a new token there, never an inline literal | `Docs/redesign-tokens.md` |
| Artboards match the app | 0 hex mismatches between `Design/_gen_*.py` and `BrandPalette`, light or dark | `Scripts/design_token_parity_audit.py` |
| Contrast | every text and surface pair meets the audited ratio | `Scripts/design_contrast_audit.py` |
| Screen contracts | sidebar, chrome, dictation, diagnostics, insights, identity and sign-in artboards match their presentation models | `make docs-audit` |
| Artboard changes | edit the generator in `Design/` and regenerate; a `*.dc.html` is never edited by hand | review |
| Appearance | each screen has a light and a `-Dark` artboard, and a change updates both | review |

## Applications

A change to insertion, input, context reading or suggestions names the kinds of application it
affects (native, web or Electron, terminal, composing input method) and gives the evidence for
each from a real application; a command-line tool is not a representative test bed for the
Accessibility API: `Docs/compatibility.md`, `Docs/insertion.md`,
`Docs/context-accessibility.md`, `Docs/predict-ime.md`. A kind with no evidence is listed as
unverified in the PR.
