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
# the linked binary, and fails loudly when it changes. Every check is default-deny: it
# looks at every module and every object in the app and asks which are *allowed* to reach
# the network, rather than at a list of places to look — a list is a thing a new module is
# absent from. The dynamic half — running the pipeline with the network denied — is in
# Docs/offline.md, which also records what this script cannot cover and why.
#
# Usage:  ./Scripts/offline_audit.sh                  audit, building the app if needed
#         ./Scripts/offline_audit.sh --no-build       skip the binary checks if unbuilt
#         ./Scripts/offline_audit.sh --require-binary fail rather than skip them
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PACKAGE_ROOT"

SKIP_BUILD=0
# Set in every GitHub Actions job, and the gate builds before it runs this, so there the
# binary checks are never optional — not even with --no-build, which says "do not build
# for me", not "do not mind if nobody did". See check 7 for why skipping them quietly is
# the failure mode that matters.
REQUIRE_BINARY=0
[[ -n "${CI:-}" ]] && REQUIRE_BINARY=1
for argument in "$@"; do
    case "$argument" in
    --no-build) SKIP_BUILD=1 ;;
    --require-binary) REQUIRE_BINARY=1 ;;
    *)
        printf 'offline audit: unknown option %s\n' "$argument" >&2
        exit 2
        ;;
    esac
done

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
# 1. Network capability lives only where it is named, and nowhere else.
# ---------------------------------------------------------------------------
#
# What this audit is trying to prove, stated once, because the checks below only mean
# something against it. SECURITY.md makes two promises: dictation never touches the
# network once the model is on disk, and the clipboard, history, dictionary and snippets
# never leave the Mac. Both reduce to one claim a tree can be checked against — network
# capability lives in a handful of named files and no other module has any — which is
# also what AGENTS.md means by "UttrflowAccount is deliberately the only module that can
# reach a server": one place to look.
#
# So this is default-deny over every module under Sources/, discovered at run time. The
# earlier version named the seven modules to check, and a module nobody added to that
# list was not audited at all — which is how the clipboard, the history, the dictionary,
# the suggestion stores, the settings and the UX went unchecked (#665). A list of what is
# *allowed* cannot fail that way: a module added tomorrow is covered by default.
ALLOWED_NETWORK_MODULE='UttrflowAccount'

# The files outside that module which may name a networking type, and why each may.
#
#   the cloud island   — all of it inside `#if UTTRFLOW_CLOUD`, which no shipping build
#                        defines. Checks 2 and 7 prove that separately.
#   the tokenizer      — fetched beside the weights at install time so that loading never
#                        has to. Check 4 proves loading cannot reach it.
#   the Apple backend  — not sanctioned. Listed in KNOWN_GAP_FILES below, and reported on
#                        every run, because it downloads on a path the promise covers.
#   onboarding         — first-run sign-in, and the reachability banner that says why it
#                        failed. Signing in is the one thing the product says needs a
#                        connection, and it happens before any dictation.
#   the developer CLIs — `uttrflow-dev sign-in` and the evaluation harness. Neither is in
#                        a shipped product; `Scripts/bundle.sh` is what proves that.
CLOUD_ISLAND='Sources/UttrflowAI/HTTPCleanupModel.swift'
DOWNLOAD_ISLAND='Sources/UttrflowSpeech/TokenizerDownload.swift'
ALLOWED_NETWORK_FILES=(
    "$CLOUD_ISLAND"
    "$DOWNLOAD_ISLAND"
    'Sources/UttrflowSpeech/AppleSpeechBackend.swift'
    'Sources/Uttrflow/Onboarding/NetworkReachability+System.swift'
    'Sources/Uttrflow/Onboarding/OnboardingAccountLayer.swift'
    'Sources/Uttrflow/Onboarding/OnboardingWindowController.swift'
    'Sources/uttrflow-dev/SignIn.swift'
    'Sources/uttrflow-eval/CorpusConnection.swift'
)

# Files that may construct the model hub's client, which is a URLSession underneath. Two
# of them name no networking type themselves — the hub does — so the source check above
# still covers them, and it is only their object files that carry the symbol.
# AnonymousHub.swift is the exception: it is where `HubClient(...)` is actually built, on
# purpose, so that everything else can go through `AnonymousHub.client()` instead of a
# bare client. Check 5 is what proves the suggestion model reads its cache before any of
# this runs, and check 7 is where this list is what keeps the module from being allowed
# one wholesale.
SNAPSHOT_FILE='Sources/UttrflowLocalModel/CachedSnapshot.swift'
HUB_CLIENT_FILES=(
    "$SNAPSHOT_FILE"
    'Sources/UttrflowLocalModel/MLXCandidateScorer.swift'
    'Sources/UttrflowLocalModel/MLXCleanupModel.swift'
    'Sources/UttrflowLocalModel/AnonymousHub.swift'
)

# Allowed above only so that the rest of the tree can be checked at all, and named on
# every run because each is a live defect rather than a design. Taking a file out of here
# is how its fix gets recorded; deleting the note is not.
#
#   AppleSpeechBackend.load() installs the system locale asset, and transcribe() calls
#   load(), so choosing the built-in recogniser and speaking downloads on a Mac that has
#   not installed that locale. WhisperKitBackend has `download: false` for exactly this;
#   the Apple asset API offers no equivalent, so the fix is a product decision about what
#   the user is told, not a flag. Docs/offline.md § What this does not prove has the
#   detail; this list is what keeps it from being forgotten.
KNOWN_GAP_FILES=(
    'Sources/UttrflowSpeech/AppleSpeechBackend.swift'
)

# Every way to reach the network that leaves a name in Swift source: Foundation's stack,
# Network.framework in both its Swift and its C spelling, CFNetwork, the BSD calls those
# sit on, XPC to a helper that could, the system speech asset installer, and the endpoint
# literal that betrays a call somebody meant to make. Matching one symbol — the earlier
# pattern was URLSession and four friends — answers a narrower question than the one being
# asked, and widening it by a name per bug report never converges on the question.
# Docs/offline.md § What this does not prove says what is still outside it.
NETWORK_PATTERN='URLSession|URLRequest|URLProtocol|URLCredential|URLCache|NSURLConnection'
NETWORK_PATTERN+='|NWConnection|NWListener|NWBrowser|NWEndpoint|NWPathMonitor'
NETWORK_PATTERN+='|import Network$|import NetworkExtension|nw_[a-z_]+\('
NETWORK_PATTERN+='|import CFNetwork|CFSocket|CFStream|CFHTTP|NSXPCConnection'
NETWORK_PATTERN+='|getaddrinfo|\bsocket\(|\bconnect\(|downloadAndInstall|AssetInventory'
NETWORK_PATTERN+='|mlx_distributed|MLXDistributed'
NETWORK_PATTERN+='|https?://[A-Za-z0-9]'

printf 'Network capability in the sources\n'

# A named exception that has moved is an exception nobody is checking: the file it covers
# is audited again, which is the safe direction, but the list above stops describing this
# tree and a reader can no longer tell which exceptions are real.
missing=""
[[ -d "Sources/$ALLOWED_NETWORK_MODULE" ]] || missing+="Sources/$ALLOWED_NETWORK_MODULE "
for file in "${ALLOWED_NETWORK_FILES[@]}" "${HUB_CLIENT_FILES[@]}" \
    ${KNOWN_GAP_FILES[@]+"${KNOWN_GAP_FILES[@]}"}; do
    [[ -f "$file" ]] || missing+="$file "
done
if [[ -n "${missing// /}" ]]; then
    fail "an allowed network path no longer exists: ${missing% }" \
        "Every exception this audit grants is written down with a reason, and one that" \
        "names a file that has gone describes a tree that no longer exists. Update the" \
        "list in the change that moved the file."
fi

# Assembled as separate grep arguments rather than one alternation because a path may
# hold a regex metacharacter — `NetworkReachability+System.swift` does.
allowed_filter=(-v -e "^Sources/$ALLOWED_NETWORK_MODULE/")
for file in "${ALLOWED_NETWORK_FILES[@]}"; do allowed_filter+=(-e "^$file:"); done

modules=0
while IFS= read -r _; do modules=$((modules + 1)); done < <(find Sources -mindepth 1 -maxdepth 1 -type d)

offenders="$(grep -rEn "$NETWORK_PATTERN" Sources --include='*.swift' \
    | grep "${allowed_filter[@]}" || true)"

if [[ -n "${offenders//[[:space:]]/}" ]]; then
    fail "a network call site appeared outside the files allowed one" \
        "Dictation must not be able to reach the network, and the clipboard, history," \
        "dictionary and snippets must not be able to leave the Mac. Every module under" \
        "Sources/ is covered by that unless it is named above. Move the call into" \
        "$ALLOWED_NETWORK_MODULE, behind an explicit user-initiated action, or behind" \
        "UTTRFLOW_CLOUD — or add the file above with the reason it is safe." \
        "" $'\n'"$offenders"
else
    pass "no network call site in $modules modules outside $ALLOWED_NETWORK_MODULE and ${#ALLOWED_NETWORK_FILES[@]} named files"
fi

# Printed every run rather than recorded once: an exception that stops being mentioned is
# an exception that has quietly become the design.
# Expanded the long way round because emptying this array is what fixing the gap looks
# like, and bash 3.2 calls an empty array unbound under `set -u`.
for file in ${KNOWN_GAP_FILES[@]+"${KNOWN_GAP_FILES[@]}"}; do
    note "KNOWN GAP: $file reaches the network on a path this promise covers."
done
if [[ "${#KNOWN_GAP_FILES[@]}" -gt 0 ]]; then
    note "  It is allowed above only so the rest of the tree can be checked."
    note "  See Docs/offline.md § What this does not prove."
fi

# ---------------------------------------------------------------------------
# 1b. Reading a URL, which looks the same whether the URL is local or remote.
# ---------------------------------------------------------------------------
#
# `Data(contentsOf:)` fetches a remote URL synchronously, and nothing above can see it:
# the transfer happens inside Foundation, so the calling module names no networking type
# in its source and carries no networking symbol in its object file either. Whether one
# of these is local is decided by where its URL came from, which grep cannot follow — so
# the question this check asks is not "is it local" but "has a new one appeared". Each
# call below was read: five take a path under Application Support or inside an installed
# model, and the rest belong to the evaluation harness and the bakeoff, which ship in
# nothing.
URL_READ_PATTERN='\b(Data|String|NSData|NSString|NSArray|NSDictionary|NSImage|XMLDocument)\(contentsOf:'
URL_READERS=(
    'Sources/UttrflowCore/Support/StoredList.swift'
    'Sources/UttrflowDictionary/PersonalDictionaryStore.swift'
    'Sources/UttrflowLocalModel/PromptTokens.swift'
    'Sources/UttrflowLocalModel/QuantizedLoad.swift'
    'Sources/UttrflowPredict/EnvironmentReading+System.swift'
    'Sources/UttrflowEval/AccuracyBaseline.swift'
    'Sources/UttrflowEval/CorpusCache.swift'
    'Sources/UttrflowEval/CorpusUploadOutbox.swift'
    'Sources/UttrflowEval/JSONRecordStore.swift'
    'Sources/UttrflowEval/SpokenPassages.swift'
    'Sources/uttrflow-bakeoff/Bakeoff.swift'
)

reader_filter=(-v)
for file in "${URL_READERS[@]}"; do reader_filter+=(-e "^$file:"); done

new_reads="$(grep -rEn "$URL_READ_PATTERN" Sources --include='*.swift' \
    | grep "${reader_filter[@]}" || true)"

if [[ -n "${new_reads//[[:space:]]/}" ]]; then
    fail "a new URL read appeared, and grep cannot tell whether the URL is local" \
        "Foundation fetches a remote URL through these initialisers with no symbol this" \
        "audit could see, in the source or in the object file. Say where the URL comes" \
        "from and add the file above, or read the file through LocalStore." \
        "" $'\n'"$new_reads"
else
    pass "no URL read outside the ${#URL_READERS[@]} files known to read local paths"
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

# The Hugging Face hub is the one legitimate network user in the speech package. It may
# be named in the file that defines the downloader and the file that fetches the tokenizer
# beside it, and nowhere else in the tree — not only nowhere else on the dictation path,
# because a module absent from a list of places to look is a module nobody looked at.
hub_hits="$(grep -rEn 'HubApi|WhisperKit\.download|AutoTokenizer' Sources --include='*.swift' \
    | grep -v "^$BACKEND:" | grep -v "^$DOWNLOAD_ISLAND:" || true)"
if [[ -n "${hub_hits//[[:space:]]/}" ]]; then
    fail "the model hub is reached from somewhere new" \
        "Only $BACKEND and $DOWNLOAD_ISLAND may name it, and only to define the" \
        "downloader the store calls at install time." \
        "" $'\n'"$hub_hits"
else
    pass "the model hub is named only where the install runs"
fi

# ---------------------------------------------------------------------------
# 4. A gap this audit found, now closed: WhisperKit's tokenizer, fetched at load time.
# ---------------------------------------------------------------------------
#
# WhisperKit loads a tokenizer after the model, and falls back to downloading it from
# the hub when it cannot find `tokenizer.json` locally. `download: false` does not cover
# that — it governs the model only. Uttrflow passed no `tokenizerFolder` and the store did
# not install one, so on a Mac that had never transcribed while online the first dictation
# reached for the network and failed. Docs/offline.md has the evidence.
#
# The store now installs the tokenizer and the backend pins the folder, so this check has
# flipped from reporting the gap to guarding the fix, and the fix cannot be undone quietly.
#
# Matched the same way as `download: false` above — a labeled argument at the start of its
# line — so a `//` comment mentioning the name, or the name appearing anywhere else in the
# file, proves nothing. `nil` is rejected explicitly: it is the one value that passes this
# shape while putting WhisperKit right back on the hub fallback this check exists to catch.
printf '\nTokenizer\n'

if grep -qE '^\s*tokenizerFolder:\s*[A-Za-z_][A-Za-z0-9_.]*\s*,?\s*$' "$BACKEND" 2>/dev/null \
    && ! grep -qE '^\s*tokenizerFolder:\s*nil\b' "$BACKEND" 2>/dev/null; then
    pass "a tokenizer folder is pinned, so loading cannot fall back to the hub"
else
    fail "$BACKEND does not pin a tokenizerFolder" \
        "WhisperKit downloads the tokenizer at model-load time when it cannot find" \
        "one on disk, which puts a network call on the dictation path for any Mac" \
        "that has not transcribed while online. See Docs/offline.md § Tokenizer."
fi

# ---------------------------------------------------------------------------
# 5. The suggestion model loads from disk when it is already there.
# ---------------------------------------------------------------------------
#
# `loadModelContainer(from: #hubDownloader(), …)` asks the hub for the repository's file
# list before it looks in the cache, so it opens a connection on every load of a model that
# is already whole on disk (#380). The weights are found by `weightsDirectory`, which asks
# the hub only when the cache is not whole, and loaded from that directory. The hub may be
# named in the file that decides that, and in the scorer and clean-up model that hand it the
# downloader, and nowhere else; and no load may take the downloader directly again.
printf '\nSuggestion model\n'

HUB_ALLOWED="${HUB_CLIENT_FILES[*]}"
if [[ ! -f "$SNAPSHOT_FILE" ]] || ! grep -q 'CachedSnapshot.complete' "$SNAPSHOT_FILE"; then
    fail "$SNAPSHOT_FILE no longer checks the cache before asking the hub" \
        "Without it every load of the suggestion model contacts the model host," \
        "even when every file is already on disk. See Docs/offline.md."
else
    pass "the suggestion model's cache is checked before the hub is asked"
fi

hub_loads="$(grep -rEn -A2 '\bloadModel(Container)?\(' Sources --include='*.swift' \
    | grep -E 'from: *#hubDownloader|from: *(hub|downloader)\b' || true)"
if [[ -n "${hub_loads//[[:space:]]/}" ]]; then
    fail "a model load takes the hub downloader directly" \
        "That load resolves the repository over the network before it reads the cache." \
        "Load from weightsDirectory(cache:downloader:onProgress:) instead." \
        "" $'\n'"$hub_loads"
else
    pass "no model load takes the hub downloader directly"
fi

hub_names="$(grep -rln '#hubDownloader\|HubClient' Sources --include='*.swift' || true)"
unexpected_hub=""
for file in $hub_names; do
    case " $HUB_ALLOWED " in
    *" $file "*) ;;
    *) unexpected_hub+="$file " ;;
    esac
done
if [[ -n "${unexpected_hub// /}" ]]; then
    fail "the model hub client is named somewhere new: ${unexpected_hub% }" \
        "Only $HUB_ALLOWED may name it."
else
    pass "the model hub client is named only where the cache is checked first"
fi

# A bare `HubClient()` resolves a token from HF_TOKEN, from $HF_HOME/token and from the hub
# CLI's own files under the real home — Uttrflow is not sandboxed, so those are the user's —
# and follows HF_ENDPOINT for the host. Both are defaults, so neither shows up in a diff.
# Every client this app builds says whose token it uses and which host it talks to (#666).
bare_clients="$(grep -rEn 'HubClient\(\s*\)' Sources --include='*.swift' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//' || true)"
if [[ -n "${bare_clients//[[:space:]]/}" ]]; then
    fail "a hub client is built with its defaults" \
        "Those defaults attach the person's own Hugging Face token to this app's downloads" \
        "and follow HF_ENDPOINT. Use AnonymousHub.client(). See Docs/predict-llm.md." \
        "" $'\n'"$bare_clients"
else
    pass "no hub client is built with its defaults"
fi

token_providers="$(grep -rEn 'tokenProvider: *\.(environment|fixed|oauth|composite)' Sources --include='*.swift' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//' || true)"
if [[ -n "${token_providers//[[:space:]]/}" ]]; then
    fail "a model download would send a token" \
        "Uttrflow fetches public weights and has no account on the model host." \
        "" $'\n'"$token_providers"
else
    pass "no model download sends a token"
fi

endpoints="$(grep -rEn 'HF_ENDPOINT|detectHost' Sources --include='*.swift' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//' || true)"
if [[ -n "${endpoints//[[:space:]]/}" ]]; then
    fail "a model download would follow an endpoint from the environment" \
        "The host is huggingface.co, named in the source, not chosen by whoever set a variable." \
        "" $'\n'"$endpoints"
else
    pass "no model download follows an endpoint from the environment"
fi

# A branch moves; a commit does not. A model fetched from a branch is whatever was pushed to it.
unpinned="$(grep -rEn 'resolve/main/|revision: *"main"' Sources --include='*.swift' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//' || true)"
if [[ -n "${unpinned//[[:space:]]/}" ]]; then
    fail "a model is fetched from a branch rather than a commit" \
        "A push to that branch reaches every new install without a release of this app." \
        "" $'\n'"$unpinned"
else
    pass "no model is fetched from a branch"
fi

# ---------------------------------------------------------------------------
# 6. The updater is in the app shell and callable from nowhere else.
# ---------------------------------------------------------------------------
#
# Sparkle fetches an appcast and an archive over the network: that is the feature, so
# inspecting the framework itself would only establish that an updater updates. The claim
# worth checking is where it can be called from — one file in the app shell, with no
# library target taking the dependency — because that is what keeps it off every path a
# dictation, a clip or a history entry runs through.
printf '\nThe updater\n'

UPDATER_FILE='Sources/Uttrflow/Updates/UpdateController.swift'
if [[ ! -f "$UPDATER_FILE" ]]; then
    fail "$UPDATER_FILE is missing" \
        "The audit cannot tell where the updater is driven from, so it cannot say that" \
        "the one network client in the app shell is out of reach of the dictation path."
else
    updater_imports="$(grep -rln 'import Sparkle' Sources --include='*.swift' \
        | grep -v "^$UPDATER_FILE\$" || true)"
    if [[ -n "${updater_imports//[[:space:]]/}" ]]; then
        fail "the updater is imported outside the app shell" \
            "Sparkle checks a feed and downloads an archive. Every file that can drive" \
            "it is a file that can reach the network, so it stays in one place in the" \
            "app shell where the audit can point at it." \
            "" $'\n'"$updater_imports"
    else
        pass "the updater is imported in one file, in the app shell"
    fi
fi

# A library target taking the dependency would make the check above unenforceable: the
# import could then move into a module the dictation path links.
sparkle_targets="$(grep -c 'package: "Sparkle"' Package.swift || true)"
if [[ "$sparkle_targets" -ne 1 ]]; then
    fail "$sparkle_targets targets depend on the updater, not one" \
        "Only the app target may. A library that links Sparkle can be linked in turn by" \
        "something on the dictation path, and the import check above stops meaning much."
else
    pass "one target depends on the updater"
fi

# ---------------------------------------------------------------------------
# 7. The built app: which linked objects can actually open a connection.
# ---------------------------------------------------------------------------
#
# The source checks above see Uttrflow's own code. This one reads the object files, so it
# also catches a dependency that started networking between releases, and a call that
# reached the network through a name the grep does not know.
printf '\nLinked binary\n'

# Every way a compiled object can reach the network, as the linker sees it: Foundation's
# stack, Network.framework (whose Swift API is these C entry points underneath), CFNetwork,
# the BSD calls, XPC, and the system speech asset installer. Counting undefined
# `urlsession` symbols alone — which is what this did — left NWConnection, a raw socket
# and the asset downloader invisible to it (#665).
BINARY_SYMBOLS='urlsession|nsurlconnection|urlrequest|urldownload'
BINARY_SYMBOLS+='|nw_connection|nw_listener|nw_browser|nw_endpoint|nw_path|nw_parameters'
BINARY_SYMBOLS+='|cfsocket|cfstream|cfnetwork|cfhttp|cfhost|cfurldownload'
BINARY_SYMBOLS+='|nsxpcconnection|assetinventory|assetinstallation'
BINARY_SYMBOLS+='| _socket$| _connect$| _getaddrinfo$| _getnameinfo$'

# Dependencies that are network clients by design. A module here is judged whole, because
# it is somebody else's source tree and this audit has no file-level claim to make about
# it; what it asserts is that the set has not grown.
#
#   Hub, ArgmaxCore  — swift-transformers' model downloader, and WhisperKit's vendored
#                      copy of the same thing. Both run from `models install`; checks 3
#                      and 4 are what prove loading cannot reach them.
#   HuggingFace,     — swift-huggingface and its server-events helper, the same machinery
#   EventSource        for the suggestion model's weights. Check 5 covers the load.
#   Cmlx             — MLX's C++ core, which links `socket`, `connect` and `getaddrinfo`
#                      for its multi-host distributed backend. Widening the symbol set is
#                      what surfaced this (#665): it was invisible while only `urlsession`
#                      was counted. Nothing here can remove it — mlx-swift exposes no
#                      build flag to drop the backend — so what is checkable is that it
#                      stays unreachable: it runs only from `mlx_distributed_init`, and
#                      check 1 fails on any Uttrflow source that names it.
ALLOWED_NETWORK_DEPENDENCIES="Hub ArgmaxCore HuggingFace EventSource Cmlx"

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
        # In the gate the binary is always there, because `make verify` runs `build`
        # before this. So a missing one there does not mean "not built yet", it means the
        # build moved — and a note would leave the whole binary half silently unrun, which
        # is how a dependency that started networking would ship (#665). Locally a bare
        # run still notes it, because a contributor mid-change wants the source checks in
        # two seconds rather than a build.
        if [[ "$REQUIRE_BINARY" -eq 1 ]]; then
            fail "no built app at ${APP_BINARY:-the expected path}" \
                "The binary checks are the only ones that can see a dependency's network" \
                "call, and skipping them silently is how one ships. 'make verify' builds" \
                "before it runs this, so a missing binary here means the build moved or" \
                "did not run — not that there is nothing to look at yet."
        else
            note "no built app to inspect; source checks only"
            note "  Pass --require-binary, or set CI, to make this a failure."
        fi
    else
        # Every Swift module linked into the app, from the linker's own file list.
        LINK_LIST="$BIN_PATH/Uttrflow.product/Objects.LinkFileList"
        if [[ ! -f "$LINK_LIST" ]]; then
            fail "no link file list at $LINK_LIST" \
                "The audit cannot tell which dependencies are in the app, so a new" \
                "networking one would not be noticed."
        else
            # Per object file, not per module. SwiftPM emits one `.o` per source file, so
            # the binary check can use the same allow list as the source check above —
            # which is what stops the app target being allowed a networking symbol
            # wholesale (#665). Only its onboarding objects are, and only while the
            # source list says so.
            #
            # The cloud island is deliberately absent: it compiles out, so its object
            # must hold no networking symbol at all, and this is what proves the `#if`
            # rather than reading it.
            # Keyed by module as well as by object, because a basename on its own would
            # let a `TelemetryService.swift` in the clipboard inherit the account's
            # allowance. SwiftPM names each module's object directory after the directory
            # under Sources/, so the two line up.
            allowed_objects=""
            while IFS= read -r file; do
                [[ "$file" == "$CLOUD_ISLAND" ]] && continue
                relative="${file#Sources/}"
                allowed_objects+="${relative%%/*}/$(basename "$file").o "
            done < <(
                find "Sources/$ALLOWED_NETWORK_MODULE" -name '*.swift'
                printf '%s\n' "${ALLOWED_NETWORK_FILES[@]}" "${HUB_CLIENT_FILES[@]}"
            )

            # One `nm -uA` over every linked object rather than one per file: the
            # audit is a step in `make verify`, and forty-odd processes per module cost
            # more than the whole rest of the script.
            object_roots=()
            while IFS= read -r module_dir; do
                [[ -d "$BIN_PATH/$module_dir" ]] && object_roots+=("$BIN_PATH/$module_dir")
            done < <(grep -oE '/[A-Za-z0-9._-]+\.build/' "$LINK_LIST" | tr -d '/' | sort -u)

            if [[ "${#object_roots[@]}" -eq 0 ]]; then
                fail "the link file list names no module object directory" \
                    "The audit cannot tell which objects are in the app, so a" \
                    "dependency that started networking would not be noticed."
            fi
            reachable="$(find ${object_roots[@]+"${object_roots[@]}"} -name '*.o' -print0 2>/dev/null \
                | xargs -0 nm -uA 2>/dev/null | grep -Ei "$BINARY_SYMBOLS" \
                | sed -E 's|^.*/([A-Za-z0-9._-]+)\.build/([^:]+):.*$|\1 \2|' | sort -u || true)"

            new_dependencies=""
            own_offenders=""
            while read -r module object; do
                [[ -n "$module" ]] || continue
                case " $ALLOWED_NETWORK_DEPENDENCIES " in
                *" $module "*) continue ;;
                esac
                case "$module" in
                Uttrflow | Uttrflow?* | uttrflow-*)
                    case " $allowed_objects " in
                    *" $module/$object "*) ;;
                    *) own_offenders+="$module/${object%.o} " ;;
                    esac
                    ;;
                *)
                    case " $new_dependencies " in
                    *" $module "*) ;;
                    *) new_dependencies+="$module " ;;
                    esac
                    ;;
                esac
            done <<< "$reachable"

            if [[ -n "${new_dependencies// /}" ]]; then
                fail "a new network-capable dependency is linked into the app: ${new_dependencies% }" \
                    "Something in the app can now open a connection that could not" \
                    "before. Find out when it runs before shipping it — the ones that" \
                    "were meant to be there are: $ALLOWED_NETWORK_DEPENDENCIES."
            else
                pass "the only network-capable dependencies are $ALLOWED_NETWORK_DEPENDENCIES"
            fi

            if [[ -n "${own_offenders// /}" ]]; then
                fail "Uttrflow's own objects can reach the network: ${own_offenders% }" \
                    "Each is a file the source list above does not allow a network call," \
                    "so either the call arrived through a name that grep does not know or" \
                    "a dependency it uses networks on its behalf." \
                    "Run: nm -u $BIN_PATH/<module>.build/<file>.swift.o | grep -Ei '$BINARY_SYMBOLS'"
            else
                pass "no Uttrflow object outside the allowed files can reach the network"
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
