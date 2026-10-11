# Data manifest

`Resources/DataManifest.json` lists every file under `Sources/*/Resources/`, which is every
file SwiftPM copies into a resource bundle and `Scripts/bundle.sh` seals into the app, and every
synthesised take under `Tests/Fixtures/SyntheticAudio/`, the one folder audio may sit in. The
speech weights are pinned separately in [speech-model-install.md](speech-model-install.md).

## Fields

| Field | Meaning |
|---|---|
| `path` | the file, from the repository root |
| `origin` | `authored`, `generated`, `third-party`, or `unrecorded` |
| `source`, `revision` | where a `third-party` file came from and which release; required for that origin |
| `licence` | an SPDX identifier, or the documented mark-use reference for a registered trademark |
| `redistribution` | whether the licence allows shipping the file in the app |
| `producedBy` | the tool or script that made the file, where one did |
| `voice` | the synthesiser voice that spoke a take; required, with origin `generated`, under `Tests/Fixtures/SyntheticAudio/` |
| `sha256`, `bytes` | the file's digest and size |
| `optional` | absent only for the registered Google Sign-In mark; a Boolean, never an exemption for another resource |
| `budgetBytes` | optional: the most bytes the file may grow to; set on each file a script derives |

A `third-party` data file comes only from an established publisher under a permissive licence.
The optional Google Sign-In artwork instead records its conditional branding use, described below.
`revision: unrecorded` means the publisher is known but the release the file was taken
from is not; replace it when the file is next refreshed.

## The check

```bash
make data-manifest        # exits 1 on any problem
```

It fails when a bundled file has no entry, an entry names a file that is not bundled, a
size or digest differs, a field is missing, an origin is not one of the four, a fixture take
is not `generated` with a `voice`, or a file is larger than its `budgetBytes`. A differing file's
failure names the size and digest it now has; each budgeted file's size is printed on every run.
`make app-preflight` and `make verify` run it first, and `.githooks/pre-push` runs it on the
pushed commit of any branch whose new commits touch the manifest or a bundled file. An `unrecorded` origin is printed as a
note and does not fail: it marks a file whose source and licence the owner has still to
confirm, so it is visible on every run without blocking the build.

## Rebuilding derived files

```bash
make assets ASSET_CACHE=<folder>   # fetch the pinned sources, rebuild, then run the check above
```

The cache must be outside the repository and outside `Application Support`; the pinned archives
are never copied into the tree ([ngram-sources.md](ngram-sources.md)). Every script it runs
writes UTF-8 with `\n` line ends, in source order, with no timestamp, so a rebuild from the same
pins gives the same bytes whatever the locale, working directory or hash seed, and the check compares them
with the committed digest. A rebuild that changes a file fails here until its entry is updated
in the same commit. The rebuild needs the archives, so `make verify` checks the committed files
only.

Changing an existing asset means refreshing its digest and size in the same commit. Run:

```bash
python3 Scripts/data_manifest.py --update
make data-manifest
```

`--update` changes only `sha256` and `bytes` for entries whose files are bundled. It does not add
entries or change their origin or other metadata. It does not refresh optional provider artwork.
Review the manifest diff before committing it.

## Reproducing a fitted asset from its tag

A fitted file's entry may carry a `recipe`, the four inputs that decide its bytes plus the engine
the fit assumed:

| Field | Meaning |
|---|---|
| `fitToolRevision` | the git commit of the fit tool; it must exist in this repository |
| `featureSpecVersion` | the version of the feature spec the fit read |
| `inputs` | each source: `path`, `sha256`, and `where` it lives, `tree` (committed) or `cache` (the pinned archives) |
| `seeds` | the whole-number seeds, passed to the command as `RECIPE_SEEDS` |
| `engine` | the identity of the engine the fit assumed, passed as `RECIPE_ENGINE` |
| `command` | the argument list, run from the tag's root; it writes the asset to `RECIPE_OUTPUT` |

```bash
make reproduce-assets TAG=<tag> [ASSET_CACHE=<folder>]
```

It checks the tag out in a scratch worktree, checks each input against its digest, deletes the
committed asset, runs the command and compares the new digest with the tag's manifest. It exits 1
and names the asset on any difference, a changed seed or input digest included, and it needs no
network when the cache is warm. It only builds and compares; it never tags.

## Optional Google Sign-In artwork

Only the Google G (`GoogleG.png`) in the app resource directory can be registered as optional;
its full path is recorded in `Resources/DataManifest.json`. Its absence is
supported by the existing onboarding fallback. When present, its bytes and SHA-256 must match
its entry; other unlisted resources, changed resources and missing required resources still fail.
`LicenseRef-GoogleSignInBranding` records Google's conditional use of its Sign-In artwork under
[its branding guidelines](https://developers.google.com/identity/branding-guidelines), for the
existing Google Sign-In button. It is not a permissive source redistribution licence; the image
remains ignored and is never committed. The entry's `revision` is the published archive's SHA-256,
and `producedBy` records the existing selector and tile extraction scripts that produce the mark.

After explicitly obtaining and inspecting the official archive and its derived mark, register a
refresh with the generator, then review the metadata diff:

```bash
python3 Scripts/provider_mark.py register --archive <official-archive.zip> --mark <derived-GoogleG.png>
make data-manifest
```

The fetcher verifies the pinned archive before extraction, verifies the output afterwards, and
verifies a pre-existing mark before accepting it. A changed publisher archive or corrupt local
mark fails until an explicit reviewed registration refresh. Registration does not copy artwork
into the repository. The generated metadata records provenance; it does not certify every aspect
of the sign-in button's branding presentation.
