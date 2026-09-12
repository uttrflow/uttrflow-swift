# Dictating with no network

Uttrflow's claim is that hold-key → capture → transcribe → tidy → insert touches the
network zero times once the speech model is on disk. This is the evidence for that
claim and the things it does not prove.

Re-run the static half with `./Scripts/offline_audit.sh`. It exits non-zero if a new
network call site appears on the dictation path.

**Nobody's Wi-Fi was switched off to produce any of this.** The network was denied per
process with `sandbox-exec`, which needs no system setting and affects nothing outside
the process it launches.

## Method

Three kinds of evidence, because no one of them is enough on its own.

| | What it can show | What it cannot |
|---|---|---|
| Source audit | Every call site somebody wrote | Nothing about dependencies compiled from elsewhere, or about what actually runs |
| Binary audit | Which linked module can open a connection at all | When, or whether, it does |
| Sandboxed run | What the code really does, once | Only the paths that run actually get exercised |

The sandbox profile is three lines:

```scheme
(version 1)
(allow default)
(deny network* (with send-signal SIGKILL))
```

`SIGKILL` rather than a plain deny is what makes a *successful* run mean something. A
denied connection returns an error the program might swallow and carry on from; a
killed process cannot. So a run that exits 0 under this profile has provably not made a
single network syscall. Verified against a control first:

```
$ sandbox-exec -f kill-on-net.sb /usr/bin/curl -s -m 8 -o /dev/null https://1.1.1.1
curl EXIT=137        # 128 + SIGKILL
```

## Every network call site

### Uttrflow's own sources: one, and it is compiled out

`URLSession`, `URLRequest`, `NWConnection`, `Network.framework`, raw sockets and
`https://` literals, across all of `Sources/`, produce exactly three hits, all in
`Sources/UttrflowAI/HTTPCleanupModel.swift`, all inside `#if UTTRFLOW_CLOUD`.

That the flag is genuinely off in the shipped build is confirmed from the artefact, not
from reading the `#if`:

```
$ nm -a .build/arm64-apple-macosx/debug/Uttrflow | swift demangle | grep -c 'UttrflowAI.HTTPCleanupModel'
0
$ nm -a .build/.../UttrflowAI.build/HTTPCleanupModel.swift.o | swift demangle \
    | grep -v 'FORCE_LOAD\|reflection_version\|ltmp\|module_hash'
(nothing)
```

The object file exists and contains nothing but autolink stubs — not one symbol from
the source it was compiled from. The only symbols in the
whole binary that mention the cloud at all are the `cloudEndpoint:` argument labels on
`TextTransformers.all` and `.router` — the parameter survives, the engine does not. A
caller that passes an endpoint to a non-cloud build gets it ignored, which is asserted
in `Tests/UttrflowAITests/OfflineGuaranteeTests.swift` rather than left to inspection.

### Dependencies: one module, and it is the model downloader

The app links nineteen Swift modules. Counting undefined `URLSession` symbols in each
module's object files, exactly one can open a connection:

| Module | URLSession refs | In the app? |
|---|---|---|
| `Hub` (swift-transformers) | 13 | **yes** — the model downloader |
| `HuggingFace` (swift-huggingface) | 37 | no — `uttrflow-bakeoff` only |
| `EventSource` | 6 | no — pulled in by MLX, bake-off only |
| `UttrflowLocalModel` | 3 | no — bake-off only |
| `WhisperKit`, `ArgmaxCore`, `Tokenizers`, `Jinja`, `Crypto`, `yyjson`, the seven Uttrflow modules, collections | 0 | yes |

`swift-crypto` is linked but is pure computation — Hub uses it to hash downloaded files.
`ArgmaxCore.ModelDownloader` wraps Hub and is never instantiated anywhere in this
build: it is linked and unreachable.

So every network call the shipping app is capable of making goes through `Hub`, and
Hub is reached from exactly two places.

### When Hub runs

**1. Installing a speech model — deliberate, and not on the dictation path.**
`FileSystemSpeechModelStore.whisperKit()` builds a downloader around `WhisperKit.download`.
It runs only when something calls `store.install(_:onProgress:)`, which today is only
`uttrflow-dev models install`. The app itself never calls it (see *Nothing installs the
model* below). Loading a model passes `download: false`, so a missing model is an error
rather than a silent 646 MB transfer mid-dictation; `offline_audit.sh` guards that.

**2. Loading the tokenizer — accidental, and squarely on the dictation path.** This is
the one real hole, below.

`HubApi` also starts an `NWPathMonitor` to decide whether to use its offline mode. That
observes the interface state; it opens nothing. It did not trip the SIGKILL profile.

## The pipeline runs offline: the evidence

`uttrflow-dev transcribe <file>` is the closest runnable slice of the dictation path:
read audio → resample to canonical → WhisperKit → `TextTransformers.router()` → output.
It is the same `AudioSamples`, the same `BackedSpeechEngine` and the same router the app
builds, with a file standing in for the microphone.

```
$ sandbox-exec -f kill-on-net.sb ./uttrflow-dev transcribe offline-probe.aiff

So the offline audit is working. No network at all.

  as heard     Um so the offline audit is a working. No network at all.
  audio        3.49s
  engine ready 4.29s
  transcribed  0.82s  (4.2× real time)
  tidied by    foundationModels in 1.65s
  language     en
  segments     2
  memory       0.01GB idle → 0.12GB ready → 0.18GB peak
EXIT=0
```

Exit 0 under a profile that kills on the first network syscall. Speech-to-text ran,
Apple's Foundation Models ran, and neither reached for anything. The audio was
synthesised locally with `say`, so even the fixture involved no network.

One thing worth knowing before somebody files a bug about it: the *first* offline run
after the model is installed took **301.91s** to reach "engine ready". The second took
**4.09s**. That is Core ML compiling the model for the Neural Engine, not a network
timeout — it happens under the SIGKILL profile, which a timeout could not.

### The test suite, offline

```
$ sandbox-exec -f deny-net.sb xcrun swift test --disable-sandbox
✔ Test run with 579 tests in 83 suites passed after 0.292 seconds.
EXIT=0
```

Use the plain `(deny network*)` profile for this, not the SIGKILL one: SwiftPM's own
build machinery talks to itself over local sockets, which macOS classifies as network
and which would kill the build before a single test ran. `--disable-sandbox` is needed
for the same reason — SwiftPM sandboxes manifest evaluation itself, and sandboxes do
not nest.

## The tokenizer: a hole this audit found, and the install now fills

`download: false` governs the *model*. It does not govern the tokenizer, so the install
fetches the tokenizer itself and `tokenizerFolder` is pinned at the model folder —
`TokenizerDownload` writes `tokenizer.json` and `tokenizer_config.json` beside the weights
during `install`, `isInstalled` is false until both are there, and `load()` refuses to start
without them. `Docs/speech-engines.md` § Keeping WhisperKit off the network says how that is
arranged; what follows is the measurement that asked for it.

After loading the model, WhisperKit calls `loadTokenizerIfNeeded`, which looks for
`tokenizer.json` in the model folder and in Hub's cache — and, failing that,
**downloads it from Hugging Face**. When this audit ran, Uttrflow passed no
`tokenizerFolder`, so Hub's cache was its default: `~/Documents/huggingface/`. That
directory is not the model store. The store did not create it, did not count it in
`isInstalled`, and did not delete it in `remove`.

On the machine this audit ran on, the two were in different places and were fetched at
different times:

```
~/Library/Application Support/Uttrflow/Models/openai_whisper-large-v3-v20240930_turbo_632MB/
    AudioEncoder.mlmodelc  MelSpectrogram.mlmodelc  TextDecoder.mlmodelc
    TextDecoderContextPrefill.mlmodelc  config.json  generation_config.json
    ← no tokenizer.json.  Written 19:19–19:27 by `models install`.

~/Documents/huggingface/models/openai/whisper-large-v3/
    tokenizer.json  tokenizer_config.json  config.json
    ← written 19:30, by the first transcription.
```

So `models install` reported success, `isInstalled` said yes, and the tokenizer was still
missing. It arrived on the first transcription — over the network.

Proved by hiding only that directory and changing nothing else:

```
$ sandbox-exec -f 'deny network* + deny read ~/Documents/huggingface' \
    ./uttrflow-dev transcribe offline-probe.aiff
EXIT=137
```

Killed. With the tokenizer cache visible, the identical command under the identical
profile exited 0. The difference between the two runs was one directory, and it was worth
a network call on the dictation path.

**Who it bit.** Anyone who installed the model and went offline before dictating once.
That included the intended first-run story — download on first launch, work offline
afterwards — if the user quit between the download and their first dictation. It bit a
side-loaded or restored-from-backup model store too, which is why an install made by an
older build is repaired rather than trusted.

**What they saw.** The dev tool reported
`modelLoadFailed(description: "Download failed: …")`. In the app the same error became
`SpeechEngineError.modelLoadFailed`, so the user got *"Speech recognition couldn't
start. Try again, or reinstall it from Settings."* — a complete sentence, but it named
the wrong cause and offered `.retry`, which failed identically every time.

**The fix landed in the store rather than the backend**, which is where the gap was.
`SpeechModelStore.missingComponents(of:)` treats the tokenizer as a component of its own,
answered by `TokenizerAssets.arePresent(in:)`, so `isInstalled` means what it says;
`install` fetches every missing component and throws if one did not arrive; and
`WhisperKitBackend` passes `tokenizerFolder: modelFolder`, so the search never reaches Hub's
cache. `FileSystemSpeechModelStoreTests` pins the repair of an install made by a build that
predates all of this.

`offline_audit.sh` § Tokenizer takes the pass branch on that pinned folder — "a tokenizer
folder is pinned, so loading cannot fall back to the hub" — and fails if it ever disappears,
so the fix cannot be quietly undone. The KNOWN GAP note it prints instead is the branch that
no longer runs.

## No model, no network

Tested, because it is the real first-run failure.

**Trying to install with no connection** — a variant that was genuinely absent, so
nothing already on disk was at risk:

```
$ sandbox-exec -f deny-net.sb ./uttrflow-dev models install --model openai_whisper-base
Installing openai_whisper-base — 147 MB
Error: modelDownloadFailed(description: "Download failed: … Operation not permitted")
EXIT=1
```

The store's clean-up works: no half-installed directory was left behind. In the app that
error reads *"Setup couldn't be completed. Check your connection and try again."* with a
`.downloadSpeechModel` action — the right sentence for the situation.

**Dictating with no model** stops before the network is ever needed:

```
$ sandbox-exec -f 'kill-on-net + deny read ~/Library/Application Support/Uttrflow' \
    ./uttrflow-dev transcribe offline-probe.aiff
openai_whisper-large-v3-v20240930_turbo_632MB is not installed. Run: uttrflow-dev models install
```

In the app the same condition raises `.modelNotInstalled` — *"Speech recognition needs
to finish setting up before you can dictate."* with a `.downloadSpeechModel` action.
No hang, no crash. Two problems with it, though:

### The model download path still has a gap

The **Download** button for `.downloadSpeechModel` is no longer inert. `DockView` sends
the recovery action through `DockPanelController`, and `AppDelegate.wireInterface()`
assigns the handler. `AppDelegate.perform(_:)` responds by opening the Settings window
on the **Dictation** tab.

That is useful navigation, but it is not an installer. The Dictation settings pane
offers the speed-and-accuracy choice and other preferences; it does not call
`SpeechModelStore.install`. The actual download lives in the onboarding setup flow:
`OnboardingFlow` enters `.setup`, then `beginInstall()` calls the injected installer.

This matters after somebody has dismissed onboarding. **Finish Setup** now opens Settings
→ Dictation, where the user can see the speech-recognition choice but cannot start the
download. The model can still be installed by the first-run setup flow when that flow is
available, or with `uttrflow-dev models install`; the recovery action itself does not
reopen the installer. The offline promise is therefore still conditional on the model
having been installed somewhere before dictation is attempted.

### Startup now says what happened

At launch, `AppDelegate.loadSpeechModel()` first asks the model store whether the default
model is installed. If it is absent, it records `.notInstalled` and returns; it does not
claim that the app is ready. If the files are present, it reports `.loading` while it
awaits `DictationPipeline.prepare()`.

`DictationPipeline.prepare()` now catches a failed speech-engine load, keeps `isReady`
false, and publishes a failed state when no dictation is in progress. The app maps a
successful preparation to `.ready` and an unsuccessful one back to `.notInstalled`, so
the menu bar can say *"Getting ready…"* or *"Setup hasn't finished"* instead of leaving
the user with a false *"Ready"*. A missing model is still a setup state rather than a
startup exception, but it is no longer silently discovered only after the first keypress.

## What this does not prove

- **The microphone and the insertion steps were not exercised offline.** `AVAudioCaptureEngine`
  needs a real hold-to-talk gesture and `TextInsertionCoordinator` needs a focused text
  field in another app; neither can be driven headlessly, and the sandbox cannot grant
  the TCC permissions they require. Both are argued to be network-free from the source
  audit only: `UttrflowAudio` and `UttrflowInput` contain no network call site, and
  `offline_audit.sh` keeps it that way. The sandboxed run does exercise the second half
  of capture — `AudioFileReader` hands its samples through the same `AudioResampler` the
  microphone path uses — but a full hold-key-to-inserted-text run offline has not been
  observed.
- **Apple's frameworks are taken at their word.** `FoundationModels`, `Speech` and
  `CoreML` are closed. The sandboxed run shows that none of them opened a socket *from
  this process*; work they hand to a system daemon over XPC is outside the sandbox and
  outside what this can see. For `FoundationModels` that is Apple's documented
  on-device guarantee, not something measured here.
- **`AppleSpeechBackend` is not offline-safe on first use, and was not tested.** Its
  `load()` calls `AssetInventory.assetInstallationRequest(...).downloadAndInstall()`,
  which fetches a system speech asset. That is a network call on the dictation path
  whenever the locale's asset is absent — it returns immediately once `status` is
  `.installed`. It is off the shipping path (`EngineConfiguration.default.speech` is
  `.whisperKit`) but one settings change away, and the audit does not flag it because
  the download is Apple's, not Uttrflow's.
- **Only the paths that ran were tested.** A sandboxed run proves what happened, not
  what would happen on a different model, locale or failure branch. That is what
  `offline_audit.sh` is for.

## Summary

The app is offline-safe on the dictation path **except** for WhisperKit's tokenizer
load, which reaches Hugging Face on any Mac that has installed the speech model but not
yet transcribed while online. Everything else — Uttrflow's own code, the clean-up
engines, the router, the model load itself — completed under a profile that kills the
process for touching the network.
