#!/usr/bin/env python3
"""Keep selected in-process package pins and release resolution flags aligned."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parent.parent
PINS = {
    "swift-argument-parser": "1.8.2",
    "mlx-swift-lm": "3.31.4",
    "swift-transformers": "1.3.4",
    "swift-huggingface": "0.10.1",
}
PACKAGE = re.compile(r'\.package\(url:\s*"([^"]+)"\s*,\s*exact:\s*"([^"]+)"\)')
FLAGS = ("-disableAutomaticPackageResolution", "-onlyUsePackageVersionsFromResolvedFile")


def inspect(root: Path) -> list[str]:
    manifest = (root / "Package.swift").read_text()
    lock = json.loads((root / "Package.resolved").read_text())
    script = (root / "Scripts/bundle.sh").read_text()
    declared = {}
    for url, version in PACKAGE.findall(manifest):
        declared[url.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")] = version
    locked = {pin["identity"]: pin["state"].get("version") for pin in lock["pins"]}
    errors = []
    for identity, version in PINS.items():
        if declared.get(identity) != version:
            errors.append(f"{identity}: Package.swift must pin exactly {version}")
        if locked.get(identity) != version:
            errors.append(f"{identity}: Package.resolved must lock {version}")
    start = script.find("xcodebuild \\\n")
    end = script.find("\\\n    build", start)
    invocation = script[start:end] if start >= 0 and end > start else ""
    for flag in FLAGS:
        if not re.search(rf"^[ \t]+{re.escape(flag)}[ \t]*\\$", invocation, re.MULTILINE):
            errors.append(f"release xcodebuild invocation must include {flag}")
    return errors


def self_test() -> int:
    with TemporaryDirectory() as temporary:
        root = Path(temporary)
        (root / "Scripts").mkdir()
        for name in ("Package.swift", "Package.resolved"):
            (root / name).write_text((ROOT / name).read_text())
        script_path = root / "Scripts/bundle.sh"
        original_script = (ROOT / "Scripts/bundle.sh").read_text()
        script_path.write_text(original_script)
        if inspect(root):
            return 1
        for flag in FLAGS:
            script_path.write_text(original_script.replace(flag, "", 1))
            if not any(flag in error for error in inspect(root)):
                return 1
        script_path.write_text(original_script)
        manifest = (root / "Package.swift").read_text().replace('exact: "1.8.2"', 'from: "1.8.0"', 1)
        (root / "Package.swift").write_text(manifest)
        if not any("swift-argument-parser" in error for error in inspect(root)):
            return 1
        (root / "Package.swift").write_text((ROOT / "Package.swift").read_text())
        resolved = json.loads((root / "Package.resolved").read_text())
        huggingface = next(pin for pin in resolved["pins"] if pin["identity"] == "swift-huggingface")
        huggingface["state"]["version"] = "0.12.0"
        (root / "Package.resolved").write_text(json.dumps(resolved))
        if not any("swift-huggingface" in error for error in inspect(root)):
            return 1
    print("dependency pin audit self-test: passed")
    return 0


def main() -> int:
    if sys.argv[1:] == ["--self-test"]:
        return self_test()
    errors = inspect(ROOT)
    if errors:
        print("\n".join(f"dependency pin audit: {error}" for error in errors), file=sys.stderr)
        return 1
    print("dependency pin audit: exact manifest pins match Package.resolved and release flags")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
