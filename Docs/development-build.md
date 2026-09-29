# The development build

`make app-dev` produces `dist/Uttrflow-Dev.app`: the same code as `make app`, under a
different identity and data folder. Only one Uttrflow build can listen for the dictation
shortcut and microphone at a time. Launching a second build shows both app names and exits;
quit the running build before starting the other.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make app-dev
open dist/Uttrflow-Dev.app
```

## What differs, and what it buys

`Scripts/bundle.sh development` takes `Resources/Uttrflow-Info.plist` and changes four
things in a temporary copy. Nothing else in the build differs, and `make app` is
untouched.

| Key | Shipped | Development |
|-----|---------|-------------|
| `CFBundleIdentifier` | `com.uttrflow.Uttrflow` | `com.uttrflow.Uttrflow.dev` |
| `CFBundleName` | `Uttrflow` | `Uttrflow Dev` |
| `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` | set | removed |
| `UttrflowBackendURL` | set | removed |

The identifier is the whole mechanism. macOS keys almost everything an app owns off it,
so changing it separates all of them at once:

- **Its defaults domain.** `~/Library/Preferences/com.uttrflow.Uttrflow.dev.plist`, so
  the settings the development build writes are not the settings the installed app reads.
- **Its Application Support folder.** `LocalStore` in `UttrflowCore` derives the folder
  name from `Bundle.main.bundleIdentifier` rather than hard-coding `Uttrflow`, so the
  clipboard, the history, the dictionary, the snippets and the predict corpus land in
  `~/Library/Application Support/Uttrflow.dev/`.
- **Its Keychain items and process identity**, so its credentials stay separate from the installed app.

The distinct identities do not let both builds dictate at once. The shortcut and microphone
are system-wide, so Uttrflow checks for other running `com.uttrflow.Uttrflow*` builds and
allows only one to start. This coordination lock does not change either build's data folder.
If a custom identifier falls back to the production data folder, the launch alert explains
that and shows how to give the build an isolated identifier.

The update feed is removed because a development build that found the release would
install it over itself, which is the one way this build can turn back into the other one.

**It signs in against nothing, on purpose.** `OnboardingAccountLayer.forThisBuild()`
only reaches the real backend when the bundle has both `UttrflowBackendURL` and a
compiled-in release key; with the URL gone, it always falls back to
`InMemoryAuthenticationService`, so the development build never opens a real account
session against the production service.

**So its sign-in is a stand-in, and the page says so.** The sign-in page reads
"Development build: signs in as a stand-in, no browser" under the providers. Pressing one
opens no browser and signs in at once as `Development User`. The stand-in is signed with a
key made fresh for each process, so it does not survive a relaunch: every launch of a
development build opens on sign-in again, and one press gets past it.

**To test real sign-in, build the release app with `make app`.** It talks to
`https://api.uttrflow.com`, opens Google in the default browser, and keeps the session in
the Keychain across relaunches. It shares its identifier with the installed app, so quit
that first. `log stream --predicate 'subsystem == "com.uttrflow.Uttrflow" AND category ==
"account"'` shows each step, as the table in `Docs/logging.md` lists.

## What it costs

**macOS treats it as a new app, so Accessibility and Microphone have to be granted to it
once, separately.** That is the trade, and it is the right one: a grant shared with the
installed app is a grant that cannot be revoked from one without revoking it from the
other. Both are in System Settings → Privacy & Security, and `Uttrflow Dev` appears
there the first time it asks.

**The speech model is downloaded again**, into `Uttrflow.dev/Models`, for the same
reason everything else is separate. If that download is not worth waiting for, point the
new folder at the one that already has it before first launch:

```bash
mkdir -p ~/Library/Application\ Support/Uttrflow.dev
ln -s ~/Library/Application\ Support/Uttrflow/Models \
      ~/Library/Application\ Support/Uttrflow.dev/Models
```

## Telling them apart

`Uttrflow Dev` in the menu bar's application menu and in the App Switcher, a menu bar
mark with a blue `Dev` label, and `Uttrflow-Dev.app` on disk.
