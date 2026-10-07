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
| `licence` | an SPDX identifier, or `LicenseRef-Uttrflow-Marks` for the marks `TRADEMARK.md` covers |
| `redistribution` | whether the licence allows shipping the file in the app |
| `producedBy` | the tool or script that made the file, where one did |
| `voice` | the synthesiser voice that spoke a take; required, with origin `generated`, under `Tests/Fixtures/SyntheticAudio/` |
| `sha256`, `bytes` | the file's digest and size |

A `third-party` file comes only from an established publisher under a permissive licence.
`revision: unrecorded` means the publisher is known but the release the file was taken
from is not; replace it when the file is next refreshed.

## The check

```bash
make data-manifest        # exits 1 on any problem
```

It fails when a bundled file has no entry, an entry names a file that is not bundled, a
size or digest differs, a field is missing, an origin is not one of the four, or a fixture take
is not `generated` with a `voice`.
`make app-preflight` and `make verify` run it first. An `unrecorded` origin is printed as a
note and does not fail: it marks a file whose source and licence the owner has still to
confirm, so it is visible on every run without blocking the build.

Changing an asset means changing its entry in the same commit. Print the two values with:

```bash
shasum -a 256 <path>; stat -f %z <path>
```
