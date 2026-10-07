# Uttrflow documentation

A page per subsystem. Each one holds what the code cannot say for itself: a measured number,
a platform trap, an approach that was tried and does not work. Comments in the source are one
line and link here rather than carrying the explanation themselves. Every rejected approach is
indexed, with the condition that reopens it, in [decisions.md](decisions.md).

Nothing here is a tutorial. If you want to run the app, the [README](../README.md) is the
place to start; if you want to change it, [CONTRIBUTING](../CONTRIBUTING.md) and
[AGENTS.md](../AGENTS.md) are the working rules.

## New here? Read these three

1. [The dictation pipeline](pipeline.md) — the path a held key takes to words on screen.
2. [Putting the words on screen, and the traps in doing it](insertion.md) — where macOS fights back.
3. [Dictating with no network](offline.md) — the promise the architecture exists to keep.

## From a held key to words

| Page | What it covers |
|---|---|
| [pipeline.md](pipeline.md) | The dictation pipeline |
| [dictation-quality.md](dictation-quality.md) | Dictation quality: the layers, and where each one lives |
| [pipeline-gestures.md](pipeline-gestures.md) | How a gesture becomes a dictation |
| [commands.md](commands.md) | Telling a spoken command from content |
| [shortcuts.md](shortcuts.md) | Watching for the shortcut |
| [microphone.md](microphone.md) | The microphone, and the hardware moving under it |
| [audio-capture.md](audio-capture.md) | Capturing the microphone |
| [silence.md](silence.md) | Silence, and why it has to be caught before the recogniser |
| [speech-engines.md](speech-engines.md) | The speech engines, and what WhisperKit does when nobody is looking |
| [decoder-evidence.md](decoder-evidence.md) | What WhisperKit can say about a doubtful word |
| [unknown-confidence.md](unknown-confidence.md) | What each layer does when a word's confidence is unknown |
| [decode-session.md](decode-session.md) | The decode loop the repository owns, and its parity with WhisperKit's |
| [speech-vocabulary-prompt.md](speech-vocabulary-prompt.md) | Conditioning Whisper on the user's own words |
| [speech-phrase-bias.md](speech-phrase-bias.md) | Helping a begun dictionary word finish at decode time |
| [speech-model-install.md](speech-model-install.md) | Installing a speech model, one component at a time |
| [early-transcription.md](early-transcription.md) | Working ahead while the key is held |
| [pipeline-changes.md](pipeline-changes.md) | What the pipeline changes about a dictation, and how it stays honest |
| [insertion.md](insertion.md) | Putting the words on screen, and the traps in doing it |
| [input-synthetic-keystrokes.md](input-synthetic-keystrokes.md) | The key events this app posts, and what the system does with them |
| [input-paste-eligibility.md](input-paste-eligibility.md) | When the paste strategy volunteers |
| [context-accessibility.md](context-accessibility.md) | What applications actually answer |
| [chat-mail-probe.md](chat-mail-probe.md) | What the dictation read gets from a chat composer or a mail body |
| [web-field-probe.md](web-field-probe.md) | What the dictation read gets from a web field |
| [terminal-probe.md](terminal-probe.md) | What the dictation read gets from a terminal |
| [accessibility-private-api.md](accessibility-private-api.md) | Accessibility private API |
| [accessibility-controls.md](accessibility-controls.md) | Every control, its accessible name and its keyboard status |
| [compatibility.md](compatibility.md) | What each kind of application actually does with the words |
| [insertion-test-matrix.md](insertion-test-matrix.md) | Which insertion situations a test, a harness or a person checks, and the set run before a tag |
| [context-budget.md](context-budget.md) | The context read's budget |
| [stuck-recording.md](stuck-recording.md) | The recording that never stops |
| [recordings.md](recordings.md) | Recordings kept for retry |

## Making the words better

| Page | What it covers |
|---|---|
| [cleanup.md](cleanup.md) | What the tidier may do to your words |
| [closed-phrase-marks.md](closed-phrase-marks.md) | Recogniser commas and stops after a closed-class word, measured |
| [lexical-class.md](lexical-class.md) | Reading a word's class, and how far the tagger holds on bare recogniser text |
| [cleanup-design.md](cleanup-design.md) | Clean-up: the low-level design |
| [dictation-trace.md](dictation-trace.md) | Explaining one dictation, stage by stage |
| [piece-seams.md](piece-seams.md) | Cleaning pieces then joining them, measured against cleaning the whole |
| [adapters.md](adapters.md) | Format adapters: one registry that grows out of the destination formatter |
| [latin-output.md](latin-output.md) | Latin letters only |
| [adding-a-language.md](adding-a-language.md) | What adding a language requires, and where each language is keyed |
| [adding-a-pass.md](adding-a-pass.md) | Adding a cleaning pass, step by step |
| [adding-a-destination.md](adding-a-destination.md) | Adding a destination, step by step |
| [data-tables.md](data-tables.md) | Word tables as data: the one loader, its checks and its fallback |
| [lexicon.md](lexicon.md) | Adding a technical term: the entry, what is rejected, the check |
| [data-manifest.md](data-manifest.md) | Origin, licence and digest of every bundled resource file, and the check |
| [ngram-sources.md](ngram-sources.md) | Pinned text sources for the shipped n-gram table, the licence allowlist, and the check |
| [data-asset-delivery.md](data-asset-delivery.md) | Bundled or downloaded data assets: sizes, load time and update path |
| [ai-model-output.md](ai-model-output.md) | What a small model does to dictation, and the guards that catch it |
| [ai-context-line.md](ai-context-line.md) | The context line, measured |
| [ai-correction-thresholds.md](ai-correction-thresholds.md) | Word correction: the numbers and why they are what they are |
| [app-dictionary.md](app-dictionary.md) | Personal dictionary: phonetics and learning |
| [app-dictionary-store.md](app-dictionary-store.md) | The personal dictionary store |
| [ai-snippet-store.md](ai-snippet-store.md) | The snippet store |
| [personal-data-archive.md](personal-data-archive.md) | Personal data archive |

## AI suggestions (tab-to-complete)

| Page | What it covers |
|---|---|
| [predict.md](predict.md) | AI suggestions (tab-to-complete) |
| [predict-probe.md](predict-probe.md) | Probes: what AI suggestions can rely on |
| [predict-context.md](predict-context.md) | AI suggestions: register, surroundings and personal style |
| [predict-accept.md](predict-accept.md) | Accepting a suggestion |
| [predict-ime.md](predict-ime.md) | Detecting a composing input method |
| [predict-llm.md](predict-llm.md) | AI suggestions: the local model |
| [predict-agent.md](predict-agent.md) | AI suggestions in a terminal: the machine as the model's tools |
| [command-lookups.md](command-lookups.md) | Command lookups in a terminal |
| [predict-reliability.md](predict-reliability.md) | AI suggestions: reliability |
| [predict-precision.md](predict-precision.md) | AI suggestions: accuracy is the product |
| [predict-terminal-paths.md](predict-terminal-paths.md) | AI suggestions in a terminal: only what exists from here |

## The clipboard and its panel

| Page | What it covers |
|---|---|
| [panel.md](panel.md) | The clipboard panel |
| [app-quick-panel.md](app-quick-panel.md) | Quick panel: the window, its measurements and platform traps |
| [ux-panel-geometry.md](ux-panel-geometry.md) | Quick panel geometry: resizing and placement |
| [ux-panel-insertion.md](ux-panel-insertion.md) | Deciding whether the panel can paste |
| [clipboard-secrets.md](clipboard-secrets.md) | Recognising a credential |
| [clipboard-plain-form.md](clipboard-plain-form.md) | Rich clips as plain text |
| [clipboard-code-language.md](clipboard-code-language.md) | Code language detection |
| [clipboard-reindent.md](clipboard-reindent.md) | Re-indenting and formatting a code clip |
| [clipboard-budget.md](clipboard-budget.md) | Clipboard memory budget |
| [clipboard-store.md](clipboard-store.md) | The clipboard store |

## The app's windows

| Page | What it covers |
|---|---|
| [startup.md](startup.md) | Launching, and loading the speech model |
| [app-main-window.md](app-main-window.md) | Main window: sizing, colours, Home and the clipboard demonstration |
| [app-dock.md](app-dock.md) | The floating button: forms, measurements and traps |
| [redesign-tokens.md](redesign-tokens.md) | Redesign tokens |
| [app-onboarding.md](app-onboarding.md) | Onboarding window: sizes and the provider marks |
| [ux-onboarding.md](ux-onboarding.md) | Onboarding: the rules the flow is built on |
| [ux-figures.md](ux-figures.md) | The figures on Dictation, Insights and Diagnostics |
| [ux-settings-model.md](ux-settings-model.md) | The settings screen's model |
| [app-settings-controls.md](app-settings-controls.md) | Settings controls |
| [app-updates.md](app-updates.md) | Updates: why the app holds Sparkle's install handle |
| [quitting.md](quitting.md) | Quitting |
| [localisation.md](localisation.md) | Words the app shows: localisable, and never the dictation |

## What is kept, and what leaves the Mac

| Page | What it covers |
|---|---|
| [offline.md](offline.md) | Dictating with no network |
| [logging.md](logging.md) | What the unified log may carry |
| [diagnostics-export.md](diagnostics-export.md) | What "Copy diagnostics" may carry |
| [entitlements.md](entitlements.md) | What somebody is allowed to do, and how that is known offline |
| [account-session.md](account-session.md) | The account session: what `HTTPAuthenticationService` promises |
| [account-keychain.md](account-keychain.md) | The refresh token in the Keychain: what `KeychainTokenStore` promises |
| [account-transport.md](account-transport.md) | The transport: why `URLSessionTransport` has no cache |
| [crash-reporting.md](crash-reporting.md) | Crash and hang reporting |
| [account-server-data.md](account-server-data.md) | Account data on the server: what is kept, for how long, and how it is deleted |
| [account-telemetry.md](account-telemetry.md) | Telemetry: what leaves the Mac, and why a dictation never waits for it |
| [core-history-decoding.md](core-history-decoding.md) | Decoding a stored history: one unreadable change costs one change |
| [core-history-undo.md](core-history-undo.md) | Undoing a correction: how the words are found and when they are left alone |
| [core-history-accuracy.md](core-history-accuracy.md) | The "Left as dictated" figure: where its denominator comes from |
| [history-store-file.md](history-store-file.md) | The dictation history file, and the shape of the store around it |
| [persona-threat-model.md](persona-threat-model.md) | Threat model for learned personal data |
| [learned-state.md](learned-state.md) | Learned state: one evidence ledger for every inferred fact |
| [local-store-permissions.md](local-store-permissions.md) | Who may read the local store |
| [local-store-encryption.md](local-store-encryption.md) | Encrypting local user stores |
| [retention-clock.md](retention-clock.md) | Retention, against a clock that may be wrong |

## Settings and system behaviour

| Page | What it covers |
|---|---|
| [core-hotkeys.md](core-hotkeys.md) | Shortcut bindings: what `HotkeyBinding` decides and why |
| [core-settings-launch-at-login.md](core-settings-launch-at-login.md) | Launch at login |
| [core-engine-kinds.md](core-engine-kinds.md) | Which transformer kinds a build contains |
| [settings-decoding.md](settings-decoding.md) | Settings: why decoding is forgiving, field by field |

## Measuring it

| Page | What it covers |
|---|---|
| [accuracy-targets.md](accuracy-targets.md) | Accuracy targets, the error taxonomy and the release gate |
| [segments.md](segments.md) | What each kind of speaker needs, and which corpus slice measures it |
| [measure-a-change.md](measure-a-change.md) | Measuring a change |
| [ci-tiers.md](ci-tiers.md) | Which gate runs per pull request, nightly and before a release |
| [measuring-accuracy.md](measuring-accuracy.md) | Measuring speech accuracy |
| [core-word-error-rate.md](core-word-error-rate.md) | Word error rate |
| [eval-methodology.md](eval-methodology.md) | How `uttrflow-eval transcribe` measures a recogniser |
| [disfluency-deletion.md](disfluency-deletion.md) | Disfluency removal scored by the words deleted, per class |
| [eval-context-cases.md](eval-context-cases.md) | The Hinglish and context cases in the evaluation corpus |
| [eval-profiling.md](eval-profiling.md) | Reading memory and processor use from inside the process |
| [performance.md](performance.md) | What Uttrflow costs a Mac |
| [performance-dictation.md](performance-dictation.md) | How long a dictation takes, and how accurate it is |
| [performance-suggestions.md](performance-suggestions.md) | What AI suggestions cost a Mac |
| [performance-idle.md](performance-idle.md) | What Uttrflow costs while nobody is using it |
| [performance-leaks.md](performance-leaks.md) | Leaks |
| [probe-log.md](probe-log.md) | Probe log — where, when and on which build every number was measured |
| [bakeoff.md](bakeoff.md) | Clean-up bake-off |
| [mutation-guard.md](mutation-guard.md) | Which meaning-guard checks a test would miss, by mutation |
| [bakeoff-method.md](bakeoff-method.md) | How the bake-off measures, and why each row is there |

## Building, testing and shipping

| Page | What it covers |
|---|---|
| [development-build.md](development-build.md) | The development build |
| [soak.md](soak.md) | Watching the heap over hours |
| [ui-tests.md](ui-tests.md) | Driving the real app |
| [packaging.md](packaging.md) | Packaging Uttrflow.app |
| [releasing.md](releasing.md) | Releasing Uttrflow |
| [rollback.md](rollback.md) | Rolling back a release |
| [operator-runbook.md](operator-runbook.md) | Operator runbook |
| [definition-of-done.md](definition-of-done.md) | Definition of done |
| [preferences-suites.md](preferences-suites.md) | Temporary `UserDefaults` suites in tests |
| [ux-test-harness.md](ux-test-harness.md) | UX test harness traps |
| [test-flakes.md](test-flakes.md) | Flaky tests |
| [account-tests-keychain-adhoc.md](account-tests-keychain-adhoc.md) | Ad-hoc-signed builds and the data-protection keychain |
| [agents/code-quality.md](agents/code-quality.md) | Code quality |
| [agents/product.md](agents/product.md) | Product rules |
| [agents/workflow.md](agents/workflow.md) | Workflow: from branch to merged pull request |
| [agents/public-boundary.md](agents/public-boundary.md) | What must never reach a tracked file |
| [disclosure-gate.md](disclosure-gate.md) | The disclosure gate |
| [tooling-traps.md](tooling-traps.md) | Tooling traps |
| [python-scripts.md](python-scripts.md) | Python scripts and their imports |
| [graphflow.md](graphflow.md) | Graphflow in this repository |

Two pages here tell an operator to run a command in the private backend repository:
[operator-runbook.md](operator-runbook.md) and [releasing.md](releasing.md). Everything else
can be followed with this repository alone.
