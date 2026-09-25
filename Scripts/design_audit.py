#!/usr/bin/env python3
"""Catches a design generator that no longer reproduces its checked-in artifact.

`Design/*.dc.html` and `Design/canvas.json` are generated files, reviewed and diffed like
any other, but nothing before this ran their generators and compared the result. A
generator could drift from what is checked in — a stale state, a size nobody updated — and
every review since would have looked at the artifact and trusted it, never the script that
claims to produce it (#1128).

This regenerates every `Design/_gen_*.py` script into a scratch copy of `Design/` and diffs
its `.dc.html` and `canvas.json` output against what is committed. `_gen_common.py` and
`_gen_shell.py` are shared helpers with nothing of their own to write, so they are not run
directly; `_preview_gen.py` takes a CLI argument and writes a throwaway preview, not a
committed artifact.

Usage:  python3 Scripts/design_audit.py            (belongs in `make verify`)
        python3 Scripts/design_audit.py --self-test   also proves the audit catches drift
"""
import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
DESIGN_DIR = PACKAGE_ROOT / "Design"
NOT_A_GENERATOR = {"_gen_common.py", "_gen_shell.py", "_preview_gen.py"}


def generator_scripts(design_dir):
    return sorted(
        p.name for p in design_dir.glob("_gen_*.py") if p.name not in NOT_A_GENERATOR
    )


def run_generators(design_dir):
    """Runs every generator script in `design_dir`, in name order for a stable result."""
    for script in generator_scripts(design_dir):
        result = subprocess.run(
            [sys.executable, script], cwd=design_dir, capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(f"{script} failed:\n{result.stderr}")


def drifted_files(design_dir):
    """Regenerates into a scratch copy and returns the committed paths that differ."""
    committed = {p.name for p in design_dir.glob("*.dc.html")}
    committed.add("canvas.json")

    with tempfile.TemporaryDirectory() as scratch:
        scratch_design = Path(scratch) / "Design"
        shutil.copytree(design_dir, scratch_design)
        run_generators(scratch_design)

        diffs = []
        for name in sorted(committed):
            before = (design_dir / name).read_text()
            after = (scratch_design / name).read_text()
            if before != after:
                diffs.append(name)
        return diffs


def self_test():
    """Proves the audit both passes a clean generator and fails a drifted one."""
    print("design_audit self-test")
    with tempfile.TemporaryDirectory() as scratch:
        design_dir = Path(scratch) / "Design"
        design_dir.mkdir()
        (design_dir / "_gen_widget.py").write_text(
            'open("Widget.dc.html", "w").write("<p>hi</p>")\n'
        )
        (design_dir / "Widget.dc.html").write_text("<p>hi</p>")
        (design_dir / "canvas.json").write_text("{}")

        assert drifted_files(design_dir) == [], "a fresh, matching artifact must pass"
        print("  ✓ a generator that reproduces its artifact passes")

        (design_dir / "Widget.dc.html").write_text("<p>tampered</p>")
        diffs = drifted_files(design_dir)
        assert diffs == ["Widget.dc.html"], f"a tampered artifact must be caught, got {diffs}"
        print("  ✓ a tampered artifact is caught")
    print("design_audit: self-test passed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    diffs = drifted_files(DESIGN_DIR)
    if diffs:
        print("design_audit: FAILED", file=sys.stderr)
        print("  the committed artifact no longer matches its generator:", file=sys.stderr)
        for name in diffs:
            print(f"    {name}", file=sys.stderr)
        print(
            "  run `python3 Design/_gen_<name>.py` (or `python3 Design/_gen_canvas.py`) "
            "and commit the result.",
            file=sys.stderr,
        )
        sys.exit(1)
    scripts = len(generator_scripts(DESIGN_DIR))
    print(f"design_audit: {scripts} generators, all match their committed artifact")


if __name__ == "__main__":
    main()
