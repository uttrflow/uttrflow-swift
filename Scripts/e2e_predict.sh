#!/bin/bash
# Drives tab-to-complete end to end in real applications, and only while nobody is at this Mac.
#
#   ./Scripts/e2e_predict.sh <report.md> [max-idle-wait-seconds] [scenario-name-regex]
#
# Needs Uttrflow-Dev.app running with its debug log streaming to $PREDICT_LOG (default
# /tmp/predict-log.txt), and Accessibility granted to the shell running this. It waits for the
# user to be idle 45 s, types only into scratch surfaces it opens itself — a Terminal window, untitled
# TextEdit documents, a Safari window's address bar, a Finder window's search field — never presses
# Return in a terminal, and stops with its windows closed the moment the user touches anything.
# Every scenario is a line of SCENARIOS; the step language is documented above that table.
set -euo pipefail

REPORT="${1:?usage: e2e_predict.sh <report.md> [max-idle-wait-seconds] [scenario-name-regex]}"
MAX_WAIT="${2:-1800}"
ONLY="${3:-.}"
LOG="${PREDICT_LOG:-/tmp/predict-log.txt}"
IDLE_REQUIRED=45
# Where the scratch Terminal window starts, so its corpus completions are the ones learned there; set PREDICT_CORPUS_DIR to yours.
CORPUS_DIR="${PREDICT_CORPUS_DIR:-$HOME}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TERM_ID=com.apple.Terminal
EDIT_ID=com.apple.TextEdit
SAFARI_ID=com.apple.Safari
FINDER_ID=com.apple.finder
GHOST_RE='(GENERATE .* got=[1-9][0-9]* |VERIFY .* out=[1-9][0-9]* )'

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
HELPER="$WORK/helper"
SHOTS="${REPORT%.md}-shots"
JSON="${REPORT%.md}.json"
LRM="$(printf '\xe2\x80\x8e')"
LONG230="The release notes for this build cover the new completion engine, the register hints, the warmed instruction prefix and the fixture set, and they run on for a good while so that the line is long enough to test the"
LONG270="${LONG230} panel and then keep going well past the cap the session enforces on a line"

# ---- run state ----------------------------------------------------------------------------------
LAST_SYNTH=0      # when the harness last posted a key, so a real keypress shows as idle shorter than that
T_LASTKEY=0       # when the last scenario key landed, which is what the ghost latency is measured from
MARK=0            # log line count when the scenario started, for counts and excerpts
KEY_MARK=0        # log line count at the last key or app switch, which waits search after
BASE_WINDOWS=""   # the app's layer-25 windows before typing, so a new one is the ghost
GHOST=""          # the ghost panel's bounds once seen
FOUND=""          # the log line the last wait matched
INDEX=0
TERM_WIN=""; TERM_WIN2=""; EDIT_DOCS=""; SAFARI_WAS_RUNNING=1; SAFARI_WIN=""; FINDER_WIN=""
SCN_NAME=""; SCN_APP=""; SCN_STATUS=""; SCN_ELAPSED=""; SCN_DETAIL=""; SCN_SHOT=""
STARTED="$(date '+%Y-%m-%d %H:%M:%S')"
IDLE_WAITED=0

# ---- small utilities ----------------------------------------------------------------------------
now() { "$HELPER" now; }
# Reads to the end rather than exiting awk early, so ioreg is never killed by SIGPIPE under pipefail.
idle_seconds() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ && !seen { print $NF / 1000000000; seen = 1 }'; }
fsub() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3f", a - b }'; }
flt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }
say() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
osa() { osascript -e "$1" 2>&1; }

# ---- the idle gate ------------------------------------------------------------------------------
wait_for_idle() {
  local start idle waited
  start="$(now)"
  say "waiting for the user to be idle ${IDLE_REQUIRED}s (giving up after ${MAX_WAIT}s)"
  while :; do
    idle="$(idle_seconds)"
    # A locked screen is idle too, and the login window must never be typed into, so it waits like a person would.
    if ! flt "$idle" "$IDLE_REQUIRED" && ! screen_locked; then
      LAST_SYNTH="$(now)"
      IDLE_WAITED="$(fsub "$LAST_SYNTH" "$start")"
      say "idle ${idle}s — starting"
      return 0
    fi
    waited="$(fsub "$(now)" "$start")"
    if flt "$MAX_WAIT" "$waited"; then return 1; fi
    sleep 5
  done
}

# Whether the screen is locked or the login window is in front, which no scenario may type into.
screen_locked() { [ "$("$HELPER" locked 2>/dev/null)" = "1" ]; }

# Aborts when the HID idle time is shorter than the time since our own last key, which only a person can cause, or when the screen has locked.
assert_idle() {
  local idle expected
  if screen_locked; then abort "the screen is locked, so nothing is typed"; fi
  idle="$(idle_seconds)"
  expected="$(fsub "$(now)" "$LAST_SYNTH")"
  if flt "$idle" "$(fsub "$expected" 1.0)"; then
    abort "the user is back: HID idle ${idle}s, but our last key was ${expected}s ago"
  fi
}

abort() {
  say "ABORT: $1"
  printf '%s\n' "$1" >"$WORK/aborted"
  [ -n "$SCN_NAME" ] && { SCN_STATUS=aborted; SCN_DETAIL="$1"; record_scenario; }
  exit 3
}

# ---- keys ---------------------------------------------------------------------------------------
note_key() { KEY_MARK="$(wc -l <"$LOG" | tr -d ' ')"; }
after_key() { LAST_SYNTH="$(now)"; T_LASTKEY="$LAST_SYNTH"; }

send_key() {
  assert_idle
  note_key
  "$HELPER" key "$1" ${2:+${2//,/ }}
  after_key
}

type_text() {
  assert_idle
  note_key
  "$HELPER" type "$1" "$2"
  after_key
}

pause_ms() {
  local left="$1"
  while [ "$left" -gt 0 ]; do
    assert_idle
    sleep "$(awk -v ms="$(( left < 500 ? left : 500 ))" 'BEGIN { printf "%.3f", ms / 1000 }')"
    left=$((left - 500))
  done
}

# ---- the log ------------------------------------------------------------------------------------
log_mark() { MARK="$(wc -l <"$LOG" | tr -d ' ')"; KEY_MARK="$MARK"; }
strip() { sed -E 's/ Db Uttrflow\[[^]]*\] \[com\.uttrflow\.Uttrflow:predict\]//'; }
log_since() { tail -n "+$(( $1 + 1 ))" "$LOG" | strip; }

# Waits for the first line after the last key matching an extended regex, into FOUND; with a third
# argument, only lines stamped at or after the last key count, so a burst's earlier passes are skipped.
log_wait() {
  local regex="$1" timeout="$2" after="${3:-}" deadline line
  deadline="$(fsub "$(now)" "-$timeout")"
  while :; do
    FOUND=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      if [ -z "$after" ] || [ "$(line_ms "$line")" -ge "$after" ]; then FOUND="$line"; break; fi
    done <<<"$(log_since "$KEY_MARK" | grep -E -- "$regex" || true)"
    [ -n "$FOUND" ] && return 0
    flt "$deadline" "$(now)" && return 1
    assert_idle
    sleep 0.1
  done
}

# The last key's own turn is stamped a few milliseconds after the key, so the cut sits just before it.
after_last_key_ms() { awk -v t="$T_LASTKEY" 'BEGIN { printf "%d", t * 1000 - 30 }'; }

line_ms() {
  local stamp="${1:0:23}" seconds
  seconds="$(date -j -f '%Y-%m-%d %H:%M:%S' "${stamp:0:19}" '+%s')"
  echo $(( seconds * 1000 + 10#${stamp:20:3} ))
}

elapsed_since_key() { awk -v a="$(line_ms "$1")" -v b="$T_LASTKEY" 'BEGIN { printf "%d", a - b * 1000 }'; }

# The loop ticks every second, so a log that has not moved in five is a loop that has stopped.
loop_alive() {
  local last age
  last="$(tail -n 1 "$LOG")"
  age=$(( $(date '+%s') * 1000 - $(line_ms "$last") ))
  [ "$age" -le 5000 ]
}

# ---- the ghost panel ----------------------------------------------------------------------------
layer25() { "$HELPER" windows "$APP_PID" | awk '$2 == 25'; }
window_baseline() { BASE_WINDOWS="$(layer25 | awk '{ print $1 }')"; }

ghost_bounds() {
  local number layer x y w h
  while read -r number layer x y w h; do
    [ -n "$layer" ] || continue
    [[ $'\n'"$BASE_WINDOWS"$'\n' == *$'\n'"$number"$'\n'* ]] || { echo "$x $y $w $h"; return; }
  done <<<"$(layer25)"
}

wait_ghost() {
  local deadline
  deadline="$(fsub "$(now)" "-$1")"
  while :; do
    GHOST="$(ghost_bounds)"
    [ -n "$GHOST" ] && return 0
    flt "$deadline" "$(now)" && return 1
    sleep 0.1
  done
}

wait_ghost_gone() {
  local deadline
  deadline="$(fsub "$(now)" "-$1")"
  while :; do
    [ -z "$(ghost_bounds)" ] && { GHOST=""; return 0; }
    flt "$deadline" "$(now)" && return 1
    sleep 0.1
  done
}

front_window_region() {
  osa 'tell application "System Events" to tell (first application process whose frontmost is true) to get {position, size} of front window' \
    | tr -d ' ' | awk -F, '{ print $1 "," $2 "," $3 "," $4 }'
}

# Captures the ghost and the line it sits on, or the front window when nothing is drawn.
shot() {
  local path="$SHOTS/$(printf '%02d' "$INDEX")-$SCN_NAME-$1.png" x y w h
  if [ -n "$GHOST" ]; then
    read -r x y w h <<<"$GHOST"
    screencapture -x -R "$((x - 360)),$((y - 40)),$((w + 420)),$((h + 80))" "$path"
  else
    screencapture -x -R "$(front_window_region)" "$path" 2>/dev/null || screencapture -x "$path"
  fi
  SCN_SHOT="$path"
}

# ---- applications -------------------------------------------------------------------------------
activate() { osa "tell application id \"$1\" to activate" >/dev/null; sleep 0.5; }

term_window() {
  local directory="$1" reply
  reply="$(osa "tell application \"Terminal\" to do script \"cd '$directory' && clear\"")"
  sleep 1.2
  echo "$reply" | sed -E 's/.*window id ([0-9]+).*/\1/'
}

term_front() {
  osa "tell application \"Terminal\" to set frontmost of window id $1 to true" >/dev/null
  activate "$TERM_ID"
}

# ⌃U empties the line, which is also what resets the field's typed-past count.
term_clear() { send_key 32 ctrl; sleep 0.4; }

edit_new() {
  local name
  name="$(osa 'tell application "TextEdit" to get name of (make new document)')"
  EDIT_DOCS="$name"$'\n'"$EDIT_DOCS"
  activate "$EDIT_ID"
  [ "${1:-}" = plain ] && edit_make_plain
  sleep 0.4
}

# ⇧⌘T converts the document, and TextEdit sometimes asks first; the sheet belongs to our own untitled document.
edit_make_plain() {
  send_key 17 cmd,shift
  sleep 0.6
  osa 'tell application "System Events" to tell process "TextEdit" to if exists sheet 1 of window 1 then click button "OK" of sheet 1 of window 1' >/dev/null
  sleep 0.4
}

edit_close_all() {
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && osa "tell application \"TextEdit\" to close document \"$name\" saving no" >/dev/null
  done <<<"$EDIT_DOCS"
  EDIT_DOCS=""
}

safari_open() {
  [ -n "$SAFARI_WIN" ] && return
  pgrep -xq Safari && SAFARI_WAS_RUNNING=1 || SAFARI_WAS_RUNNING=0
  osa 'tell application "Safari" to make new document' >/dev/null
  sleep "$([ "$SAFARI_WAS_RUNNING" = 1 ] && echo 1.5 || echo 4)"
  SAFARI_WIN="$(osa 'tell application "Safari" to get id of front window')"
}

safari_front() { osa "tell application \"Safari\" to set index of window id $SAFARI_WIN to 1" >/dev/null; activate "$SAFARI_ID"; }

safari_close() {
  [ -n "$SAFARI_WIN" ] || return 0
  osa "tell application \"Safari\" to close window id $SAFARI_WIN" >/dev/null
  [ "$SAFARI_WAS_RUNNING" = 0 ] && osa 'tell application "Safari" to quit' >/dev/null
  SAFARI_WIN=""
}

finder_open() {
  [ -n "$FINDER_WIN" ] && return
  osa "tell application \"Finder\" to get id of (make new Finder window to (POSIX file \"$WORK\" as alias))" >"$WORK/finder-id"
  FINDER_WIN="$(cat "$WORK/finder-id")"
  sleep 1
}

finder_front() { osa "tell application \"Finder\" to set index of Finder window id $FINDER_WIN to 1" >/dev/null; activate "$FINDER_ID"; }
finder_close() { [ -n "$FINDER_WIN" ] && osa "tell application \"Finder\" to close Finder window id $FINDER_WIN" >/dev/null; FINDER_WIN=""; }

# Empties a one-line field with select-all and delete — never ⎋⎋, which silences the field for the session.
field_clear() {
  send_key 0 cmd
  send_key 51
  sleep 0.3
}

bundle_of() {
  case "$1" in
    term|term2|cross) echo "$TERM_ID" ;;
    edit|edit-plain) echo "$EDIT_ID" ;;
    safari) echo "$SAFARI_ID" ;;
    finder) echo "$FINDER_ID" ;;
  esac
}

bring_front() {
  case "$1" in
    term) term_front "$TERM_WIN" ;;
    term2) term_front "$TERM_WIN2" ;;
    edit) activate "$EDIT_ID" ;;
    safari) safari_front ;;
    finder) finder_front ;;
  esac
  note_key
  LAST_SYNTH="$(now)"
}

setup() {
  case "$1" in
    term) [ -n "$TERM_WIN" ] || TERM_WIN="$(term_window "$CORPUS_DIR")"; bring_front term; term_clear ;;
    term2) [ -n "$TERM_WIN2" ] || TERM_WIN2="$(term_window "$WORK")"; bring_front term2; term_clear ;;
    edit) edit_new ;;
    edit-plain) edit_new plain ;;
    safari) safari_open; bring_front safari; send_key 37 cmd; sleep 0.4 ;;
    finder) finder_open; bring_front finder; send_key 3 cmd; sleep 0.6 ;;
    cross) edit_new; [ -n "$TERM_WIN" ] || TERM_WIN="$(term_window "$CORPUS_DIR")"; bring_front term; term_clear ;;
  esac
  sleep 0.5
  log_mark
  window_baseline
  GHOST=""
}

# Leaves every surface as it was found; on an abort only AppleScript runs, never a key.
cleanup() {
  [ -e "$WORK/aborted" ] && return 0
  case "$1" in
    term|term2) term_clear ;;
    edit|edit-plain) edit_close_all ;;
    safari) field_clear "$SAFARI_ID" ;;
    finder) field_clear "$FINDER_ID" ;;
    cross) term_clear; edit_close_all ;;
  esac
}

close_everything() {
  edit_close_all
  safari_close
  finder_close
  for window in "$TERM_WIN" "$TERM_WIN2"; do
    [ -n "$window" ] && osa "tell application \"Terminal\" to close window id $window" >/dev/null
  done
  return 0
}

# ---- assertions ---------------------------------------------------------------------------------
fail_scn() { SCN_STATUS=fail; SCN_DETAIL="$1"; [ -n "$SCN_SHOT" ] || shot fail; return 1; }
brief() { printf '%s' "${1:24}" | cut -c1-140; }

expect_ghost() {
  log_wait "$GHOST_RE" "$1" "$(after_last_key_ms)" || fail_scn "no GENERATE got>0 or VERIFY out>0 within ${1}s of the last key" || return 1
  SCN_ELAPSED="$(elapsed_since_key "$FOUND")"
  SCN_DETAIL="ghost after ${SCN_ELAPSED}ms: $(brief "$FOUND")"
  [ "$2" = log ] && return 0
  wait_ghost 1.5 || fail_scn "log drew a suggestion but no panel appeared: $(brief "$FOUND")"
}

expect_regex() {
  log_wait "$1" "$2" || fail_scn "no log line matching /$1/ within ${2}s" || return 1
  SCN_DETAIL="$(brief "$FOUND")"
}

expect_first() {
  log_wait "$1" "$3" || fail_scn "no /$1/ line within ${3}s of the switch" || return 1
  printf '%s' "$FOUND" | grep -Eq -- "$2" || fail_scn "first pass after the switch was not for the new field: $(brief "$FOUND")" || return 1
  SCN_DETAIL="$(brief "$FOUND")"
}

expect_absent() {
  pause_ms "$(awk -v s="$2" 'BEGIN { printf "%d", s * 1000 }')"
  local hit
  hit="$(log_since "$KEY_MARK" | grep -E -m1 -- "$1" || true)"
  [ -z "$hit" ] || fail_scn "unexpected within ${2}s: $(brief "$hit")"
}

expect_count() {
  local n
  n="$(log_since "$MARK" | grep -Ec -- "$1" || true)"
  [ "$n" -le "$2" ] || fail_scn "$n lines matched /$1/, at most $2 allowed" || return 1
  SCN_DETAIL="${SCN_DETAIL:+$SCN_DETAIL; }$n × /$1/"
}

expect_readback() {
  local text
  text="$("$HELPER" read "$(bundle_of "$SCN_APP")" "$1")"
  printf '%s' "$text" | grep -Eq -- "$2" || fail_scn "field reads back [$(printf '%s' "$text" | tail -c 120)], wanted /$2/" || return 1
  SCN_DETAIL="${SCN_DETAIL:+$SCN_DETAIL; }reads back: $(printf '%s' "$text" | tail -c 60)"
}

expect_gone() { wait_ghost_gone "$1" || fail_scn "the ghost panel is still on screen ${1}s later"; }

# ---- the step language --------------------------------------------------------------------------
#   t:MS:TEXT           type TEXT at MS per character           k:CODE[:mod,mod]  press a key (cmd ctrl opt shift)
#   p:MS                pause                                    front:APP         bring an open surface to the front
#   eg:S | el:S         a ghost within S s of the last key (el: log line only, no panel check)
#   ex:REGEX:S          a log line matching REGEX within S s     first:KIND:MUST:S first KIND line after the switch matches MUST
#   eq:REASON:S         a QUIET with that reason within S s      nx:REGEX:S        nothing matching REGEX in the next S s
#   count:REGEX:MAX     at most MAX matches since the scenario began
#   rb:FIELD:REGEX      the focused field's FIELD (line|value) matches REGEX
#   gone:S              the ghost panel leaves within S s        shot:LABEL        screenshot for the report
run_step() {
  local kind a b c
  IFS=: read -r kind a b c <<<"$1"
  case "$kind" in
    t) IFS=: read -r _ a b <<<"$1"; type_text "$a" "$b" ;;
    p) pause_ms "$a" ;;
    k) send_key "$a" "${b:-}" ;;
    front) bring_front "$a"; sleep 0.3 ;;
    eg) expect_ghost "$a" panel ;;
    el) expect_ghost "$a" log ;;
    ex) expect_regex "$a" "$b" ;;
    first) expect_first "$a" "$b" "$c" ;;
    eq) expect_regex "QUIET .*reason=$a( |$)" "$b" ;;
    nx) expect_absent "$a" "$b" ;;
    count) expect_count "$a" "$b" ;;
    rb) expect_readback "$a" "$b" ;;
    gone) expect_gone "$a" ;;
    shot) shot "$a" ;;
    *) fail_scn "unknown step '$1'" ;;
  esac
}

# ---- scenarios: name | surface | steps ----------------------------------------------------------
SCENARIOS=(
  "term-git-c-accept|term|t:25:git c; eg:3; shot:ghost; k:124; p:700; ex:ACCEPT text=git .* via=:2; rb:line: git [a-z-]{2,}( .*)?$"
  "term-ls-has-corpus|term|t:25:ls; ex:QUERY typed=ls corpus=[1-9]:3; ex:VERIFY typed=ls in=[1-9]:3"
  "term-fast-burst-then-pause|term|t:12:git ch; eg:3"
  "term-slow-typing|term|t:220:git st; eg:3"
  "term-git-s-accept|term|t:25:git s; eg:3; k:124; p:700; ex:ACCEPT text=git [a-z-]+.* typed=git s via=:2; rb:line: git [a-z-]{2,}( .*)?$"
  "term-typed-past-3x-goes-quiet|term|t:25:git c; el:3; t:25:x; p:900; k:51; el:3; t:25:z; p:900; k:51; el:3; t:25:q; ex:QUIET typed=git cq .*rejections=3:3"
  "term-double-space-then-backspace|term|t:25:git c; eg:3; k:49; k:49; p:600; k:51; k:51; eg:3; count:rejectedTooOften:0"
  "term-ctrl-u-then-new-line|term|t:25:git c; eg:3; k:32:ctrl; gone:1.5; t:25:git c; eg:3"
  "term-finished-command-one-pass|term|t:25:ls -la; ex:(GENERATE|VERIFY|QUIET) typed=ls -la:4; p:5000; count:GENERATE .*typed=ls -la .*elapsed=[1-9][0-9]{2,}ms:1"
  "term-single-char-no-model-pass|term|t:25:g; ex:(QUERY|QUIET) typed=g:2; nx:GENERATE .*typed=g :2"
  "loop-tick-alive|term|p:2500; ex:TURN front=:3"
  "edit-prose-pause-rich|edit|t:15:Deploy the re; ex:QUIET typed=Deploy .*writingFluently:2; ex:QUERY typed=Deploy the re corpus=:3; eg:3; shot:ghost-rich"
  "edit-prose-pause-plain|edit-plain|t:15:Deploy the re; ex:QUIET typed=Deploy .*writingFluently:2; eg:3; shot:ghost-plain"
  "edit-tab-accepts|edit|t:15:Deploy the re; eg:3; k:48; p:800; ex:ACCEPT text=Deploy the re.* via=:2; rb:value:^Deploy the re[a-z].{3,}"
  "edit-mixed-rhythm|edit|t:200:Deploy; t:12: the re; eg:3"
  "edit-down-opens-list-escape-collapses|edit|t:15:I hope this message; el:6; ex:ALTERNATIVES typed=I hope this message got=[1-9]:8; k:125; ex:SWALLOWED key=downArrow .*decision=redraw:3; shot:list; k:53; ex:SWALLOWED key=escape .*decision=redraw:2"
  "edit-trademark-line|edit|t:15:The Acme™ product ships; ex:GENERATE .*typed=.*Acme™ product ships got=:6"
  "edit-lrm-prefixed-word|edit|t:15:${LRM}Deploy the re; el:4"
  "edit-emoji-line|edit|t:15:Let us ship 🚀 today and; ex:GENERATE .*typed=.*🚀.* got=:6"
  "edit-long-line-230|edit|t:6:${LONG230}; ex:GENERATE .*typed=.{200,} got=:6"
  "edit-line-over-256-silent|edit|t:5:${LONG270}; ex:QUIET typed=.{240,} reason=lineTooLong:3; nx:(QUERY|GENERATE) .*typed=.{240,}:1"
  "edit-typed-past-generated-5x-no-silence|edit|t:15:I wanted to let you know; el:6; t:15:x; p:300; k:51; t:15:y; p:300; k:51; t:15:z; p:300; k:51; t:15:w; p:300; k:51; t:15:v; p:800; count:rejectedTooOften:0"
  "edit-caret-inside-text-quiet|edit|t:15:Deploy the re; el:3; k:123; eq:caretInsideText:2"
  "safari-git-ghost|safari|t:25:git; el:5; ex:GENERATE .*typed=git got=[1-9]:5"
  "safari-lin-ghost|safari|t:25:lin; el:5; ex:GENERATE .*typed=lin got=[1-9]:5"
  "safari-escape-dismisses|safari|t:25:git; eg:4; k:53; ex:SWALLOWED key=escape .*decision=redraw:2; nx:SWALLOWED key=return:1"
  "finder-search-short-query|finder|t:25:readme; ex:(GENERATE .*got=[1-9]|VERIFY .*out=[1-9]|QUIET typed=readme reason=[a-zA-Z]|TURN front=com.apple.finder .*placement=nil):4"
  "cross-terminal-textedit-terminal|cross|t:25:git c; eg:3; front:edit; gone:1.5; t:15:Deploy the re; first:(GENERATE|VERIFY|QUERY) typed=:typed=Deploy the re:3; front:term; first:(GENERATE|VERIFY|QUERY) typed=:typed=git c:3"
)

# ---- running and recording ----------------------------------------------------------------------
record_scenario() {
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$INDEX" "$SCN_NAME" "$SCN_APP" "$SCN_STATUS" "${SCN_ELAPSED:--}" "$SCN_DETAIL" "$SCN_SHOT" >>"$WORK/rows.tsv"
  log_since "$MARK" | tail -n 60 >"$WORK/excerpt-$INDEX.txt"
  say "[$INDEX] $SCN_NAME → $SCN_STATUS${SCN_ELAPSED:+ (${SCN_ELAPSED}ms)}: $SCN_DETAIL"
  SCN_NAME=""
}

run_scenario() {
  local steps step
  IFS='|' read -r SCN_NAME SCN_APP steps <<<"$1"
  INDEX=$((INDEX + 1))
  SCN_STATUS=pass; SCN_ELAPSED=""; SCN_DETAIL=""; SCN_SHOT=""
  say "[$INDEX] $SCN_NAME"
  assert_idle
  setup "$SCN_APP"
  IFS=';' read -ra steps <<<"$steps"
  for step in "${steps[@]}"; do
    step="${step# }"
    run_step "$step" || break
  done
  cleanup "$SCN_APP"
  loop_alive || { SCN_STATUS=fail; SCN_DETAIL="LOOP DEAD: the log has not advanced in 5 s. $SCN_DETAIL"; }
  record_scenario
  [ "$SCN_STATUS" = fail ] && [[ "$SCN_DETAIL" == LOOP\ DEAD* ]] && abort "the suggestion loop stopped ticking"
  return 0
}

write_report() {
  local passed failed aborted total reason
  total="$(wc -l <"$WORK/rows.tsv" | tr -d ' ')"
  passed="$(awk -F'\t' '$4 == "pass"' "$WORK/rows.tsv" | wc -l | tr -d ' ')"
  failed="$(awk -F'\t' '$4 == "fail"' "$WORK/rows.tsv" | wc -l | tr -d ' ')"
  aborted="$(awk -F'\t' '$4 == "aborted"' "$WORK/rows.tsv" | wc -l | tr -d ' ')"
  reason="$(cat "$WORK/aborted" 2>/dev/null || true)"
  {
    echo "# Tab-to-complete live end-to-end run — $STARTED"
    echo
    echo "- App pid $APP_PID, log \`$LOG\`, idle gate waited ${IDLE_WAITED}s, ${#SCENARIOS[@]} scenarios declared, $total run."
    echo "- **$passed passed, $failed failed, $aborted aborted.**${reason:+ Run aborted: $reason}"
    echo
    echo "| # | scenario | surface | result | last key → ghost | detail |"
    echo "|---|---|---|---|---|---|"
    awk -F'\t' '{ gsub(/\|/, "\\|", $6); printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, toupper($4), ($5 == "-" ? "" : $5 " ms"), $6 }' "$WORK/rows.tsv"
    echo
    echo "## Per scenario"
    while IFS=$'\t' read -r index name app status elapsed detail screenshot; do
      echo; echo "### $index. $name ($app) — $status"
      echo; echo "$detail"
      [ -n "$screenshot" ] && { echo; echo "Screenshot: \`$screenshot\`"; }
      echo; echo '```'; cat "$WORK/excerpt-$index.txt"; echo '```'
    done <"$WORK/rows.tsv"
  } >"$REPORT"
  python3 - "$WORK/rows.tsv" "$JSON" "$STARTED" "$LOG" "$APP_PID" "$IDLE_WAITED" "$reason" <<'EOF'
import csv, json, sys
rows, out, started, log, pid, waited, reason = sys.argv[1:8]
scenarios = []
with open(rows, newline="") as handle:
    for index, name, app, status, elapsed, detail, shot in csv.reader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
        scenarios.append({"index": int(index), "name": name, "surface": app, "status": status,
                          "ghost_ms": None if elapsed == "-" else int(elapsed), "detail": detail, "screenshot": shot or None})
totals = {s: sum(1 for x in scenarios if x["status"] == s) for s in ("pass", "fail", "aborted")}
json.dump({"started": started, "log": log, "app_pid": int(pid), "idle_gate_waited_s": float(waited),
           "aborted_reason": reason or None, "totals": totals, "scenarios": scenarios}, open(out, "w"), indent=1, ensure_ascii=False)
EOF
  say "report: $REPORT"
  say "json:   $JSON"
}

# Runs once on exit, tolerating errors so a partial or aborted run still closes its windows and writes a report.
finish() {
  trap - EXIT
  set +e
  close_everything
  [ -s "$WORK/rows.tsv" ] && write_report
  rm -f "$WORK"/excerpt-*.txt "$WORK/rows.tsv" "$WORK/finder-id"
}

# ---- main ---------------------------------------------------------------------------------------
[ -r "$LOG" ] || { echo "no log at $LOG — start: log stream --level debug --predicate 'subsystem == \"com.uttrflow.Uttrflow\"' --style compact >> $LOG" >&2; exit 2; }
APP_PID="$(pgrep -f 'Uttrflow-Dev.app/Contents/MacOS/Uttrflow' | head -n 1)" || true
[ -n "$APP_PID" ] || { echo "Uttrflow-Dev.app is not running" >&2; exit 2; }
[ -d "$CORPUS_DIR" ] || { echo "no corpus directory at $CORPUS_DIR" >&2; exit 2; }
mkdir -p "$SHOTS" "$(dirname "$REPORT")"
xcrun swiftc -O "$HERE/e2e_predict_helper.swift" -o "$HELPER"
: >"$WORK/rows.tsv"
trap finish EXIT

wait_for_idle || { echo "the user was never idle ${IDLE_REQUIRED}s within ${MAX_WAIT}s; nothing was run" >&2; exit 4; }
loop_alive || { echo "the log at $LOG has not advanced in 5 s; is the app running and the stream attached?" >&2; exit 2; }

for scenario in "${SCENARIOS[@]}"; do
  [[ "${scenario%%|*}" =~ $ONLY ]] || continue
  run_scenario "$scenario"
  sleep 1
done
