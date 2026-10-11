# Mid-word tab-to-complete: the calibration set

A prefix cut inside a word (`gi` for `git status`) is judged by the same `Verification.plausibilityFloor` as a whole-word prefix, after `ScoredSpan` has scored the word's first token over the bytes the typing still owes (see [predict.md](predict.md)). The floor was set on whole-word lines, so what it keeps and refuses for mid-word cuts needs a labelled set of its own.

## The set

`MidWordCalibration.all` (`Sources/UttrflowEval/MidWordCalibration.swift`) holds invented command-line prefixes across git, docker, kubectl, swift, npm, brew, cargo, python, make, curl, grep, tar, systemctl, terraform, go, ffmpeg, rsync and others. Each prefix has:

- sensible lines: whole commands the prefix could honestly be heading for, which a floor should keep;
- nonsense lines: whole lines that begin the same way and look like commands but name nothing real, which a floor should refuse.

Every line begins with the prefix and the prefix stops inside a word; `MidWordCalibrationTests` checks both, and that no line holds a personal path or a host outside `example.com`. Values are invented. To add a prefix, append a `Probe` and keep it mid-word.

## The report

```bash
make bakeoff ARGS="midword --sweep"
```

scores every line with the local model (mean log-probability per judged token, as `uttrflow-bakeoff score` does) and prints, for `--floor` (default `Verification.plausibilityFloor`), how many sensible lines are kept and how many nonsense lines pass. `--sweep` adds a row per floor from -9 to -2, and `--verbose` prints every line's score.

## Status

The set and the report exist. The floor has not yet been chosen from a run: that needs the model loaded on an otherwise quiet Mac, and the table belongs here when it exists.
