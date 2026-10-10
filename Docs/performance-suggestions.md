# What AI suggestions cost a Mac

With AI suggestions on, tab-to-complete runs Gemma 3 4B (QAT) on MLX in-process to propose the
rest of a line. That model is the largest thing Uttrflow can hold, so this page covers how its
memory is bounded, released and reloaded, and what one suggestion pass costs. The model is driven
by `MLXCandidateScorer` and loaded through `ReloadableWeights` and `QuantizedLoad`
(`Sources/UttrflowLocalModel/`); release and reload are `IdleReleasingModel`, `IdleRelease` and
`DiscretionaryGenerator` (`Sources/UttrflowPredict/`); the app wires them in `AppDelegate` and
`SuggestionCoordinator` (`Sources/Uttrflow/`). The budget lines are in
[`performance.md`](performance.md); how suggestions are chosen is in [`predict.md`](predict.md).

## GPU memory, pass by pass

MLX keeps every buffer it frees in a cache for reuse, reuses one only for a request of nearly the
same size, and by default empties the cache only near most of the GPU's working set — tens of
gigabytes on a 48 GB Mac. Every suggestion pass reads a prompt of a different length, so left
alone every pass leaves buffers nothing can reuse (one app grew from 2.9 GB to 12 GB in forty
minutes of typing).

`GPUBufferCache` caps that cache at 256 MB (`GPUBufferCache.limit`) for the process, and every
pass through `MLXCandidateScorer` — a generation, an alternatives pass, a score — empties it when
the pass ends, however it ends, a tidying rewrite included.

Measured with `uttrflow-bakeoff gpu-memory` (Release, 48 GB Apple silicon): forty passes over
invented message threads of 120–310 words, every fourth cancelled part-way, each followed by one
score. MLX's own counters, in MB, without the cap and emptying, then with them:

| after | active, uncapped | cache, uncapped | peak, uncapped | active | cache | peak |
|---|---|---|---|---|---|---|
| loading | 2,485 | 218 | 2,701 | 2,485 | 218 | 2,701 |
| pass 1 | 2,485 | 807 | 2,907 | 2,541 | 0 | 2,843 |
| pass 10 | 2,485 | 3,931 | 3,041 | 2,485 | 0 | 3,036 |
| pass 40 | 2,485 | 9,565 | 3,111 | 2,485 | 0 | 3,036 |
| 5 s idle | 2,485 | 9,565 | 3,111 | 2,485 | 0 | 3,036 |

- **The bound is the weights plus one pass.** The weights hold 2,485 MB, one pass needs about
  550 MB more at its peak, and the cache holds nothing once a pass has ended. The worst reading
  between passes was 86 MB, from buffers a cancelled pass freed after it returned.
- **It costs a pass no measurable time.** Paired runs of forty passes, binaries alternating, gave
  medians within the run-to-run spread (647 against 661 ms, 762 against 653 ms, 640 against
  628 ms).
- **Either half alone leaves memory behind.** A 1 GB cap without emptying held 1,024 MB after every
  run; emptying without a cap left 107 MB behind a cancelled pass.

The scorer's CPU-side judgement cache keeps one `Float` per candidate token and one optional
prefix log-mass per token position, never a vocabulary row per position: for a 262,000-token
vocabulary and a 20-token candidate that is at most 160 bytes of payload, and 2.6 KB across the
16-entry cache (calculated payload, not a process reading).

### Token prefix index

The opt-in `TokenHealingPerformanceTests` probe measures a generated 262,144-entry vocabulary
whose tokens are fixed-width five-byte ASCII strings. The latest recorded debug run on arm64e macOS
compared the original implementation with the sorted-ID prefix index:

| implementation | vocabulary init | first prefix lookup | combined footprint delta |
|---|---:|---:|---:|
| prefix dictionary | 1,113 ms | under 1 ms | 55.5 MiB |
| sorted-ID index, earlier run | 419 ms | 233 ms | 27.3 MiB |
| compact two-byte buckets, full candidate selection | 273 ms | 147 ms | 24.4 MiB |

The sorted-ID radix-sort experiment later measured 246 ms for initialization and 866 ms for its
first lookup, or 1,112 ms combined, with a 29.8 MiB footprint delta. It failed the 500 ms timing
limit while remaining within the 32 MiB memory limit. The current compact index builds one-byte or
two-byte buckets on first use; longer prefixes filter the matching two-byte bucket. The opt-in
debug probe exercises `allowedIDs` with a five-byte owed token, including shorter-prefix queries
and candidate filtering. It measured 273 ms initialization plus 147 ms for first candidate
selection, or 420 ms combined, with a 24.4 MiB footprint delta. It meets the synthetic 500 ms and
32 MiB budgets. These are synthetic debug measurements, not measurements of the pinned Gemma
vocabulary, release performance, or reload latency inside a live app.

## Turning it off gives the memory back

`AppDelegate` releases the model when the switch goes off or memory is pressed. A load still
running is stopped first rather than waited out: the download is cancelled and the weights are not
read, or, when the read had begun, not kept. Then `MLXCandidateScorer.release()` swaps the weights
out (keeping the modules and tokenizer, [`performance-leaks.md`](performance-leaks.md)), drops the
warmed instructions, the vocabulary and the kept prompt cache, and empties MLX's cache. A release
from the switch or memory pressure also empties the queried one-byte and two-byte prefix buckets;
only an idle release keeps them, so the reload a query brings reuses those indexes. The measurements below
predate this retained index and remain the model/Metal release baseline, not the current scorer
footprint. Measured with `uttrflow-bakeoff gpu-memory --release`:

| | MLX active | process footprint |
|---|---|---|
| loaded, after six passes and 5 s idle | 2,485 MB | 2,677 MB |
| one second after `release()` | 0 MB | 190 MB |

The 190 MB left is the process with MLX and Metal initialised. Turning the feature back on reads
the weights from disk again: 3.2 s and 4.4 s in two runs, back to 2,485 MB active.

## When nothing is being typed

`IdleReleasingModel` lets the weights go when no suggestion has asked for the model within
`IdleRelease.window(physicalMemory:)`: `tight` (180 s) on a Mac with less than 16 GB, `roomy`
(600 s) otherwise. The next query in a supported field loads it again in the background; that
moment's model suggestion stays quiet, as during any load, and remembered completions are
unaffected. A release made by turning the switch off is never undone by a query. So
on a small Mac the 3 GB is held while somebody is typing, not through a meeting or a film.

That reload reads the weights from disk and nothing else: `ReleasableModel.reload()` passes no
downloader, so a cache that is no longer whole — removed, cut short, or a first download left
unfinished — throws `WeightsNotOnDisk` rather than start a fetch of several gigabytes nobody asked
for. Only that error shows the model as needing to be fetched again; any other failure, such as too
little memory to read the weights in, shows as a load failure. The next query reloads from disk
again; after two failures in a row each further reload waits 120 seconds, doubling up to 1,800, and
an explicit prepare, release or calm after memory pressure clears the wait. A reload that holds
shows the model ready. Only turning the switch on, which shows progress, downloads.

## Under memory pressure

`MemoryPressureSource` watches the kernel's pressure events. At a warning or critical reading
`AppDelegate` releases the suggestion model the same way, and the AI suggestions screen says it is
paused to free memory. Once pressure is back to normal the model waits for the calm to last before
it is eligible for a reload: `ModelMemoryPressure` starts at 120 s (`firstWait`) and doubles,
up to 1,800 s (`longestWait`), each time a query-driven reload is followed by pressure within that
longest wait; a reload that holds for it starts the wait over. Weights stay unloaded until the next
suggestion query, so an idle Mac does not load them just because pressure cleared. If pressure
interrupts the first download, the app waits for the same calm period and retries through the
download-capable preparation path; it does not use the disk-only query reload for incomplete
weights. Without the wait, the 3 s reload of 2.5 GB pushes a small Mac straight back into pressure
and the model loads and drops in a loop.

## What a pass costs: the prompt's tokens

`PromptTokens` tokenises the chat template's frame once, when the model loads, and each line of the
message once, keyed by its exact bytes; a pass pays only for the lines that changed. It is
token-identical to tokenising the whole template because every break it cuts at is a hard boundary
for this tokenizer: `\n` is an added token, every added token holding a line break is only line
breaks, none swallows whitespace, and the frame's edges are added tokens no first or last
character of the message can join. It checks each of those at load against `tokenizer.json` and
probe messages, and tokenises whole any message it cannot vouch for. `PromptTokensTests` holds it
to the whole template over 3,000 random messages of boundary characters with a shared cache, and
over Gemma 3's own tokenizer where it is on disk (`UTTRFLOW_TOKENIZER_PROOF`). The keys are bytes
because Swift calls the two spellings of "é" one string and the tokenizer does not.

Tokenising the whole prompt every pass is not used. The tokenizer splits text on its added tokens
with one alternation regex, Gemma 3 declares 6,415 of them, and `sample` put 35% of all on-CPU
samples in that regex. Measured on one Release binary with the cache switched off by a local
environment variable, 100 passes each, every fourth cancelled, one score a pass:

| harness | processor a pass, whole → `PromptTokens` | tokenising a pass | pass p50 / p95 |
|---|---|---|---|
| `gpu-memory --typing`: one reply typed a character a pass under one screen | 1.54–1.93 s → 0.31–0.32 s | 1,111–1,494 ms → 6–7 ms | 2,244 / 2,565 ms → 425 / 828 ms |
| `gpu-memory`: a different screen every pass | 0.92–0.96 s → 0.38–0.40 s | 587–615 ms → 50–54 ms | 1,122 / 1,578 ms → 550 / 1,128 ms |

All 75 completed passes of every run returned the same lines either way. Over all 1,154
`complete --fixtures` fixtures, back to back: 1,086 processor-seconds whole against 192, so 0.94
against 0.17 a pass, p50 1,166 against 207 ms, every line identical.

### The score's opening

`judgedTokens` tokenises a candidate once. `ScoredSpan.divergence(whole:continuation:bytes:)`
walks the line's last tokens back until their bytes have written what the line adds past what was
typed, which gives the first judged index and the typed remainder from one encoding. A vocabulary
those bytes cannot spell the continuation back through still tokenises the opening — which is what
a pass arriving before the byte table has been read finds. `ScoredSpanTests` holds the two
readings to each other over Gemma 3's own tokenizer.

Tokenising the typed opening a second time is not used; it cost about 100 ms a pass through the
same regex. `gpu-memory --typing --passes 100`, builds interleaved: 136–194 ms a pass and p50 /
p95 245 / 290 ms tokenising twice, 107–110 ms and 201 / 251 ms once. One score alone, over the 30
candidates `uttrflow-bakeoff score` judges: 103 ms median tokenising twice, 69 ms once, all 30
scored identically per judged token. The remaining regex pass is the one encoding a score cannot
avoid, and lives in the tokenizer dependency.

## What a pass prefills

Consecutive keystrokes on one line ask almost the same question. `CompletionPromptBuilder.message` puts the
stable parts first — where the caret is, the screen around it, this person's earlier lines, the
text before the line — and the typed line last, so one keystroke's prompt shares all but its last
tokens with the one before.

`MLXCandidateScorer` keeps the last pass's prompt tokens and the `[KVCache]` they were read into.
The next pass takes the longest run of tokens the two prompts share, trims the kept cache back to
it and reads only the rest, falling back to a copy of the warm instructions when the shared run is
no longer than those and to a whole prefill when the cache cannot be trimmed. The last shared token
is always read again, since the model answers from the token it has just read. The kept cache is
handed to one pass at a time — taken out of the actor when a pass adopts it, put back when that
pass's decode has stopped — so two overlapping passes never write one cache, and it is dropped on
release, on memory pressure and on a reload.

`gpu-memory --typing --passes 50 --cancel-every 0`, Release, six rounds per build interleaved,
against a whole prefill after the warm instructions:

| | prompt tokens | read a pass | prefill p50, six rounds | pass p50, six rounds |
|---|--:|--:|--:|--:|
| whole prefill | 328 | 123 | 65, 66, 71, 74, 90, 97 ms | 229, 230, 236, 245, 307, 608 ms |
| kept cache | 328 | 11–15 | 45, 46, 46, 52, 55, 70 ms | 204, 206, 208, 228, 239, 428 ms |

- **The shared run is almost the whole prompt.** Of 328 tokens, 315 at p50 were shared with the
  previous keystroke's prompt, 110 of them past the 205-token instruction prefix.
- **It saves about 20–25 ms a pass**, on every keystroke's pass and again on its alternatives pass.
  `promptTime` counts the first decode step as well as the prefill, which is why reading 11 tokens
  costs 45 ms rather than nothing. On the browser moments in
  [`predict-context.md`](predict-context.md) a whole pass is 902–1,160 ms, because those decode
  forty to ninety tokens, so the share saved is smaller there.
- **It holds 91 MB of GPU memory between passes**: MLX active memory after fifty passes is 2,576 MB
  against 2,485 MB, process footprint 2,932 MB against 2,841 MB. `gpu-memory --typing` reads
  `suggestionsBetweenPasses` at 3,169–3,201 MB with the kept cache against the 3,072 MB line in
  [the budget](performance.md#the-budget), so that line is exceeded while somebody is typing.
- **It can change an answer that was a near tie.** The last tokens are read in a batch of eleven
  rather than 123, and bf16 rounds a small batch differently, so a temperature-0 near tie can fall
  the other way. Over the 1,154 fixtures 81 came to a different first line: 79 hit either way, one
  miss became a hit, one stayed a miss, and all stayed in register. With reuse switched off the
  same binary reproduced every line of a whole prefill exactly. The shared tokens sit at the same
  positions and hold the state a fresh prefill would compute, so this is rounding, not a stale
  read.

### Cancellation between model chunks

Prompt prefill and candidate scoring now use separate serialized model operations for chunks of at
most 128 tokens. The next operation checks cancellation before it enters the model container, so a
cancelled pass releases the shared slot after its current synchronous chunk finishes. This bounds
the work that can remain ahead of a fresh keystroke to one model operation of at most 128 input
tokens; its elapsed time remains model- and device-dependent. A controllable slow-chunk test holds
one operation open, queues a fresh pass, then verifies that only the current chunk completes before
the fresh pass acquires the slot.

## Low Power Mode and thermal pressure

A model pass is the most expensive thing tab-to-complete does (0.17 processor-seconds here), and it is discretionary: the corpus still offers what it remembers without it. So
the app hands `SuggestionCoordinator` its model wrapped in `DiscretionaryGenerator`, which:

- runs every pass in a utility task, resumed through a continuation so the awaiting turn does not
  raise the pass back to its own priority, with the caller's cancellation passed on;
- reports itself not ready, and starts no pass, while `EnergyConditions.current()` says the Mac is
  in Low Power Mode or at serious or critical thermal pressure. It also reports this energy hold
  separately from model readiness, so VoiceOver does not mistake a load or unavailable model for
  an energy pause.

Scoring a remembered candidate is left at its own priority: it is one forward pass raced against a
deadline, and slowing it would turn a slow answer into a refused candidate.

## Reading a terminal line for its prompt

`ShellPrompt.input` runs on the main actor each suggestion turn in a terminal, so its cost is
bounded rather than left to the line's length. It reads the line once, carrying forward what each
terminator needs to know about the text before it, and looks for a prompt only in the first
`ShellPrompt.searchLimit` (4,096) characters; a terminator past that point is not taken for a
prompt. Release, a line of `ab# ` repeated, best of 20 runs:

| line | time |
|---|---|
| 1 KB | 0.05 ms |
| 10 KB | 0.20 ms |
| 100 KB | 0.37 ms |
| 1 MB | 0.36 ms |

A reading that rescans the text before each terminator is not used: it is quadratic (15.3 s at
100 KB). `ShellPromptScalingTests` counts characters read through `ShellPrompt.tally` rather than
timing.
