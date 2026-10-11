#!/usr/bin/env python3
"""Prove documented source paths are checked independently of ignored build output."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    audit = Path(__file__).with_name("docs_audit.sh").read_text()
    program = audit.split("PATH_PROGRAM <<'PYTHON'", 1)[1].split("\n", 1)[1].split("\nPYTHON", 1)[0]
    with tempfile.TemporaryDirectory(prefix="uttrflow-doc-paths-") as directory:
        root = Path(directory)
        subprocess.run(["git", "init", "-q", directory], check=True)
        (root / ".gitignore").write_text("dist/\n")
        (root / "Sources").mkdir()
        (root / "Sources" / "Real.swift").write_text("// fixture\n")
        document = root / "README.md"
        document.write_text("Generated report: `dist/release-quality.md`.\n")
        subprocess.run(["git", "add", "."], cwd=root, check=True)

        def report():
            return subprocess.run([sys.executable, "-c", program], cwd=root,
                                  input="README.md\n", text=True, capture_output=True,
                                  check=True).stdout

        assert report() == "", "generated output must not be required on a clean checkout"
        (root / "dist").mkdir()
        assert report() == "", "creating ignored output must not change repository authority"
        document.write_text("Missing source: `Sources/Missing.swift`.\n")
        assert "MISSING\tREADME.md:1\tSources/Missing.swift" in report()
        document.write_text("Source: `Sources/Real.swift`.\n")
        assert report() == "", "a tracked source path must resolve"
        shutil.rmtree(root / "Sources")
        assert "MISSING\tREADME.md:1\tSources/Real.swift" in report(), (
            "removing an entire tracked directory must not hide a missing source")
    print("docs path self-test: ignored output is independent; missing source still fails")


if __name__ == "__main__":
    main()
