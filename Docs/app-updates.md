# Updates: why the app holds Sparkle's install handle

`Sources/Uttrflow/Updates/UpdateController.swift` wires Sparkle; the rule about *when* an
update may install is `UpdateGate` in `UttrflowUX`, which is a tested value.

## The delegate call that matters

Sparkle's default is to install a downloaded update the next time the app quits. A menu-bar
app that is opened once and never quit means never, so the update would sit staged for weeks.
`updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` offers an install-now
handle; the controller keeps it, returns `true` to take responsibility for the timing, and
calls it the moment the app has been quiet for `UpdateGate.settleSeconds`.

Found by rehearsing an update end to end rather than by reading. An earlier attempt used
`updaterShouldRelaunchApplication`, which is a different question (whether to come back
after installing, not whether to install); answering "no" there would have installed the
update and left the app closed.

## The wake-up

The gate opens at an instant, a minute after the app went quiet, and the app only reports its
activity when something changes. An app that goes quiet and stays quiet reports nothing more,
so the moment the gate opens is precisely a moment nothing is asking it. A version that only
listened left the update staged indefinitely on a Mac nobody was touching. `scheduleWakeUp`
sleeps for exactly the time remaining and calls `refresh()` (not the install check alone,
because the app may be busy again by then).

`progress = .installing` is set *before* the handle is called: the call ends with this
process being replaced, and without the line the relaunch looks like a crash.

## Feed acceptance

`isConfigured` requires an `https` feed, or `http` to `127.0.0.1`, `localhost` or `::1` only.
The loopback exception is what makes the feature rehearsable on one Mac (build, sign, serve,
install, and watch a running app replace itself and keep its permissions). It is not a hole:
anything that can serve on this Mac's loopback is already running as the user, and
`Scripts/bundle.sh` applies the same rule so a build pointed at a local feed cannot be
published.

A placeholder `SUPublicEDKey` fails closed. The entitlement work found the same shape of bug,
an all-zero Ed25519 key that verified forged signatures.

## What is never sent

`feedParameters(for:sendingSystemProfile:)` returns nothing. Sparkle offers to attach OS
version, model, CPU and launch counts; Uttrflow collects none of that anywhere else.
