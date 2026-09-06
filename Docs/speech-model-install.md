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

Weights are detected as "any file in the directory that is not part of the tokenizer", since
a directory holding nothing but a tokenizer has no model in it.

## Missing components are ordered weights-first

The weights are the wait: they own the progress bar, so asking for them first means the bar
starts moving straight away.

## Installing fetches only what is missing

That is what keeps an install made by an earlier build cheap to repair: those have the weights
and no tokenizer, and re-downloading six hundred megabytes to add three would be a poor way to
apologise.

A download that reports success and produces nothing is checked for on the spot, rather than
being discovered a launch later as a model that will not load.

## Unwinding a failed fetch, in proportion

| Failed component | What is removed        | Why |
|------------------|------------------------|-----|
| weights          | the whole directory    | what it left is unusable and indistinguishable from a complete install by size alone |
| tokenizer        | the tokenizer only     | the weights beside it may be six hundred megabytes the user has already waited for, and are still perfectly good |

`isInstalled` already refuses to call what remains usable, so nothing can mistake a
weights-only directory for a working model in the meantime.

## Hoisting the download out of its wrapper

Model repositories nest their output — WhisperKit's lands in
`destination/models/<repo>/<variant>/`. The store's contract is that a model's files sit
directly in `location(of:)`, so the nesting is undone in `hoist(contentsOf:into:)` rather than
leaking into every caller that needs a path. The wrapper directory is identified *before*
anything moves; afterwards there is nothing left to identify it by.

## `FileManager`

`FileManager` is not `Sendable`, and the shared instance is documented as safe for the file
operations used here. Tests run against real temporary directories, which is more faithful
than a substitute would be.
