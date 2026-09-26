#!/usr/bin/env bash
# Proves Scripts/publish.sh can resume a publish that failed after the release and its
# two assets were created but before latest.json and appcast.xml were pushed — the gap
# described in the issue this guards. Every network-facing tool (gh, hdiutil, xcrun) is
# faked; only ditto, plutil and git run for real, and all of them stay local.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'chmod -R u+w "$test_root" 2>/dev/null; rm -rf "$test_root"' EXIT

# ---------------------------------------------------------------------------
# An isolated copy of the package, so PACKAGE_ROOT inside publish.sh resolves here and
# the real checkout's .build is never touched.
# ---------------------------------------------------------------------------
pkg="$test_root/pkg"
mkdir -p "$pkg/Scripts" "$pkg/.build/artifacts/sparkle/Sparkle/bin"
cp "$repo_root/Scripts/publish.sh" "$pkg/Scripts/publish.sh"
cp "$repo_root/Scripts/appcast.py" "$pkg/Scripts/appcast.py"
cp "$repo_root/Scripts/update_feed_gate.py" "$pkg/Scripts/update_feed_gate.py"
chmod +x "$pkg/Scripts/publish.sh"

cat > "$pkg/.build/artifacts/sparkle/Sparkle/bin/sign_update" <<'EOF'
#!/usr/bin/env bash
# Mimics the two attributes the real tool prints, in the same shape appcast.py parses.
target="${@: -1}"
size="$(stat -f%z "$target" 2>/dev/null || echo 0)"
digest="$(shasum -a 256 "$target" | cut -c1-16)"
echo "sparkle:edSignature=\"fake-$digest==\" length=\"$size\""
EOF
chmod +x "$pkg/.build/artifacts/sparkle/Sparkle/bin/sign_update"

# ---------------------------------------------------------------------------
# A fake .app to mount: a real Info.plist (plutil reads real ones) with no SUFeedURL, so
# the feed gate reports "absent" and asks no key of the fixture.
# ---------------------------------------------------------------------------
app_root="$test_root/app-src/Uttrflow.app"
app_src="$app_root/Contents"
mkdir -p "$app_src"
cat > "$app_src/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleShortVersionString</key>
    <string>2026.9.14</string>
    <key>CFBundleVersion</key>
    <string>42</string>
    <key>UttrflowBuildCommit</key>
    <string>deadbeef</string>
</dict>
</plist>
EOF
printf 'not a real binary, never executed\n' > "$app_src/fixture"
image="$test_root/Uttrflow-test.dmg"
printf 'placeholder disk image bytes\n' > "$image"

# ---------------------------------------------------------------------------
# The downloads repository publish.sh clones, commits to and pushes — a real local git
# repository, so the manifest/appcast half of the script runs unmodified.
# ---------------------------------------------------------------------------
downloads_bare="$test_root/downloads.git"
downloads_seed="$test_root/downloads-seed"
git init -q -b main "$downloads_seed"
git -C "$downloads_seed" config user.email "publish-test@example.invalid"
git -C "$downloads_seed" config user.name "Publish Test"
printf '{}' > "$downloads_seed/latest.json"
printf '<xml/>\n' > "$downloads_seed/appcast.xml"
git -C "$downloads_seed" add latest.json appcast.xml
git -C "$downloads_seed" commit -qm seed
git init -q --bare -b main "$downloads_bare"
git -C "$downloads_seed" remote add origin "$downloads_bare"
git -C "$downloads_seed" push -q origin main

# ---------------------------------------------------------------------------
# Fakes for every external tool publish.sh shells out to that would otherwise touch the
# network or a real disk image.
# ---------------------------------------------------------------------------
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
gh_state="$test_root/gh-state"
mkdir -p "$gh_state"

cat > "$fake_bin/hdiutil" <<EOF
#!/usr/bin/env bash
case "\$1" in
    attach)
        mount_dir="\$(mktemp -d /tmp/publish-resume-test-mount.XXXXXX)"
        cp -Rp "$app_root" "\$mount_dir/"
        echo "/dev/disk9s1  \$mount_dir"
        ;;
    detach)
        exit 0
        ;;
    *)
        echo "fake hdiutil: unhandled \$*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$fake_bin/hdiutil"

cat > "$fake_bin/xcrun" <<'EOF'
#!/usr/bin/env bash
# Every image in this test is treated as unnotarised — the notarised path needs nothing
# different from the resume logic under test.
if [[ "$1" == "stapler" && "$2" == "validate" ]]; then
    exit 1
fi
echo "fake xcrun: unhandled $*" >&2
exit 1
EOF
chmod +x "$fake_bin/xcrun"

cat > "$fake_bin/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
state="$gh_state"
downloads="$downloads_bare"

case "\$1 \$2" in
    "auth status")
        exit 0
        ;;
    "release view")
        tag="\$3"
        [[ -f "\$state/created-\$tag" ]] || exit 1
        if [[ "\$*" == *"--json assets"* ]]; then
            cat "\$state/assets-\$tag"
        fi
        exit 0
        ;;
    "release create")
        shift 2
        tag="\$1"; shift
        files=()
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                --repo|--title|--notes) shift 2 ;;
                --prerelease) shift ;;
                *) files+=("\$1"); shift ;;
            esac
        done
        : > "\$state/assets-\$tag"
        for f in "\${files[@]}"; do
            printf '%s %s\n' "\$(basename "\$f")" "\$(stat -f%z "\$f")" >> "\$state/assets-\$tag"
            mkdir -p "\$state/files-\$tag"
            cp "\$f" "\$state/files-\$tag/"
        done
        touch "\$state/created-\$tag"
        count_file="\$state/create-calls"
        current="0"
        [[ -f "\$count_file" ]] && current="\$(cat "\$count_file")"
        echo "\$((current + 1))" > "\$count_file"
        exit 0
        ;;
    "release download")
        shift 2
        tag="\$1"; shift
        dir=""; patterns=()
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                --dir) dir="\$2"; shift 2 ;;
                --pattern) patterns+=("\$2"); shift 2 ;;
                --repo) shift 2 ;;
                *) shift ;;
            esac
        done
        for p in "\${patterns[@]}"; do
            cp "\$state/files-\$tag/\$p" "\$dir/" 2>/dev/null || true
        done
        ;;
    "repo clone")
        dest="\$4"
        git clone --quiet --depth 1 "\$downloads" "\$dest"
        ;;
    *)
        echo "fake gh: unhandled \$*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$fake_bin/gh"

export PATH="$fake_bin:$PATH"
export UTTRFLOW_DOWNLOADS_REPO="test/releases"

run_log_1="$test_root/run1.log"
run_log_2="$test_root/run2.log"

# ---------------------------------------------------------------------------
# Run 1: release and both assets are created, then the feed push fails — modelled here
# as the downloads remote having gone temporarily unwritable, same as a transient
# GitHub or network failure would leave it.
# ---------------------------------------------------------------------------
chmod -R a-w "$downloads_bare"
if "$pkg/Scripts/publish.sh" "$image" > "$run_log_1" 2>&1; then
    echo "error: first publish run was expected to fail before the feed push" >&2
    cat "$run_log_1" >&2
    exit 1
fi
if ! grep -Fq 'could not push latest.json' "$run_log_1"; then
    echo "error: first run did not fail at the feed push as expected" >&2
    cat "$run_log_1" >&2
    exit 1
fi
chmod -R u+w "$downloads_bare"

if [[ "$(cat "$gh_state/create-calls")" != "1" ]]; then
    echo "error: release create was not called exactly once after the first run" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Run 1b: an image of the same size but different bytes must be refused, not resumed.
# ---------------------------------------------------------------------------
cp "$image" "$test_root/image.orig"
printf 'PLACEHOLDER disk image bytes\n' > "$image"
run_log_drift="$test_root/run-drift.log"
if "$pkg/Scripts/publish.sh" "$image" > "$run_log_drift" 2>&1; then
    echo "error: a same-size, different-content image was resumed" >&2
    cat "$run_log_drift" >&2
    exit 1
fi
if ! grep -Fq 'with different assets' "$run_log_drift"; then
    echo "error: the drifted image did not fail on the content check" >&2
    cat "$run_log_drift" >&2
    exit 1
fi
cp "$test_root/image.orig" "$image"

# The archive is rebuilt with the same size and different bytes, as a re-signed build would be.
printf 'NOT a real binary, never executed\n' > "$app_src/fixture"

# ---------------------------------------------------------------------------
# Run 2: the same command, unchanged inputs. It must resume — reuse the already-created
# release rather than fail on the existing tag, and finish the feed update.
# ---------------------------------------------------------------------------
if ! "$pkg/Scripts/publish.sh" "$image" > "$run_log_2" 2>&1; then
    echo "error: the rerun did not finish" >&2
    cat "$run_log_2" >&2
    exit 1
fi
if ! grep -Fq 'resuming the feed update' "$run_log_2"; then
    echo "error: the rerun did not take the resume path" >&2
    cat "$run_log_2" >&2
    exit 1
fi
if [[ "$(cat "$gh_state/create-calls")" != "1" ]]; then
    echo "error: the rerun created a second release instead of resuming" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# The feed itself must carry the resumed run's version — proof the manifest and appcast
# actually reached the downloads repository, not just that the script exited 0.
# ---------------------------------------------------------------------------
verify_clone="$test_root/verify-clone"
git clone --quiet "$downloads_bare" "$verify_clone"
if ! grep -Fq '2026.9.14' "$verify_clone/latest.json"; then
    echo "error: latest.json was not updated to the published version" >&2
    cat "$verify_clone/latest.json" >&2
    exit 1
fi
if ! grep -Fq '2026.9.14' "$verify_clone/appcast.xml"; then
    echo "error: appcast.xml was not updated to the published version" >&2
    cat "$verify_clone/appcast.xml" >&2
    exit 1
fi

published_signature="fake-$(shasum -a 256 "$gh_state/files-v2026.9.14/Uttrflow.zip" | cut -c1-16)=="
if ! grep -Fq "$published_signature" "$verify_clone/appcast.xml"; then
    echo "error: the appcast signature is not the signature of the published archive" >&2
    cat "$verify_clone/appcast.xml" >&2
    exit 1
fi

printf 'publish resume test passed\n'
