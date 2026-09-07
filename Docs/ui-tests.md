# Driving the real app

`make verify` proves the logic. It cannot prove the app opens a window, because there is no
window in a `swift test` process. That gap is what this suite is for, and it is deliberately
small: everything a headless test can assert belongs in a headless test, where it runs in
milliseconds and never flakes.

## Where it lives, and why it is not a SwiftPM target

SwiftPM cannot express a UI-testing bundle — `bundle.ui-testing` is an Xcode product type. So
`UITests/project.yml` describes one target, `Scripts/uitest.sh` generates a project from it with
XcodeGen, and the generated `.xcodeproj` is gitignored. The configuration is the source; the
project is build output.

Nothing about the app's own build changes. SwiftPM still compiles it and `Scripts/bundle.sh`
still assembles it; the suite drives `dist/Uttrflow.app` through
`XCUIApplication(url:)` rather than building its own copy. That is the whole reason this can be
added without porting the project to Xcode.

```bash
brew install xcodegen   # once
make app                # the bundle under test
make uitest
```

## Why it is not in `make verify`

Three reasons, in order of how much they matter:

- **It needs a windowing session.** A UI test on a machine with no logged-in GUI session fails
  for a reason that has nothing to do with the change under test.
- **It needs permissions `make verify` never asks for.** Anything touching the keyboard tap, the
  microphone or a global hotkey needs Accessibility granted to both the app and the test runner.
  A GitHub-hosted runner cannot grant that, and cannot be made to.
- **It is slow enough to change how the gate feels.** `make verify` already takes 9–18 minutes on
  CI. The gate should not grow for tests that cannot run there anyway.

## The two tiers

**Launch and draw** — the tests here now. No permission, no state, no keyboard. That the app
comes up, that every settings pane renders, that quitting leaves nothing running. These can run
anywhere a screen exists, including a hosted runner.

**Keyboard and lifetime** — not written yet, and needs a machine with Accessibility pre-granted.
Posting `CGEvent`s to exercise a real shortcut is the automated form of the manual procedure
`shortcuts.md` already describes. A soak run — hours of synthetic activity, then a clean quit,
asserting object counts stayed flat — belongs here too, and is the only thing that can catch the
teardown crash class.

## What to be careful of

The suite drives the app you have installed state for. On a developer's Mac that means real
settings and real history, read-only in these tests but not isolated. Before the second tier is
written, the app should accept a container path at launch, the way `AppDelegate.init(container:)`
already allows in unit tests — that isolates settings, history, clipboard and corpus in one move
and is what makes a keyboard test repeatable.

Selectors are titles the presenters produce. When a pane is renamed, this suite is where it is
felt, which is the cost of testing what the user sees rather than what the code returns.
