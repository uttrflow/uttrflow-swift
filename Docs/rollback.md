# Rolling back a release

What to do when a full release turns out to carry a quality regression, such as a scoring or
clean-up layer that makes transcripts worse. [`releasing.md`](releasing.md) and
[`RELEASING.md`](../RELEASING.md) cover the forward path; this page covers the way back.

## What the updater allows

- Sparkle offers an item only when its `sparkle:version` (`CFBundleVersion`) is higher than the
  installed copy's. It never offers a downgrade.
- `appcast.xml` carries exactly one item, written by `Scripts/appcast.py`.

So a copy that already installed the broken release leaves it only for a **higher** build. A
rollback is always a new patch release, never a republished old one. Republishing the previous
item only stops copies that have not updated yet from being offered the broken build.

## The order of actions

| Step | Who | Command |
|---|---|---|
| 1. Pause the feed (optional) | maintainer | restore the previous `appcast.xml` and `latest.json` in `uttrflow/releases`, below |
| 2. Revert or switch off the cause | anyone, through a pull request into `main` | `git revert <merge commit>` |
| 3. Bump the version | the same pull request | `CFBundleShortVersionString` to the next revision, `CFBundleVersion` up by one |
| 4. Tag a candidate and soak briefly | maintainer | `git tag v26.0926.1-rc.1 && git push origin v26.0926.1-rc.1` |
| 5. Prove the patch sorts above the broken build | maintainer | `python3 Scripts/update_feed_gate.py check-order <broken appcast> <patch appcast>` |
| 6. Release the patch | maintainer | `git tag v26.0926.1 && git push origin v26.0926.1` |

Step 2 is the root of the rollback, so it goes through review and CI like every change. A soak
for a revert can be shorter than the three days `RELEASING.md` sets for a feature release; the
other "holding up" criteria still apply. Step 6 rewrites `appcast.xml` and `latest.json`, which
also ends a pause from step 1.

### Pausing the feed

In a clone of `uttrflow/releases`, put back the manifest and appcast of the last good release:

```bash
git log --oneline -- appcast.xml                 # find the commit that published the broken one
git checkout <that commit>~1 -- appcast.xml latest.json
git commit -m "Pause the feed at <last good version>"
git push
```

The backend caches the appcast for five minutes, so the pause takes effect within that window.
The previous item keeps its tag-pinned enclosure URL and signature, so nothing is re-signed.

### What a user on the broken build is told

The patch's `CHANGELOG.md` entry names the regression and says the patch fixes it. The appcast's
`sparkle:releaseNotesLink` points at the patch's release page on `uttrflow/releases`, which is
what Sparkle shows when it offers the update. Nothing reaches the user before the patch exists.

## The ordering check

`update_feed_gate.py check-order` reads two appcasts and exits 1 unless the second has a full
`N.N.N` version and a build strictly above the first; a prerelease version, an equal build or a
lower version is refused. `make update-feed-test` covers it.

Run against a staging copy of the feed written by `Scripts/appcast.py` with invented values
(`26.0925.0` build 8 last good, `26.0926.0` build 9 broken, `26.0926.1` build 10 patch):

| Check | Output | Exit |
|---|---|---|
| broken, then patch | `26.0926.1 (10) above 26.0926.0 (9)` | 0 |
| broken, then paused feed | `patch build 8 does not rise above 9, so Sparkle would not offer it` | 1 |
| patch, then broken | `patch build 9 does not rise above 10, so Sparkle would not offer it` | 1 |

The second row is the reason a pause protects only copies that have not updated yet.
