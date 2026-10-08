# Installing a speech model, one component at a time

`FileSystemSpeechModelStore` in `Sources/UttrflowSpeech/SpeechModelStore.swift` owns where
speech models live on disk and how they get there: a `Models` folder under Application Support
(`FileSystemSpeechModelStore.defaultRoot()`), one folder per model variant. The model is
`SpeechModel.default` (`Sources/UttrflowSpeech/SpeechModel.swift`), and the tokenizer is fetched
by `TokenizerDownload` (`Sources/UttrflowSpeech/TokenizerDownload.swift`). The download itself is
injected, so everything else (where files go, what counts as installed, refusing to re-download,
cleaning up a failed install) is testable against a temporary directory with no network.
[`offline.md`](offline.md) states what may touch the network;
[`speech-engines.md`](speech-engines.md) covers why the tokenizer is fetched here.

| Value | Where | What it is |
|---|---|---|
| 645,668,913 bytes | `SpeechModel.largeV3Turbo.downloadBytes` | the default model's weights download |
| 200 MB | `FileSystemSpeechModelStore.installMargin` | free space required beyond the rest of the download |
| `.weights-revision` | `WeightsAssets.revisionFileName` | the file recording which pinned weights revision is installed |
| `<root>/.partial/<variant>/` | `stagingLocation(of:)` | where weights download before they are complete |

## Two components, fetched separately

The weights and the tokenizer come from different repositories and go missing independently,
so the store asks for them one at a time instead of treating an install as all or nothing.

## Installed means "everything needed to transcribe with it"

The weights alone are not enough. WhisperKit quietly fetches a missing tokenizer from Hugging
Face the first time somebody dictates; on a plane, that is an unrecoverable failure reported as a
load error rather than the missing download it actually is. So `isInstalled` answers `true` only
when the weights *and* both tokenizer files are present, and answering `false` is what puts the
offer to install back in front of the user.

An empty directory is what a cancelled download leaves behind, and is likewise not installed:
treating it as installed would fail later, further from the cause.

Weights are detected by the model's manifest (`SpeechModel.weightFiles`, read through
`WeightsAssets`): every file in the model's folder at the pinned commit — each `.mlmodelc` bundle's
`coremldata.bin`, `model.mil`, `metadata.json`, `analytics/coremldata.bin` and
`weights/weight.bin`, the optional `TextDecoderContextPrefill.mlmodelc`, `config.json` and
`generation_config.json` — each at its pinned byte count. A bundle without its `model.mil` fails to load
with "Failed to parse ML Program", so a folder missing any listed file is not installed.
`isIncomplete(_:)` names that case: the folder is there and a file is not, so the app offers to
download it again rather than to load it. The manifest adds up to `downloadBytes`, and a test holds
it there, so a manifest that forgets a file fails before it ships.

The store checks pinned byte counts and a recorded weights revision on every menu draw; hashing
600 MB there is not affordable. The downloader hashes each staged file before reusing it, so a
revision bump fetches only changed files while the complete replacement stays in staging.

An install made before the revision record existed has every pinned file and no record, so it
reads as not installed. `install(_:onProgress:)` hashes such a folder in place first: when every
file matches its pinned digest it writes the record and fetches nothing, and otherwise the
ordinary repair runs. `whyNotInstalled(_:)` names which of these cases applies, and the
`uttrflow-dev` refusals print it. Measured on an Apple M5 Pro with a pre-record install of the
default model: `uttrflow-dev models install` adopted it in 4 seconds with no `.partial` folder.

## Missing components are ordered weights-first

The weights are the wait: they own the progress bar, so asking for them first means the bar
starts moving straight away.

## Installing fetches only what is missing

The downloader reuses files whose size and digest still match the new pin, so a revision bump
does not re-fetch unchanged weights. A tokenizer-only repair likewise leaves the weights alone.

A download that reports success and produces nothing is checked for on the spot, rather than
being discovered a launch later as a model that will not load.

## Weights are staged, then moved in whole

The weights download into `<root>/.partial/<variant>/`, never into the model's directory. The
installed files are seeded into staging and verified against the new pin. Only when every weight
file and the revision record are there are they moved in: a tokenizer already in the model's directory is
copied into staging, not moved, so the model's directory keeps its own tokenizer until staging
replaces the whole directory in one `replaceItemAt`. A process killed at any point before that —
including between the copy and the swap — leaves the model's directory as it was, so nothing
half-fetched is ever mistaken for a model.

The model root, staging folders, installed model folders and tokenizer files are excluded from
backup (`PrivateFile.excludeFromBackup`). They are public downloaded data and can be fetched again, so backup tools
that honour Finder's exclusion flag should not spend space carrying them.

After a successful default install, every other model folder not in use is removed and the freed
bytes are logged. A loaded recogniser holds a shared lock on its model folder until it unloads
(`ModelDirectoryUseLease`), and removal takes the exclusive lock, so a folder in use is never
deleted.

## Unwinding a failed fetch, in proportion

| Failed component | What is removed        | Why |
|------------------|------------------------|-----|
| weights, with an error | nothing; staging is kept | the files already fetched let asking again resume instead of restarting, and the model's directory was never touched |
| weights, reported done but incomplete | the staging directory | what it holds is not a model and would not become one by resuming |
| tokenizer        | the tokenizer only     | the weights beside it may be six hundred megabytes the user has already waited for, and are still perfectly good |

`remove(_:)` discards staging along with the model.

## Checking the disk before downloading

The default model is about 650 MB, and a disk too full to hold it would otherwise fail partway
through and be reported as a connection problem the user cannot fix by retrying.

- Before fetching the weights, the store reads `volumeAvailableCapacityForImportantUsageKey` for
  the volume under its root and refuses with `SpeechEngineError.notEnoughSpace` when that is less
  than the rest of the download plus a 200 MB margin. Bytes already staged by an earlier attempt
  count towards the download, so a resume asks only for what is left.
- A volume that cannot report its capacity is not refused; the download is tried.
- A download, move or tokenizer fetch that fails with `NSFileWriteOutOfSpaceError` or `ENOSPC`,
  directly or as an underlying error, raises the same failure. Its message names the space needed
  rather than asking the user to check their connection; every other failure keeps that wording.

## Pinned model files

Both halves of the model are fetched from `huggingface.co/<repository>/resolve/<commit>/<file>`.
The CoreML weights use `SpeechModel.weightsRevision`, `weightsRepository`, and `weightFiles`; the
tokenizer uses `tokenizerRevision`, `tokenizerRepository`, and `tokenizerDigests`. Each weight file
is downloaded to a temporary file, counted, hashed, tightened, and only then moved into staging.
Each tokenizer file is likewise checked before it is written. A pinned commit says which file to
fetch; only the size and digest say it is the file that was pinned.

The app does not call `WhisperKit.download` for installs. That downloader has no revision argument
for these weights and can fall back to the person's own Hugging Face token. Uttrflow fetches public
files directly instead, with `huggingface.co` and the commit named in source.

**To bump a weight revision**, take the CoreML repository's current commit and the metadata for
every file in the model's folder:

```bash
curl -s https://huggingface.co/api/models/argmaxinc/whisperkit-coreml \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])'
curl -s "https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/<commit>/<variant>?recursive=1" \
  | python3 -c 'import sys,json; [print(i["path"], i["size"], i.get("lfs", {}).get("oid")) for i in json.load(sys.stdin)]'
```

Put the commit in `weightsRevision`, and put every file's `size` and SHA-256 in `weightFiles`: the
LFS `oid` for a file stored in LFS, and `shasum -a 256` of the downloaded file for one that is not
(`model.mil`, `metadata.json`, `config.json`), whose `oid` is a git hash and not a digest.

**To bump a tokenizer revision**, take the repository's current commit and the files' digests:

```bash
curl -s https://huggingface.co/api/models/openai/whisper-large-v3 | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])'
curl -sL https://huggingface.co/openai/whisper-large-v3/resolve/<commit>/tokenizer.json | shasum -a 256
curl -sL https://huggingface.co/openai/whisper-large-v3/resolve/<commit>/tokenizer_config.json | shasum -a 256
```

Put the commit in `tokenizerRevision` and the digests in `tokenizerDigests`, and say in the pull request what changed in the tokenizer and why the
app should follow it. `Scripts/offline_audit.sh` fails on `resolve/main/`, so a revision cannot
quietly become a branch again.

**After either bump**, or a change to the `WhisperKit` version in `Package.swift`, run
`make accuracy-gate` and paste its output in the pull request. The committed baseline records the
recogniser pins it was measured with, so the gate fails with "baseline is for a different model"
until the same pull request saves a new baseline with `--save-baseline`
([measuring-accuracy.md](measuring-accuracy.md#the-committed-baseline)).

## A load that fails

A load checks only that each pinned file is present at its byte count, so a file damaged at the
same size passes that check and fails inside Core ML. When a load fails, `WeightsAssets.loadFailure`
reads the files: a missing or wrong-size file or tokenizer is `modelNotInstalled`; a file whose
SHA-256 no longer matches its pin is `modelDamaged`, whose recovery is the download, and the
revision record is withdrawn so the next install re-verifies through staging and fetches only the
bad files; anything else stays `modelLoadFailed` with its retry. Nothing is downloaded until the
person asks. Hashing the 618 MB large-v3 turbo install takes about 1.3 s on an Apple M5 Pro
(`shasum -a 256` over its `.bin` files), paid only on the failure path, off the main actor.

## `FileManager`

`FileManager` is not `Sendable`, and the shared instance is documented as safe for the file
operations used here. Tests run against real temporary directories, which is more faithful
than a substitute would be.
