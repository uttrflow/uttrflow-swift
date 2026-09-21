# Installing a speech model, one component at a time

`FileSystemSpeechModelStore` in `Sources/UttrflowSpeech/SpeechModelStore.swift` owns where
speech models live on disk and how they get there. The download itself is injected, so
everything else — where files go, what counts as installed, refusing to re-download, cleaning
up a failed install — is testable against a temporary directory with no network.

## Two components, fetched separately

The weights and the tokenizer come from different repositories and go missing independently,
so the store asks for them one at a time instead of treating an install as all or nothing.

## Installed means "everything needed to transcribe with it"

The weights alone are not enough, and treating them as enough made `isInstalled` a lie.
WhisperKit will quietly fetch a missing tokenizer from Hugging Face the first time somebody
dictates — on a plane, that is an unrecoverable failure reported as a load error rather than
the missing download it actually is. Answering `false` is what puts the offer to install back
in front of the user, which is the whole remedy for an install made by a build that only
fetched weights.

An empty directory is what a cancelled download leaves behind, and is likewise not installed:
treating it as installed would fail later, further from the cause.

Weights are detected by the files a load reads (`WeightsAssets`): `coremldata.bin` and
`weights/weight.bin` inside each of `MelSpectrogram.mlmodelc`, `AudioEncoder.mlmodelc` and
`TextDecoder.mlmodelc`, each at least one byte. Any other file counting as weights is how a
download killed partway came to read as installed, fail every load, and never be repaired.
There is no manifest of sizes to check against, so a file truncated to a non-zero length is not
detected here; staging below is what keeps one from arriving in the model's directory.

## Missing components are ordered weights-first

The weights are the wait: they own the progress bar, so asking for them first means the bar
starts moving straight away.

## Installing fetches only what is missing

That is what keeps an install made by an earlier build cheap to repair: those have the weights
and no tokenizer, and re-downloading six hundred megabytes to add three would be a poor way to
apologise.

A download that reports success and produces nothing is checked for on the spot, rather than
being discovered a launch later as a model that will not load.

## Weights are staged, then moved in whole

The weights download into `<root>/.partial/<variant>/`, never into the model's directory. Only
when every weight file is there are they moved in: a tokenizer already in the model's directory is
carried into staging, and staging then replaces the directory in one `replaceItemAt`. A process
killed at any point before that leaves the model's directory as it was, so nothing half-fetched is
ever mistaken for a model.

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

## Hoisting the download out of its wrapper

Model repositories nest their output — WhisperKit's lands in
`<staging>/models/<repo>/<variant>/`. The store's contract is that a model's files sit
directly in `location(of:)`, so the nesting is undone in `hoist(contentsOf:into:)` rather than
leaking into every caller that needs a path. The wrapper directory is identified *before*
anything moves; afterwards there is nothing left to identify it by.

## `FileManager`

`FileManager` is not `Sendable`, and the shared instance is documented as safe for the file
operations used here. Tests run against real temporary directories, which is more faithful
than a substitute would be.
