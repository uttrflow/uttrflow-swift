# Uttrflow documentation

A page per subsystem. Each one holds what the code cannot say for itself: a measured number,
a platform trap, an approach that was tried and does not work. Comments in the source are one
line and link here rather than carrying the explanation themselves.

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
| [pipeline-gestures.md](pipeline-gestures.md) | How a gesture becomes a dictation |
| [shortcuts.md](shortcuts.md) | Watching for the shortcut |
| [microphone.md](microphone.md) | The microphone, and the hardware moving under it |
| [audio-capture.md](audio-capture.md) | Capturing the microphone |
| [silence.md](silence.md) | Silence, and why it has to be caught before the recogniser |
| [speech-engines.md](speech-engines.md) | The speech engines, and what WhisperKit does when nobody is looking |
| [early-transcription.md](early-transcription.md) | Working ahead while the key is held |
| [pipeline-changes.md](pipeline-changes.md) | What the pipeline changes about a dictation, and how it stays honest |
| [insertion.md](insertion.md) | Putting the words on screen, and the traps in doing it |
| [stuck-recording.md](stuck-recording.md) | The recording that never stops |
| [recordings.md](recordings.md) | Recordings kept for retry |

## Making the words better

| Page | What it covers |
|---|---|
| [cleanup.md](cleanup.md) | What the tidier may do to your words |
| [cleanup-design.md](cleanup-design.md) | Clean-up: the low-level design |
| [ai-model-output.md](ai-model-output.md) | What a small model does to dictation, and the guards that catch it |
| [ai-context-line.md](ai-context-line.md) | The context line, measured |
| [ai-correction-thresholds.md](ai-correction-thresholds.md) | Word correction: the numbers and why they are what they are |
| [app-dictionary.md](app-dictionary.md) | Personal dictionary: phonetics and learning |

## Tab-to-complete

| Page | What it covers |
|---|---|
| [predict.md](predict.md) | Tab-to-complete, and the rules that keep it quiet |
| [predict-probe.md](predict-probe.md) | Phase 0 — what tab-to-complete can rely on |
| [predict-context.md](predict-context.md) | Context-aware suggestions: register, surroundings and personal style |
| [predict-accept.md](predict-accept.md) | Accepting a suggestion |
| [predict-ime.md](predict-ime.md) | Detecting a composing input method |
| [predict-llm.md](predict-llm.md) | The LLM-arbitrated design |
| [predict-agent.md](predict-agent.md) | The machine as the agent's tools |
| [predict-reliability.md](predict-reliability.md) | Reliability loop for tab-to-complete |

## The clipboard and its panel

| Page | What it covers |
|---|---|
| [panel.md](panel.md) | The clipboard panel |
| [app-quick-panel.md](app-quick-panel.md) | Quick panel: measurements and platform traps |
| [ux-panel-geometry.md](ux-panel-geometry.md) | Quick panel geometry: resizing and placement |
| [ux-panel-insertion.md](ux-panel-insertion.md) | Deciding whether the panel can paste |
| [clipboard-secrets.md](clipboard-secrets.md) | Recognising a credential |
| [clipboard-plain-form.md](clipboard-plain-form.md) | Rich clips as plain text |
| [clipboard-code-language.md](clipboard-code-language.md) | Code language detection |
| [clipboard-reindent.md](clipboard-reindent.md) | Re-indenting a code clip |
| [clipboard-budget.md](clipboard-budget.md) | Clipboard memory budget |

## The app's windows

| Page | What it covers |
|---|---|
| [startup.md](startup.md) | Launching, and the minute before the app can dictate |
| [app-main-window.md](app-main-window.md) | Main window: sizing and the clipboard demonstration |
| [app-dock.md](app-dock.md) | Dock button: measurements and traps |
| [app-onboarding.md](app-onboarding.md) | Onboarding window: sizes and the provider marks |
| [ux-onboarding.md](ux-onboarding.md) | Onboarding: the rules the flow is built on |
| [ux-figures.md](ux-figures.md) | The figures on Dictation and Insights |
| [app-updates.md](app-updates.md) | Updates: why the app holds Sparkle's install handle |
| [quitting.md](quitting.md) | Quitting |

## What is kept, and what leaves the Mac

| Page | What it covers |
|---|---|
| [offline.md](offline.md) | Dictating with no network |
| [entitlements.md](entitlements.md) | What somebody is allowed to do, and how that is known offline |
| [account-session.md](account-session.md) | The account session |
| [account-keychain.md](account-keychain.md) | The refresh token in the Keychain |
| [account-transport.md](account-transport.md) | Why the transport has no cache |
| [account-telemetry.md](account-telemetry.md) | What leaves the Mac, and why a dictation never waits for it |
| [core-history-decoding.md](core-history-decoding.md) | Decoding a stored history: one unreadable change costs one change |
| [core-history-undo.md](core-history-undo.md) | Undoing a correction: how the words are found and when they are left alone |
| [core-history-accuracy.md](core-history-accuracy.md) | The accuracy figure: where its denominator comes from |

## Settings and system behaviour

| Page | What it covers |
|---|---|
| [core-hotkeys.md](core-hotkeys.md) | Shortcut bindings: what `HotkeyBinding` decides and why |
| [core-settings-launch-at-login.md](core-settings-launch-at-login.md) | Why launch-at-login re-reads instead of believing `SMAppService` |
| [core-engine-kinds.md](core-engine-kinds.md) | Which transformer kinds a build contains |

## Measuring it

| Page | What it covers |
|---|---|
| [measuring-accuracy.md](measuring-accuracy.md) | Making speech accuracy measurable |
| [core-word-error-rate.md](core-word-error-rate.md) | How word error rate is measured, and why it lives in Core |
| [eval-methodology.md](eval-methodology.md) | How `uttrflow-eval transcribe` measures a recogniser |
| [eval-context-cases.md](eval-context-cases.md) | The context pairs in the evaluation corpus |
| [eval-profiling.md](eval-profiling.md) | Reading memory and processor use from inside the process |
| [performance.md](performance.md) | What Uttrflow costs a Mac |
| [bakeoff.md](bakeoff.md) | Local model bake-off |

## Building, testing and shipping

| Page | What it covers |
|---|---|
| [development-build.md](development-build.md) | The development build |
| [packaging.md](packaging.md) | Packaging Uttrflow.app |
| [releasing.md](releasing.md) | Releasing Uttrflow |
| [operator-runbook.md](operator-runbook.md) | Operator runbook |
| [definition-of-done.md](definition-of-done.md) | Definition of done |
| [preferences-suites.md](preferences-suites.md) | Temporary `UserDefaults` suites in tests |
| [ux-test-harness.md](ux-test-harness.md) | UX test harness traps |
| [account-tests-keychain-adhoc.md](account-tests-keychain-adhoc.md) | Ad-hoc-signed builds and the data-protection keychain |

Two pages here tell an operator to run a command in the private backend repository:
[operator-runbook.md](operator-runbook.md) and [releasing.md](releasing.md). Everything else
can be followed with this repository alone.
