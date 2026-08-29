#!/usr/bin/env bash
#
# Notarises a distribution build of Uttrflow and staples the ticket to it.
#
#   ./Scripts/notarise.sh --check                    preflight only; needs no credentials
#   ./Scripts/notarise.sh                            preflight, submit, wait, staple, verify
#   ./Scripts/notarise.sh dist/Uttrflow.app           the same, on an explicit bundle
#   ./Scripts/notarise.sh dist/Uttrflow-0.1.0.dmg     the same, on the disk image that ships
#
# An app or a disk image, and which one is not a matter of taste. Apple staples the
# ticket to whatever was submitted, and Gatekeeper checks whatever the user opened.
# Somebody who downloads a .dmg and double-clicks it is having the *image* checked, so
# an image with no ticket of its own is refused before the app inside is looked at.
#
# So a release notarises twice, and Scripts/dmg.sh sits between the two runs:
#
#   make app-dist                      Developer ID, hardened
#   ./Scripts/notarise.sh              the app: ticket stapled into the bundle
#   ./Scripts/dmg.sh                   the image, built out of the stapled app
#   ./Scripts/notarise.sh dist/*.dmg   the image: ticket stapled into the image
#
# The order is what makes the app work offline after it has been dragged out of the
# image — it carries its own ticket rather than relying on the one stapled to a disk
# image the user has since ejected. `make release` runs all four.
#
# Notarisation is Apple looking at the binary and agreeing to vouch for it. Until that
# has happened and the resulting ticket is stapled into the bundle, Uttrflow.app will not
# open on a Mac that did not build it — Gatekeeper says the developer "cannot be
# verified", and the only visible way past it is a right-click-Open that most people
# will not find and should not be asked to perform.
#
# Everything before the submission is a preflight, and it is worth having, because
# notarytool's rejections arrive minutes later as a JSON log referencing an audit UUID.
# Each thing checked below is something Apple refuses, restated as the reason it exists:
#
#   hardened runtime      Apple will not notarise a build without it. This is the
#                         requirement that forced the whole question — see the note in
#                         Scripts/bundle.sh and Docs/packaging.md.
#   audio-input           NOT an Apple requirement. Ours. Under the hardened runtime a
#                         build missing it has no working microphone on any Mac that has
#                         not already granted this identifier, and fails silently. Apple
#                         will happily notarise that app. Nothing downstream catches it.
#   secure timestamp      A signature without one is rejected: Apple has to know the
#                         signing happened while the certificate was valid.
#   no get-task-allow     A debuggable build is rejected. Release builds do not carry it.
#   Developer ID          An "Apple Development" certificate is not accepted for
#                         distribution outside the App Store, though it signs perfectly.
#
# What this script cannot do for you is obtain the credentials. See Docs/packaging.md.
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    printf '\n== %s\n' "$*"
}

CHECK_ONLY=no
TARGET="dist/Uttrflow.app"
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=yes ;;
        -h | --help)
            sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*) fail "unknown option '$arg'" ;;
        *) TARGET="$arg" ;;
    esac
done

# The kind decides three things: what gets submitted, what gets stapled, and how
# Gatekeeper is asked about the result afterwards. Everything else below is shared,
# because the checks that matter are checks of the app either way — an image is a
# wrapper, and a wrapper cannot make a broken app acceptable.
case "$TARGET" in
    *.app) KIND=app ;;
    *.dmg) KIND=dmg ;;
    *) fail "$(
        printf 'do not know what to do with %s\n' "$TARGET"
        printf '  Expected a .app or a .dmg.'
    )" ;;
esac

# Whatever gets mounted has to get detached, on the failure paths too: a leftover
# mount makes the next run fail with a name collision, which is a confusing way to be
# told about a problem that happened an hour ago.
MOUNTED=""
cleanup() {
    [[ -n "$MOUNTED" ]] && hdiutil detach "$MOUNTED" -quiet -force >/dev/null 2>&1 || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

# Everything Apple would refuse, plus the one thing it would happily accept and should
# not: the missing microphone entitlement. Written as a function taking a path, because
# an image has to run every one of these against the app inside it. Skipping them for a
# .dmg would mean the container Apple actually vouches for is the one nothing checked.
check_app() {
    local app="$1"

    [[ -d "$app" ]] || fail "$(
        printf 'no bundle at %s\n' "$app"
        printf '  Build one first: ./Scripts/bundle.sh distribution "Developer ID Application: NAME (TEAMID)"'
    )"

    # codesign reports through stderr and signals failure through its exit code; a pipe
    # would discard the code and leave us grepping an empty string. Capture, check, then read.
    local signing_info entitlement_info
    if ! signing_info="$(codesign -d --verbose=4 "$app" 2>&1)"; then
        fail "$app is not signed at all"
    fi
    if ! entitlement_info="$(codesign -d --entitlements - --xml "$app" 2>&1)"; then
        fail "could not read the entitlements embedded in $app"
    fi

    codesign --verify --deep --strict "$app" \
        || fail "the signature on $app does not verify; notarisation would reject it outright"

# Checked before anything else it would cause, because an ad-hoc bundle fails several of
# the tests below and none of those failures name the actual problem. This is what
# `make app` and `make app-hardened` produce, and reaching here with one is the single
# most likely way to use this script wrongly.
#
# Written as an `if` and not `grep ... && fail`: under `set -e` that list returns
# non-zero when the grep finds nothing, which is the path where everything is fine.
    if printf '%s\n' "$signing_info" | grep -q 'flags=.*adhoc'; then
        fail "$(
            printf '%s is signed ad-hoc, and an ad-hoc signature can never be notarised.\n' "$app"
            printf '  `make app` and `make app-hardened` both produce ad-hoc bundles: the first\n'
            printf '  for daily use, the second to rehearse the hardened runtime without a\n'
            printf '  certificate. Neither can be shipped. For a submittable build:\n'
            printf '    make app-dist IDENTITY="Developer ID Application: NAME (TEAMID)"'
        )"
    fi

    printf '%s\n' "$signing_info" | grep -q 'flags=.*runtime' || fail "$(
        printf '%s is not signed with the hardened runtime.\n' "$app"
        printf '  Notarisation requires it. Rebuild with:\n'
        printf '    ./Scripts/bundle.sh distribution "Developer ID Application: NAME (TEAMID)"'
    )"

    printf '%s\n' "$entitlement_info" | grep -q 'com.apple.security.device.audio-input' || fail "$(
        printf 'com.apple.security.device.audio-input is missing from %s.\n' "$app"
        printf '  Apple would notarise this build. It would also have no microphone on any\n'
        printf '  Mac that has not already granted this identifier: no prompt, no error, and\n'
        printf '  every captured sample exactly zero. Refusing to ship it.'
    )"

    printf '%s\n' "$signing_info" | grep -q '^Timestamp=' \
        || fail "$app carries no secure timestamp; notarisation rejects that. Re-sign with the network up."

    if printf '%s\n' "$entitlement_info" | grep -q 'com.apple.security.get-task-allow'; then
        fail "com.apple.security.get-task-allow is embedded in $app; notarisation rejects debuggable builds"
    fi

    printf '%s\n' "$signing_info" | grep -q 'Authority=Developer ID Application:' || fail "$(
        printf '%s is not signed by a Developer ID Application certificate.\n' "$app"
        printf '  Authorities present:\n'
        printf '%s\n' "$signing_info" | sed -n 's/^Authority=/    /p'
        printf '  Only Developer ID Application can be notarised for distribution.'
    )"

    TEAM_FROM_SIGNATURE="$(printf '%s\n' "$signing_info" | sed -n 's/^TeamIdentifier=//p' | head -1)"
}

# The image's own signature. Thinner than the app's on purpose: an image carries no
# entitlements and no hardened runtime, so there is nothing there to check beyond who
# signed it and when. The substance is inside, and check_app is what looks at it.
check_image() {
    local image="$1"
    local signing_info

    [[ -f "$image" ]] || fail "$(
        printf 'no disk image at %s\n' "$image"
        printf '  Build one first: ./Scripts/dmg.sh'
    )"

    signing_info="$(codesign -d --verbose=4 "$image" 2>&1)" || fail "$(
        printf '%s is not signed.\n' "$image"
        printf '  Scripts/dmg.sh signs the image when the app inside it is Developer ID\n'
        printf '  signed, and leaves it unsigned when the app is ad-hoc — so an unsigned\n'
        printf '  image here means the app that went into it was never distributable.'
    )"

    codesign --verify --strict "$image" || fail "the signature on $image does not verify"

    printf '%s\n' "$signing_info" | grep -q 'Authority=Developer ID Application:' \
        || fail "$image is not signed by a Developer ID Application certificate"
    printf '%s\n' "$signing_info" | grep -q '^Timestamp=' \
        || fail "$image carries no secure timestamp; notarisation rejects that"
}

step "Preflight on $TARGET"

if [[ "$KIND" == "app" ]]; then
    check_app "$TARGET"
else
    check_image "$TARGET"

    # Mounted read-only and off the sidebar, so preflighting a release does not make
    # windows appear on somebody's screen mid-run.
    MOUNT_OUTPUT="$(hdiutil attach "$TARGET" -readonly -noverify -nobrowse -mountrandom /tmp)" \
        || fail "$TARGET will not mount"
    MOUNTED="$(printf '%s\n' "$MOUNT_OUTPUT" | grep -o '/tmp/[^[:space:]]*' | head -1)"
    [[ -n "$MOUNTED" ]] || fail "$TARGET mounted but hdiutil did not say where"

    INSIDE="$(find "$MOUNTED" -maxdepth 1 -name '*.app' | head -1)"
    [[ -n "$INSIDE" ]] || fail "there is no application inside $TARGET"

    check_app "$INSIDE"

    # Stapled before the image was built, which is the order that makes the app work
    # offline once it has been dragged out and the image ejected. A warning rather than
    # a failure: the image is about to get its own ticket either way, and refusing to
    # notarise an image over this would block the very release that fixes it.
    if ! xcrun stapler validate "$INSIDE" >/dev/null 2>&1; then
        printf '  note: the app inside carries no notarisation ticket of its own.\n'
        printf '        Dragged out of this image and run on a Mac that is offline, it will\n'
        printf '        be refused. Notarise the app first, then rebuild the image from it:\n'
        printf '          ./Scripts/notarise.sh dist/Uttrflow.app && ./Scripts/dmg.sh\n'
    fi

    hdiutil detach "$MOUNTED" -quiet || fail "could not detach $TARGET"
    MOUNTED=""
fi

echo "  signature   ok (hardened runtime, secure timestamp, Developer ID)"
echo "  team        ${TEAM_FROM_SIGNATURE:-<none>}"
echo "  entitlement com.apple.security.device.audio-input present"

# `--type exec` asks whether something may be *run*, which is the question about an
# app. A disk image is opened rather than run, and is assessed against the primary
# signature instead; ask the wrong one and the answer is a rejection that has nothing to
# do with notarisation. Chosen once here so the --check summary and the real run cannot
# print different advice.
if [[ "$KIND" == "app" ]]; then
    ASSESS_ARGS="--type exec"
else
    ASSESS_ARGS="--type open --context context:primary-signature"
fi

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
ZIP="${TARGET%.app}.zip"

# An .app cannot be submitted as it stands — notarytool takes a single file — so it is
# packaged first. An image already is a single file, and repackaging one would only add
# a container Apple would staple the ticket to instead of the image itself.
if [[ "$KIND" == "app" ]]; then
    step "Packaging $ZIP"
    rm -f "$ZIP"
    # ditto, not zip. An .app is a directory of symlinks and extended attributes, and the
    # plain zip tool flattens enough of that to invalidate the signature it just packaged.
    # --keepParent keeps Uttrflow.app as the top-level entry, which notarytool expects.
    ditto -c -k --keepParent "$TARGET" "$ZIP" || fail "ditto could not package $TARGET"
    SUBMISSION="$ZIP"
    echo "  $ZIP ($(du -h "$ZIP" | cut -f1))"
else
    SUBMISSION="$TARGET"
    echo "  submitting $TARGET ($(du -h "$TARGET" | cut -f1)) as it stands"
fi

if [[ "$CHECK_ONLY" == "yes" ]]; then
    cat <<EOF

Preflight passed and $SUBMISSION is ready to submit.

Stopping here because --check was given. The remaining steps all need Apple
credentials:

  xcrun notarytool submit "$SUBMISSION" --keychain-profile uttrflow-notary --wait
  xcrun stapler staple "$TARGET"
  xcrun stapler validate "$TARGET"
  spctl --assess $ASSESS_ARGS --verbose=2 "$TARGET"

Docs/packaging.md explains how to create the keychain profile.
EOF
    exit 0
fi

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
# Two accepted shapes. The keychain profile is preferred and is what the docs describe:
# it is created once with `notarytool store-credentials` and keeps the app-specific
# password in the keychain rather than in a shell history or a CI log.

step "Credentials"
NOTARY_ARGS=()
PROFILE="${UTTRFLOW_NOTARY_PROFILE:-uttrflow-notary}"

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    NOTARY_ARGS=(--keychain-profile "$PROFILE")
    echo "  using keychain profile '$PROFILE'"
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    # Accepted for CI, where a keychain may not be unlocked. The password must be an
    # app-specific password from appleid.apple.com, never the Apple ID password itself.
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
    echo "  using APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD from the environment"
else
    fail "$(
        printf 'no notarisation credentials.\n'
        printf '  Create the keychain profile once:\n'
        printf '    xcrun notarytool store-credentials %s \\\n' "$PROFILE"
        printf '      --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PASSWORD\n'
        printf '  or set APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD.\n'
        printf '  The password is an app-specific password from appleid.apple.com, not\n'
        printf '  your Apple ID password. Run with --check to preflight without any of this.'
    )"
fi

# ---------------------------------------------------------------------------
# Submit
# ---------------------------------------------------------------------------
# --wait blocks until Apple has an answer, usually a couple of minutes. Without it the
# script would "succeed" while the submission was still pending, and the staple below
# would fail for a reason that has nothing to do with the app.

step "Submitting to Apple"
SUBMIT_LOG="$(mktemp -t uttrflow-notary)"
set +e
xcrun notarytool submit "$SUBMISSION" "${NOTARY_ARGS[@]}" --wait 2>&1 | tee "$SUBMIT_LOG"
SUBMIT_STATUS="${PIPESTATUS[0]}"
set -e

# A submission can be *accepted by notarytool* and *rejected by Apple*, so the exit code
# alone is not the answer; the status line is.
SUBMISSION_ID="$(sed -n 's/^ *id: *//p' "$SUBMIT_LOG" | head -1)"
if (( SUBMIT_STATUS != 0 )) || ! grep -q 'status: Accepted' "$SUBMIT_LOG"; then
    if [[ -n "$SUBMISSION_ID" ]]; then
        # The one genuinely useful artefact of a rejection, and the step everybody
        # forgets: the summary says "Invalid", the log says which binary and why.
        step "Apple rejected it. Fetching the reasons for submission $SUBMISSION_ID"
        xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_ARGS[@]}" || true
    fi
    rm -f "$SUBMIT_LOG"
    fail "notarisation did not succeed; see the log above"
fi
rm -f "$SUBMIT_LOG"

# ---------------------------------------------------------------------------
# Staple
# ---------------------------------------------------------------------------
# Apple's approval currently lives only on Apple's servers. Stapling writes the ticket
# into the bundle so the app also opens on a Mac that is offline the first time it runs.

step "Stapling the ticket"
xcrun stapler staple "$TARGET" || fail "could not staple the ticket to $TARGET"
xcrun stapler validate "$TARGET" || fail "the stapled ticket on $TARGET does not validate"

# ---------------------------------------------------------------------------
# Verify, then repackage
# ---------------------------------------------------------------------------
# The zip made before submission does not contain the ticket, because the ticket did not
# exist yet. Shipping that one is the classic way to do all of this correctly and still
# hand people an app Gatekeeper blocks. Repackage from the stapled bundle.

step "Verifying as Gatekeeper will see it"
# The assessment type is not interchangeable. `--type exec` asks "may this be run",
# which is the question about an app; a disk image is not run, it is opened, and asking
# the wrong question of it returns a rejection that has nothing to do with the ticket.
spctl --assess $ASSESS_ARGS --verbose=2 "$TARGET" \
    || fail "Gatekeeper still rejects $TARGET after stapling"

if [[ "$KIND" == "app" ]]; then
    codesign --verify --deep --strict --test-requirement="=notarized" --verbose=2 "$TARGET" \
        || fail "$TARGET does not satisfy the 'notarized' requirement"

    # The zip made before submission does not contain the ticket, because the ticket did
    # not exist yet. Shipping that one is the classic way to do all of this correctly and
    # still hand people an app Gatekeeper blocks. Repackage from the stapled bundle.
    step "Repackaging with the ticket"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$TARGET" "$ZIP" || fail "ditto could not repackage $TARGET"

    cat <<EOF

Notarised, stapled and verified.

  bundle  $TARGET
  ship    $ZIP  ($(du -h "$ZIP" | cut -f1))

The bundle now carries its own ticket, so it opens offline wherever it ends up. Build
the disk image people will actually download out of *this* bundle, and notarise that too:

  ./Scripts/dmg.sh && ./Scripts/notarise.sh dist/Uttrflow-*.dmg

If you send the zip instead, send the zip and not the bundle: copying an .app through
anything that does not preserve extended attributes breaks the signature.
EOF
else
    cat <<EOF

Notarised, stapled and verified.

  ship  $TARGET  ($(du -h "$TARGET" | cut -f1))

This is the file to publish. It opens on any Mac running macOS 26 or later with a
double-click, offline, with no right-click-Open and no warning — and so does the app
inside it, once dragged to Applications.
EOF
fi
