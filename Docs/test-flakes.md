# Flaky tests

A test that fails on one run and passes on the next is measured, not retried by hand.

## Finding them

```bash
swift build --build-tests
for i in $(seq 1 20); do
    swift test --skip-build --parallel --xunit-output "$TMPDIR/run$i.xml"
done
python3 Scripts/flake_report.py "$TMPDIR"/run*-swift-testing.xml
```

`Scripts/flake_report.py` reads two or more JUnit files and prints each test that passed in
one run and failed in another, with failures divided by the runs in which that test executed.
Skipped or absent observations are reported together as `unobserved`; neither counts as a pass
or enlarges the failure-rate denominator. A complete cohort retains its failure count over all
runs. A test that fails in every observed run is broken, not flaky, and is not listed.

## Quarantine

Each flaky test is either fixed at its cause (inject a clock; no real sleep, no real device)
or listed in `Scripts/flake_quarantine.json` as
`{"test": "<classname>/<name>", "owner_issue": "<number>", "expires": "YYYY-MM-DD"}`.

- A quarantined test still runs and its result is still reported; nothing is skipped.
- `make flake-audit`, part of `make verify`, fails when an entry is past its expiry or has
  no owner issue. The way past it is fixing the test or deleting it, not moving the date.

## Probe result

Not yet recorded. The test target does not compile on `origin/main` at the time this page was
written (`Tests/UttrflowAccountTests/LoopbackTests.swift`, a strict-concurrency
`SendingClosureRisksDataRace` error), so no run of the suite can be taken. Once it builds, run
the loop above twenty times on one Mac and record here: host, run count, tests run, and every
test `flake_report.py` lists.
