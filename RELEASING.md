# Releasing Uttrflow

For the maintainer. Contributors do not need this; [`CONTRIBUTING.md`](CONTRIBUTING.md) is
the whole of what they do.

## The model

One long-lived branch, `main`, always releasable. **A release is a tag.** There is no
staging branch and no release branch, and this is deliberate rather than lax — see
"Why there is no staging branch" below.

```
fork / branch ──PR──> main ──tag v26.0926.0-rc.1──> prerelease  (soak)
                       │
                       └──tag v26.0926.0────────> release       (download button moves)
```

Versions are **`YY.MMDD.REVISION`** for the day the release is cut — `26.0926.0`, then
`26.0926.1` for a second release that day. Month before day with the leading zero kept, so
versions sort in date order. `2026.9.14` and semver up to `0.5.0` are retired; the updater
orders by `CFBundleVersion`, which keeps rising across every scheme.

## Cutting a release

**One.** Decide the version and put it in the one place it lives:

```
Resources/Uttrflow-Info.plist
  CFBundleShortVersionString   26.0926.0   what people see
  CFBundleVersion              9           a counter; only has to increase
```

Both are edited by hand, at the moment the release is cut. `CFBundleVersion` is what the
updater compares, so it must go up by at least one every release, whatever the date says. The release workflow **refuses a tag that disagrees
with the plist** — a `v26.0926.0` tag on a build reporting `0.5.0` publishes an appcast that
offers every installed copy a downgrade.

**Two.** Update `CHANGELOG.md`: move everything under `## [Unreleased]` into a new
version heading with today's date.

Run `make accuracy-report VERSION=<version>` and commit the report it writes under
`Docs/accuracy-reports/` with the new line of `Docs/accuracy-history.json`; the release notes link
that report ([`Docs/measuring-accuracy.md`](Docs/measuring-accuracy.md#the-release-report)).

Add `Tests/Fixtures/stores/<tag>/` with each covered store's file as the release writes it
(invented content only) and add the tag to `releases` in `ReleasedStoreFixtureTests`; see
[`Tests/Fixtures/stores/README.md`](Tests/Fixtures/stores/README.md).

**Three.** Land all of it through a pull request, like everything else.

**Four.** Run the quality gate on the commit to be tagged, and attach the file it writes to the
candidate's release notes:

```bash
make release-quality BAKEOFF_BASELINE=<saved bake-off result> RUN=<uttrflow-dev bench run>
```

It exits non-zero when any gate fails or has no verdict, and `dist/release-quality.md` names
which ([`Docs/releasing.md`](Docs/releasing.md#the-gate-before-a-release)). Then tag a candidate
and let it soak:

```bash
git checkout main && git pull
git tag v26.0926.0-rc.1
git push origin v26.0926.0-rc.1
```

That builds, notarises and publishes a **prerelease**. It does not move
`/releases/latest/download/Uttrflow.dmg` and it does not touch `latest.json`, so no
installed copy is offered it and the download button is unchanged. Give it to whoever is
willing to run it.

**Holding up** means every one of these is true of the candidate, checked on the day you
tag the release:

| Criterion | Limit | Check |
|---|---|---|
| Soak time since the candidate's tag | at least 3 days | `git log -1 --format=%ci v26.0926.0-rc.1` |
| Open `P0` issues reported against the candidate | 0 | `gh issue list --label P0 --state open` |
| Crash-free sessions in the opt-in report | at or above the previous release | the release-health view described in [`Docs/crash-reporting.md`](Docs/crash-reporting.md) |
| `make verify` on the tagged commit | exit 0 | the release workflow's verify step for the `-rc` tag |
| Transcription accuracy against `Scripts/accuracy_baseline.json` | no slice worse | `make accuracy-gate` on the tagged commit, with the shipping model installed |
| Live-model suites (`*LiveModelTests`) on a Mac with Apple Intelligence | 0 skipped, 0 failed | `make verify` prints `live-model tests: N run, 0 skipped` |
| The candidate's bundle launches, draws every settings pane and quits cleanly | exit 0 | `make uitest` against the candidate's `Uttrflow.app` ([`Docs/ui-tests.md`](Docs/ui-tests.md)) |
| Heap growth over a used session with suggestions on | no class whose count only rises, and a clean quit | `make soak` against the running candidate, then quit it ([`Docs/soak.md`](Docs/soak.md)) |

A new candidate restarts the soak time. A criterion with no data, such as a candidate
nobody has run yet, is not met.

**Five.** When it holds up, ship the same tree:

```bash
git tag v26.0926.0
git push origin v26.0926.0
```

That publishes a full release, which takes over the download URL and the appcast the
moment it lands.

If the candidate does not hold up, fix it on `main` through a pull request and tag
`-rc.2`. Candidates are cheap; that is the point of them.

If a full release turns out to carry a regression, follow
[`Docs/rollback.md`](Docs/rollback.md): the way back is a higher patch release, never a downgrade.

## What the tag actually does

`.github/workflows/release.yml`, in order:

1. **Checks the tag against the plist** on a Linux runner, because it costs seconds and the
   rest costs an hour.
2. **Publishes the changelog entry as a release on this repository**, from
   `Scripts/changelog.py`, marked a prerelease for an `-rc` tag. It carries no assets — the
   disk image and the update archive live in `uttrflow/releases`, and a second copy of
   either is a second answer to which build a version is. This job holds no secrets, so it
   runs whether or not a Developer ID exists.
3. **Asks whether this repository holds a Developer ID at all.** Without one, everything
   below is skipped rather than attempted: it used to run `make verify` on a macOS runner —
   billed at ten times a Linux one — and then fail at the certificate import.
4. **Runs `make verify`.** A tag can point at any commit, including one that never went
   through a pull request, so this is not redundant with CI.
5. **Imports the Developer ID certificate** into a keychain created for that job.
6. **`make app-dist`** — hardened runtime, secure timestamp, Developer ID.
7. **`make notarise`** — submits to Apple and staples the ticket.
8. **`make dmg`** then **`make notarise-dmg`** — in that order, so the app carries its own
   ticket before the image is built around it. The other way round leaves the app depending
   on a ticket stapled to a disk image the user no longer has.
9. **`make publish`** — builds the update archive from the app *inside the mounted image*
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
