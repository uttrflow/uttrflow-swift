# Driving the real app

`make uitest` drives the built `dist/Uttrflow.app` through an XCUITest suite: that it launches,
that every settings pane draws, that quitting leaves nothing running, and that a test launch
uses disposable stores and locks. `make verify` proves the logic but cannot prove the app opens
a window, because a `swift test` process has none; this suite covers that gap and nothing
more. Everything a headless test can assert belongs in a headless test, where it runs in
milliseconds and never flakes. The tests are in `UITests/UttrflowUITests/`.

```bash
brew install xcodegen   # once
sudo automationmodetool enable-automationmode-without-authentication   # once
make app                # the bundle under test
make uitest
```

XCUITest drives the app through macOS automation mode. Where enabling it needs authentication,
which `automationmodetool` with no arguments reports, `xcodebuild` waits about a minute and
fails with "Timed out while enabling automation mode" before any test runs. The `sudo` line
above removes that prompt for the logged-in user; `Scripts/uitest.sh` checks for it first and
stops with that instruction instead of the timeout.

## Where it lives, and why it is not a SwiftPM target

SwiftPM cannot express a UI-testing bundle; `bundle.ui-testing` is an Xcode product type. So
`UITests/project.yml` describes one target, `Scripts/uitest.sh` generates a project from it
with XcodeGen, and the generated `.xcodeproj` is gitignored. The configuration is the source;
the project is build output.

The app's own build does not change. SwiftPM and `Scripts/bundle.sh` still build and assemble
it, and the suite launches `dist/Uttrflow.app` through `XCUIApplication(url:)` rather than
building its own copy (`AppUnderTest` in `UITests/UttrflowUITests/Support/AppUnderTest.swift`).
A missing bundle fails with "Run `make app` first" rather than a timeout.

`make uitest` writes its result bundle to `dist/uitest.xcresult`. `xcodebuild` refuses to write
into one that exists, so `Scripts/uitest_result_path.sh` first moves a previous bundle aside
under a timestamped name, keeping it for debugging. `make uitest-result-path`, part of
`make verify`, proves a second run does not fail.

## Why it is not in `make verify`

- **It needs a windowing session.** On a machine with no logged-in GUI session a UI test fails
  for a reason unrelated to the change under test.
- **Keyboard and microphone tests need permissions `make verify` never asks for.** Anything
  touching the keyboard tap, the microphone or a global hotkey needs Accessibility granted to
  both the app and the test runner, which a hosted runner cannot grant.
- **It would slow the gate** for tests that cannot run there anyway.

The suite as written needs no permission, no state and no keyboard, so it runs anywhere a
screen exists. Exercising a real shortcut with posted `CGEvent`s needs a machine with
Accessibility pre-granted; until then the manual procedure in `Docs/shortcuts.md` covers it,
and `Docs/soak.md` covers long-lived teardown.

## Isolation

Each launch gets its own disposable container through the test-only
`UTTRFLOW_TEST_CONTAINER` environment variable, read in `Sources/Uttrflow/UttrflowApp.swift`.
App data and the singleton locks live in that folder, and settings and onboarding use the
defaults suite `com.uttrflow.UITests.<container name>`. In that mode the app also starts with
onboarding finished, uses an in-memory account, turns off automatic update checks and installs,
and makes the login item inert. `AppUnderTest.terminate(_:)` waits up to 20 seconds for exit,
then removes the defaults suite and the folder. A UI run therefore neither reads nor writes the
installed app's state and does not contend for its locks.

Selectors are the titles the presenters produce. When a pane is renamed this suite is where it
is felt, which is the cost of testing what the user sees rather than what the code returns.

## Screen-capture privacy

The quick panel, the main window and the suggestion overlay set `NSWindow.sharingType` to
`.none` through `PrivateWindowSharing` (`Sources/Uttrflow/Privacy/PrivateWindowSharing.swift`);
`WindowSharingTests` covers that configuration. Not every capture path honours the setting on
every macOS release, so before a release on a new macOS version check it by hand: open the quick
panel on copied text and on a copied picture, open the History page with a recent dictation
visible, and show an inline suggestion in another app, then take a screenshot, a screen
recording and a video-call screen share. The captures should omit those windows. If one does
not, record the macOS version, the capture tool and the app version on this page, and rely on
ordinary secret masking as the fallback protection.

For a local development-build capture check, run
`open dist/Uttrflow-Dev.app --args --uttrflow-allow-window-capture`. Only the
`com.uttrflow.Uttrflow.dev` bundle honours this argument, and it leaves window sharing at AppKit's
default; without it, and in the release build, the windows remain excluded from capture. A capture
can contain text visible in the app, so use the argument only for intentional local checks.
