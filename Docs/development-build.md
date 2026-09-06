# The development build

`make app-dev` produces `dist/Uttrflow-Dev.app`: the same code as `make app`, under a
different identity, so it can run at the same time as the installed `Uttrflow.app` and
never touches its data.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make app-dev
open dist/Uttrflow-Dev.app
```

## What differs, and what it buys

`Scripts/bundle.sh development` takes `Resources/Uttrflow-Info.plist` and changes three
things in a temporary copy. Nothing else in the build differs, and `make app` is
untouched.

| Key | Shipped | Development |
|-----|---------|-------------|
| `CFBundleIdentifier` | `com.uttrflow.Uttrflow` | `com.uttrflow.Uttrflow.dev` |
| `CFBundleName` | `Uttrflow` | `Uttrflow Dev` |
| `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks` | set | removed |

The identifier is the whole mechanism. macOS keys almost everything an app owns off it,
so changing it separates all of them at once:

- **Its defaults domain.** `~/Library/Preferences/com.uttrflow.Uttrflow.dev.plist`, so
  the settings the development build writes are not the settings the installed app reads.
- **Its Application Support folder.** `LocalStore` in `UttrflowCore` derives the folder
  name from `Bundle.main.bundleIdentifier` rather than hard-coding `Uttrflow`, so the
  clipboard, the history, the dictionary, the snippets and the predict corpus land in
  `~/Library/Application Support/Uttrflow.dev/`.
- **Its Keychain items and its own process**, so both apps can be signed in and running.

The update feed is removed because a development build that found the release would
install it over itself, which is the one way this build can turn back into the other one.

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

`Uttrflow Dev` in the menu bar's application menu and in the App Switcher, and
`Uttrflow-Dev.app` on disk. The icon is the same one: the identity is what differs, not
the artwork.
