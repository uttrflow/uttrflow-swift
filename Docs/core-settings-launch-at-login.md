# Launch at login: why `LaunchAtLogin` re-reads instead of believing `SMAppService`

`SMAppService.mainApp` is the app's own login item: no helper bundle to install and
nothing to keep in step with it. It is the replacement for the deprecated
`SMLoginItemSetEnabled`.

Neither half of `SMAppService`'s answer means what it looks like:

- `register()` throws when the caller already has what it wanted — registering twice —
  over a database that says enabled.
- `register()` returns without complaint for a build macOS will never launch: one that is
  not a signed app bundle, whose `status` is `.notFound` and which `LaunchAtLogin` reports
  as `.unavailable`, so a developer running from the command line sees an honest "cannot"
  rather than a switch that appears to work.
- `register()` can succeed and leave the app at `.requiresApproval`: macOS will not start
  it until the user allows it under Login Items, and asking again cannot move that on.

So the thrown error is not evidence of failure and its absence is not evidence of success.
`LaunchAtLogin.applying(_:)` makes the change with `try?` and returns a fresh
`readStatus()`, the only answer that says what happens at the next login. `status` is read
afresh on every access for the same reason: the user can change it in System Settings
while the app runs and never tell it.

`SMAppService.Status` is an Objective-C enum, so a later macOS can hand back a case this
build does not name. That maps to `.disabled`: certainly not `enabled`, but it leaves the
switch with the user, and the re-read after their next attempt tells the truth.

The three system calls are injected so outcomes a test machine cannot be talked into — a
user who refused the app under Login Items, a build macOS will not launch — run without
writing to the real login-item database. `LaunchAtLoginTests` combines "what the database
ends up as" and "whether the call throws" independently because `SMAppService` really does
combine them in all four ways. The wiring in `LaunchAtLogin+System.swift` is excluded from
the coverage gate and kept short enough that reading it is the review.
