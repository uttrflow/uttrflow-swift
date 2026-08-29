#!/usr/bin/env bash
#
# Wraps dist/Uttrflow.app in the disk image people actually download.
#
#   ./Scripts/dmg.sh                    wrap whatever is in dist/
#   ./Scripts/dmg.sh dist/Uttrflow.app   the same, on an explicit bundle
#
# A .dmg is not packaging ceremony. It is the only container that survives the trip
# through a web browser intact: an .app is a directory of symlinks and extended
# attributes, and every archiver that is not `ditto` flattens enough of that to break
# the signature. A disk image is one file, mounted rather than unpacked, so the bytes
# that arrive are the bytes that were signed. It also gives the drag-to-Applications
# window that tells somebody where the app is supposed to go — which matters here more
# than usual, because Uttrflow has no Dock tile and an app left in ~/Downloads is one
# somebody will lose.
#
# What this needs from Apple: nothing. `hdiutil` ships with macOS and asks no
# permission. A certificate changes what the image is *for*, not whether it can be
# built — see "Two kinds of image" below.
#
# ---------------------------------------------------------------------------
# Two kinds of image, decided by the app rather than by an argument
# ---------------------------------------------------------------------------
# The mode is read out of the signature on the bundle instead of being passed in,
# because the two cannot be allowed to disagree. An ad-hoc app inside a Developer
# ID-signed image is the worst of both: it looks shippable, and Gatekeeper refuses the
# app the moment it is dragged out. So the image is whatever the app already is.
#
#   ad-hoc app        -> unsigned image. For testing on another Mac. Gatekeeper will
#                        refuse it if it arrives through a browser, and Scripts/dmg.sh
#                        prints the one command that gets past that.
#   Developer ID app  -> image signed with the *same* identity, read back out of the
#                        app's own signature so a typo cannot introduce a second one.
#                        Ready for Scripts/notarise.sh.
#
# ---------------------------------------------------------------------------
# Why the image is built twice
# ---------------------------------------------------------------------------
# A volume's custom icon is a Finder attribute on the volume root, and a volume root
# only exists once the image is mounted. So: create a read-write image, mount it, set
# the attribute, detach, and convert to the compressed read-only image that ships.
# Building UDZO directly would mean the icon is set on a folder and hoped to survive,
# which is the kind of thing that quietly stops working.
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

APP="${1:-dist/Uttrflow.app}"
ICON="Design/uttrflow.icns"
VOLUME_NAME="Uttrflow"

# Everything that gets mounted has to get detached, including on the failure paths —
# a leftover /Volumes/Uttrflow makes the *next* run fail with a name collision, which
# is a confusing way to be told about a problem that happened an hour ago.
MOUNTED=""
STAGE=""
cleanup() {
    [[ -n "$MOUNTED" ]] && hdiutil detach "$MOUNTED" -quiet -force >/dev/null 2>&1 || true
    [[ -n "$STAGE" ]] && rm -rf "$STAGE" || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

step "Preflight on $APP"

[[ -d "$APP" ]] || fail "$(
    printf 'no bundle at %s\n' "$APP"
    printf '  Build one first:\n'
    printf '    make app             ad-hoc, for this Mac\n'
    printf '    make app-hardened    ad-hoc + hardened runtime, for testing on another Mac\n'
    printf '    make app-dist        Developer ID, for release'
)"

# The image seals nothing. Whatever is wrong with the app on the way in is wrong with
# it on the way out, discovered by somebody else, so it is checked here.
codesign --verify --deep --strict "$APP" \
    || fail "the signature on $APP does not verify; a broken app in a disk image is still a broken app"

SIGNING_INFO="$(codesign -d --verbose=4 "$APP" 2>&1)" || fail "$APP is not signed at all"

HARDENED=no
printf '%s\n' "$SIGNING_INFO" | grep -q 'flags=.*runtime' && HARDENED=yes

if printf '%s\n' "$SIGNING_INFO" | grep -q 'flags=.*adhoc'; then
    DISTRIBUTABLE=no
    SIGNING_IDENTITY=""
else
    # Read the identity back out of the app rather than taking it as an argument. The
    # Authority lines run leaf-first, so the first Developer ID Application line is the
    # certificate that actually signed this bundle.
    SIGNING_IDENTITY="$(
        printf '%s\n' "$SIGNING_INFO" \
            | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' \
            | head -1
    )"
    [[ -n "$SIGNING_IDENTITY" ]] || fail "$(
        printf '%s is signed, but not ad-hoc and not by a Developer ID Application certificate.\n' "$APP"
        printf '  Authorities present:\n'
        printf '%s\n' "$SIGNING_INFO" | sed -n 's/^Authority=/    /p'
        printf '  An Apple Development certificate signs perfectly and cannot be distributed.'
    )"
    DISTRIBUTABLE=yes
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null)" \
    || fail "$APP/Contents/Info.plist has no CFBundleShortVersionString"

DMG="dist/Uttrflow-$VERSION.dmg"
READWRITE="dist/.Uttrflow-$VERSION-rw.dmg"

echo "  app        $APP ($VERSION)"
echo "  signature  ${SIGNING_IDENTITY:-ad-hoc}$([[ "$HARDENED" == "yes" ]] && echo ", hardened runtime")"
echo "  image      $DMG"

# ---------------------------------------------------------------------------
# Stage
# ---------------------------------------------------------------------------
# Exactly two things go in the window: the app, and a symlink to /Applications for it
# to be dragged onto. Anything else — a README, a licence, an uninstaller — is one more
# thing between somebody and a working app.

step "Staging"

STAGE="$(mktemp -d -t uttrflow-dmg)"

# ditto, not cp -R. cp does not carry extended attributes, and the signature is stored
# in some of them; an app copied with cp into an image is an app that fails to verify
# on the far side, with nothing to say why.
ditto "$APP" "$STAGE/$(basename "$APP")" || fail "could not stage $APP"

ln -s /Applications "$STAGE/Applications"

cp "$ICON" "$STAGE/.VolumeIcon.icns" || fail "missing $ICON"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
# Sized by hdiutil from the staged contents, with room to spare: setting the volume
# icon writes to the mounted volume, and a read-write image sized exactly to its
# contents has nowhere to put it.

step "Creating the image"

rm -f "$DMG" "$READWRITE"
mkdir -p dist

hdiutil create \
    -srcfolder "$STAGE" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    -quiet \
    "$READWRITE" \
    || fail "hdiutil could not create the read-write image"

# -nobrowse keeps it off the Finder sidebar and the desktop while it is being prepared,
# so a build does not make windows appear on somebody's screen mid-run.
MOUNT_OUTPUT="$(hdiutil attach "$READWRITE" -readwrite -noverify -nobrowse -mountrandom /tmp)" \
    || fail "could not mount the read-write image"
MOUNTED="$(printf '%s\n' "$MOUNT_OUTPUT" | grep -o '/tmp/[^[:space:]]*' | head -1)"
[[ -n "$MOUNTED" ]] || fail "the image mounted but hdiutil did not say where"

# The Finder flag that makes .VolumeIcon.icns the volume's icon. Cosmetic, and treated
# as such: a failure here is worth saying out loud and is not worth failing a release.
if ! SetFile -a C "$MOUNTED" 2>/dev/null; then
    echo "  note: could not set the custom-icon flag; the image will use the generic one"
fi

hdiutil detach "$MOUNTED" -quiet || fail "could not detach the read-write image"
MOUNTED=""

# UDZO: compressed and read-only. Read-only matters beyond size — a writable image is
# one a user can modify in place, which puts a modified app behind a signature that
# was checked when it mounted.
hdiutil convert "$READWRITE" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet \
    || fail "could not convert the image to its compressed read-only form"
rm -f "$READWRITE"

# ---------------------------------------------------------------------------
# Sign
# ---------------------------------------------------------------------------
# Signing the image is separate from signing the app inside it and does not replace it.
# The app's signature is what Gatekeeper checks after somebody drags it to
# /Applications; the image's is what is checked when they open the download. Both, or
# the download is refused before the app inside is ever looked at.

if [[ "$DISTRIBUTABLE" == "yes" ]]; then
    step "Signing the image"
    # --timestamp contacts Apple's timestamp authority, so this step needs the network.
    # Notarisation rejects a signature without a secure timestamp.
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG" \
        || fail "could not sign $DMG"
    codesign --verify --strict "$DMG" || fail "the signature on $DMG does not verify"
    codesign -d --verbose=4 "$DMG" 2>&1 | grep -q '^Timestamp=' \
        || fail "no secure timestamp on $DMG; notarisation requires one (was the network up?)"
fi

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------
# By mounting it and looking, because every check that reads the staging directory is a
# check of something that is not what ships. The image is the artefact now.

step "Verifying the image as a user's Mac will see it"

MOUNT_OUTPUT="$(hdiutil attach "$DMG" -readonly -noverify -nobrowse -mountrandom /tmp)" \
    || fail "the finished image will not mount"
MOUNTED="$(printf '%s\n' "$MOUNT_OUTPUT" | grep -o '/tmp/[^[:space:]]*' | head -1)"
[[ -n "$MOUNTED" ]] || fail "the finished image mounted but hdiutil did not say where"

INSIDE="$MOUNTED/$(basename "$APP")"
[[ -d "$INSIDE" ]] || fail "there is no $(basename "$APP") inside the image"

# The one that matters. An app whose signature did not survive being staged, imaged and
# compressed is an app that is refused on the far side, and nothing before this point
# would have noticed.
codesign --verify --deep --strict "$INSIDE" \
    || fail "the app inside the image does not verify — its signature did not survive packaging"

[[ -L "$MOUNTED/Applications" && "$(readlink "$MOUNTED/Applications")" == "/Applications" ]] \
    || fail "the drag-to-Applications symlink is missing or points somewhere else"

# Nothing but the app, the symlink and the volume icon. A stray file here is a file
# every user sees in the window they open, and it is the kind of thing that arrives by
# accident from a staging directory that was not clean.
STRAY="$(
    find "$MOUNTED" -maxdepth 1 -mindepth 1 \
        ! -name "$(basename "$APP")" \
        ! -name Applications \
        ! -name .VolumeIcon.icns \
        ! -name .fseventsd \
        ! -name .Trashes \
        ! -name .DS_Store
)"
[[ -z "$STRAY" ]] || fail "$(
    printf 'the image window would show more than the app and the symlink:\n'
    printf '%s\n' "$STRAY" | sed 's/^/    /'
)"

# On a distribution image, the app inside must still be the hardened, Developer
# ID-signed thing that went in. Checked here rather than trusted, because this is the
# last point at which it is cheap to find out.
if [[ "$DISTRIBUTABLE" == "yes" ]]; then
    INSIDE_INFO="$(codesign -d --verbose=4 "$INSIDE" 2>&1)"
    printf '%s\n' "$INSIDE_INFO" | grep -q 'flags=.*runtime' \
        || fail "the app inside the image is not hardened; notarisation would reject it"
    printf '%s\n' "$INSIDE_INFO" | grep -q 'Authority=Developer ID Application:' \
        || fail "the app inside the image is not Developer ID signed"
fi

hdiutil detach "$MOUNTED" -quiet || fail "could not detach the finished image"
MOUNTED=""

SIZE="$(du -h "$DMG" | cut -f1)"

# ---------------------------------------------------------------------------

if [[ "$DISTRIBUTABLE" == "yes" ]]; then
    cat <<EOF

Built and signed $DMG ($SIZE)

  app        Uttrflow $VERSION, hardened, Developer ID
  image      signed with the same certificate, secure timestamp

Not shippable yet — nothing here has been notarised. Next:

  ./Scripts/notarise.sh $DMG

Until Apple has vouched for it and the ticket is stapled, this image is refused on any
Mac that downloads it.
EOF
else
    cat <<EOF

Built $DMG ($SIZE)

  app        Uttrflow $VERSION, ad-hoc signed$([[ "$HARDENED" == "yes" ]] && echo ", hardened runtime")
  image      unsigned

For testing, not for release. An ad-hoc signature can never be notarised, so a Mac that
receives this through a browser, Mail or AirDrop will refuse to open it — those stamp
the file with a quarantine attribute, and that is what Gatekeeper acts on.

Two ways past it, on the Mac doing the testing:

  scp $DMG you@other-mac.local:~/Desktop/     # scp sets no quarantine; nothing else needed

or, having sent it any other way, after dragging the app to /Applications:

  xattr -dr com.apple.quarantine /Applications/Uttrflow.app

$(if [[ "$HARDENED" == "yes" ]]; then cat <<'NOTE'
This app has the hardened runtime on, which is what ships. That is the right thing to
test on a second Mac: the failure the runtime can cause — no microphone, no prompt, no
error, every sample zero — is invisible on any Mac that has already granted this
identifier, which includes the one that built it.
NOTE
else cat <<'NOTE'
This app has the hardened runtime OFF, and the shipped one will have it on. Rebuild with
`make app-hardened` before testing on a second Mac: the failure the runtime can cause —
no microphone, no prompt, no error, every sample zero — only shows up on a Mac that has
not already granted this identifier, so this build cannot rule it out.
NOTE
fi)
EOF
fi
