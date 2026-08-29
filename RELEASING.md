# Releasing Uttrflow

For the maintainer. Contributors do not need this; [`CONTRIBUTING.md`](CONTRIBUTING.md) is
the whole of what they do.

## The model

One long-lived branch, `main`, always releasable. **A release is a tag.** There is no
staging branch and no release branch, and this is deliberate rather than lax — see
"Why there is no staging branch" below.

```
fork / branch ──PR──> main ──tag v0.3.0-rc.1──> prerelease  (soak)
                       │
                       └──tag v0.3.0────────> release       (download button moves)
```

Versions follow [semantic versioning](https://semver.org). For an app rather than a
library that means, roughly: **patch** for a fix nobody has to read about, **minor** for a
feature, **major** when somebody's settings, data or habits stop working the way they did.

## Cutting a release

**One.** Decide the version and put it in the one place it lives:

```
Resources/Uttrflow-Info.plist
  CFBundleShortVersionString   0.3.0     what people see
  CFBundleVersion              6         a counter; only has to increase
```

Both are edited by hand, at the moment the release is cut, because that is the only moment
the number can actually be decided. The release workflow **refuses a tag that disagrees
with the plist** — a `v0.3.0` tag on a build reporting `0.2.2` publishes an appcast that
offers every installed copy a downgrade.

**Two.** Update `CHANGELOG.md`: move everything under `## [Unreleased]` into a new
version heading with today's date.

**Three.** Land both through a pull request, like everything else.

**Four.** Tag a candidate and let it soak:

```bash
git checkout main && git pull
git tag v0.3.0-rc.1
git push origin v0.3.0-rc.1
```

That builds, notarises and publishes a **prerelease**. It does not move
`/releases/latest/download/Uttrflow.dmg` and it does not touch `latest.json`, so no
installed copy is offered it and the download button is unchanged. Give it to whoever is
willing to run it.

**Five.** When it holds up, ship the same tree:

```bash
git tag v0.3.0
git push origin v0.3.0
```

That publishes a full release, which takes over the download URL and the appcast the
moment it lands.

If the candidate does not hold up, fix it on `main` through a pull request and tag
`-rc.2`. Candidates are cheap; that is the point of them.

## What the tag actually does

`.github/workflows/release.yml`, in order:

1. **Checks the tag against the plist** on a Linux runner, because it costs seconds and the
   rest costs an hour.
2. **Runs `make verify`.** A tag can point at any commit, including one that never went
   through a pull request, so this is not redundant with CI.
3. **Imports the Developer ID certificate** into a keychain created for that job.
4. **`make app-dist`** — hardened runtime, secure timestamp, Developer ID.
5. **`make notarise`** — submits to Apple and staples the ticket.
6. **`make dmg`** then **`make notarise-dmg`** — in that order, so the app carries its own
   ticket before the image is built around it. The other way round leaves the app depending
   on a ticket stapled to a disk image the user no longer has.
7. **`make publish`** — builds the update archive from the app *inside the mounted image*
   so the two assets cannot be different builds, signs it with the Sparkle EdDSA key,
   writes the appcast, and pushes it all to `uttrflow/releases`.

## Secrets this repository needs

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE` | Developer ID Application `.p12`, base64. `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` | The password set when that `.p12` was exported |
| `MACOS_SIGNING_IDENTITY` | `Developer ID Application: NAME (TEAMID)` |
| `APPLE_ID` | The Apple ID owning the developer account |
| `APPLE_TEAM_ID` | The ten-character team identifier |
| `APPLE_APP_PASSWORD` | An app-specific password from appleid.apple.com — **not** the Apple ID password |
| `SPARKLE_PRIVATE_KEY` | The base64 EdDSA private half, from `generate_keys -x` |
| `RELEASES_TOKEN` | A PAT with `contents:write` on `uttrflow/releases`. The built-in `GITHUB_TOKEN` cannot write to another repository, which is why downloads live in one |

**`SPARKLE_PRIVATE_KEY` has no backup anywhere.** It exists in the release Mac's login
keychain and, once you add it, here. Losing it does not break installed copies — it means
no future release can ever be signed for them, and every one has to be replaced by hand.
Export it with `generate_keys -x` and keep it somewhere that survives this Mac.

## Releasing by hand

The workflow is a convenience, not the only path. Everything it runs is a `make` target,
so a release can be cut from the release Mac with the same commands — `make release` then
`make publish`. `Docs/releasing.md` covers that path and the reasoning behind each step.

## Why there is no staging branch

Because the gate belongs on the pull request, not after it.

A staging branch tests code that has **already been merged**. The bad change is in a
shared branch, blocking every other feature waiting there, and somebody has to notice and
back it out. CI on a pull request tests the merge result **before** the merge is allowed,
so the bad change never lands at all. That is the same check, earlier, and earlier is
strictly better.

The branch was only ever a proxy for "has this been tested?", and a required status check
answers that question directly. What a staging branch additionally gives you — a build
that real people run before it becomes the default — is what `-rc` tags give you, without
a permanent branch to keep in sync, and without the merge to `main` being itself an
untested change.

Batching is preserved exactly: it is now "when do I tag" rather than "when do I merge
beta". Releases stay as infrequent as you want them.
