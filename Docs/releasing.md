# Releasing Uttrflow

Everything happens on a Mac somebody is sitting at. There is no build server, and adding
one is not a pending task — see [Why there is no CI](#why-there-is-no-ci).

## The version

Semantic versioning, in `Resources/Uttrflow-Info.plist`, edited by hand:

| Key | Example | What it is |
| --- | --- | --- |
| `CFBundleShortVersionString` | `0.1.0` | The marketing version. Patch for fixes, minor for features, major for breaking changes. |
| `CFBundleVersion` | `1` | The build counter. Only has to increase; macOS uses it to tell two builds of one version apart. |

By hand, because semantic versioning depends on *what changed*, which no script can read.
Bump it in the commit that cuts the release.

**Calendar versioning was tried and rejected.** `YEAR.MONTH.DAY.HOUR.PATCH` works
technically — a five-component version signs, verifies `--deep --strict`, and Spotlight
reports `kMDItemVersion` correctly — but Apple documents these keys as three integers, so
it is outside spec and the App Store would refuse it. Do not re-propose it.

## A test build

No Apple account, no certificate, nothing to configure.

```bash
make app               # ad-hoc signature, no hardened runtime — what a test build ships
make dmg               # dist/Uttrflow-<version>.dmg
make publish           # a release on uttrflow/releases, with the signed update archive
```

**`make app`, not `app-hardened`, until there is a Developer ID.** This reversed when
Sparkle arrived, and the reason is worth reading before somebody reverses it back.

An ad-hoc signature has no Team ID. Library validation — part of the hardened runtime —
requires that an app and the code it loads share one, so an ad-hoc *hardened* build
cannot load `Sparkle.framework` at all: it dies at launch with "different Team IDs". The
only way to harden a test build is to disable library validation, and that entitlement
would then be in the build every tester runs, letting any library signed by anyone load
into a process holding microphone and Accessibility access. That is a permanent cost for
no benefit, because the hardened runtime buys nothing until it is paired with
notarisation.

`make app-hardened` still exists and is still worth running before a release — it is now
purely a rehearsal, it adds the library-validation exception to a *copy* of the
entitlements and says so, and `bundle.sh` check 4c refuses a distribution build that
carries it. What it rehearses is the microphone trap below.

The day a Developer ID exists this goes back to `app-dist`: the app and every nested
piece of Sparkle carry the same team, library validation passes on its merits, and
nothing needs an exception.

The trap `app-hardened` exists to catch: a hardened build **without** the audio-input
entitlement does not prompt and does not error — `requestAccess` returns false, the
engine starts, and every sample is exactly 0.0. It is invisible on a Mac that has
already granted this bundle identifier, which includes the one that built it.

This is published as a **full release**, so `/releases/latest/download/Uttrflow.dmg`
resolves to it and `uttrflow.com/download` serves it. That is deliberate: the day a
Developer ID exists, publishing a notarised image is the entire migration — same command,
same URL, no site deploy, and the page drops the `xattr` note on its own because it reads
`gatekeeper` out of `latest.json`.

The cost is stated rather than hidden: until then, the public download button serves a
build macOS calls damaged. `publish.sh` prints that in capitals before it uploads.

Unsigned builds still take a `-test.<sha>` tag, never a bare `v<version>` — that tag
belongs to the notarised release of that version, which may not exist yet.

Gatekeeper refuses an un-notarised app that arrived through a browser, saying it is
damaged. It is not. The release notes carry the fix, and so does the download page:

```bash
xattr -dr com.apple.quarantine /Applications/Uttrflow.app
```

Transferring with `scp`, `rsync` or a USB stick sets no quarantine attribute at all, so
none of that is needed — it is the *receiving application* that stamps the file, not the
signature.

## Pointing a build at the backend

A shipped build needs two things before it talks to `uttrflow-backend`, and it needs
**both** or neither:

1. **`UttrflowBackendURL` in `Resources/Uttrflow-Info.plist`** — the origin of the deployed
   service, e.g. `https://api.uttrflow.com`. Absent in this repository on purpose: there is
   no deployment yet, and a placeholder that looks like a URL is worse than no key at all.
2. **`Ed25519EntitlementVerifier.releasePublicKeyBytes`** — the 32 raw bytes of the
   backend's entitlement public key, which `npm run keygen` prints on the backend side.

`OnboardingAccountLayer.forThisBuild()` checks for both and falls back to the in-process
development backend when either is missing. That pairing is deliberate: a build with an
address and no key signs somebody in and then refuses the entitlement it was just handed,
with a signature error nobody can act on. A build with a key and no address never reaches
a server at all.

Neither value is a secret. A public key is public, and the address is in every packet the
app sends.

## A real release

Needs an Apple Developer Program membership. As of 2026-08-26 there is none:
`security find-identity -v -p codesigning` reports zero identities.

```bash
# once, ever
xcrun notarytool store-credentials uttrflow-notary \
  --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD

export UTTRFLOW_SIGNING_IDENTITY="Developer ID Application: NAME (TEAMID)"

make release      # stamp nothing, build, notarise app, build image, notarise image
make publish      # release + rewrite latest.json
```

`make release` runs four steps and **the order is the whole point**:

1. `app-dist` — Developer ID, hardened runtime, secure timestamp
2. `notarise` — Apple vouches for the **app**, ticket stapled into the bundle
3. `dmg` — the image is built **from the already-stapled app**
4. `notarise-dmg` — Apple vouches for the **image**, ticket stapled into it

Apple staples the ticket to whatever was *submitted*, and Gatekeeper checks whatever the
user *opened*. Notarise only the image and the app works until somebody drags it out and
ejects the image; notarise only the app and the download itself is refused before the app
inside is ever looked at. Both, in that order.

## Publishing

`Scripts/publish.sh` uses the `gh` login already on this Mac. Nothing is stored in a
secret anywhere, because nothing needs to leave the machine that has it.

It reads the version and the notarisation state **out of the image** rather than taking
them as arguments, so the tag cannot disagree with the file it names. It refuses when
`dist/` holds more than one image — `ls` sorts alphabetically, and a stale `0.1.0` sorted
ahead of a newer version once already, which would have published the wrong build under
the right command with no sign of it.

```bash
make publish-dry-run                        # say what would happen, do none of it
./Scripts/publish.sh dist/Uttrflow-1.2.dmg  # name one explicitly
```

## Updating

A published release carries two files: `Uttrflow.dmg`, which a person downloads, and
`Uttrflow.zip`, which an installed copy fetches. `publish.sh` builds the zip from the app
*inside the mounted image* — so the two cannot be different builds — signs it with the
EdDSA key in this Mac's login keychain, and writes `appcast.xml` beside `latest.json`.

The app asks `api.uttrflow.com/v1/updates/macos/appcast.xml`, which serves that file. It
does not ask GitHub, for two reasons in `internal/api/updates.go`: the app talks to one
host, and a check every six hours from every install is a heartbeat nobody else should
receive.

**The private key exists in one place: this Mac's login keychain**, as
"Private key for signing Sparkle updates". It is not in the repository and not in any
backup this project makes. Losing it does not break installed copies — it means no
future release can be signed for them, and every one of them has to be replaced by hand,
because the public half is compiled into each build. Export it with `generate_keys -x`
before this Mac is ever wiped.

A build with `SUFeedURL` set and no usable `SUPublicEDKey` is refused by `bundle.sh`
check 4a: a feed with nothing to verify against installs whatever it is handed.

## Where downloads live

The public repository **[uttrflow/releases](https://github.com/uttrflow/releases)**. It
holds disk images and `latest.json` and no source code. The source repositories are
private and stay that way; a download link has to be public, so the two are separated.

One repository serves every platform. A release is a version of the *product*, not of a
build, and splitting per platform would let `1.2.3` exist for macOS and not for Windows
with nothing enforcing they are the same code.

The published asset is **`Uttrflow.dmg`, with no version in the name**. That is what makes

```
https://github.com/uttrflow/releases/releases/latest/download/Uttrflow.dmg
```

a permanent address: GitHub resolves it to the newest release carrying an asset of
exactly that name. A version in the filename would make that URL a 404 the day after it
was written. The local file keeps its version — a developer building by hand wants it —
and `publish.sh` renames the copy it uploads. Opposite needs, met in different places.

`latest.json` is what `uttrflow.com/download` reads to name the version and its size. The
page treats it as decoration and never as the source of the link, so a stale, missing or
unreachable manifest costs a caption rather than the download.

When a second platform exists, it uploads into the **same release**, and `latest.json`
must be written only after every platform has uploaded — otherwise the page can advertise
a version that exists for one OS and 404s for another.

## Why there is no CI

GitHub Actions bills macOS runners at **ten times** Linux, and this project cannot use
Linux: it builds against macOS 26 frameworks and its tests drive the real Accessibility,
clipboard and speech APIs. Fifty-one runs over two days consumed **97% of the free plan's
2,000 monthly minutes**, after which jobs stopped starting — silently, for days, while the
repository went on looking green. A gate that can fail without saying so is worse than no
gate, because it is trusted.

The source is private, so the free minutes public repositories get are not available.

The gate is therefore **`.githooks/pre-push`**, which runs `make verify` — the same lint,
build, 2,640 tests and coverage floor the workflow ran — before anything reaches `main`.

```bash
make hooks     # once per clone: hooks are not cloned, this sets core.hooksPath
```

Two details that were learned rather than designed:

- **It verifies the pushed commit, in a worktree of its own.** The first version checked
  the working tree and was immediately blocked by a lint error in a file its commit never
  touched, belonging to a concurrent session still typing. What is pushed is a commit; the
  working tree is whatever is on the desk. The worktree is reused so `.build` stays warm
  (~47s warm, ~114s cold) and lives inside `.git`, so it never appears in `git status`.
- **Only `main` is gated.** Blocking branches teaches people to reach for `--no-verify`,
  which turns the gate off for `main` too.

Windows and Linux runners bill at 2× and 1×, so when a second platform exists, building
*it* on Actions is affordable. The 10× problem is specific to macOS.
