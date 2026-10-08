# Dictating with no network

Uttrflow's claim is that hold-key → capture → transcribe → tidy → insert touches the network
zero times once the speech model is on disk. This page is the evidence for that claim and the
list of what it does not prove. The static half is `Scripts/offline_audit.sh`, which runs in
`make verify`; the dynamic half is a set of sandboxed runs of `uttrflow-dev` and the test
suite, recorded below with the commands that produced them.

Network access that is not dictation lives elsewhere: sign-in in `UttrflowAccount` and the
onboarding window, the model downloads at install time, the updater
([app-updates.md](app-updates.md); scheduled checks can be turned off in the General tab, and
**Check Now** makes a request only when asked) and opt-in crash reports
([crash-reporting.md](crash-reporting.md)).

```bash
./Scripts/offline_audit.sh                   # audit, building the app if needed
./Scripts/offline_audit.sh --no-build        # skip the binary check when nothing is built
./Scripts/offline_audit.sh --require-binary  # fail rather than skip it (the default when CI is set)
```

The sandboxed runs deny the network per process with `sandbox-exec`, which needs no system
setting and affects nothing outside the process it launches.

## Method

Three kinds of evidence, because no one of them is enough on its own.

| | What it can show | What it cannot |
|---|---|---|
| Source audit | Every call site somebody wrote | Nothing about dependencies compiled from elsewhere, or about what actually runs |
| Binary audit | Which linked object can open a connection at all | When, or whether, it does |
| Sandboxed run | What the code really does, once | Only the paths that run get exercised |

The sandbox profile `kill-on-net.sb` is three lines:

```scheme
(version 1)
(allow default)
(deny network* (with send-signal SIGKILL))
```

`SIGKILL` rather than a plain deny is what makes a *successful* run mean something. A denied
connection returns an error the program might swallow and carry on from; a killed process
cannot. So a run that exits 0 under this profile made no network syscall. The control:

```
$ sandbox-exec -f kill-on-net.sb /usr/bin/curl -s -m 8 -o /dev/null https://1.1.1.1
curl EXIT=137        # 128 + SIGKILL
```

`deny-net.sb` is the same profile with a plain `(deny network*)`, for the runs below that need
the build tools to work.

## Every network call site

### Uttrflow's own sources

The audit's source pattern (Foundation's URL stack, Network.framework in both spellings,
CFNetwork, the BSD calls, XPC, the speech asset installer, `mlx_distributed`, and `http(s)://`
literals) matches these files under `Sources/`:

| Where | Files | Why |
|---|---|---|
| `Sources/UttrflowAccount/` | 4 files match; the whole module is allowed | sign-in, session refresh and telemetry |
| `Sources/Uttrflow/Onboarding/` | `NetworkReachability+System.swift`, `OnboardingAccountLayer.swift`, `OnboardingWindowController.swift` | first-run sign-in, and the banner that says why it failed |
| `Sources/UttrflowSpeech/TokenizerDownload.swift` | 1 | fetches the speech model's weights and tokenizer at install time |
| `Sources/uttrflow-dev/SignIn.swift`, `Sources/uttrflow-eval/CorpusConnection.swift` | 2 | developer tools that ship in nothing |

The source audit also recognizes local URL readers only after each call site has been reviewed
for its URL origin. The reviewed readers cover files under Application Support, bundled resources,
the temporary audio file produced by `say`, and the baseline path supplied to `uttrflow-dev seams`.
The formatting corpus contains a URL in an expected transcript; escaped slash characters keep that
fixture text in `Sources/UttrflowEval/FormattingCorpus.swift` out of the source audit's
network-literal pattern while Swift still constructs the same transcript. Every other module under
`Sources/` has no network match, and that is what the audit's first check asserts.

No clean-up engine is hosted: `TextTransformers.all` assembles only on-device engines, and
`Tests/UttrflowAITests/OfflineGuaranteeTests.swift` asserts every assembled and selectable kind
runs without the network. `TransformerKind.cloud` survives only so a stored record naming it
still decodes; it is never selectable.

### What the person can see

Each shipped call site counts its requests in `NetworkActivityLedger` (`UttrflowCore`) under a
closed `NetworkPurpose`: account, model download, update check, crash report, usage statistics.
The ledger keeps a count per purpose per day for 30 days, as integers and dates only, in
`network-activity.v1.json` beside the other local stores, and never sends it anywhere. The
Privacy pane lists each purpose with its count, and a "Dictation: 0 requests" row: dictation has
no purpose, so no request can be counted under it. Check 8 below keeps the two in step.

### Dependencies

The binary check reads the undefined symbols of every object the app links, against a family
of networking names rather than `URLSession` alone (Foundation's stack, Network.framework's C
entry points, CFNetwork, the BSD calls, XPC, and the system speech asset installer).

| Module | What can reach the network | In the app? |
|---|---|---|
| `Hub` (swift-transformers), `ArgmaxCore` | `URLSession` | yes, through WhisperKit; see *Tokenizer* for why loading never reaches it |
| `HuggingFace` (swift-huggingface), `EventSource` | `URLSession` | yes, the suggestion model's downloader |
| `UttrflowLocalModel` | `URLSession`, in the files that build the hub client | yes, the suggestion model |
| `UttrflowAccount`, and the app shell's onboarding | `URLSession`, `NWListener`, `NWPathMonitor` | yes, sign-in |
| `UttrflowSpeech` | `URLSession` in `TokenizerDownload.swift` | yes |
| `Cmlx` (MLX's C++ core) | `socket`, `connect`, `getaddrinfo` in `mlx/distributed/jaccl/utils.cpp` | yes, see below |
| Sparkle, Sentry | network clients by design | yes, confined by checks 6 and 6b |
| `WhisperKit`, `Tokenizers`, `Jinja`, `Crypto`, `yyjson`, the collections, every other Uttrflow module | nothing | yes |

**MLX's distributed backend is linked and unreachable.** `Cmlx` compiles MLX's multi-host
support, so the app binary contains the BSD socket calls whether or not anything uses them,
and mlx-swift exposes no build flag that drops it. Those calls run only from
`mlx_distributed_init`; no Uttrflow source names it, and the audit's source check fails on any
that does. mlx-swift's Swift surface has no distributed API, so reaching it would mean calling
the C symbol directly.

`swift-crypto` is linked but is pure computation. `ArgmaxCore.ModelDownloader` wraps Hub and is
never instantiated in this build.

### The speech model download

`FileSystemSpeechModelStore.whisperKit()` installs a model with `downloadWeights` and
`downloadTokenizer` in `Sources/UttrflowSpeech/TokenizerDownload.swift`: each file is fetched
from `huggingface.co` at a pinned commit (`SpeechModel.weightsRevision`,
`tokenizerRevision`) and checked against its recorded size and SHA-256. Installing runs from
onboarding's setup page and from `uttrflow-dev models install`, never from loading. Loading
passes `download: false` to WhisperKit, so a missing model is an error rather than a 646 MB
transfer (`SpeechModel.largeV3Turbo.downloadBytes` is 645,668,913) in the middle of a
dictation. The install is described in [speech-model-install.md](speech-model-install.md).

## The pipeline runs offline: the evidence

`uttrflow-dev transcribe <file>` is the closest runnable slice of the dictation path: read
audio, resample to canonical, WhisperKit, `TextTransformers.router()`, output. It builds its
recogniser with `SpeechEngineFactory.make` and its cleaner with `TextTransformers.router()`,
as the app does, with a file standing in for the microphone.

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

Exit 0 under a profile that kills on the first network syscall: speech-to-text and Apple's
Foundation Models both ran, and neither reached for anything. The audio was synthesised
locally with `say`.

The first run after an install is slow, and that is not a network timeout. In the same
measurement the first offline run took **301.91s** to reach "engine ready" and the second
**4.09s**. The difference is Core ML compiling the model for the Neural Engine, and it happens
under the SIGKILL profile, where a timeout could not.

### The test suite, offline

```
$ sandbox-exec -f deny-net.sb xcrun swift test --disable-sandbox
✔ Test run with 579 tests in 83 suites passed after 0.292 seconds.
EXIT=0
```

What the run shows is the exit status; the count is whatever the run held. Use the plain
`deny-net.sb` profile, not the SIGKILL one: SwiftPM's build machinery talks to itself over
local sockets, which macOS classifies as network and which would kill the build before a test
ran. `--disable-sandbox` is needed for the same reason: SwiftPM sandboxes manifest evaluation
itself, and sandboxes do not nest.

## Tokenizer

`download: false` governs the model, not the tokenizer. After loading the model, WhisperKit
calls `loadTokenizerIfNeeded`, which looks for `tokenizer.json` in its tokenizer folder and in
the Hub cache and, failing that, **downloads it from Hugging Face**. With no `tokenizerFolder`
given, that cache defaults to `~/Documents/huggingface/`, which is not the model store.

So the tokenizer is a component of the install:

- `TokenizerAssets.fileNames` is `tokenizer.json` and `tokenizer_config.json`, and
  `TokenizerAssets.arePresent(in:)` requires both, non-empty, in the model folder.
- `SpeechModelStore.missingComponents(of:)` lists the tokenizer separately from the weights, so
  `isInstalled` is false until both are on disk, and `install` fetches every missing component
  and throws if one did not arrive. An install that has the weights but no tokenizer is topped
  up without fetching the weights again.
- `WhisperKitBackend.load()` refuses with `.modelNotInstalled` when the tokenizer is absent, and
  passes `tokenizerFolder: modelFolder`, so the search never reaches the Hub cache.

`FileSystemSpeechModelStoreTests` covers the tokenizer cases (topping up, a failed or empty
fetch, keeping a tokenizer across a weights swap). Check 4 of `offline_audit.sh` fails if the
pinned `tokenizerFolder` disappears or becomes `nil`.

What happens without the pin, measured with a model folder that holds no tokenizer and the
tokenizer only in the Hub cache:

```
$ sandbox-exec -f 'deny network* + deny read ~/Documents/huggingface' \
    ./uttrflow-dev transcribe offline-probe.aiff
EXIT=137
```

With the cache readable, the same command under the same profile exits 0. The one directory
is the difference between a local load and a network call on the dictation path.

Loading the tokenizer still constructs WhisperKit's `HubApi`, which starts an `NWPathMonitor`
to decide whether to use its offline mode. That observes the interface state and opens
nothing; it does not trip the SIGKILL profile.

## No model, no network

**Installing with no connection**, for a variant that was not on disk:

```
$ sandbox-exec -f deny-net.sb ./uttrflow-dev models install --model openai_whisper-base
Installing openai_whisper-base — 147 MB
Error: modelDownloadFailed(description: "Download failed: … Operation not permitted")
EXIT=1
```

No half-installed directory is left behind. In the app that error reads *"Setup couldn't be
completed. Check your connection and try again."* with a `.downloadSpeechModel` action.

**Dictating with no model** stops before the network is needed:

```
$ sandbox-exec -f 'kill-on-net + deny read ~/Library/Application Support/Uttrflow' \
    ./uttrflow-dev transcribe offline-probe.aiff
openai_whisper-large-v3-v20240930_turbo_632MB is not installed. Run: uttrflow-dev models install
```

In the app the same condition raises `.modelNotInstalled`: *"Speech recognition needs to
finish setting up before you can dictate."* with a `.downloadSpeechModel` action. A model that
is present and fails to load raises `.modelLoadFailed`, *"Speech recognition couldn't start.
Try again."*, with `.retry`.

### Recovering from a missing or broken model

`AppDelegate.perform(_:)` handles `.downloadSpeechModel`:

- With the model absent, it opens onboarding (`show(.onboarding)`), whose setup page calls
  `beginInstall()` and shows progress, the same surface a first run uses. Dismissing onboarding
  once does not strand anybody: the action reopens it.
- With the model present but failing to load (`.loadFailed`, `.loadFailedAgain`), it calls
  `repairSpeechModel()`, which removes the install, resets readiness to `.notInstalled` and
  opens onboarding, so setup downloads a fresh copy instead of retrying the same load.

At launch `AppDelegate.loadSpeechModel()` asks the store first. An absent model records
`.notInstalled` (or `.incomplete` for a partial install) without loading; a present one shows
`.loading` while `DictationPipeline.prepare()` runs. The menu bar then reads *"Getting ready…"*,
*"Speech model didn't load"* or *"Speech model not downloaded"* rather than a false *"Ready"*.
See [startup.md](startup.md).

## The suggestion model

`MLXCandidateScorer.prepare()` loads the suggestion model whenever AI suggestions is turned on
or the weights are loaded again. It goes through
`LocalModel.weightsDirectory(cache:downloader:onProgress:)`, which reads the local Hugging Face
cache first. Loading straight through the hub client is avoided because it asks the model host for
the repository's file list before it looks in the cache, so every load on an online Mac would
open a connection even with every file present.

`CachedSnapshot.complete` accepts `snapshots/<LocalModel.revision>/` only when:

- the revision is a full 40-character commit hash;
- `config.json`, `tokenizer.json` and `tokenizer_config.json` are bounded, nonempty JSON objects;
- every `*.safetensors` file is exactly as long as its own header says, and every numbered
  shard its name implies is present (the shard index is not trusted as a list of files: one
  candidate's index names two shards while its repository holds one);
- the weights total at least `minimumWeightBytes`, nine tenths of `LocalModel.downloadBytes`.

Then the model loads from that directory and the hub is never constructed. Anything less goes
to the hub through `AnonymousHub.client()`, so a first download still works. A model already
whole on disk is never refreshed from the hub; a new revision arrives only when the cache is
missing or incomplete.

`CachedSnapshotTests` pins this with a downloader that counts and refuses every call, and
check 5 fails if a load takes the hub downloader directly.

Measured with `uttrflow-bakeoff gpu-memory --passes 1` against a cache holding the whole
`mlx-community/gemma-3-4b-it-qat-4bit` snapshot, under `kill-on-net.sb`:

| Load | Exit |
|---|---|
| through the hub downloader | 137, killed before "loaded" |
| through `weightsDirectory` | 0 |

## What the audit checks

`Scripts/offline_audit.sh` runs in `make verify` after `build`, because its binary check reads
object files. Every check is default-deny: every module and every linked object is covered
unless it is named, with the reason, in the script. A list of places to look would miss a
module nobody added to it; a list of what is allowed covers a new module by default.

| # | What it asserts | How |
|---|---|---|
| 1 | No file under `Sources/` names a way to reach the network, except `UttrflowAccount` and the files in `ALLOWED_NETWORK_FILES`; every named exception still exists; any known gap is printed every run | Source grep with `NETWORK_PATTERN` |
| 1b | No file reads a URL through `Data(contentsOf:)` or its siblings outside the files in `URL_READERS` | Source grep; see the limits below |
| 2 | No source or target names `UTTRFLOW_CLOUD`, so no build flag can switch a hosted engine back on | grep on `Package.swift` and `Sources/` |
| 3 | Loading a speech model passes `download: false`, and `HubApi`, `WhisperKit.download` and `AutoTokenizer` are named nowhere but the backend and the install file | Source grep |
| 4 | A non-`nil` `tokenizerFolder` is pinned, so loading cannot fall back to the hub | Source grep on `WhisperKitBackend.swift` |
| 5 | The suggestion model checks its cache before the hub, no load takes the hub downloader directly, the hub client is named only in `HUB_CLIENT_FILES`, no client is built with its defaults, no download sends a token or follows `HF_ENDPOINT`, and no model is fetched from a branch | Source grep |
| 6 | Sparkle is imported in one file in the app shell, and one target depends on it | Source grep, grep on `Package.swift` |
| 6b | Sentry is imported only in `UttrflowDiagnostics`, one target links it, and only the app depends on that module | Source grep, grep on `Package.swift` |
| 7 | No linked Uttrflow object can reach the network unless its source file is allowed one, and no network-capable dependency outside `ALLOWED_NETWORK_DEPENDENCIES` (`Hub ArgmaxCore HuggingFace EventSource Cmlx`) is linked | one `nm -uA` over every object in `Uttrflow.product/Objects.LinkFileList` |
| 8 | Every shipped call site in `LEDGER_FILES` records its requests in `NetworkActivityLedger`, and every `NetworkPurpose` is recorded somewhere | Source grep |

The URL-reader allowlist includes `UttrflowEval/AccuracyReport.swift` because the
non-shipping `accuracy-report` command reads the history file named by `--history`
(default `Docs/accuracy-history.json`). This is a file-backed evaluation input, not a
network client; the audit's source scan cannot prove where an arbitrary caller-supplied
file URL resolves, so a mounted network filesystem remains outside that claim.

Check 7 needs the built binary. With `--require-binary`, or whenever `CI` is set, a missing one
is a failure, because it is the only check that can see a dependency's network call. A bare
local run notes the skip and carries on, so a contributor mid-change gets the source checks in
a second or two. One `nm -uA` pass over every linked object, rather than one per file, is what
keeps the per-file resolution affordable in a gate.

## What this does not prove

- **The microphone and the insertion steps were not exercised offline.** `AVAudioCaptureEngine`
  needs a real hold-to-talk gesture and `TextInsertionCoordinator` needs a focused text field
  in another app; neither can be driven headlessly, and the sandbox cannot grant the TCC
  permissions they require. Both are argued network-free from the source audit only:
  `UttrflowAudio` and `UttrflowInput` contain no network call site, and `offline_audit.sh` keeps
  it that way. The sandboxed run does exercise the second half of capture (`AudioFileReader`
  hands its samples through the same `AudioResampler` the microphone path uses), but a full
  hold-key-to-inserted-text run offline has not been observed.
- **Apple's frameworks are taken at their word.** `FoundationModels`, `Speech` and `CoreML` are
  closed. The sandboxed run shows that none of them opened a socket *from this process*; work
  they hand to a system daemon over XPC is outside the sandbox and outside what this can see.
  For `FoundationModels` that is Apple's documented on-device guarantee, not something
  measured here.
- **Reading a URL cannot be told from fetching one.** `Data(contentsOf:)` and
  `String(contentsOf:)` fetch a remote URL synchronously inside Foundation, so the calling
  module names no networking type and its object file carries no networking symbol. Both
  halves of the audit are blind to it. Check 1b names every file that uses one, so a new one
  has to be argued for; it does not establish that the existing ones are local, which was done
  by reading them. `Sources/UttrflowTestSupport/GoldenFile.swift` reads the repository fixture beside
  its calling test, derived from that test's `#filePath`; it is not linked into the app.
- **A dependency is judged whole, not per file.** The per-object check applies to Uttrflow's
  own modules, where the audit has a file-level claim to make. For a dependency it asserts only
  that the set of network-capable dependencies has not grown, which says nothing about when any
  of them runs.
- **Sparkle and Sentry are not inspected.** Sparkle fetches an appcast and an archive, and
  Sentry sends opt-in reports; that is each one's feature, so reading the framework would only
  confirm it. Checks 6 and 6b establish where each can be driven from, which is what keeps them
  off every path a dictation, a clip or a history entry runs through.
- **Only the paths that ran were tested.** A sandboxed run proves what happened, not what would
  happen on a different model, locale or failure branch. That is what `offline_audit.sh` is for.

## Summary

The app is offline-safe on the dictation path with WhisperKit, its only recogniser:
Uttrflow's own code, the clean-up engines, the router and the model load all completed under a
profile that kills the process for touching the network, and the tokenizer is installed beside
the weights with its folder pinned.

Related: [speech-engines.md](speech-engines.md) § Keeping WhisperKit off the network,
[speech-model-install.md](speech-model-install.md), [predict-llm.md](predict-llm.md),
[app-updates.md](app-updates.md), [crash-reporting.md](crash-reporting.md).
