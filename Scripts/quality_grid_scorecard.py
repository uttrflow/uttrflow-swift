#!/usr/bin/env python3
"""Validate structured grid reports and compare their existing gates with a measured base."""

import argparse
import json
from pathlib import Path

PREFIX = "QUALITY_GRID "
GROUPS = {"onset", "condition", "number", "inflected", "lexicon", "clip-prefilter"}


def records_from_text(text):
    if text.lstrip().startswith("{"):
        return json.loads(text)["records"]
    return [json.loads(line[len(PREFIX):]) for line in text.splitlines() if line.startswith(PREFIX)]


def validate(records, groups=GROUPS):
    indexed = {}
    for record in records:
        if not isinstance(record, dict) or type(record.get("version")) is not int or record.get("version") != 1:
            raise ValueError("unsupported quality record")
        if set(record) - {"version", "suite", "id", "passed", "failed", "allowed", "measurements"}:
            raise ValueError("unknown quality record fields")
        suite, identifier = record.get("suite"), record.get("id")
        if suite not in groups or not isinstance(identifier, str) or not identifier:
            raise ValueError("unknown group or missing stable ID")
        key = (suite, identifier)
        if key in indexed:
            raise ValueError(f"duplicate quality record: {suite}/{identifier}")
        if "passed" in record and type(record["passed"]) is not bool:
            raise ValueError(f"invalid verdict: {suite}/{identifier}")
        measurements = record.get("measurements")
        if not isinstance(measurements, dict) or any(type(v) is not int for v in measurements.values()):
            raise ValueError(f"invalid measurements: {suite}/{identifier}")
        if ("failed" in record) != ("allowed" in record):
            raise ValueError(f"incomplete bucket: {suite}/{identifier}")
        for field in ("failed", "allowed"):
            if field in record and (type(record[field]) is not int or record[field] < 0):
                raise ValueError(f"invalid {field}: {suite}/{identifier}")
        if "failed" in record and record.get("passed") != (record["failed"] <= record["allowed"]):
            raise ValueError(f"bucket verdict contradicts its allowance: {suite}/{identifier}")
        indexed[key] = record
    missing = groups - {key[0] for key in indexed}
    if missing:
        raise ValueError("missing quality groups: " + ", ".join(sorted(missing)))
    return indexed


def compare(base, measured):
    problems = [
        "/".join(key) + ": existing gate fails"
        for key, record in sorted(measured.items()) if record.get("passed") is False
    ]
    for key, old in sorted(base.items()):
        current = measured.get(key)
        name = "/".join(key)
        if current is None:
            problems.append(f"{name}: missing measured case")
            continue
        if ("passed" in old) != ("passed" in current):
            problems.append(f"{name}: gate ownership changed")
            continue
        if "passed" not in old:
            continue
        if ("failed" in old) != ("failed" in current):
            problems.append(f"{name}: bucket gate kind changed")
            continue
        if "failed" in old:
            if "failed" not in current:
                problems.append(f"{name}: bucket gate disappeared")
            elif current["allowed"] > old["allowed"]:
                problems.append(f"{name}: failure allowance increased")
            elif current["failed"] > old["failed"]:
                problems.append(f"{name}: failures rose {old['failed']} -> {current['failed']}")
        elif old["passed"] and not current["passed"]:
            problems.append(f"{name}: a passing case regressed")
    return problems


def absorb(measured_path, output):
    measured = validate(records_from_text(Path(measured_path).read_text()))
    previous = validate(records_from_text(output.read_text())) if output.exists() else {}
    problems = compare(previous, measured)
    for problem in problems:
        print("quality grid scorecard: " + problem)
    if problems:
        return 1
    records = [measured[key] for key in sorted(measured)]
    output.write_text(json.dumps({"records": records}, indent=2, sort_keys=True) + "\n")
    print(f"quality grid scorecard: absorbed {len(records)} records into {output}")
    return 0


def self_test():
    def record(identifier="case", **fields):
        return {"version": 1, "suite": "fixture", "id": identifier, "measurements": {}} | fields

    def checked(items):
        return validate(items, {"fixture"})

    base = checked([record(passed=True)])
    assert not compare(base, base)
    assert compare(base, checked([record(passed=False)]))
    assert not compare(checked([record(passed=False)]), base)
    assert compare(base, {})
    assert compare(base, checked([record()]))
    assert compare(base, checked([record(passed=True), record("extra", passed=False)]))
    assert not compare(base, checked([record(passed=True), record("extra", passed=True)]))
    assert not compare(base, checked([record(passed=True), record("extra")]))
    diagnostic = checked([record(measurements={"clip": 0})])
    assert not compare(diagnostic, checked([record(measurements={"clip": 500})]))
    bucket = checked([record(passed=True, failed=2, allowed=4)])
    assert not compare(bucket, checked([record(passed=True, failed=1, allowed=4)]))
    assert compare(bucket, checked([record(passed=True, failed=3, allowed=4)]))
    assert compare(bucket, checked([record(passed=False, failed=5, allowed=4)]))
    assert compare(bucket, checked([record(passed=True, failed=2, allowed=5)]))
    assert compare(bucket, base)
    assert compare(base, bucket)
    for bad in [[], [record(), record()], [record(passed="yes")], [record(failed=1)],
                [record(raw="unexpected")], [record(version=True)],
                [record(passed=True, failed=2, allowed=1)], [record(measurements={"clip": "zero"})]]:
        try:
            checked(bad)
        except ValueError:
            continue
        raise AssertionError("malformed, duplicate or missing records passed")
    try:
        records_from_text(PREFIX + "{broken}")
    except json.JSONDecodeError:
        pass
    else:
        raise AssertionError("malformed JSON passed")
    assert records_from_text("progress\n" + PREFIX + json.dumps(record())) == [record()]
    print("quality grid scorecard: comparator self-tests passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--measured")
    parser.add_argument("--base")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--absorb")
    parser.add_argument("--output")
    args = parser.parse_args()
    if args.absorb:
        if args.measured or args.base or args.self_test:
            parser.error("--absorb cannot be combined with comparison or self-test")
        try:
            output = Path(args.output) if args.output else Path(__file__).with_name("quality_grid_baseline.json")
            return absorb(args.absorb, output)
        except (OSError, ValueError, KeyError, TypeError) as error:
            print(f"quality grid scorecard: {error}")
            return 1
    if args.output:
        parser.error("--output requires --absorb")
    if args.self_test:
        return self_test()
    if not args.measured or not args.base:
        parser.error("--measured and --base are required; no absent-base success")
    try:
        base = validate(records_from_text(Path(args.base).read_text()))
        measured = validate(records_from_text(Path(args.measured).read_text()))
        problems = compare(base, measured)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"quality grid scorecard: {error}")
        return 1
    for problem in problems:
        print("quality grid scorecard: " + problem)
    print(f"quality grid scorecard: {len(measured)} records, {len(problems)} problems")
    return int(bool(problems))


if __name__ == "__main__":
    raise SystemExit(main())
