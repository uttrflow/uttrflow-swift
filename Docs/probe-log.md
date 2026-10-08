# Probe log — where, when and on which build every number was measured

A number in `compatibility.md`, `performance.md` or any other page is true of one Mac, one
build and one moment. Without those three it reads as true everywhere and forever: a figure
from a 48 GB machine is taken as the 8 GB answer, and a stale figure looks current. Every probe
result is therefore recorded here, in one table format, and the page that quotes the number
cites its row.

## The format

| Issue | Date | Host class | Chip | Memory | OS | Build | Command | Result |
|---|---|---|---|--:|---|---|---|---|

- **Issue** — the issue the measurement answers, or `—`.
- **Date** — the day it was taken, `YYYY-MM-DD`, in the measurer's time zone.
- **Host class** — every class below the host belonged to, then the one-minute load average
  and the active cores it was read against.
- **Chip and OS** — as `MachineDescription.current()` reports them. **Memory** — physical memory rounded down to whole GiB and labelled `GB` by `ProbeLogRow`.
- **Build** — configuration and commit; `+dirty` when tracked files had uncommitted changes (the status check excludes untracked files).
- **Command** — what was run, with the binary named rather than located.
- **Result** — the figures, on one line.

Every `uttrflow-dev probe` subcommand prints its row after its own output, ready to paste.
Pass `--issue N` to fill the first column. The row is built by `ProbeLogRow` in
`Sources/UttrflowEval/ProbeLogRow.swift`, the single home of the format; a measurement taken
by any other tool is written in the same columns by hand. Keep raw dated rows here: probe
commands explicitly print this destination, and measurement pages cite the row while keeping
their interpretation beside the relevant feature.

**A new probe issue's acceptance includes its row here**, and the page the result lands on
cites the row by issue and date.

## The hosts

Budgets are stated against four classes. Two are the hardware and one is the moment, and all
three are derived by `HostClass`; the fourth is the audio route, which no probe reads today.

| Class | Meaning | How it is decided |
|---|---|---|
| minimum-spec | the smallest Mac the budgets are written for | memory at or under `HostClass.minimumSpecBytes` |
| base chip | the base chip of a generation, no Pro, Max or Ultra | chip is `Apple <name>` with no word in `HostClass.chipTiers` |
| quiet | nothing was waiting for a core | one-minute load average below the active core count; an unread load is never quiet |
| Bluetooth headset | the input was a Bluetooth headset | stated by the measurer in the Result cell; not read by any probe |

A row on none of the classes is still a valid row: it is a measurement on a large, loaded
machine, and says so.

## Rows

| Issue | Date | Host class | Chip | Memory | OS | Build | Command | Result |
|---|---|---|---|--:|---|---|---|---|
| #3751 | 2026-10-03 | load 274.4 on 18 cores | Apple M5 Pro | 48 GB | macOS Version 26.5.1 (Build 25F80) | release d011ea0e5+dirty | `uttrflow-dev probe retrieval --issue 3751` | 50000 entries: range scan 7.4 µs, LIKE 30.9 µs, fuzzy 36658.0 µs, 6-byte mask 754.4 µs, 12-byte mask 3409.2 µs |
| — | 2026-09-03 | not recorded | Apple M5 Pro | not recorded | not recorded | release, commit not recorded | `uttrflow-dev probe retrieval` | 50000 entries: range scan 4.7 µs, LIKE 19.8 µs, fuzzy 7128 µs, 6-byte mask 478 µs, 12-byte mask 1764 µs |
| — | 2026-09-21 | not recorded | not recorded | not recorded | macOS 26.5.1 | not recorded | `uttrflow-dev transcribe` on three seconds of digital silence | `SpeechEngineError.nothingHeard` |
| #2336 | 2026-10-08 | load 31.9 on 18 cores | Apple M5 Pro | 48 GB | macOS 26.5.1 (Build 25F80) | no build; tree at 5442d6bb10 | one-off `numpy` script on `say` clips, method in [silence.md](silence.md#a-second-voice-after-the-last-word-is-not-trimmed) | held-out half: foreign reply removed 453 of 1536 (29.5%); user's own reply cut 4 of 1536; joined or lone sentence cut 0 of 224 |

The first row re-takes the retrieval table of [predict-probe.md](predict-probe.md), whose
original is the second row, transcribed from that page with the columns it never recorded
marked as such. The re-take ran under a load average of 274 on 18 cores, and every figure
came out slower — fuzzy matching five times so — while every ratio the page's decision rests
on held: the range scan is still about four times faster than `LIKE`, and the 6-byte mask
still the fastest prefilter. Without the load column the two rows would read as a regression.

The third row is the silence measurement in [audio-capture.md](audio-capture.md), transcribed
the same way. Re-taking it needs the speech model installed, which the host of the first row
did not have.
