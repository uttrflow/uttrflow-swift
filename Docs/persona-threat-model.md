# Threat model for learned personal data

Uttrflow learns about the person using it: the words they use, the lines they type, which
applications they allowed it to learn in. This page is the one place that lists what is
learned, who could get at it, what stops them, the test or script that proves each
mitigation, and what is left over. A change that stores learned data updates this page in the
same pull request; the checklist for that is in
[`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md).

The persona store of derived aggregates and the edit learner that watches a field after
insertion are not in the tree yet. Each of them adds its asset rows, mitigation rows and
residual risks here when it lands, and is held to the rules below.

## Rules

1. **Nothing learned leaves the Mac.** No learned value, aggregate or per-application map is
   sent anywhere, in any form, by any module. Checked by `make offline-audit`
   ([offline.md](offline.md)).
2. **An application name never leaves the device.** Bundle identifiers and application names
   key several stores and appear in the unified log; neither crosses the network, and a crash
   report carries none of them. Checked by `make offline-audit` and
   `Tests/UttrflowDiagnosticsTests/CrashReporterTests.swift`.
3. **Every learned store is resettable.** Reset personalisation removes it, and a store that is
   added without a reset target is a bug.
4. **Learning stops where it is refused.** Text from a secure field is never read, and an
   application the user declined teaches nothing. An application nobody has been asked about is
   learned from, because everything learned stays on this Mac; that default is
   `ConsentState.dictationMayLearn` and `CapturePreferences` ([predict.md](predict.md)).
   **Learn from my dictation**, off in Settings, declines every application at once before the
   learner runs (`SwitchedLearningConsent`).

## Assets

| Asset | Where it lives | Encrypted at rest | In the export archive | Cleared by |
|---|---|---|---|---|
| Learned dictionary words (from titles seen and said, and from the user's own corrections) | `dictionary.v1.json`, `Sources/UttrflowDictionary/PersonalDictionaryStore.swift` | yes | yes | `removeLearned()`, reset |
| Words the user deleted from the dictionary | `dictionary.v1.refused.json`, same file | **no** | no | reset |
| Pending sightings of title words | memory only ([app-dictionary.md](app-dictionary.md)) | not on disk | no | quit, reset |
| Lines learned from typing or accepted suggestions per surface (application, role, document) | the suggestion corpus, `Sources/UttrflowPredictStore/PredictStore.swift` | yes | no | per-application forget, reset |
| Per-application capture consent | `predict-consent.v1.json`, `Sources/UttrflowPredictCapture/CapturePreferences.swift` | **no** | no | reset |
| Dictation history | `Sources/UttrflowHistory/DictationHistoryStore.swift` | yes | no | retention, reset |
| Snippets | `Sources/UttrflowAI/SnippetStore.swift` | yes | yes | reset |

## Adversaries and non-adversaries

| Who | Can they reach the assets? |
|---|---|
| Another local user account | No: owner-only modes on every file and folder. |
| A copy of the store folder (backup, migration, `tar`, external disk) | Sees ciphertext for encrypted stores; the key is device-only and stays in the Keychain. Sees plaintext for the two unencrypted files above. |
| A process running as the same user | Yes, while the session is unlocked. Out of scope: it can read the screen and the Keychain item as well. |
| The export archive, once written | Yes: it is plaintext JSON wherever the user saved it. |
| A crash or hang report | No learned value, and no application name: the event is scrubbed before it leaves. |
| The unified log | Lengths and application identifiers only, never typed, read or said text. Stays on the Mac unless the user shares a system diagnostic. |
| Somebody looking at the screen | Yes: Settings lists dictionary words and the applications that taught the corpus. |
| A page or document that shows text to feed the learner | Limited: a title word must also be spoken in three separate dictations, and learned lines come from the user's keystrokes or accepted suggestions in an application they have not declined. |
| Uttrflow's own servers | Not an adversary for this data, because none of it is sent. |

## Mitigations

| Mitigation | Proved by |
|---|---|
| Store files are `0600` in `0700` folders and excluded from backup | `Tests/UttrflowCoreTests/PrivateFileTests.swift`, `make store-permissions` |
| Encrypted stores refuse a wrong key, a swapped filename and a modified envelope, and never read as empty | `Tests/UttrflowCoreTests/EncryptedStoreTests.swift` |
| Reset revokes the encryption key after every target is cleared | `Tests/UttrflowUXTests/SettingsResetTests.swift` |
| Forgetting an application, a line or everything leaves none of it in the corpus or its log | `Tests/UttrflowPredictStoreTests/ForgettingLeavesNothingTests.swift`, `Tests/UttrflowTests/SuggestionForgettingTests.swift` |
| Only learned dictionary words are removed by `removeLearned()` | `Tests/UttrflowDictionaryTests/PersonalDictionaryStoreTests.swift` |
| A word is learned only after three sightings that were also spoken, never from window chrome | `Tests/UttrflowDictionaryTests/DictionaryLearningTests.swift`, `Tests/UttrflowDictionaryTests/LearnableWordsTests.swift` |
| Secure and one-time-code fields are refused before consent is consulted; unasked applications are refused | `Tests/UttrflowPredictCaptureTests/CaptureGateTests.swift` |
| A declined application, or the Settings switch turned off, teaches dictation nothing | `Tests/UttrflowPipelineTests/DictationLearningConsentTests.swift` |
| Secrets are swept out of captured lines | `Tests/UttrflowPredictCaptureTests/SecretSweepTests.swift` |
| Nothing is read in or around a secure field | `Tests/UttrflowContextTests/SurroundingsSecureTests.swift`, `Tests/UttrflowCoreTests/SecureFieldTests.swift` |
| Dictation into a secure field is marked as kept nowhere | `Tests/UttrflowPipelineTests/DictationSecureFieldTests.swift` |
| A credential-shaped dictation is inserted and kept nowhere | `Tests/UttrflowPipelineTests/DictationCredentialTests.swift` |
| A secure-field or credential-shaped dictation counts no dictionary word or snippet and writes no evidence row | `Tests/UttrflowTests/PersonaSecureFieldTests.swift` |
| No log line carries typed, read or said text | `make log-audit`, `Tests/UttrflowTests/SuggestionLogTests.swift` |
| A crash report carries no path, host name, message or application data | `Tests/UttrflowDiagnosticsTests/CrashReporterTests.swift` |
| The dictation path cannot reach the network | `make offline-audit` |
| An archive import is validated whole before either store changes | `Tests/UttrflowAITests/PersonalDataArchiveTests.swift`, `Tests/UttrflowAITests/PersonalDataTransferTests.swift` |
| A personal-data export is created owner-only before any byte is written, and the user is warned it is not encrypted | `Tests/UttrflowCoreTests/PrivateFileTests.swift`, `Tests/UttrflowTests/PersonalDataExportTests.swift` |
| A personal-data export writes only its allow-listed fields, so no evidence row or projection reaches it | `Tests/UttrflowTests/PersonalDataExportTests.swift` |

## Residual risks

- **Two learned files are not encrypted.** The dictionary's refusal record lists words the user
  deleted, and the consent file lists every application the corpus has asked about. Both are
  owner-only and backup-excluded, but a copy of the folder reads them.
- **The export archive is plaintext.** It is written owner-only by
  `AppDelegate.exportPersonalData`, and the user is warned before it is written, but a copy of
  the file reads it.
- **A same-user process sees everything** while the session is unlocked. Encryption protects
  data at rest, not a running session ([local-store-encryption.md](local-store-encryption.md)).
- **Old disk blocks and old backups** keep whatever was there before encryption or deletion.
- **A system diagnostic** the user chooses to share carries the unified log, application
  identifiers included.
- **A screenshot of Settings** shows learned words and the applications that taught the corpus.
- **Learning is on until the person acts.** It runs in every application not declined until
  **Learn from my dictation** is turned off; nothing asks first.
