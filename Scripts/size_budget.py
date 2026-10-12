#!/usr/bin/env python3
"""Fails when the app bundle or the resolved Swift packages outgrow `Scripts/size_budget.json` (see `Docs/performance.md`)."""

import argparse
import json
import os
import subprocess
from pathlib import Path
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUDGET = os.path.join(ROOT, "Scripts", "size_budget.json")
RESOLVED = os.path.join(ROOT, "Package.resolved")


def load_budget(path=BUDGET):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def tree_bytes(path):
    """Sum of regular file sizes under path, symlinks not followed, so the figure is the same on every file system."""
    total = 0
    for directory, _, files in os.walk(path):
        for name in files:
            full = os.path.join(directory, name)
            if not os.path.islink(full):
                total += os.path.getsize(full)
    return total


def zip_bytes(app):
    with tempfile.TemporaryDirectory() as scratch:
        archive = os.path.join(scratch, "app.zip")
        subprocess.run(["ditto", "-c", "-k", "--keepParent", app, archive], check=True)
        return os.path.getsize(archive)


def resolved_packages(path=RESOLVED):
    with open(path, encoding="utf-8") as handle:
        resolved = json.load(handle)
    if not isinstance(resolved, dict) or not isinstance(resolved.get("pins"), list):
        raise ValueError("resolved package count requires a pins list")
    return len(resolved["pins"])


def over_budget(measured, budget):
    """The measures over their limit, as (name, measured, limit); a measure missing from the budget is over it."""
    return [(name, value, budget.get(name)) for name, value in measured.items()
            if budget.get(name) is None or value > budget[name]]


def report(measured, budget):
    for name, value in measured.items():
        limit = budget.get(name)
        print(f"  {name:<18} {value:>13,}  budget {'none' if limit is None else format(limit, ','):>13}")
    failures = over_budget(measured, budget)
    for name, value, limit in failures:
        print(f"error: {name} is {value:,}, over its budget of {limit}. Shrink it, or raise "
              f"Scripts/size_budget.json in a reviewed change that says why.", file=sys.stderr)
    return 1 if failures else 0


def resolved_probe(script, content):
    """Runs the size gate against a private fixture manifest."""
    manifest = script.parent.parent / "Package.resolved"
    if content is None:
        manifest.unlink(missing_ok=True)
    else:
        manifest.write_text(content)
    return subprocess.run([sys.executable, str(script)], capture_output=True, text=True)


def resolved_evidence_self_test():
    """Checks missing evidence and real dependency-count boundaries through the CLI."""
    failures = []
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        scripts = root / "Scripts"
        scripts.mkdir()
        script = scripts / "size_budget.py"
        script.write_bytes(Path(__file__).read_bytes())
        (scripts / "size_budget.json").write_bytes(Path(BUDGET).read_bytes())
        invalid = [None, "not json", "[]", '"text"', "{}", '{"pins":"x"}',
                   '{"pins":{}}', '{"pins":null}']
        for content in invalid:
            result = resolved_probe(script, content)
            if result.returncode != 1 or result.stdout or "could not measure resolved" not in result.stderr:
                failures.append(f"invalid manifest {content!r} did not fail before reporting")
        limit = load_budget()["resolved_packages"]
        for count in (0, limit, limit + 1):
            result = resolved_probe(script, json.dumps({"pins": [{}] * count}))
            expected = f"  {'resolved_packages':<18} {count:>13,}  budget {limit:>13,}\n"
            if result.returncode != int(count > limit) or result.stdout != expected:
                failures.append(f"valid package count {count} changed its status or report")
        current = resolved_probe(script, Path(RESOLVED).read_text())
        if current.returncode != 0 or current.stderr:
            failures.append("current resolved manifest was refused")
    for failure in failures:
        print(f"size budget self-test: {failure}", file=sys.stderr)
    assert not failures, "resolved-package evidence controls failed"
    print("size budget self-test: 8 invalid inputs refused; empty/current/exact/over boundaries preserved")


def self_test():
    budget = {"app_bytes": 100, "resolved_packages": 2}
    assert over_budget({"app_bytes": 100, "resolved_packages": 2}, budget) == []
    assert over_budget({"app_bytes": 101}, budget) == [("app_bytes", 101, 100)]
    assert over_budget({"resolved_packages": 3}, budget) == [("resolved_packages", 3, 2)]
    assert over_budget({"app_zip_bytes": 1}, budget) == [("app_zip_bytes", 1, None)]
    with tempfile.TemporaryDirectory() as scratch:
        os.makedirs(os.path.join(scratch, "A.app", "Contents", "Resources"))
        with open(os.path.join(scratch, "A.app", "Contents", "Resources", "blob"), "wb") as handle:
            handle.write(b"\0" * 150)
        os.symlink("blob", os.path.join(scratch, "A.app", "Contents", "Resources", "link"))
        assert tree_bytes(os.path.join(scratch, "A.app")) == 150
        assert over_budget({"app_bytes": tree_bytes(os.path.join(scratch, "A.app"))}, budget)
        resolved = os.path.join(scratch, "Package.resolved")
        with open(resolved, "w", encoding="utf-8") as handle:
            json.dump({"pins": [{"identity": "a"}, {"identity": "b"}, {"identity": "c"}]}, handle)
        assert resolved_packages(resolved) == 3
    assert set(load_budget()) == {"app_bytes", "app_zip_bytes", "resolved_packages"}
    resolved_evidence_self_test()
    print("size budget self-test passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", help="a built .app bundle to measure as well as the resolved packages")
    parser.add_argument("--self-test", action="store_true", help="prove the check bites, then check the packages")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    budget = load_budget()
    try:
        measured = {"resolved_packages": resolved_packages()}
    except (OSError, ValueError) as error:
        print(f"error: could not measure resolved Swift packages: {error}", file=sys.stderr)
        return 1
    if args.app:
        measured["app_bytes"] = tree_bytes(args.app)
        measured["app_zip_bytes"] = zip_bytes(args.app)
    else:
        budget = {"resolved_packages": budget["resolved_packages"]}
    return report(measured, budget)


if __name__ == "__main__":
    sys.exit(main())
