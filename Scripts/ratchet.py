"""The count-may-fall-never-rise baseline shared by the audits that ratchet."""

import json
import os


def add_arguments(parser):
    parser.add_argument("--update", action="store_true", help="record the current counts")
    parser.add_argument(
        "--after-merge",
        action="store_true",
        help="with --update, accept counts that rose because main moved underneath",
    )


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path) as handle:
        return json.load(handle)


def risen(counts, recorded):
    """Each key whose count is above what the baseline allows, as (was, now)."""
    return {key: (recorded.get(key, 0), count) for key, count in counts.items() if count > recorded.get(key, 0)}


def update(path, counts, noun, to_do, after_merge, extra=None):
    """Record `counts` and any `extra` keys, refusing a rise unless `after_merge`. `to_do` finishes "Each is a ... to ... later"."""
    baseline = load(path)
    # With a baseline, a file it does not list was clean, so any count there is a rise.
    rises = risen(counts, baseline.get("files", {})) if baseline else {}
    if rises and not after_merge:
        print("Refusing to record a higher count. The baseline only goes down.")
        for key, (was, now) in sorted(rises.items()):
            print(f"  {key}: {was} -> {now}")
        print("\nIf these arrived from main rather than from your own work, re-record")
        print("with --after-merge. The rise then shows in the baseline's diff, where a")
        print("reviewer can see it, rather than passing unremarked.")
        return 1
    if rises:
        print(f"Absorbing counts that rose with main. Each is {to_do}:")
        for key, (was, now) in sorted(rises.items()):
            print(f"  {key}: {was} -> {now}")
    total = sum(counts.values())
    with open(path, "w") as handle:
        json.dump({"total": total, "files": counts, **(extra or {})}, handle, indent=2, sort_keys=True)
    print(f"Recorded {total} {noun} across {len(counts)} files.")
    return 0


def missing(path, script):
    print(f"No baseline at {path}. Run: python3 {script} --update")
    return 1
