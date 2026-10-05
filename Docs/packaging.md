# Packaging Uttrflow.app

`Scripts/bundle.sh` turns the SwiftPM package into `dist/Uttrflow.app`: built with
`xcodebuild` in Release, assembled, signed, and then checked against a list of failures that
otherwise surface only when somebody dictates. `make app`, `make app-dev`, `make app-hardened`
and `make app-dist` each call it in one mode; `Scripts/dmg.sh` (`make dmg`) wraps the result in
a disk image. This page says why the script has the shape it has; `Docs/releasing.md` is the
runbook for notarising and publishing.

## Modes

| Mode | Make target | Signature | Hardened runtime | For |
| --- | --- | --- | --- | --- |
| `local` (default) | `make app` | ad-hoc | no | Running on this Mac, and every test build. |
| `development` | `make app-dev` | ad-hoc | no | Running beside the installed app under its own identifier; see `Docs/development-build.md`. |
| `rehearsal` | `make app-hardened` | ad-hoc | yes | Testing the hardened runtime on another Mac with no certificate. Not distributable. |
| `distribution` | `make app-dist` | Developer ID, secure timestamp | yes | Notarisable; what users download. |

`Scripts/dmg.sh` reads the signature off the app rather than taking a mode, so an ad-hoc app
can only produce an unsigned image and the two cannot disagree.

## Why `xcodebuild` and not `swift build`

Three dependencies the app links carry resources of their own: swift-transformers' `Hub`
(fallback tokeniser configurations), swift-crypto's `Crypto` (a privacy manifest), and
mlx-swift's `Cmlx` (the compiled Metal shader library, `default.metallib`). Each gets a
generated `Bundle.module` accessor that decides at runtime where to find its `.bundle`. The
accessor `swift build` generates knows two places:

```swift
let mainPath = Bundle.main.bundleURL.appendingPathComponent("swift-transformers_Hub.bundle").path
let buildPath = "/Users/<whoever-built-this>/.../.build/arm64-apple-macosx/release/swift-transformers_Hub.bundle"
guard let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath) else { fatalError(…) }
```

Inside a `.app`, `Bundle.main.bundleURL` *is* the `.app`, so the first candidate puts the
resource bundle beside `Contents`. A bundle root may hold nothing but `Contents`, so codesign
refuses with `unsealed contents present in the bundle root`. The second candidate is an
absolute path into the build tree of the machine that built the binary, and works nowhere
else. With `swift build` the app is self-contained *or* signed, never both, and neither failure
shows at launch: nothing on the startup path touches `Bundle.module`. The accessor is first
reached when a tokeniser loads, which is the first dictation.

Xcode generates a different accessor for the same package:

```swift
let candidates = overrides + [
    Bundle.main.resourceURL,                     // an App
    Bundle(for: BundleFinder.self).resourceURL,  // a framework
    Bundle.main.bundleURL,                       // a command-line tool
]
```

`Bundle.main.resourceURL` is `Contents/Resources`, which codesign seals. Its only absolute-path
escape hatch is an environment variable behind `#if DEBUG`, so a Release build bakes in no
developer path. `bundle.sh` therefore builds with `xcodebuild`, copies every `*.bundle` the
build produced into `Contents/Resources` and every `*.framework` (Sparkle) into
`Contents/Frameworks` with `ditto`, adds the `@executable_path/../Frameworks` rpath, and only
then signs. Bundles and frameworks are discovered, never listed by name, so a new dependency
that carries resources cannot go missing quietly.

### Measured

Same harness source, same `.app` layout, same ad-hoc signature, build directory moved aside in
both cases. The harness calls `LanguageModelConfigurationFromHub.tokenizerConfig`, the public
API that reaches `Hub.fallbackTokenizerConfig(for:)` and so `Bundle.module`, the same code the
dictation path runs through:

| built with | result |
| --- | --- |
| `swift build` | `Fatal error: could not load resource bundle: from …/spm-proof.app/swift-transformers_Hub.bundle or …/.build/arm64-apple-macosx/release/swift-transformers_Hub.bundle` |
| `xcodebuild` | `OK: Hub's Bundle.module resolved; tokenizer_class = GPT2Tokenizer` |

A launch test proves nothing here: an app with no bundles at all survives launch
indefinitely. The seal covers the bundles' contents, not only their presence: editing one byte
of `Contents/Resources/swift-transformers_Hub.bundle/Contents/Resources/gpt2_tokenizer_config.json`
turns `codesign --verify --deep --strict` into `a sealed resource is missing or invalid`.

## What the script checks

Each check is numbered in `Scripts/bundle.sh`, and each catches a failure otherwise found at
runtime by a person holding a dictation key that does nothing.

| Check | What it refuses |
| --- | --- |
| before the build | A missing Metal Toolchain, with the install command `xcodebuild -downloadComponent MetalToolchain`. |
| 1 | An Info.plist missing a key the app cannot start or record without, including `NSMicrophoneUsageDescription`. |
| 1b | A hardened build without both `UttrflowBackendURL` and the release entitlement key in the binary; see `Docs/releasing.md`. |
| 2 | A `CFBundleExecutable` that names no file in `Contents/MacOS`. |
| 3 | Anything in the bundle root but `Contents`. |
| 4 | A resource bundle the binary asks for that is not in `Contents/Resources`. |
| 4a | An update feed with no usable `SUPublicEDKey`, without `SUVerifyUpdateBeforeExtraction`, or (in `distribution`) pointing at a loopback host. |
| 4b | A framework the binary links that is not in `Contents/Frameworks`, or no rpath reaching it. |
| 4c | A `distribution` build carrying the rehearsal's library-validation exception. |
| 4d | A `.jsonl`, `.json`, `.txt` or `.csv` app resource whose full bundle-relative path is not in `ALLOWED_TEXT_RESOURCES` in `Scripts/bundle.sh`. |
| 5 | A signature that fails `codesign --verify --deep --strict`. |
| 6 | A designated requirement not pinned to this app. |
| 7 | An audio-input entitlement that is absent or not `true`. |
| 8, 9 | In `distribution`, no secure timestamp; in any mode, a hardened runtime that is on when not asked for or off when asked for. |
| unnumbered | A path into this machine's build tree in the binary (paths under SwiftPM's `checkouts/` are ignored: MLX bakes a `__FILE__` assert string there). |
| 10 | Any trace of the evaluation corpus: `UttrflowEval` symbols, audio files, corpus endpoints or `UTTRFLOW_OPERATOR_TOKEN`. |
| 11 | Coverage instrumentation (`__llvm_prf`/`__llvm_cov` sections) in the shipped binary; the build turns it off with `ENABLE_CODE_COVERAGE=NO`. |

Check 4 reads the *binary*, not what was copied: the accessor's bundle name is a string literal
compiled into the executable, so the check asks the question the accessor will ask at runtime,
and an app that ships nothing cannot pass by having nothing to check. A name counts only when
it is a whole `strings` line, `<Package>_<Target>.bundle` and nothing else, because that is the
shape of the literal. Matching the text anywhere in a line would read `surface.bundle` out of
`WHERE surface.bundle_id = ?`, a column in the prediction store. `./Scripts/bundle.sh
--self-test` (`make bundle-test`, part of `make verify`) proves both halves against a fixture
without a build: the SQL is not read as a bundle, and a required bundle removed from
`Contents/Resources` still fails. `make bundle-requirement-test` proves every mode has a
designated requirement.

## Signing

An ad-hoc signature's default designated requirement is a cdhash, which changes on every
build, and TCC keys grants on the requirement: every rebuild would be a new app and lose the
microphone grant. So ad-hoc builds are signed with `designated => identifier
"com.uttrflow.Uttrflow"` (`.dev` for the development build). A Developer ID build keeps Apple's
default requirement, and check 6 proves it pins the identifier and the Team ID.

**The audio-input entitlement is the hardened runtime's one trap.** Measured on macOS 26.5.1:
on a Mac that has already granted this identifier the microphone, the hardened runtime changes
nothing, which is why it cannot be reasoned about on the machine that built the app. On a Mac
seeing Uttrflow for the first time, a hardened build *without*
`com.apple.security.device.audio-input` does not prompt and does not error: `requestAccess`
returns false at once, the engine starts, buffers arrive, every sample is exactly 0.0, and
macOS writes no TCC record. To the user it is indistinguishable from pressing Deny. With the
entitlement present it behaves normally. Check 7 is the gate, and stripping the entitlement
makes it fire.

The other half of the microphone pair is `NSMicrophoneUsageDescription`. Without it the
hardened runtime ends the process when the microphone is first touched, where a missing
entitlement fails silently. Check 1 reads it from the assembled bundle's Info.plist, with the
other keys the app cannot start or record without, and refuses to finish.

**Rehearsal disables library validation, and only rehearsal.** An ad-hoc signature has no Team
ID, and library validation requires the app and every framework it loads to share one, so an
ad-hoc hardened build cannot load `Sparkle.framework`. `rehearsal` adds
`com.apple.security.cs.disable-library-validation` to a temporary copy of the entitlements and
says so; check 4c refuses it in `distribution`, where the Developer ID gives both sides the
same team.

## Notarisation credentials

`Scripts/notarise.sh` and `Scripts/notarise_dmg.sh` use a notarytool keychain profile, named
`uttrflow-notary` unless `UTTRFLOW_NOTARY_PROFILE` says otherwise. Create it once:

```bash
xcrun notarytool store-credentials uttrflow-notary \
  --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD
```

Without a profile they accept `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD` from the
environment, which is what the release workflow passes. `make notarise-check` runs every
preflight with no credentials.

## Cost

`-scheme Uttrflow` builds the app target's whole dependency graph, which includes
`UttrflowLocalModel` and therefore MLX for the suggestion feature. So `Cmlx` is compiled by
every mode, and **every mode needs the Metal Toolchain**, the same optional Xcode component
`make bakeoff` needs. Package resolution fetches every dependency the manifest names, so a
fresh clone spends a while on the network before the first build. Measured with `make app` on
an M-series Mac: about 3m40s cold (resolution plus a full Release build), a few seconds warm.
Derived data lands in `.build/xcode`, so `make clean` clears it.

Related: `Docs/releasing.md` (notarising, publishing, updates), `Docs/development-build.md`,
`Docs/tooling-traps.md`.
