#!/usr/bin/env bash
# Watches a running Uttrflow for the accumulate-then-unwind shape in #140: takes `heap`
# snapshots on a clock and reports which classes grew between the first and the last.
#
#   ./Scripts/soak.sh                    # 6 samples, 10 minutes apart, on the running app
#   ./Scripts/soak.sh --every 60 --times 3
#   ./Scripts/soak.sh --pid 1234
#
# Leave the app running and used — dictations, and suggestions on, since the twelve-hour
# crash had them enabled. A class whose count only ever rises is the chain to look at.
set -euo pipefail

EVERY=600
TIMES=6
PID=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --every) EVERY="$2"; shift 2 ;;
        --times) TIMES="$2"; shift 2 ;;
        --pid) PID="$2"; shift 2 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
done

[[ -n "$PID" ]] || PID="$(pgrep -x Uttrflow | head -1 || true)"
[[ -n "$PID" ]] || { printf 'Uttrflow is not running, and no --pid was given.\n' >&2; exit 1; }

OUT="dist/soak-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
printf 'pid %s, %s samples %ss apart, into %s\n' "$PID" "$TIMES" "$EVERY" "$OUT"

# One sample: the class table, as `count<tab>class`, plus the footprint beside it.
sample() {
    local n="$1"
    local file="$OUT/sample-$n.tsv"
    # Only the first table, and the class name read by column so one with a space in it survives.
    heap "$PID" 2>/dev/null \
        | awk '
            /^ *COUNT +BYTES +AVG +CLASS_NAME/ {
                name = index($0, "CLASS_NAME"); type = index($0, "TYPE"); on = 1; next
            }
            on && $1 !~ /^[0-9]+$/ { if (seen) exit; next }
            on {
                width = (type > name) ? type - name : 200
                label = substr($0, name, width)
                gsub(/^[ \t]+|[ \t]+$/, "", label)
                if (label != "") { print $1 "\t" label; seen = 1 }
            }' \
        | sort -u -k2,2 > "$file"
    local footprint=""
    footprint="$(heap "$PID" 2>/dev/null | awk -F: '/^Physical footprint:/ {gsub(/ /,"",$2); print $2}')"
    printf '%s\t%s\t%s\n' "$(date +%H:%M:%S)" "$footprint" "$(awk -F'\t' '{s+=$1} END {print s}' "$file")" \
        >> "$OUT/footprint.tsv"
    printf '  sample %s: footprint %s\n' "$n" "$footprint"
}

for ((i = 1; i <= TIMES; i++)); do
    kill -0 "$PID" 2>/dev/null || { printf 'the process is gone; stopping.\n' >&2; break; }
    sample "$i"
    [[ $i -lt $TIMES ]] && sleep "$EVERY"
done

FIRST="$OUT/sample-1.tsv"
LAST="$(ls "$OUT"/sample-*.tsv | sort -V | tail -1)"
[[ "$FIRST" != "$LAST" ]] || { printf 'only one sample; nothing to compare.\n'; exit 0; }

printf '\nGrew most between the first sample and the last:\n\n'
join -j 2 -o 0,1.1,2.1 -t $'\t' "$FIRST" "$LAST" \
    | awk -F'\t' '{ d = $3 - $2; if (d > 0) printf "%12d  %10d → %-10d  %s\n", d, $2, $3, $1 }' \
    | sort -rn | head -20

printf '\nFootprint over the run (time, footprint, live nodes):\n'
cat "$OUT/footprint.tsv"
printf '\nA count that only rises is the chain #140 unwinds. Snapshots kept in %s\n' "$OUT"
