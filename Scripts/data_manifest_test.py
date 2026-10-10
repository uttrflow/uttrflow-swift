#!/usr/bin/env python3
"""Proves the data manifest check fails on a missing entry, an edited byte or an asset over its budget."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

import data_manifest


class DataManifestTests(unittest.TestCase):
    def tree(self, origin="authored"):
        root = tempfile.mkdtemp()
        folder = os.path.join(root, "Sources", "Module", "Resources")
        os.makedirs(folder)
        os.makedirs(os.path.join(root, "Resources"))
        asset = os.path.join(folder, "table.json")
        with open(asset, "wb") as handle:
            handle.write(b"{}")
        entry = {
            "path": os.path.join("Sources", "Module", "Resources", "table.json"),
            "origin": origin,
            "licence": "MIT",
            "redistribution": True,
            "sha256": data_manifest.digest(asset),
            "bytes": 2,
        }
        self.write(root, [entry])
        return root, asset, entry

    def write(self, root, entries):
        with open(os.path.join(root, data_manifest.MANIFEST), "w", encoding="utf-8") as handle:
            json.dump({"assets": entries}, handle)

    def test_matching_tree_passes(self):
        root, _, _ = self.tree()
        self.assertEqual(data_manifest.check(root), ([], []))

    def test_removed_entry_fails(self):
        root, _, _ = self.tree()
        self.write(root, [])
        self.assertIn("bundled but not in", data_manifest.check(root)[0][0])

    def test_edited_byte_fails(self):
        root, asset, _ = self.tree()
        with open(asset, "wb") as handle:
            handle.write(b"[]")
        self.assertIn("SHA-256 differs", data_manifest.check(root)[0][0])

    def test_update_refreshes_only_digest_and_size_for_existing_entries(self):
        root, asset, original_entry = self.tree(origin="generated")
        original_entry["note"] = "keep this metadata"
        self.write(root, [original_entry])
        with open(asset, "wb") as handle:
            handle.write(b"[1, 2, 3]")

        changed, errors = data_manifest.update(root)

        self.assertEqual((changed, errors), (1, []))
        with open(os.path.join(root, data_manifest.MANIFEST), encoding="utf-8") as handle:
            updated = json.load(handle)["assets"][0]
        self.assertEqual(updated["origin"], "generated")
        self.assertEqual(updated["note"], "keep this metadata")
        self.assertEqual(updated["sha256"], data_manifest.digest(asset))
        self.assertEqual(updated["bytes"], os.path.getsize(asset))
        self.assertEqual(data_manifest.check(root), ([], []))

    def test_update_does_not_add_an_entry_for_an_unlisted_file(self):
        root, _, _ = self.tree()
        self.write(root, [])

        changed, errors = data_manifest.update(root)

        self.assertEqual((changed, errors), (0, []))
        self.assertIn("bundled but not in", data_manifest.check(root)[0][0])

    def test_update_command_refreshes_a_stale_entry(self):
        root, asset, _ = self.tree()
        with open(asset, "wb") as handle:
            handle.write(b"updated")

        result = subprocess.run(
            [
                sys.executable,
                os.path.join(os.path.dirname(data_manifest.__file__), "data_manifest.py"),
                "--root",
                root,
                "--update",
            ],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("updated 1 existing entries", result.stdout)
        self.assertEqual(data_manifest.check(root), ([], []))

    def test_changed_asset_names_the_values_to_record(self):
        root, asset, _ = self.tree()
        with open(asset, "wb") as handle:
            handle.write(b"[1]")
        failure = data_manifest.check(root)[0][0]
        self.assertIn(f"bytes 3, sha256 {data_manifest.digest(asset)}", failure)

    def test_asset_over_its_budget_fails_with_its_name(self):
        root, _, entry = self.tree()
        entry["budgetBytes"] = 2
        self.write(root, [entry])
        self.assertEqual(data_manifest.check(root), ([], []))
        self.assertEqual(data_manifest.budgeted(root), [(entry["path"], 2, 2)])
        entry["budgetBytes"] = 1
        self.write(root, [entry])
        self.assertEqual(data_manifest.check(root)[0], [f"{entry['path']}: 2 bytes, over its budgetBytes of 1"])

    def test_budget_must_be_a_positive_whole_number(self):
        root, _, entry = self.tree()
        for budget in (0, "2", 2.5, True):
            entry["budgetBytes"] = budget
            self.write(root, [entry])
            self.assertIn("positive whole number", data_manifest.check(root)[0][0])

    def test_stale_entry_fails(self):
        root, asset, _ = self.tree()
        os.remove(asset)
        self.assertIn("not bundled", data_manifest.check(root)[0][0])

    def test_third_party_needs_source_and_revision(self):
        root, _, entry = self.tree(origin="third-party")
        self.assertIn("missing source, revision", data_manifest.check(root)[0][0])
        entry.update(source="https://example.com/list", revision="1.0")
        self.write(root, [entry])
        self.assertEqual(data_manifest.check(root)[0], [])

    def test_unrecorded_origin_is_reported_not_failed(self):
        root, _, _ = self.tree(origin="unrecorded")
        failures, notes = data_manifest.check(root)
        self.assertEqual(failures, [])
        self.assertIn("owner to confirm", notes[0])

    def test_unknown_origin_fails(self):
        root, _, _ = self.tree(origin="found")
        self.assertIn("origin must be one of", data_manifest.check(root)[0][0])

    def audio_tree(self, **fields):
        root, _, entry = self.tree()
        folder = os.path.join(root, data_manifest.SYNTHETIC_AUDIO)
        os.makedirs(folder)
        take = os.path.join(folder, "hello.wav")
        with open(take, "wb") as handle:
            handle.write(b"RIFF")
        audio = {
            "path": os.path.join(data_manifest.SYNTHETIC_AUDIO, "hello.wav"),
            "licence": "MIT",
            "redistribution": True,
            "sha256": data_manifest.digest(take),
            "bytes": 4,
            **fields,
        }
        self.write(root, [entry, audio])
        return root

    def test_fixture_take_needs_an_entry(self):
        root, _, entry = self.tree()
        os.makedirs(os.path.join(root, data_manifest.SYNTHETIC_AUDIO))
        with open(os.path.join(root, data_manifest.SYNTHETIC_AUDIO, "take.wav"), "wb") as handle:
            handle.write(b"RIFF")
        self.assertIn("bundled but not in", data_manifest.check(root)[0][0])

    def test_fixture_take_needs_generated_origin_and_voice(self):
        root = self.audio_tree(origin="authored")
        self.assertIn("synthesiser's voice", data_manifest.check(root)[0][0])
        root = self.audio_tree(origin="generated")
        self.assertIn("synthesiser's voice", data_manifest.check(root)[0][0])
        root = self.audio_tree(origin="generated", voice="Example Voice")
        self.assertEqual(data_manifest.check(root), ([], []))


if __name__ == "__main__":
    unittest.main()
