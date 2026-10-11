# Absorbing a closed formatting gap

`python3 Scripts/formatting_gap_ratchet.py` measures every ID recorded by
`FormattingParityTests.knownGaps` and reports which now pass. A dry run does not
write the registries, golden outputs or parity report.

Run it through the worktree pool build wrapper, with the configured Xcode toolchain.
Add `--absorb` only after reviewing the source change and its corpus comparison.
The updater invokes the existing golden and parity generators into temporary files.
It requires unchanged case IDs, output changes belonging exactly to passing gaps,
and report changes that only move those gaps into the passing count.

Absorption removes freshly passing IDs from both applicable failure registries.
It preserves the absolute destination-case count when updating its passing count.
The four recorded artifacts must remain unchanged during measurement and generation.
All replacement files are staged first; a write failure restores completed writes.
A failed restoration retains recovery copies and reports their location.

Corpus inputs, reference answers and positive assertions remain required.
This command does not authorize an assertion change or replace the required bakeoff.
