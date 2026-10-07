#!/usr/bin/env python3
"""Proves the data manifest check fails on a missing entry or an edited byte."""

import json
import os
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
