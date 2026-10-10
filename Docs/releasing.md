# Releasing Uttrflow

A release is a build of `main` named by a tag, wrapped in a disk image, and published to the
public `uttrflow/releases` repository, where the download button and every installed copy's
updater find it. The scripts are `Scripts/bundle.sh` (build and sign, see
`Docs/packaging.md`), `Scripts/notarise.sh` and `Scripts/notarise_dmg.sh`, `Scripts/dmg.sh`,
and `Scripts/publish.sh`; the Makefile targets below drive them. A release can be cut by hand
on a Mac, as this page describes, or by pushing a tag through `.github/workflows/release.yml`,
documented in [`RELEASING.md`](../RELEASING.md). Releasing is a maintainer's job; agents never
tag.

## The version

Calendar versioning, in `Resources/Uttrflow-Info.plist`, edited by hand:

| Key | Example | What it is |
| --- | --- | --- |
| `CFBundleShortVersionString` | `26.0926.0` | The version people see: `YY.MMDD.REVISION`, two-digit year, month and day, then the release number that day from 0. |
| `CFBundleVersion` | `10` | The build counter. Goes up by one every release; the updater compares this, not the date. |

Bump both in the commit that cuts the release. The tag is `v` and the version, `v26.0926.0`;
a candidate for it is `v26.0926.0-rc.1`; a second release that day is `v26.0926.1`. Month
before day, leading zero kept, so versions sort in date order within a year (`0110` for
1 October is above `0926`). The release workflow compares the tag to the plist as text, and
`Scripts/release_tag_ancestry.sh` refuses a tag whose commit is not on `main`.

The retired schemes, `2026.9.14` (`YEAR.MONTH.DAY`) and semantic versions up to `0.5.0`, are
numerically above a `26.x` version. That is harmless: Sparkle orders by `CFBundleVersion`
(the appcast's `sparkle:version`), and that counter only rises across every scheme.

**A five-part `YEAR.MONTH.DAY.HOUR.PATCH` version is not used.** It signs, verifies
`--deep --strict`, and Spotlight reports `kMDItemVersion` correctly, but Apple documents these
keys as three integers, so it is outside the specification and the App Store refuses it.

## A test build

No Apple account, no certificate, nothing to configure:

```bash
make app               # ad-hoc signature, no hardened runtime
make dmg               # dist/Uttrflow-<version>.dmg
```

That produces a disk image on this Mac and nothing more. **`make publish` is a separate,
externally visible step**: it pushes to the public `uttrflow/releases` repository and can make
this unsigned image the default download. Run `make publish-dry-run` first to see what it
would do without doing any of it.

**A test build is `make app`, not `make app-hardened`.** An ad-hoc signature has no Team ID,
and library validation, part of the hardened runtime, requires the app and the code it loads
to share one, so an ad-hoc *hardened* build cannot load `Sparkle.framework`: it dies at launch
with "different Team IDs". Hardening a test build would mean shipping the library-validation
exception to every tester, letting any library signed by anyone load into a process holding
microphone and Accessibility access, for no benefit until the build is notarised.
`make app-hardened` remains the rehearsal: it adds that exception to a *copy* of the
entitlements, says so, and `bundle.sh` check 4c refuses a distribution build that carries it.
What it rehearses is the microphone trap: a hardened build without the audio-input
entitlement does not prompt and does not error, and every sample is exactly 0.0, invisibly on
any Mac that already granted this bundle identifier. `Docs/packaging.md` has the measurement.

### Gatekeeper and an unsigned download

Gatekeeper refuses an un-notarised app that arrived through a browser, saying it is damaged.
It is not. The release notes `publish.sh` writes carry the fix:

```bash
xattr -dr com.apple.quarantine /Applications/Uttrflow.app
```

Copying with `scp`, `rsync` or a USB stick sets no quarantine attribute, so none of that is
needed: the receiving application stamps the file, not the signature.

An unsigned build is published as a **full release**, so
`/releases/latest/download/Uttrflow.dmg` resolves to it. That makes notarisation a drop-in
change: publishing a notarised image is the same command and the same URL, and `latest.json`
records `gatekeeper` (`notarised` or `unsigned`) so the download page shows the `xattr`
instruction only when it applies. The cost is that the public download is a build macOS calls
damaged until then, and `publish.sh` prints that in capitals before it uploads.

## Pointing a build at the backend

A shipped build needs two things before it talks to the account backend, and needs **both** or
neither:

1. **`UttrflowBackendURL`** in `Resources/Uttrflow-Info.plist`: the origin of the deployed
   service.
2. **`Ed25519EntitlementVerifier.releasePublicKeyBase64`** in
   `Sources/UttrflowAccount/EntitlementSignature.swift`: the backend's entitlement public key,
   base64.

`OnboardingAccountLayer.forThisBuild()` checks for both and falls back to the in-process
development backend when either is missing. A build with an address and no key would sign
somebody in and then refuse the entitlement it was handed; a build with a key and no address
never reaches a server. `bundle.sh` check 1b refuses a hardened build missing either. Rotating
either value is a coordinated release with the backend; see `Docs/operator-runbook.md`.
Neither value is a secret: a public key is public, and the address is in every packet the app
sends.

## A real release

Needs an Apple Developer Program membership and a Developer ID Application certificate
(`security find-identity -v -p codesigning` lists what this Mac holds), plus the notarytool
keychain profile `Docs/packaging.md` describes.

```bash
export UTTRFLOW_SIGNING_IDENTITY="Developer ID Application: NAME (TEAMID)"   # or IDENTITY=… on the make line
make release      # build, notarise app, build image, notarise image
make publish      # release on uttrflow/releases, then latest.json and appcast.xml
```

`make release` runs four steps, each a separate `$(MAKE)` line so `-j` cannot reorder them
(`make release-order-test` proves it), and **the order is the point**:

1. `app-dist`: Developer ID, hardened runtime, secure timestamp
2. `notarise`: Apple vouches for the **app**; the ticket is stapled into the bundle
3. `dmg`: the image is built **from the already-stapled app**
4. `notarise-dmg`: Apple vouches for the **image**; the ticket is stapled into it

Apple staples the ticket to whatever was *submitted*, and Gatekeeper checks whatever the user
*opened*. Notarise only the image and the app works until somebody drags it out and ejects the
image; notarise only the app and the download itself is refused before the app inside is
looked at.

## Publishing

`Scripts/publish.sh` (`make publish`) needs a `gh` login that can write to `uttrflow/releases`
and the Sparkle EdDSA private key, from the login keychain or `SPARKLE_PRIVATE_KEY`. By hand it
uses this Mac's `gh` login and keychain; in the release workflow it receives `RELEASES_TOKEN`
and `SPARKLE_PRIVATE_KEY` from repository secrets.

It reads the version, the build commit and the notarisation state **out of the image** rather
than taking them as arguments, so the release cannot disagree with the file it names. It
refuses an image built from a dirty checkout, and refuses when `dist/` holds more than one
image, because a directory listing can sort an old version ahead of a new one and publish the
wrong build under the right command.

```bash
make publish-dry-run                                 # say what would happen, do none of it
./Scripts/publish.sh dist/Uttrflow-26.0926.0.dmg     # name one explicitly
```

The tag names the release. A run triggered by a pushed tag publishes under exactly that tag;
a hand run uses `v<version>` from the plist. **A tag with anything after the version is a
prerelease**: `v26.0926.0-rc.1` publishes as one, GitHub keeps it out of `/latest/`, and
`publish.sh` leaves `latest.json` and `appcast.xml` alone, so neither the site nor the updater
offers it. That is the soak; `v26.0926.0` releases it. A rerun after the release was created
resumes the feed update instead of failing (`make publish-resume-test`).

## Updating

A published release carries two files: `Uttrflow.dmg`, which a person downloads, and
`Uttrflow.zip`, which an installed copy fetches. `publish.sh` builds the zip from the app
*inside the mounted image*, so the two cannot be different builds, signs it with the EdDSA
key, and writes `appcast.xml` beside `latest.json` with one item. The app's feed is
`SUFeedURL` in the plist, an address on the account backend that serves that appcast, so the
app talks to one host; it checks every six hours (`SUScheduledCheckInterval` 21600).

**The EdDSA private key** lives in the release Mac's login keychain and in the repository's
secrets as `SPARKLE_PRIVATE_KEY`. Losing it breaks no installed copy, but no future release
can be signed for them and every one must be replaced by hand, because the public half is
compiled into each build. Export it with Sparkle's `generate_keys -x` and keep the export
safe.

`bundle.sh` check 4a refuses a build with `SUFeedURL` set and no usable `SUPublicEDKey`: a
feed with nothing to verify against installs whatever it is handed. It parses the feed URL by
scheme and host: `https` with a host ships, and `http` is accepted only for exact loopback
hosts (`127.0.0.1`, `localhost`, `::1`), for rehearsing an update on one Mac.
`bundle.sh distribution` and `publish.sh` both refuse a loopback feed. `make update-feed-test`
proves the parsing.

`SUVerifyUpdateBeforeExtraction` is `true`, so Sparkle checks the archive against
`SUPublicEDKey` before it unpacks anything, and accepts no substitute for that signature but a
Developer ID signature from the running app's own team. Check 4a refuses a build with a feed
and without it, `UpdateController` does not start the updater without it, and
`UpdateConfigurationTests` fails if it leaves the plist. The development build has no feed;
see `Docs/development-build.md`. `Docs/app-updates.md` covers the updater inside the app.

## The signing identity

Every build without a Developer ID is signed ad hoc with the designated requirement
`identifier "com.uttrflow.Uttrflow"`: it names the bundle identifier and nothing else.
Privacy grants and keychain access follow the designated requirement, so an ad-hoc build is
identified by its identifier alone. A Developer ID build's requirement also pins the Team ID
(check 6), which is what makes Sparkle's Developer ID fallback usable. Nothing in the app
grants trust by bundle identifier on its own: the single-instance hand-off and the check that
skips reading Uttrflow's own windows compare identifiers, and neither unlocks anything.

## Where downloads live

The public repository **[uttrflow/releases](https://github.com/uttrflow/releases)** holds disk
images, update archives, `latest.json` and `appcast.xml`, and no source code.

The published asset is **`Uttrflow.dmg`, with no version in the name**. That makes

```
https://github.com/uttrflow/releases/releases/latest/download/Uttrflow.dmg
```

a permanent address: GitHub resolves it to the newest full release carrying an asset of
exactly that name, and a versioned filename would turn the URL into a 404 after the next
release. The local file keeps its version for whoever builds by hand, and `publish.sh` renames
the copy it uploads.

`latest.json` names the version, its size and `gatekeeper` for the download page, which treats
it as a caption and never as the source of the link, so a stale or missing manifest costs a
caption rather than the download.

## The gate before a release

`.github/workflows/ci.yml` runs `make verify` on every pull request into `main` and every push
to `main`, with dependency review beside it on pull requests; Scorecard runs on pushes to
`main` and weekly, and CodeQL weekly. The release
workflow runs `make verify` again before it builds. macOS runners are the only option: the
project builds against macOS 26 frameworks and its tests drive the real Accessibility,
clipboard and speech APIs.

The local gate is **`.githooks/pre-push`**, installed once per clone:

```bash
make hooks     # sets core.hooksPath; hooks are not cloned
```

It runs the disclosure audit on every commit pushed to any branch, and runs `make verify` (lint,
PII audit, build, the full test suite, the coverage floor) before a push to `main`. It verifies
the **pushed commit**, not the working tree, in a worktree of its own under the git directory,
reused so its `.build` stays warm and never shown in `git status`. Only `main` gets the full
`make verify`: blocking every branch would teach people to reach for `--no-verify`, which
turns the gate off for `main` too.

The quality gate for a candidate is **`make release-quality`**, run on the commit to be tagged
before the tag. It runs, in order, `make accuracy-gate`, `make seam-score`, the bake-off's held-out compare against
`BAKEOFF_BASELINE`, `Scripts/perf_budget_audit.py` on the source and on the bench run `RUN`, the
coverage matrix tests, the contamination and split tests, the degraded-path matrix tests, and
`Scripts/disclosure_audit.py --history`. It prints a table of each gate's verdict, threshold and
result, writes the same table to `dist/release-quality.md` for the candidate's release notes,
followed by each quality layer's marginal contribution with its measured latency and verdict, and exits non-zero when any gate
fails or has no verdict, such as a missing saved result. It tags nothing.
`make release-quality-test`, in `make verify`, proves a failure in each gate fails the command and
is named in the table.
