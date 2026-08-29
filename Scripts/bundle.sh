#!/usr/bin/env bash
#
# Packages the Uttrflow executable as a signed, self-contained, runnable Uttrflow.app
# in dist/.
#
# SwiftPM builds a bare Mach-O executable. Almost everything the product needs from
# macOS — the microphone, the menu bar, Accessibility, and being remembered by TCC
# between launches — is granted to a *bundle*, not to a binary, so the bundle is not
# packaging polish. It is the thing under test.
#
# Why the build is xcodebuild and not `swift build`
#
# Two of the dependencies the app links carry resources of their own —
# swift-transformers' Hub and swift-crypto's Crypto — and the build system generates
# a `Bundle.module` accessor for each of them. The accessor `swift build` generates
# knows exactly two places to look:
#
#     <Bundle.main.bundleURL>/swift-transformers_Hub.bundle
#     /Users/<whoever-built-this>/.../.build/.../swift-transformers_Hub.bundle
#
# Neither is usable in a shipped app. Inside a .app, Bundle.main.bundleURL *is* the
# .app, so the first candidate puts the resource bundle beside Contents — and a
# bundle root may hold nothing but Contents, so codesign refuses to seal it ("unsealed
# contents present in the bundle root"). That is a straight either/or: install the
# bundles and the app cannot be signed, sign the app and the bundles cannot be
# installed. The second candidate is an absolute path into the build tree of the
# machine that produced the binary, so on anyone else's Mac it misses too and the
# accessor reaches its `fatalError`. Not at launch — the accessor is only touched when
# a tokeniser is loaded, which is the first time somebody dictates.
#
# Xcode generates a different accessor for the very same package. It tries
# `Bundle.main.resourceURL` first — Contents/Resources, an ordinary, sealable place
# for a bundle to live — and in release it bakes no absolute path at all (its only
# override is an environment variable, behind `#if DEBUG`). So the resource bundles go
# inside Contents/Resources *before* signing, the whole app seals, and it seals with
# everything it needs already in it.
#
# Why the signature is done the way it is
#
# The signature is ad-hoc (`--sign -`): no certificate, no keychain, no password, so
# this runs unattended and on a fresh clone. The catch is that an ad-hoc signature's
# *designated requirement* defaults to the code directory hash:
#
#     designated => cdhash H"d8b105741a15308f1035fbfec733cd4b676daa7f"
#
# That hash changes on every single build. TCC stores the designated requirement
# alongside a grant, so with the default requirement every rebuild is a different app
# as far as macOS is concerned, and the microphone permission the user granted a
# minute ago is gone. That is the whole reason first-run behaviour is so tedious to
# test by hand.
#
# Pinning the requirement to the bundle identifier instead fixes it. Verified here
# across three rebuilds with three different cdhashes: one stable requirement, and
# the grant survives.
#
# Hardened runtime: OFF locally, ON for distribution. That was measured, not assumed —
# see the note above the codesign call and Docs/packaging.md.
set -euo pipefail

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
#   local        (default) ad-hoc, no hardened runtime. Runs here, keeps TCC grants.
#   rehearsal    hardened runtime, still ad-hoc. Exercises the runtime with no
#                certificate, because the expensive half of "does the hardened runtime
#                break anything" needs no Developer ID to answer.
#   distribution Developer ID + hardened runtime + secure timestamp. Notarisable.
MODE="${1:-local}"
case "$MODE" in
    local | rehearsal | distribution) ;;
    *) echo "error: unknown mode '$MODE'. Expected local, rehearsal or distribution." >&2
       exit 1 ;;
esac

HARDENED=no
REAL_CERTIFICATE=no
[[ "$MODE" == "rehearsal" ]] && HARDENED=yes
[[ "$MODE" == "distribution" ]] && { HARDENED=yes; REAL_CERTIFICATE=yes; }

# A parameter rather than a constant: whoever ships this is not whoever wrote it.
SIGNING_IDENTITY="${2:-${UTTRFLOW_SIGNING_IDENTITY:-}}"
if [[ "$REAL_CERTIFICATE" == "yes" && -z "$SIGNING_IDENTITY" ]]; then
    {
        printf 'error: distribution mode needs a Developer ID Application identity.\n'
        printf '  pass it:  ./Scripts/bundle.sh distribution "Developer ID Application: NAME (TEAMID)"\n'
        printf '  or set:   export UTTRFLOW_SIGNING_IDENTITY="Developer ID Application: NAME (TEAMID)"\n'
        printf '  list yours: security find-identity -v -p codesigning\n'
    } >&2
    exit 1
fi

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

PRODUCT="Uttrflow"
SCHEME="Uttrflow"
# Xcode's spelling, not SwiftPM's: capitalised, and it names the products directory.
CONFIGURATION="Release"
DERIVED_DATA="$PACKAGE_ROOT/.build/xcode"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
SOURCE_PLIST="Resources/Uttrflow-Info.plist"
ENTITLEMENTS="Resources/Uttrflow.entitlements"
ICON="Design/uttrflow.icns"
APP="dist/$PRODUCT.app"

fail() {
    echo "error: $*" >&2
    exit 1
}

# Reads one key out of a plist, failing if it is absent. Everything the bundle needs
# to know about itself comes from Resources/Uttrflow-Info.plist through this, so the
# identifier and the executable name are stated once and never repeated here.
plist_value() {
    plutil -extract "$1" raw -o - "$2" 2>/dev/null
}

for required in "$SOURCE_PLIST" "$ENTITLEMENTS" "$ICON"; do
    [[ -f "$required" ]] || fail "missing $required"
done

BUNDLE_ID="$(plist_value CFBundleIdentifier "$SOURCE_PLIST")" \
    || fail "$SOURCE_PLIST has no CFBundleIdentifier"
EXECUTABLE="$(plist_value CFBundleExecutable "$SOURCE_PLIST")" \
    || fail "$SOURCE_PLIST has no CFBundleExecutable"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
# The script builds rather than the Makefile, so that `./Scripts/bundle.sh` on its own
# produces the same bundle `make app` does. Scripts/coverage.sh runs its own `swift
# test` for the same reason.
#
# The Makefile exports DEVELOPER_DIR; run standalone, the script has to pick one
# itself. An existing choice is left alone so a second toolchain can be pointed at.

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
command -v xcodebuild >/dev/null 2>&1 \
    || fail "xcodebuild is not on PATH — the full Xcode is required, the Command Line Tools alone will not do"

# -scheme Uttrflow builds the app target's own dependency graph and nothing else, so
# MLX — which is reachable only from uttrflow-bakeoff — is never compiled and the Metal
# Toolchain is not needed here. (`make bakeoff` is the target that does need it.)
# Package *resolution* still fetches every dependency the manifest names, MLX
# included, so the first run on a fresh clone spends a while in the network.
echo "Building $SCHEME ($CONFIGURATION) with xcodebuild — a few minutes from cold."

# ENABLE_CODE_COVERAGE=NO, because a Release build of this package is instrumented
# unless it is told not to be. Nothing in Package.swift asks for coverage; the scheme
# xcodebuild generates for a package brings it, and it does not confine itself to the test
# action. A shipped build came out with 6,869 profiling counters, nine `__llvm_prf` and
# `__llvm_cov` sections, the profile runtime linked and `default.profraw` baked in — so
# every property getter incremented a counter and the app tried to write a profile when it
# quit. Turning it off takes the binary from 21.2 MB to 15.5 MB: more than a quarter of
# what a user downloads, spent on measurement nobody was collecting.
#
# This one setting is enough, and it is the only one here for that reason.
# `SWIFT_ENABLE_CODE_COVERAGE=NO` alone changes nothing — measured, 21.2 MB and 6,885
# counters — so a build that also passed it would be teaching the next reader something
# untrue. Step 11 below proves this is still working, since a setting that quietly stops
# applying looks exactly like one that was never needed.
xcodebuild \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DERIVED_DATA" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    ENABLE_CODE_COVERAGE=NO \
    -quiet \
    build \
    || fail "xcodebuild failed — rerun without -quiet in this script to see the whole log"

BUILT_BINARY="$PRODUCTS_DIR/$PRODUCT"
[[ -f "$BUILT_BINARY" ]] || fail "$(
    printf 'no executable at %s\n' "$BUILT_BINARY"
    printf '  xcodebuild reported success, so the products directory is not where this\n'
    printf '  script expects it. What is actually under Build/Products:\n'
    find "$DERIVED_DATA/Build/Products" -maxdepth 1 -mindepth 1 2>/dev/null \
        | sed 's/^/    /' || printf '    (nothing)\n'
)"

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------
# Built from scratch every time. Signing seals the bundle's contents, so a file left
# behind by a previous layout is not inert — it invalidates the signature.

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The name in MacOS/ is what CFBundleExecutable has to match, so take it from there.
cp "$BUILT_BINARY" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$SOURCE_PLIST" "$APP/Contents/Info.plist"

# The commit this bundle was built from, stamped into the bundle itself.
#
# publish.sh used to tag the release with whatever the checkout's HEAD happened to be
# when somebody ran it — which is not necessarily what is inside the image. A release
# named for one commit and built from another is a release nobody can reason about
# afterwards, and that is exactly what happened with v0.1.0-test.8c29f54: the tag was
# right, and it was published an hour after the commit that would have made the build
# work. Reading it back out of the image is the only way for the tag to be a fact about
# the artifact rather than about the terminal it was published from.
BUILD_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
if ! git diff --quiet HEAD 2>/dev/null; then
    BUILD_COMMIT="$BUILD_COMMIT-dirty"
fi
/usr/libexec/PlistBuddy -c "Add :UttrflowBuildCommit string $BUILD_COMMIT" \
    "$APP/Contents/Info.plist" >/dev/null
cp "$ICON" "$APP/Contents/Resources/$(basename "$ICON")"

# Eight bytes the Finder still reads before it parses the Info.plist: an application
# with no creator code.
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Every resource bundle the build produced, discovered rather than listed. A new
# dependency that carries resources gets one of these, and if it is not copied the
# app dies at the accessor's fatalError the first time that dependency is used — so
# naming them here would be a list that is wrong exactly when it matters.
RESOURCE_BUNDLES=()
while IFS= read -r bundle; do
    RESOURCE_BUNDLES+=("$bundle")
done < <(find "$PRODUCTS_DIR" -maxdepth 1 -mindepth 1 -type d -name '*.bundle' | LC_ALL=C sort)

for bundle in ${RESOURCE_BUNDLES[@]+"${RESOURCE_BUNDLES[@]}"}; do
    # Into Contents/Resources, which is where the Xcode-generated accessor looks
    # first, and which — unlike the bundle root — codesign is willing to seal.
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# Every framework the binary links, discovered the same way and for the same reason.
#
# Sparkle is the first dependency that is a framework rather than a static library with
# a resource bundle, and it exposed a hole this script had all along: it copied what a
# `Bundle.module` accessor needs and nothing else, then reported success. The app it
# produced died at launch with a dyld error — after printing a summary saying the
# signature verified `--deep --strict`, which it did. Check 6 below is the other half.
#
# `ditto` rather than `cp -R`: a framework is a tree of symlinks (Versions/Current, and
# the flat names beside it), and `cp -R` resolves them into copies — which triples the
# size and, worse, breaks the seal, because the signature Sparkle shipped covers a
# symlink where the copy now holds a file.
FRAMEWORKS=()
while IFS= read -r framework; do
    FRAMEWORKS+=("$framework")
done < <(find "$PRODUCTS_DIR" -maxdepth 1 -mindepth 1 -type d -name '*.framework' | LC_ALL=C sort)

if (( ${#FRAMEWORKS[@]} > 0 )); then
    mkdir -p "$APP/Contents/Frameworks"
    for framework in "${FRAMEWORKS[@]}"; do
        ditto "$framework" "$APP/Contents/Frameworks/$(basename "$framework")"
    done

    # The linker wrote `@rpath/Sparkle.framework/...` into the binary but the only rpath
    # it left is the one SwiftPM needs for its own layout. Added here, to the copy, and
    # before signing: `install_name_tool` rewrites the load commands, which invalidates
    # any signature already on it.
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null \
        || fail "could not point the binary at Contents/Frameworks"
fi

# ---------------------------------------------------------------------------
# Sign
# ---------------------------------------------------------------------------
# --options runtime is intentionally absent.
#
# The hardened runtime buys us nothing here and costs us the one failure we can least
# afford. It is a prerequisite for notarisation, which an ad-hoc signature can never
# pass anyway; what it changes today is that it makes the audio-input entitlement
# load-bearing, and a mismatch there denies the microphone *silently* — no prompt, no
# error, nothing to distinguish it from the user choosing Deny. Without the hardened
# runtime, microphone access is gated by TCC and the Info.plist usage string alone,
# which fail loudly and visibly when they are wrong.
#
# So: least likely to silently deny the microphone wins. The entitlement is still
# embedded (harmless when unenforced) so that adding --options runtime later, with a
# real certificate, is a one-word change that cannot regress the microphone.
#
# --deep is absent too, and deliberately so. The resource bundles now in
# Contents/Resources are real bundles with their own Contents/Info.plist, so it is a
# fair question whether they need signatures of their own. They do not: none declares
# a CFBundleExecutable, so codesign classifies them as resources rather than as nested
# code, seals every file inside them into Contents/_CodeSignature/CodeResources, and
# --deep changes nothing. Checked by signing both ways — the resulting app verifies
# identically, and editing a byte inside either bundle fails --verify --deep --strict
# in both. Leaving --deep out keeps the signing call the one thing it should be.

# What the hardened runtime actually does, measured on macOS 26.5.1 rather than feared:
#
# On a Mac that has ALREADY granted this identifier the microphone, the hardened runtime
# changes nothing, with or without the audio-input entitlement. That is exactly why this
# is dangerous to reason about — it is unreproducible on the machine that built the app.
#
# On a Mac seeing Uttrflow for the first time, a hardened build WITHOUT the entitlement
# does not prompt and does not error: requestAccess returns false immediately, the engine
# starts, buffers arrive, and every sample is exactly 0.0. macOS writes no TCC record at
# all. From the user's chair that is indistinguishable from having pressed Deny.
#
# With the entitlement present, the hardened runtime changes nothing there either: the
# prompt appears, the grant is recorded, real audio arrives.
#
# So the risk is entirely conditional on the entitlement being absent — and check 5 below
# refuses to ship a bundle that has lost it. The old position was to leave the runtime off
# for ever, which paid a permanent cost (an app nobody can be given, since notarisation
# requires it) to avoid a failure one check prevents.
# Rehearsal is ad-hoc *and* hardened, and that pair cannot load an embedded framework:
# library validation requires the app and the code it loads to share a Team ID, and an
# ad-hoc signature has none. The app dies at launch with "different Team IDs".
#
# So rehearsal — and only rehearsal — signs with library validation turned off, using a
# copy of the entitlements rather than the file itself, so the exception cannot leak into
# a build anybody receives. A distribution build needs nothing: the app and every nested
# piece of Sparkle carry the same Developer ID, and the check passes on its merits.
if [[ "$MODE" == "rehearsal" && -d "$APP/Contents/Frameworks" ]]; then
    REHEARSAL_ENTITLEMENTS="$(mktemp -t uttrflow-rehearsal-entitlements)"
    # A copy of the real file with one key added, so the rehearsal still carries every
    # entitlement the shipping build does — the microphone above all, which is the thing
    # this mode exists to rehearse.
    cp "$ENTITLEMENTS" "$REHEARSAL_ENTITLEMENTS"
    # Two things about this one line, both found the hard way. `-insert`, not
    # `-replace`: replace only rewrites a key that is already present, and this one
    # deliberately is not. And the dots are escaped, because plutil reads a key path
    # where `.` means nesting — unescaped it goes looking for a key "com" holding a key
    # "apple", finds neither, and says "Key path not found" about a key that is simply
    # not spelled the way it was asked for.
    plutil -insert 'com\.apple\.security\.cs\.disable-library-validation' -bool true \
        "$REHEARSAL_ENTITLEMENTS" >/dev/null \
        || fail "could not derive the rehearsal entitlements"
    ENTITLEMENTS="$REHEARSAL_ENTITLEMENTS"
    printf 'Rehearsal: library validation disabled, because an ad-hoc signature has no\n'
    printf '  Team ID for the embedded framework to match. A distribution build does not\n'
    printf '  do this and does not need to — check 7 refuses one that carries it.\n\n'
fi

COMMON_ARGS=(--force --identifier "$BUNDLE_ID" --entitlements "$ENTITLEMENTS")

if [[ "$REAL_CERTIFICATE" == "yes" ]]; then
    # No --requirements here on purpose. Developer ID's default designated requirement
    # already pins identifier AND team, so TCC grants survive a rebuild for free; a
    # hand-written bare `identifier "..."` would replace that with something weaker.
    #
    # --timestamp (not =none) contacts Apple's timestamp authority, so this step needs
    # the network. Notarisation rejects a signature without a secure timestamp.
    COMMON_ARGS+=(--sign "$SIGNING_IDENTITY" --timestamp)
    SIGNATURE_SUMMARY="Developer ID, hardened runtime, secure timestamp, verifies --deep --strict"
else
    REQUIREMENT="designated => identifier \"$BUNDLE_ID\""
    COMMON_ARGS+=(--sign - --requirements "=$REQUIREMENT" --timestamp=none)
    SIGNATURE_SUMMARY="ad-hoc, no hardened runtime, verifies --deep --strict"
fi

[[ "$HARDENED" == "yes" ]] && COMMON_ARGS+=(--options runtime)
[[ "$MODE" == "rehearsal" ]] && SIGNATURE_SUMMARY="ad-hoc, hardened runtime, verifies --deep --strict — NOT distributable"

# Nested code first, and from the inside out. A signature seals what is beneath it, so
# signing the app before the framework inside it seals a signature that is about to be
# replaced — and `codesign --verify --deep` then fails on the app, not on the thing that
# actually changed.
#
# Sparkle arrives already signed, by the Sparkle project. That is enough for an ad-hoc
# build and is not enough for a distributed one: notarisation requires every piece of
# nested code to carry the *same* Developer ID as the app around it. Re-signing here
# costs nothing on an ad-hoc build and is the difference between a notarisable app and a
# rejection on the day the certificate exists.
#
# Without `--entitlements`: our entitlements say this program records audio. Sparkle's
# helpers do not, and an entitlement granted to code that has no use for it is exactly
# the kind of thing the hardened runtime exists to stop.
NESTED_ARGS=(--force)
[[ "$REAL_CERTIFICATE" == "yes" ]] \
    && NESTED_ARGS+=(--sign "$SIGNING_IDENTITY" --timestamp) \
    || NESTED_ARGS+=(--sign - --timestamp=none)
[[ "$HARDENED" == "yes" ]] && NESTED_ARGS+=(--options runtime)

for framework in "$APP/Contents/Frameworks/"*.framework; do
    [[ -d "$framework" ]] || continue
    VERSIONED="$framework/Versions/Current"
    [[ -d "$VERSIONED" ]] || VERSIONED="$framework"

    # Deepest first: the XPC services, then the helper app, then the loose executables
    # beside them, then the versioned directory that contains the lot.
    while IFS= read -r nested; do
        [[ -n "$nested" ]] || continue
        codesign "${NESTED_ARGS[@]}" "$nested" \
            || fail "could not sign $nested"
    done < <(
        find "$VERSIONED/XPCServices" -maxdepth 1 -mindepth 1 -name '*.xpc' 2>/dev/null
        find "$VERSIONED" -maxdepth 1 -mindepth 1 -name '*.app' 2>/dev/null
        find "$VERSIONED" -maxdepth 1 -mindepth 1 -type f -perm -u+x 2>/dev/null
    )

    codesign "${NESTED_ARGS[@]}" "$VERSIONED" || fail "could not sign $framework"
done

codesign "${COMMON_ARGS[@]}" "$APP"

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
# Nothing below is a formality. Each check catches a failure that is otherwise found
# at runtime, by a person, holding a microphone key that does nothing.

# 1. Every Info.plist key the app cannot start, or cannot record, without. Checked on
#    the assembled bundle rather than the source file, because it is the copy that runs.
for key in CFBundleIdentifier CFBundleExecutable CFBundleName CFBundlePackageType \
    CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion LSUIElement \
    NSMicrophoneUsageDescription; do
    plist_value "$key" "$APP/Contents/Info.plist" >/dev/null \
        || fail "Info.plist in the bundle is missing $key"
done

# 1b. The pair that decides whether this build talks to the real service at all.
#
#     `OnboardingAccountLayer.forThisBuild()` needs BOTH an address in the Info.plist and
#     a release public key compiled in. With either missing it silently wires up the
#     development stub, whose sign-in opens a host in the .invalid domain and whose
#     entitlement key is minted per process — so the cached profile is rejected on the
#     next launch and dictation is refused until somebody signs in again, for ever.
#
#     That build shipped. v0.1.0-test.8c29f54 was cut 57 minutes before the commit that
#     added the plist key, and it was the download on the website until somebody mounted
#     the disk image and looked. Nothing in this script objected, which is why this exists.
#
#     Only for a build meant to leave this Mac: a development build with neither value is
#     exactly what a developer wants, and is the reason the fallback exists at all.
if [[ "$HARDENED" == "yes" ]]; then
    plist_value UttrflowBackendURL "$APP/Contents/Info.plist" >/dev/null \
        || fail "Info.plist has no UttrflowBackendURL, so this build would sign in against nothing"

    RELEASE_KEY="$(grep -o 'releasePublicKeyBase64 = "[^"]*"' \
        "Sources/UttrflowAccount/EntitlementSignature.swift" 2>/dev/null \
        | sed 's/.*"\(.*\)"/\1/')"
    if [[ -z "$RELEASE_KEY" ]]; then
        fail "could not read releasePublicKeyBase64 to check the binary against it"
    fi
    # `grep -a` on the binary rather than piping `strings`: one process fewer, and no
    # dependency on a tool whose absence would look exactly like a missing key.
    grep -aqF "$RELEASE_KEY" "$APP/Contents/MacOS/$EXECUTABLE" \
        || fail "the binary does not carry the release entitlement key, so it would reject every entitlement"
fi

# 2. CFBundleExecutable against the file that is actually there. A mismatch is a
#    bundle that will not launch at all.
[[ -x "$APP/Contents/MacOS/$EXECUTABLE" ]] \
    || fail "CFBundleExecutable is '$EXECUTABLE' but Contents/MacOS/$EXECUTABLE is not there"

# 3. Nothing but Contents in the bundle root. This is the old failure, kept as a check
#    so it cannot come back quietly: anything else here — a resource bundle above all —
#    is what macOS calls unsealed content, and it makes step 5 fail.
STRAY_ROOT_ENTRIES="$(find "$APP" -maxdepth 1 -mindepth 1 ! -name Contents)"
[[ -z "$STRAY_ROOT_ENTRIES" ]] || fail "$(
    printf 'the bundle root holds more than Contents:\n'
    printf '%s\n' "$STRAY_ROOT_ENTRIES" | sed 's/^/    /'
    printf '  macOS will not seal a bundle root with anything beside Contents in it.'
)"

# 4. Every resource bundle the shipped binary asks for is in Contents/Resources.
#    This is the check that makes the app genuinely self-contained, and the reason it
#    reads the *binary* rather than counting what got copied: the accessor's bundle
#    name is a string literal compiled into the executable, so this asks the same
#    question the accessor will ask at runtime, and an app that ships no bundles at
#    all cannot pass it by having nothing to check.
#    The `|| true` is load-bearing under `set -o pipefail`: grep exits 1 when it
#    matches nothing, and "this binary needs no resource bundles" is a legitimate
#    answer, not a build failure.
REQUIRED_BUNDLES="$(
    strings -a "$APP/Contents/MacOS/$EXECUTABLE" \
        | { grep -oE '[A-Za-z0-9_+.-]+\.bundle' || true; } \
        | LC_ALL=C sort -u
)"
while IFS= read -r required_bundle; do
    [[ -n "$required_bundle" ]] || continue
    [[ -d "$APP/Contents/Resources/$required_bundle" ]] || fail "$(
        printf 'the binary looks for %s and it is not in Contents/Resources.\n' "$required_bundle"
        printf '  Its Bundle.module accessor would reach fatalError the first time that\n'
        printf '  dependency is used — on the dictation path, not at launch, so nothing\n'
        printf '  short of dictating would have found it.\n'
        printf '  Built bundles were: %s' "${RESOURCE_BUNDLES[*]:-<none>}"
    )"
done <<< "$REQUIRED_BUNDLES"

# 4a. The updater is configured, or it is honestly absent.
#
#     A feed address with no key beside it is the dangerous half of this feature on its
#     own: Sparkle would have nothing to check a download against. The placeholder in
#     Resources/Uttrflow-Info.plist contains spaces and so cannot be mistaken for one,
#     and this refuses to ship it.
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist" 2>/dev/null || true)"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [[ -n "$FEED_URL" ]]; then
    # https, or http to this machine — the loopback address is what makes an update
    # rehearsable end to end on one Mac. See UpdateController.isAcceptable.
    case "$FEED_URL" in
        https://*) ;;
        http://127.0.0.1*|http://localhost*) LOCAL_FEED="yes" ;;
        *) fail "SUFeedURL is neither https nor a local address: $FEED_URL" ;;
    esac
    [[ -n "$PUBLIC_KEY" && "$PUBLIC_KEY" != *" "* ]] || fail "$(
        printf 'SUFeedURL is set and SUPublicEDKey is not a key.\n'
        printf '  An update feed with nothing to verify downloads against installs\n'
        printf '  whatever it is handed. Run generate_keys and paste the public half\n'
        printf '  into Resources/Uttrflow-Info.plist — see Docs/releasing.md ("Updating").'
    )"
fi

# 4b. Every framework the shipped binary links is in Contents/Frameworks, and the
#     binary has an rpath that reaches it.
#
#     This check exists because its absence shipped: adding Sparkle produced an app that
#     died at launch with `Library not loaded: @rpath/Sparkle.framework/...`, and this
#     script printed its whole success summary first — signature verified, `--deep
#     --strict` passed, resources sealed. All of that was true. The app just could not
#     start. Check 4 asks the binary what resource bundles it wants; this asks it what
#     libraries it wants, which is the same question about the other half of the bundle.
LINKED_FRAMEWORKS="$(
    otool -L "$APP/Contents/MacOS/$EXECUTABLE" \
        | { grep -oE '@rpath/[A-Za-z0-9_+.-]+\.framework' || true; } \
        | sed 's|@rpath/||' | LC_ALL=C sort -u
)"
while IFS= read -r linked; do
    [[ -n "$linked" ]] || continue
    [[ -d "$APP/Contents/Frameworks/$linked" ]] || fail "$(
        printf 'the binary links %s and it is not in Contents/Frameworks.\n' "$linked"
        printf '  The app dies at launch with a dyld error, before any of its own code\n'
        printf '  runs — so nothing in it can report the problem, and every check below\n'
        printf '  this one still passes.\n'
        printf '  Built frameworks were: %s' "${FRAMEWORKS[*]:-<none>}"
    )"
done <<< "$LINKED_FRAMEWORKS"

if [[ -n "$LINKED_FRAMEWORKS" ]]; then
    otool -l "$APP/Contents/MacOS/$EXECUTABLE" \
        | grep -q 'path @executable_path/../Frameworks' || fail "$(
        printf 'the binary links a framework but has no rpath reaching Contents/Frameworks.\n'
        printf '  dyld looks where the load commands say and nowhere else.'
    )"
fi

# 4c. A distribution build must not carry the rehearsal's library-validation exception.
#     It is added to a temporary copy of the entitlements and could only reach here
#     through a mistake — which is exactly the kind of mistake that is invisible until
#     somebody reads a signature months later.
if [[ "$REAL_CERTIFICATE" == "yes" ]]; then
    codesign -d --entitlements - --xml "$APP" 2>/dev/null \
        | plutil -convert xml1 -o - - 2>/dev/null \
        | grep -q "disable-library-validation" && fail "$(
        printf 'this distribution build has library validation disabled.\n'
        printf '  That exception belongs to rehearsal builds alone. A signed app that\n'
        printf '  carries it will load any library signed by anyone, in a process that\n'
        printf '  holds microphone and Accessibility access.'
    )"
fi

# 5. The signature itself: seals intact, binary untampered, nested code valid. With
#    the resource bundles now inside Contents/Resources this passes, which is the
#    whole point of building with xcodebuild — before, the app could be self-contained
#    or verifiable, never both.
# Read once and reused by the checks below, so they cannot disagree about what was
# actually signed.
SIGNING_INFO="$(codesign -d --verbose=4 "$APP" 2>&1)" \
    || fail "$APP has no signature to inspect"

codesign --verify --deep --strict "$APP" \
    || fail "the signature on $APP does not verify"

# 6. The designated requirement really is pinned to the identifier. This is the check
#    that matters most and the one step 5 cannot do for it: an unpinned, cdhash-based
#    signature verifies perfectly and still loses the microphone grant on next build.
ACTUAL_REQUIREMENT="$(
    codesign -d -r- "$APP" 2>/dev/null \
        | sed -n 's/^#* *designated =>/designated =>/p' \
        | head -1
)"
[[ "$ACTUAL_REQUIREMENT" == "$REQUIREMENT" ]] || fail "$(
    printf 'designated requirement is not pinned to the bundle identifier.\n'
    printf '  expected: %s\n' "$REQUIREMENT"
    printf '  actual:   %s\n' "${ACTUAL_REQUIREMENT:-<none>}"
    printf '  TCC would drop the microphone grant on the next build.'
)"

# 7. The audio-input entitlement made it into the signature. Inert today, because we
#    do not enable the hardened runtime — but the day someone does, its absence is a
#    silent microphone denial, so it is checked now while the failure is still cheap.
codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | grep -q 'com.apple.security.device.audio-input' \
    || fail "$(
        printf 'com.apple.security.device.audio-input is not in the embedded entitlements.\n'
        printf '  Under the hardened runtime this ships an app whose microphone returns\n'
        printf '  silence on any Mac that has not already granted it — with no prompt, no\n'
        printf '  error and no TCC record. Do not ship without it.'
    )"

# 8. Gates that only apply to a build meant to leave this Mac. A rehearsal build is
#    hardened but ad-hoc, so it must not be held to these.
if [[ "$REAL_CERTIFICATE" == "yes" ]]; then
    printf '%s\n' "$SIGNING_INFO" | grep -q '^Timestamp=' \
        || fail "no secure timestamp; notarisation requires one (was the network up?)"
    printf '%s\n' "$SIGNING_INFO" | grep -q 'Authority=Developer ID Application:' \
        || fail "$(
            printf 'not signed by a Developer ID Application certificate.\n'
            printf '  identity used: %s' "$SIGNING_IDENTITY"
        )"
fi

# 9. The hardened runtime is on when it was asked for, and off when it was not. A
#    distribution build that quietly lost it is one notarytool will reject; a local
#    build that quietly gained it is one whose failure mode nobody here would see.
if [[ "$HARDENED" == "yes" ]]; then
    printf '%s\n' "$SIGNING_INFO" | grep -q 'flags=.*runtime' \
        || fail "the hardened runtime was requested but is not in the signature"
else
    printf '%s\n' "$SIGNING_INFO" | grep -q 'flags=.*runtime' \
        && fail "the hardened runtime is on in a $MODE build, which did not ask for it"
fi

# 8. No path out of this machine's build tree survives in the shipped binary. A
#    `swift build` binary carries the builder's own .build directory as the fallback
#    resource-bundle location; it works on the machine that produced it and nowhere
#    else, which is the most expensive kind of bug to notice. Xcode's release accessor
#    bakes no such path, and this asserts that it stays that way.
#    As in step 4, `|| true` keeps a clean result — grep matching nothing — from
#    looking like a failed pipeline to `set -o pipefail`.
LEAKED_PATHS="$(
    strings -a "$APP/Contents/MacOS/$EXECUTABLE" \
        | { grep -F "$PACKAGE_ROOT" || true; } \
        | LC_ALL=C sort -u \
        | head -5
)"
[[ -z "$LEAKED_PATHS" ]] || fail "$(
    printf 'the shipped binary still names this machine'"'"'s build tree:\n'
    printf '%s\n' "$LEAKED_PATHS" | sed 's/^/    /'
    printf '  A path only this Mac has cannot be a fallback anywhere else.'
)"

# 10. Nothing about the evaluation corpus is in the shipped app.
#     The corpus is roughly a thousand recordings of real people, kept in a private
#     bucket behind an operator token. None of it may be inside an app a user installs —
#     not the audio, not the bucket, not the endpoints that hand out signed URLs, and not
#     the code that knows how to ask. `UttrflowEval` is a library product, so an `import`
#     in the wrong module is all it would take, and the harness is exactly what somebody
#     reaches for when a diagnostics pane needs a word error rate.
#     Read from the artefact rather than the sources: the test suite already asserts no
#     app module imports it, and this proves the assertion was about what ships.
EVAL_SYMBOLS="$(
    nm -a "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null \
        | xcrun swift demangle 2>/dev/null \
        | { grep -oE 'UttrflowEval\.[A-Za-z_]+' || true; } \
        | LC_ALL=C sort -u | head -5
)"
[[ -z "$EVAL_SYMBOLS" ]] || fail "$(
    printf 'the evaluation harness is linked into the app:\n'
    printf '%s\n' "$EVAL_SYMBOLS" | sed 's/^/    /'
    printf '  UttrflowEval knows how to reach the corpus bucket. Nothing a user installs\n'
    printf '  may. Remove the dependency; measurement belongs in uttrflow-eval.'
)"

STRAY_AUDIO="$(find "$APP" \( -name '*.wav' -o -name '*.aiff' -o -name '*.aif' \
    -o -name '*.m4a' -o -name '*.flac' -o -name '*.caf' \) | head -5)"
[[ -z "$STRAY_AUDIO" ]] || fail "$(
    printf 'the bundle contains audio:\n'
    printf '%s\n' "$STRAY_AUDIO" | sed 's/^/    /'
    printf '  The only sound Uttrflow ships is its recording cue, which comes from the\n'
    printf '  system. Anything else here is corpus audio that has been swept in.'
)"

# 11. The shipped binary carries no coverage instrumentation.
#     A Release build of this package came out with 6,869 profiling counters in it, nine
#     `__llvm_prf`/`__llvm_cov` sections, the profile runtime linked, and `default.profraw`
#     baked into it — so every property getter incremented a counter and the app tried to
#     write a profile on exit. It cost 5.7 MB of a 21.2 MB binary, more than a quarter of
#     what a user downloads, and nothing in Package.swift asked for any of it.
#     The build now turns it off explicitly. This proves the flag is still doing its job,
#     because a setting that silently stops applying looks exactly like one that was never
#     needed.
PROFILING="$(
    otool -l "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null \
        | { grep -aoE '__llvm_(prf|cov)[a-z_]*' || true; } \
        | LC_ALL=C sort -u | head -5
)"
[[ -z "$PROFILING" ]] || fail "$(
    printf 'the shipped binary carries coverage instrumentation:\n'
    printf '%s\n' "$PROFILING" | sed 's/^/    /'
    printf '  Every getter increments a counter and the app writes a .profraw on exit.\n'
    printf '  The xcodebuild invocation above disables this; check that it still does.'
)"

CORPUS_STRINGS="$(
    strings -a "$APP/Contents/MacOS/$EXECUTABLE" \
        | { grep -aoE '/v1/corpus[A-Za-z0-9/_-]*|UTTRFLOW_OPERATOR_TOKEN|s3[.-][a-z0-9-]*\.amazonaws\.com' || true; } \
        | LC_ALL=C sort -u | head -5
)"
[[ -z "$CORPUS_STRINGS" ]] || fail "$(
    printf 'the shipped binary names the evaluation corpus:\n'
    printf '%s\n' "$CORPUS_STRINGS" | sed 's/^/    /'
    printf '  A bucket name or an operator endpoint in a shipped binary is a map to\n'
    printf '  private recordings, handed to everyone who downloads the app.'
)"

# ---------------------------------------------------------------------------

# Basenames only; the full paths are build-tree noise nobody reading this needs.
RESOURCE_SUMMARY="no resource bundles"
if (( ${#RESOURCE_BUNDLES[@]} > 0 )); then
    RESOURCE_SUMMARY="${RESOURCE_BUNDLES[*]##*/}"
fi

cat <<EOF

Built and signed $APP

  identifier   $BUNDLE_ID
  requirement  $REQUIREMENT
  signature    $SIGNATURE_SUMMARY
  resources    $RESOURCE_SUMMARY

Run it:

  open $APP

Uttrflow has no Dock tile — it is a menu-bar app — so look for the microphone in the
menu bar. macOS asks for the microphone the first time you dictate, and for
Accessibility in System Settings before it can type into another app. Both grants are
pinned to the identifier above and survive a rebuild.

The bundle is self-contained: every resource bundle its dependencies need is sealed
inside Contents/Resources, so it runs with .build deleted and on a Mac that never
built it. Gatekeeper will still refuse an ad-hoc bundle copied from another Mac;
built here, it runs.
EOF
