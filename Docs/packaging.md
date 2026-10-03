# Packaging Uttrflow.app

`make app` (or `./Scripts/bundle.sh` directly) produces `dist/Uttrflow.app`: signed,
verifiable, and self-contained. This note records why the script is shaped the way it
is, because the obvious shape does not work and the failure it produces is expensive
to rediscover.

## The bind

Three of the dependencies the app links carry resources of their own —
swift-transformers' `Hub`, which ships fallback tokeniser configurations,
swift-crypto's `Crypto`, which ships a privacy manifest, and mlx-swift's `Cmlx`, which
ships the compiled Metal shader library the local model runs on
(`default.metallib`). Each gets a generated `Bundle.module` accessor, and the accessor
decides at runtime where to look for its `.bundle`. The accessor `swift build`
generates knows exactly two places:

```swift
let mainPath = Bundle.main.bundleURL.appendingPathComponent("swift-transformers_Hub.bundle").path
let buildPath = "/Users/<whoever-built-this>/.../.build/arm64-apple-macosx/release/swift-transformers_Hub.bundle"
guard let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath) else { fatalError(…) }
```

Inside a `.app`, `Bundle.main.bundleURL` *is* the `.app`, so the first candidate puts
the resource bundle beside `Contents`. A bundle root may hold nothing but `Contents`,
so codesign refuses:

```
root-proof.app: unsealed contents present in the bundle root
```

The second candidate is an absolute path into the build tree of the machine that
produced the binary. It works there and nowhere else.

So with `swift build` the app can be self-contained *or* signed, never both — and the
"self-contained" half is only true on the build machine. Worse, neither failure shows
up at launch. Nothing on the startup path touches `Bundle.module`; the accessor is
first reached when a tokeniser is loaded, which is the first time somebody dictates.
An app with no resource bundles at all launches happily and sits in the menu bar
looking correct.

## The way out

Xcode generates a different accessor for the very same package:

```swift
let candidates = overrides + [
    Bundle.main.resourceURL,                     // an App
    Bundle(for: BundleFinder.self).resourceURL,  // a framework
    Bundle.main.bundleURL,                       // a command-line tool
]
```

`Bundle.main.resourceURL` is `Contents/Resources` — an ordinary place for a bundle to
live, and one codesign is perfectly willing to seal. The only absolute-path escape
hatch is an environment variable behind `#if DEBUG`, so a release build bakes no
developer path at all.

So `Scripts/bundle.sh` builds with xcodebuild in Release, copies every `*.bundle` the
build produced into `Contents/Resources`, and *then* signs. The bundles are discovered,
never listed by name: a new dependency that carries resources must not be able to go
missing quietly.

## What the script asserts

Beyond the Info.plist and entitlement checks it has always made:

- The Metal Toolchain is installed, before `xcodebuild` is invoked — see Cost, above.
- `codesign --verify --deep --strict` passes. This is the headline: it is what the old
  layout could not do.
- The designated requirement is pinned to the bundle identifier, not to a cdhash.
  Unpinned, every rebuild is a new app to TCC and the microphone grant is lost.
- The bundle root holds nothing but `Contents` — the old broken layout, kept as a check
  so it cannot return quietly.
- Every `*.bundle` named in the shipped binary's strings exists in
  `Contents/Resources`. It reads the binary rather than counting what got copied,
  because the accessor's bundle name is a string literal compiled into the executable:
  this asks exactly the question the accessor will ask at runtime, and an app that
  ships nothing cannot pass it by having nothing to check.

  A name counts only when it is a whole `strings` line — `<Package>_<Target>.bundle`
  and nothing else on the line — because that is the shape of the literal an accessor
  is compiled with. Looking for that text anywhere in a line instead read
  `surface.bundle` out of `WHERE surface.bundle_id = ?`, which is a column in the
  prediction store, and failed builds over a bundle nothing had ever asked for.
  `./Scripts/bundle.sh --self-test` — `make bundle-test`, and part of `make verify` —
  proves both halves against a fixture and needs no build: that the SQL is not read as
  a bundle, and that a required bundle taken out of `Contents/Resources` still fails.
- No path into this machine's build tree survives in the shipped binary.
- No `.jsonl`, `.json`, `.txt` or `.csv` file reaches the app unless its full bundle-relative
  path is in `ALLOWED_TEXT_RESOURCES` in `Scripts/bundle.sh`. The allow list covers only
  tokenizer fallback configs, the font licence, BIP39 resources, Unicode property data and
  Sentry's architecture metadata; `./Scripts/bundle.sh --self-test` proves those named files
  pass and a corpus fixture in each supported format fails.

## Verified

Same harness source, same `.app` layout, same ad-hoc signature, build directory moved
aside in both cases:

| built with | result |
| --- | --- |
| `swift build` | `Fatal error: could not load resource bundle: from …/spm-proof.app/swift-transformers_Hub.bundle or …/.build/arm64-apple-macosx/release/swift-transformers_Hub.bundle` |
| `xcodebuild` | `OK: Hub's Bundle.module resolved; tokenizer_class = GPT2Tokenizer` |

The harness calls `LanguageModelConfigurationFromHub.tokenizerConfig`, the public API
that reaches `Hub.fallbackTokenizerConfig(for:)` and therefore `Bundle.module` — the
same code the dictation path runs through. A launch test proves nothing here: an app
with no bundles at all survives launch indefinitely.

The seal covers the bundles' contents, not merely their presence. Editing one byte of
`Contents/Resources/swift-transformers_Hub.bundle/Contents/Resources/gpt2_tokenizer_config.json`
turns `codesign --verify --deep --strict` into:

```
dist/Uttrflow.app: a sealed resource is missing or invalid
```

## Cost

`-scheme Uttrflow` builds the app target's own dependency graph — and that graph
includes `UttrflowLocalModel`, which depends on MLX for the shipped suggestion
feature. So `Cmlx` **is** compiled by `make app`, `make app-dev`, `make app-hardened`,
and `make app-dist` alike, and **the Metal Toolchain is required for all four**, the
same optional Xcode component `make bakeoff` needs. `Scripts/bundle.sh` checks for it
before starting the `xcodebuild` build and fails with the install command
(`xcodebuild -downloadComponent MetalToolchain`) rather than letting the build run
long enough to fail inside MLX compilation.

Package *resolution* still fetches every dependency the manifest names, MLX included,
so a fresh clone spends a while in the network before the first build starts. Measured
on an M-series Mac: about 3m40s cold (resolution plus a full Release build), a few
seconds warm. Derived data lands in `.build/xcode`, alongside the bake-off's, so
`make clean` still clears everything.

## Signing, and what changed

The signature was ad-hoc for a long time, and the hardened runtime was refused outright on
the argument that it costs the microphone. The mechanism was real; the conclusion was not,
and the price of it was an app that could never be given to anybody.

Measured rather than feared, on macOS 26.5.1: on a Mac that has already granted this
identifier the microphone, the hardened runtime changes nothing either way — which is
exactly why it is dangerous to reason about, because it is unreproducible on the machine
that built the app. On a Mac seeing Uttrflow for the first time, a hardened build *without*
the audio-input entitlement does not prompt and does not error. `requestAccess` returns
false immediately, the engine starts, buffers arrive, and every sample is exactly 0.0.
macOS writes no TCC record at all. From the user's chair that is indistinguishable from
having pressed Deny. With the entitlement present it behaves normally.

So the risk was conditional on one entitlement, and that entitlement is now a hard gate —
check 7 in `Scripts/bundle.sh`, proved to fire by stripping it.

`Scripts/bundle.sh` therefore has three modes:

| Mode | Signature | Hardened | For |
| --- | --- | --- | --- |
| `local` | ad-hoc | no | Running here. Fails loudly rather than silently. |
| `rehearsal` | ad-hoc | **yes** | Testing on another Mac. No certificate needed. |
| `distribution` | Developer ID | **yes** | Notarisable. The thing users download. |

`Scripts/dmg.sh` wraps whichever of those was built, and reads the signature off the app
rather than taking a mode argument — so an ad-hoc app can only ever produce an unsigned
image, and the two cannot disagree.

**`Docs/releasing.md` is the runbook.** It covers the version, the four-step order that
notarisation requires, and where downloads live.
