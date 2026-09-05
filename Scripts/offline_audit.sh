#!/usr/bin/env bash
#
# Re-runs the static half of the airplane-mode audit.
#
# Uttrflow's promise is that dictation — hold the key, speak, see the words — never
# touches the network once the speech model is on disk. That promise is easy to make
# and easy to break by accident: one `URLSession` in a helper, one dependency that
# phones home on load, one `#if` removed, and nobody notices for six months because
# every machine that runs the tests has Wi-Fi.
#
# So this script asserts the shape the promise depends on, against both the sources and
# the linked binary, and fails loudly when it changes. The dynamic half — running the
# pipeline with the network denied — is in Docs/offline.md, which also records what
# this script deliberately does not cover.
#
# Usage:  ./Scripts/offline_audit.sh            audit, building the app if needed
#         ./Scripts/offline_audit.sh --no-build skip the binary checks if unbuilt
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

SKIP_BUILD=0
[[ "${1:-}" == "--no-build" ]] && SKIP_BUILD=1

failures=0

# Each failure says what broke and why that matters, because "offline_audit.sh: FAILED"
# six months from now tells the next person nothing they can act on.
fail() {
    printf '\n  ✗ %s\n' "$1" >&2
    shift
    for line in "$@"; do printf '    %s\n' "$line" >&2; done
    failures=$((failures + 1))
}

pass() { printf '  ✓ %s\n' "$1"; }
note() { printf '  · %s\n' "$1"; }

# ---------------------------------------------------------------------------
# 1. No network call site in any module the dictation path runs through.
# ---------------------------------------------------------------------------
#
# These are the modules between the key going down and the text appearing. The app
# shell and the developer CLI are deliberately absent: a first-run model download has
# to live somewhere, and those are the two honest places for it.
DICTATION_MODULES=(
    UttrflowCore UttrflowAudio UttrflowSpeech UttrflowAI
    UttrflowContext UttrflowInput UttrflowPipeline
)

# Anything that can open a connection, plus the literal that betrays an endpoint
# someone meant to call. `Network` is listed as an import because NWConnection and
# NWBrowser are unusable without it.
NETWORK_PATTERN='URLSession|URLRequest|NWConnection|NWBrowser|NWListener|import Network|CFSocket|NSURLConnection|https?://|getaddrinfo|\bsocket\('

# The files allowed to contain a network call. Each is a whole file with one job, which
# is the only shape of exception this rule can actually police: a permitted *function*
# sitting among the ones that run during a dictation is indistinguishable, to grep, from
# one somebody added later.
#
#   the cloud island   — all of it inside `#if UTTRFLOW_CLOUD`, which no shipping build
#                        defines. Check 4 below proves that separately.
#   the tokenizer      — reached only from a model install, which the user asks for and
#                        which plainly needs the network. Check 3 proves that loading and
#                        decoding cannot reach it, which is the half that matters.
CLOUD_ISLAND='Sources/UttrflowAI/HTTPCleanupModel.swift'
DOWNLOAD_ISLAND='Sources/UttrflowSpeech/TokenizerDownload.swift'

printf 'Network call sites on the dictation path\n'

offenders=""
for module in "${DICTATION_MODULES[@]}"; do
    [[ -d "Sources/$module" ]] || {
        fail "Sources/$module does not exist" \
            "The audit is checking a module that has been renamed or removed, so" \
            "whatever is in its place is not being checked at all."
        continue
    }
    # grep exits 1 on no matches, which is the good case; `|| true` keeps `set -e`
    # from treating a clean module as a script failure.
    hits="$(grep -rEn "$NETWORK_PATTERN" "Sources/$module" --include='*.swift' \
        | grep -v "^$CLOUD_ISLAND:" | grep -v "^$DOWNLOAD_ISLAND:" || true)"
    [[ -n "$hits" ]] && offenders+="$hits"$'\n'
done

if [[ -n "${offenders//[[:space:]]/}" ]]; then
    fail "a network call site appeared on the dictation path" \
        "Everything below runs between the user pressing the key and the text being" \
        "inserted, so any of it can stall or fail when there is no connection." \
        "Move it behind an explicit, user-initiated action, or behind UTTRFLOW_CLOUD." \
        "" $'\n'"$offenders"
else
    pass "no network call site in ${#DICTATION_MODULES[@]} dictation-path modules"
fi

# ---------------------------------------------------------------------------
# 2. The cloud model is still entirely inside its compile-time island.
# ---------------------------------------------------------------------------
printf '\nThe cloud island\n'

if [[ ! -f "$CLOUD_ISLAND" ]]; then
    note "$CLOUD_ISLAND has gone; nothing to gate"
else
    if [[ "$(head -n 1 "$CLOUD_ISLAND")" != "#if UTTRFLOW_CLOUD" ]]; then
        fail "$CLOUD_ISLAND no longer opens with #if UTTRFLOW_CLOUD" \
            "The hosted model is the only network path Uttrflow has. If it is not" \
            "wrapped from the very first line, some of it compiles into the app."
    elif [[ "$(tail -n 1 "$CLOUD_ISLAND")" != "#endif" ]]; then
        fail "$CLOUD_ISLAND no longer ends with #endif" \
            "Code after the #endif compiles unconditionally, which is how a network" \
            "call gets into a build that promises not to have one."
    else
        pass "the hosted model is wrapped from first line to last"
    fi
fi

if grep -rqE 'UTTRFLOW_CLOUD' Package.swift; then
    fail "Package.swift now defines UTTRFLOW_CLOUD" \
        "That switches the hosted model on for every target, which contradicts the" \
        "product's stated promise that the shipping build has no network path."
else
    pass "no target defines UTTRFLOW_CLOUD"
fi

# ---------------------------------------------------------------------------
# 3. Nothing on the dictation path asks a model store to download.
# ---------------------------------------------------------------------------
#
# `download: false` in the WhisperKit configuration is what turns a missing model into
# a clear error instead of a silent stall on a slow connection. Flipping it would put a
# 646 MB download in the middle of somebody's first dictation.
printf '\nModel downloads\n'

BACKEND='Sources/UttrflowSpeech/WhisperKitBackend.swift'
if [[ ! -f "$BACKEND" ]]; then
    fail "$BACKEND is missing" \
        "The audit cannot confirm that loading a speech model still refuses to" \
        "download one, which is the check that keeps the network off the hot path."
elif grep -qE '^\s*download:\s*false\b' "$BACKEND"; then
    pass "loading a speech model still refuses to download one"
else
    fail "$BACKEND no longer passes download: false" \
        "With downloading enabled, a missing model turns the first dictation into a" \
        "646 MB transfer that hangs rather than an error the user can act on."
fi

# The Hugging Face hub is the one legitimate network user in the package. It may be
# named in the file that defines the downloader and nowhere else on the dictation path.
hub_hits="$(grep -rEn 'HubApi|WhisperKit\.download|AutoTokenizer' \
    "${DICTATION_MODULES[@]/#/Sources/}" --include='*.swift' 2>/dev/null \
    | grep -v "^$BACKEND:" || true)"
if [[ -n "${hub_hits//[[:space:]]/}" ]]; then
    fail "the model hub is reached from somewhere new" \
        "Only $BACKEND may name it, and only to define the downloader the store calls." \
        "" $'\n'"$hub_hits"
else
    pass "the model hub is named in one file only"
fi

# ---------------------------------------------------------------------------
# 4. The known gap: WhisperKit's tokenizer is fetched separately, at load time.
# ---------------------------------------------------------------------------
#
# WhisperKit loads a tokenizer after the model, and falls back to downloading it from
# the hub when it cannot find `tokenizer.json` locally. `download: false` does not cover
# that — it governs the model only. Uttrflow does not pass a `tokenizerFolder`, and the
# store does not install one, so on a Mac that has never transcribed while online the
# first dictation reaches for the network and fails. Docs/offline.md has the evidence.
#
# The check flips once somebody fixes it: while unfixed it reports, and after the fix it
# guards, so the fix cannot be undone quietly.
printf '\nTokenizer\n'

if grep -q 'tokenizerFolder' "$BACKEND" 2>/dev/null; then
    pass "a tokenizer folder is pinned, so loading cannot fall back to the hub"
else
    note "KNOWN GAP: no tokenizerFolder is pinned in $BACKEND."
    note "  WhisperKit downloads the tokenizer at model-load time when it cannot find"
    note "  one on disk, which puts a network call on the dictation path for any Mac"
    note "  that has not transcribed while online. See Docs/offline.md § Tokenizer."
fi

# ---------------------------------------------------------------------------
# 5. The built app: which linked modules can actually open a connection.
# ---------------------------------------------------------------------------
#
# The source checks above can only see Uttrflow's own code. This one reads the binary,
# so it also catches a dependency that started networking between releases.
printf '\nLinked binary\n'

if ! command -v xcrun >/dev/null 2>&1; then
    fail "xcrun is not on PATH" \
        "The binary half of the audit cannot run, so a dependency that started" \
        "networking would go unnoticed. Install the Xcode command line tools."
else
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

    # Capture the exit code rather than piping: a pipeline reports the last command's
    # status, and a failed build would look like a passing audit.
    if ! BIN_PATH="$(xcrun swift build --show-bin-path 2>/dev/null)"; then
        fail "could not resolve the build directory" \
            "Without it there is no binary to inspect, so the audit is only as good" \
            "as the source grep above."
        BIN_PATH=""
    fi

    APP_BINARY="${BIN_PATH:+$BIN_PATH/Uttrflow}"
    if [[ -n "$BIN_PATH" && ! -f "$APP_BINARY" && "$SKIP_BUILD" -eq 0 ]]; then
        note "building Uttrflow so the binary can be inspected…"
        if ! xcrun swift build --product Uttrflow >/dev/null; then
            fail "the app did not build" \
                "The binary checks are skipped, and a build this broken cannot be" \
                "shipped anyway. Run 'swift build' to see the errors."
            APP_BINARY=""
        fi
    fi

    if [[ -z "${APP_BINARY:-}" || ! -f "$APP_BINARY" ]]; then
        note "no built app to inspect; source checks only"
    else
        # Every Swift module linked into the app, from the linker's own file list.
        LINK_LIST="$BIN_PATH/Uttrflow.product/Objects.LinkFileList"
        if [[ ! -f "$LINK_LIST" ]]; then
            fail "no link file list at $LINK_LIST" \
                "The audit cannot tell which dependencies are in the app, so a new" \
                "networking one would not be noticed."
        else
            # Hub — swift-transformers — is the legitimate model downloader that
            # WhisperKit pulls in. Anything else with a URLSession in it is new, and
            # is in the app for a reason nobody has written down yet.
            #   Hub           — swift-transformers, the model downloader WhisperKit
            #                     pulls in. Runs only from `models install`.
            #   UttrflowSpeech — TokenizerDownload.swift, which fetches the tokenizer
            #                     beside the weights at install time so that loading
            #                     never has to. Check 3 is what proves loading cannot
            #                     reach it; this line only records that the reference
            #                     is expected.
            #
            # Anything else with a URLSession in it is new, and is in the app for a
            # reason nobody has written down yet.
            #   UttrflowAccount   — the account layer, added after this list was written.
            #                       It talks to api.uttrflow.com and nothing else: sign in,
            #                       read the profile, refresh a token, report telemetry.
            #                       It is on no dictation path — the audit's subject is
            #                       whether *speaking* can reach the network, and signing
            #                       in is the one thing the product says needs it. The
            #                       privacy tests in UttrflowAccountTests are what police
            #                       what it may send.
            #   UttrflowLocalModel — the on-device model that validates and generates
            #                       suggestions. Like Hub for speech, it fetches its weights
            #                       from Hugging Face once; every inference then runs on the
            #                       GPU with nothing sent out. It is on no dictation path, so
            #                       the guarantee this audit exists for — that speaking cannot
            #                       reach the network — is untouched (check 1 still proves it).
            #   HuggingFace,       — swift-huggingface and its SSE helper, the download
            #   EventSource          machinery UttrflowLocalModel pulls in, the way Hub is
            #                       WhisperKit's. They fetch model files and nothing else.
            #   Uttrflow          — the app target links the above, so it inherits the
            #                       symbol. Nothing in it opens a connection of its own.
            ALLOWED_NETWORK_MODULES="Hub UttrflowSpeech UttrflowAccount UttrflowLocalModel HuggingFace EventSource Uttrflow"
            networking=""
            while IFS= read -r module_dir; do
                found="$(find "$BIN_PATH/$module_dir" -name '*.o' -print0 2>/dev/null \
                    | xargs -0 nm -u 2>/dev/null | grep -ci 'urlsession' || true)"
                [[ "$found" -gt 0 ]] && networking+="${module_dir%.build} "
            done < <(grep -oE '/[A-Za-z0-9._-]+\.build/' "$LINK_LIST" | tr -d '/' | sort -u)
            # Accumulated with trailing spaces; re-split so messages read cleanly.
            networking="$(echo $networking)"

            unexpected=""
            for module in $networking; do
                case " $ALLOWED_NETWORK_MODULES " in
                *" $module "*) ;;
                *) unexpected+="$module " ;;
                esac
            done

            if [[ -n "${unexpected// /}" ]]; then
                fail "a new network-capable module is linked into the app: ${unexpected% }" \
                    "Something in the app can now open a connection that could not" \
                    "before. Find out when it runs before shipping it — the only one" \
                    "that was ever meant to be there is: $ALLOWED_NETWORK_MODULES."
            else
                # The list is accumulated with trailing spaces; read it back through
                # word splitting so the message does not end in one.
                pass "network-capable modules in the app, all expected: ${networking:-none}"
            fi

            # Uttrflow's own modules, narrowed to the ones the app actually links. The one
            # exception, UttrflowLocalModel, is allowed above because it is the model's own
            # downloader; every other Uttrflow-named module opening a connection is new.
            own_offenders=""
            for module in $networking; do
                case " $ALLOWED_NETWORK_MODULES " in
                *" $module "*) continue ;;
                esac
                case "$module" in
                Uttrflow*) own_offenders+="$module " ;;
                esac
            done
            if [[ -n "${own_offenders// /}" ]]; then
                fail "Uttrflow's own modules now reference URLSession: ${own_offenders% }" \
                    "The product's own code is not supposed to contain a single one, so" \
                    "this is a network call somebody added to the app itself." \
                    "Run: nm -u \$(find $BIN_PATH/<module>.build -name '*.o') | grep -i urlsession"
            else
                pass "no Uttrflow module in the app references URLSession"
            fi
        fi

        # The compile-time gate, verified against the shipped artefact rather than
        # assumed from reading the #if.
        cloud_symbols="$(nm -a "$APP_BINARY" 2>/dev/null | xcrun swift demangle 2>/dev/null \
            | grep -c 'UttrflowAI\.HTTPCleanupModel' || true)"
        if [[ "$cloud_symbols" -gt 0 ]]; then
            fail "HTTPCleanupModel is in the built app ($cloud_symbols symbols)" \
                "The hosted model was supposed to be compiled out entirely. It is not," \
                "so the shipping binary contains a network path after all."
        else
            pass "HTTPCleanupModel is absent from the built app"
        fi
    fi
fi

# ---------------------------------------------------------------------------
printf '\n'
if [[ "$failures" -gt 0 ]]; then
    printf 'offline audit: %d check(s) failed — see above.\n' "$failures" >&2
    exit 1
fi
printf 'offline audit: everything the static half can prove still holds.\n'
printf 'The dynamic evidence, and its limits, are in Docs/offline.md.\n'
