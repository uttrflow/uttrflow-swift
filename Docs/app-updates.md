# Updates: why the app holds Sparkle's install handle

Uttrflow updates itself with Sparkle. `Sources/Uttrflow/Updates/UpdateController.swift` wires it;
the rule about *when* an update may install is `UpdateGate` in `Sources/UttrflowUX/`, a tested
value, and which feed addresses are acceptable is `UpdateFeed` beside it. The feed address, the
public signing key and the check interval are in `Resources/Uttrflow-Info.plist`. How a release
reaches the feed is in [`releasing.md`](releasing.md).

| Value | Where | Meaning |
| --- | --- | --- |
| 60 s | `UpdateGate.settleSeconds` | how long the app must be quiet before a downloaded update installs |
| 21600 s (6 h) | `SUScheduledCheckInterval` | how often Sparkle checks when automatic checks are on |
| the appcast on the account API | `SUFeedURL` | the feed every shipped copy asks, which can never change |

## The delegate call that matters

Sparkle's default is to install a downloaded update the next time the app quits. A menu-bar app
that is opened once and never quit means never, so the update would sit staged for weeks.
`updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` offers an install-now handle; the
controller keeps it, returns `true` to take responsibility for the timing, and calls it the moment
the app has been quiet for `UpdateGate.settleSeconds`.

`updaterShouldRelaunchApplication` is not the hook for this: it answers a different question
(whether to come back after installing, not whether to install), and answering "no" there would
install the update and leave the app closed.

## The wake-up

The gate opens at an instant, a minute after the app went quiet, and the app only reports its
activity when something changes. An app that goes quiet and stays quiet reports nothing more, so
the moment the gate opens is precisely a moment nothing is asking it; listening alone would leave
the update staged indefinitely on a Mac nobody was touching. `scheduleWakeUp` sleeps for exactly
the time remaining and calls `refresh()` (not the install check alone, because the app may be busy
again by then).

`progress = .installing` is set *before* the handle is called: the call ends with this process
being replaced, and without the line the relaunch looks like a crash.

Typing observed by the suggestions loop, an armed suggestion or a turn still in flight also keeps
the gate busy. Once those have settled, the update gate starts its own full quiet interval.

## Feed acceptance

`UpdateController.isConfigured` requires the feed to pass `UpdateFeed.isAcceptable`: `https`, or
`http` to `127.0.0.1`, `localhost` or `::1` only (`UpdateFeed.loopbackHosts`). The loopback
exception is what makes the feature rehearsable on one Mac (build, sign, serve, install, and watch
a running app replace itself and keep its permissions). It is not a hole: anything that can serve
on this Mac's loopback is already running as the user. `Scripts/bundle.sh` applies the same rule
through `Scripts/update_feed_gate.py`; local and rehearsal builds may use a loopback feed,
distribution builds may not, and `Scripts/publish.sh` checks the app inside the disk image again
(`check-plist --forbid-local`) before calling it publishable.

A placeholder `SUPublicEDKey` fails closed: `isConfigured` accepts only base64 for a 32-byte
Ed25519 public key that is not all zeros, because an all-zero key would verify forged signatures
and Sparkle would install whatever the feed handed it. `Scripts/bundle.sh` refuses to build an app
with a feed and no real key, or without `SUVerifyUpdateBeforeExtraction` set to true.

## Automatic checks and installs

The General tab keeps two choices separate. **Check for updates automatically** controls Sparkle's
scheduled check, every six hours when enabled. Turning it off stops those background requests;
**Check Now** still asks Sparkle to check immediately. A check reveals the Mac's IP address, the
app version in its request user agent, and that the Mac is online at that time.

**Install updates automatically** controls whether a found update downloads without asking. It
does not control whether Sparkle checks. A downloaded update still waits until the app has been
quiet for `UpdateGate.settleSeconds` before it installs. A check that fails is silent: a feed that
could not be reached is not something the user can fix.

## What is never sent

`feedParameters(for:sendingSystemProfile:)` returns nothing. Sparkle offers to attach OS version,
model, CPU and launch counts; Uttrflow sends none of them.
