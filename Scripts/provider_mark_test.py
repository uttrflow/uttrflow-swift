#!/usr/bin/env python3
"""Proves optional provider registration preserves the manifest's integrity checks."""

import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

import data_manifest
import provider_mark


class ProviderMarkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "Resources").mkdir()
        self.manifest = self.root / data_manifest.MANIFEST
        self.manifest.write_text('{"assets": []}')
        self.archive = self.root / "archive.zip"
        self.archive.write_bytes(b"invented archive fixture")
        self.mark = self.root / provider_mark.MARK_PATH
        self.mark.parent.mkdir(parents=True)
        self.mark.write_bytes(b"invented artwork fixture")
        provider_mark.register(self.root, self.archive, self.mark)

    def alter(self, **changes):
        manifest = json.loads(self.manifest.read_text())
        manifest["assets"][0].update(changes)
        self.manifest.write_text(json.dumps(manifest))

    def test_registered_present_and_absent_mark_pass(self):
        self.assertEqual(data_manifest.check(self.root), ([], []))
        self.mark.unlink()
        self.assertEqual(data_manifest.check(self.root), ([], []))

    def test_changed_mark_and_unknown_resource_fail(self):
        self.mark.write_bytes(b"corrupt artwork")
        self.assertTrue(any("SHA-256 differs" in error for error in data_manifest.check(self.root)[0]))
        self.mark.with_name("Unknown.png").write_bytes(b"unknown")
        self.assertTrue(any("bundled but not in" in error for error in data_manifest.check(self.root)[0]))

    def test_required_resource_is_not_optional(self):
        self.alter(optional=False)
        self.mark.unlink()
        self.assertTrue(any("not bundled" in error for error in data_manifest.check(self.root)[0]))

    def test_other_paths_cannot_opt_out_of_required_presence(self):
        self.alter(path="Sources/Module/Resources/required.json")
        failures = data_manifest.check(self.root)[0]
        self.assertTrue(any("requires path" in error for error in failures))
        self.assertTrue(any("not bundled" in error for error in failures))

    def test_optional_metadata_cannot_omit_provenance(self):
        for changes in ({"revision": "unrecorded"}, {"source": "invented"},
                        {"licence": "MIT"}, {"optional": "true"}):
            with self.subTest(changes=changes):
                provider_mark.register(self.root, self.archive, self.mark)
                self.alter(**changes)
                self.assertTrue(data_manifest.check(self.root)[0])

    def test_general_update_cannot_absorb_corrupt_optional_mark(self):
        self.mark.write_bytes(b"corrupt artwork")
        self.assertEqual(data_manifest.update(self.root), (0, []))
        self.assertTrue(data_manifest.check(self.root)[0])

    def run_check(self, command, flag, path):
        return subprocess.run(
            [sys.executable, provider_mark.__file__, command, "--root", str(self.root), flag, str(path)],
            capture_output=True, check=False, text=True)

    def test_archive_and_mark_verification_reject_corruption(self):
        self.assertEqual(self.run_check("verify-archive", "--archive", self.archive).returncode, 0)
        self.assertEqual(self.run_check("verify-mark", "--mark", self.mark).returncode, 0)
        self.archive.write_bytes(b"wrong archive")
        self.assertEqual(self.run_check("verify-archive", "--archive", self.archive).returncode, 1)
        self.mark.write_bytes(b"wrong mark")
        self.assertEqual(self.run_check("verify-mark", "--mark", self.mark).returncode, 1)


if __name__ == "__main__":
    unittest.main()
